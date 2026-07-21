# fw.ps1 - FlutterWrapper v3 Unified CLI
#
# Single entry point for all FlutterWrapper operations.
# Routes to doctor, repair, provider, flutter helpers, status, etc.
#
# Usage: see `fw help` or README.

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir   = Split-Path -Parent $scriptDir
$configPath = Join-Path $rootDir 'config\wrapper.yaml'

# ============================================================
# Shared helpers (dot-sourced from lib/config.ps1)
# ============================================================
. "$PSScriptRoot/../lib/config.ps1"

$config = Read-WrapperConfigSafe $configPath
$distro = if ($config) { $config.wsl.distro } else { $null }

# ============================================================
# Commands that require config
# ============================================================
function Require-Config {
    if (-not $config) {
        Write-Err "Config not found: $configPath"
        Write-Host "  Run: fw setup  or  install.ps1" -ForegroundColor Yellow
        exit 1
    }
}

# ============================================================
# Repair engine
# ============================================================
$repairModules = @{
    'package-config' = 'Re-run pub get and translate package_config.json for W: drive compat'
    'dart-sdk'       = 'Re-create bin/cache/dart-sdk Junction to Windows Dart SDK'
    'symlinks'       = 'Re-create WSL path symlinks (/w:/, /W:/, /blaze-out)'
    'config'         = 'Re-detect Flutter/Dart/JDK paths and rewrite wrapper.yaml'
    'vfox'           = 'Check and re-create vfox global Junction workaround'
    'daemon'         = 'Kill stale daemon processes on TCP port 9876'
    'cache'          = 'Clean Dart/Flutter build caches (.dart_tool/, .cxx/)'
}

function Repair-PackageConfig {
    Require-Config
    Write-Step "Repairing package_config.json"
    $winCwd = (Get-Location).Path
    $pkgConfig = Join-Path $winCwd '.dart_tool\package_config.json'
    if (-not (Test-Path (Join-Path $winCwd 'pubspec.yaml'))) {
        Write-Warn "Not in a Flutter project (no pubspec.yaml). Skipping."
        return
    }
    Write-Host "    Running: flutter pub get"
    $flutterExe = $config.flutter.executable
    $wslCwd = ConvertTo-WslPathSimple $winCwd
    & wsl.exe -d $distro --cd $wslCwd -e $flutterExe pub get 2>&1 | ForEach-Object { Write-Host "    $_" }
    if ($LASTEXITCODE -ne 0) {
        Write-Err "flutter pub get failed (exit=$LASTEXITCODE)"
        return
    }
    # Translate package_config.json
    if (Test-Path $pkgConfig) {
        try {
            $bytes = [System.IO.File]::ReadAllBytes($pkgConfig)
            if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
                $bytes = $bytes[3..($bytes.Length - 1)]
            }
            $content = [System.Text.Encoding]::UTF8.GetString($bytes)
            $mappedDrive = if ($config.workspace.mappedDrive) { $config.workspace.mappedDrive.ToLower() } else { 'w' }
            $translated = $content -replace 'file:///(?!/wsl\.|/W:/|/w:/)', "file:///$mappedDrive:/"
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($pkgConfig, $translated, $utf8NoBom)
            Write-OK "package_config.json translated to $($mappedDrive): form"
        } catch {
            Write-Err "Failed to translate package_config.json: $($_.Exception.Message)"
        }
    } else {
        Write-Warn "No package_config.json found after pub get"
    }
}

function Repair-DartSdk {
    Write-Step "Repairing dart-sdk Junction"
    $dartSdkLink = Join-Path $rootDir 'bin\cache\dart-sdk'
    $cacheDir = Split-Path -Parent $dartSdkLink
    if (-not (Test-Path $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }
    # Remove existing if broken
    if (Test-Path $dartSdkLink) {
        $existing = Get-Item $dartSdkLink -Force -ErrorAction SilentlyContinue
        if ($existing -and $existing.LinkType -ne 'Junction') {
            Remove-Item $dartSdkLink -Force -Recurse -ErrorAction SilentlyContinue
            Write-Host "    Removed non-Junction entry"
        } elseif ($existing) {
            Write-OK "Junction already exists: $($existing.Target)"
            return
        }
    }
    # Find Windows dart-sdk target
    $vfoxDartSdk = Join-Path $env:USERPROFILE 'vfox-global\flutter\bin\cache\dart-sdk'
    $stdDartSdk = 'C:\flutter\bin\cache\dart-sdk'
    $target = $null
    if (Test-Path $vfoxDartSdk) { $target = $vfoxDartSdk }
    elseif (Test-Path $stdDartSdk) { $target = $stdDartSdk }
    if ($target) {
        cmd /c mklink /J "$dartSdkLink" "$target" 2>&1 | Out-Null
        if (Test-Path $dartSdkLink) {
            Write-OK "Created Junction: $dartSdkLink -> $target"
        } else {
            Write-Err "Failed to create Junction (try running as Administrator)"
        }
    } else {
        Write-Err "No Windows-side dart-sdk found (vfox-global not set up?)"
    }
}

function Repair-Symlinks {
    Require-Config
    Write-Step "Repairing WSL path symlinks"
    $symlinkScript = Join-Path $rootDir 'tools\setup-wsl-symlink.sh'
    if (-not (Test-Path $symlinkScript)) {
        Write-Err "setup-wsl-symlink.sh not found"
        return
    }
    $sDrive = $symlinkScript.Substring(0,1).ToLower()
    $sRest = $symlinkScript.Substring(2) -replace '\\', '/'
    $wslScript = "/mnt/$sDrive$sRest"
    $symDrive = if ($config.workspace.mappedDrive) { $config.workspace.mappedDrive } else { 'W' }
    Write-Host "    Running: bash $wslScript $distro $symDrive (may need sudo)"
    $result = & wsl.exe -d $distro -e bash -c "sudo bash $wslScript $distro $symDrive 2>&1"
    if ($LASTEXITCODE -eq 0) {
        Write-OK "WSL symlinks repaired"
    } else {
        Write-Warn "Symlink script returned non-zero. You may need to run manually:"
        Write-Host "      wsl -e bash -c 'sudo bash $wslScript $distro $symDrive'"
    }
}

function Repair-Config {
    Write-Step "Repairing wrapper.yaml configuration"
    Require-Config
    Write-Host "    Running install.ps1 -Auto -SkipSmoke to re-detect..."
    $installPath = Join-Path $rootDir 'install.ps1'
    if (-not (Test-Path $installPath)) {
        Write-Err "install.ps1 not found"
        return
    }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $installPath -Auto -SkipSmoke -Distro $distro
    if ($LASTEXITCODE -eq 0) {
        Write-OK "Configuration regenerated"
    } else {
        Write-Err "install.ps1 failed (exit=$LASTEXITCODE)"
    }
}

function Repair-Vfox {
    Write-Step "Repairing vfox global Junction workaround"
    $vfoxGlobal = Join-Path $env:USERPROFILE 'vfox-global'
    if (-not (Test-Path $vfoxGlobal)) {
        New-Item -ItemType Directory -Path $vfoxGlobal -Force | Out-Null
    }
    $sdks = @('flutter', 'nodejs', 'java')
    foreach ($sdk in $sdks) {
        $junctionPath = Join-Path $vfoxGlobal $sdk
        $targetPath = Join-Path $env:USERPROFILE ".version-fox\sdks\$sdk"
        if (-not (Test-Path $targetPath)) { continue }
        if (Test-Path $junctionPath) {
            $existing = Get-Item $junctionPath -Force -ErrorAction SilentlyContinue
            if ($existing.LinkType -eq 'Junction') {
                Write-OK "vfox-global/$sdk Junction OK"
                continue
            }
        }
        try {
            Remove-Item $junctionPath -Force -Recurse -ErrorAction SilentlyContinue
            New-Item -ItemType Junction -Path $junctionPath -Target $targetPath -Force | Out-Null
            Write-OK "Created Junction: $junctionPath -> $targetPath"
        } catch {
            Write-Warn "Failed for $sdk`: $($_.Exception.Message)"
        }
    }
}

function Repair-Daemon {
    Require-Config
    Write-Step "Repairing daemon (killing stale processes)"
    $port = if ($config.daemon.tcpPort) { $config.daemon.tcpPort } else { '9876' }
    try {
        $result = & wsl.exe -d $distro -e bash -lc "fuser -k $port/tcp 2>&1 || true" 2>$null
        Write-Host "    $result"
    } catch {}
    # Also kill any wsl.exe stuck processes on Windows side
    try {
        $wslProcs = Get-Process wsl -ErrorAction SilentlyContinue
        if ($wslProcs) { Write-OK "WSL processes running: $($wslProcs.Count)" }
    } catch {}
    Write-OK "Daemon port $port cleaned"
}

function Repair-Cache {
    Write-Step "Cleaning build caches"
    $winCwd = (Get-Location).Path
    $cacheDirs = @('.dart_tool', '.cxx', 'build')
    foreach ($dir in $cacheDirs) {
        $fullPath = Join-Path $winCwd $dir
        if (Test-Path $fullPath) {
            try {
                Remove-Item $fullPath -Force -Recurse -ErrorAction Stop
                Write-OK "Removed $dir/"
            } catch {
                Write-Warn "Could not remove $dir/: $($_.Exception.Message)"
            }
        } else {
            Write-Host "    $dir/ not present (skip)"
        }
    }
}

# ============================================================
# Provider detection
# ============================================================
function Detect-Provider {
    Require-Config
    Write-Host ""
    Write-Host "Detected providers:" -ForegroundColor Cyan
    Write-Host ('─' * 30) -ForegroundColor Cyan

    # Check vfox
    $vfoxExe = Get-Command vfox -ErrorAction SilentlyContinue
    if ($vfoxExe) {
        $vfoxCurrent = $null
        try {
            $vfoxCurrent = (& vfox current flutter 2>$null | Where-Object { $_ -match 'flutter' } | Select-Object -First 1) -replace '\s+', ' '
        } catch {}
        Write-Host "  ✓ vfox" -ForegroundColor Green
        if ($vfoxCurrent) { Write-Host "    $vfoxCurrent" -ForegroundColor Gray }
        # Check Junction workaround
        $jPath = Join-Path $env:USERPROFILE 'vfox-global\flutter'
        if (Test-Path $jPath) {
            Write-Host "    Junction workaround: active" -ForegroundColor Green
        } else {
            Write-Host "    Junction workaround: missing (run: fw repair vfox)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  ✗ vfox" -ForegroundColor DarkGray
    }

    # Check FVM (in WSL)
    if ($distro) {
        $fvmFound = $false
        $fvmVersionsList = @()
        try {
            $fvmDefault = & wsl.exe -d $distro -e bash -lc "test -f ~/fvm/default/bin/flutter && echo 'default' || true" 2>$null
            if ($fvmDefault.Trim()) { $fvmFound = $true; $fvmVersionsList += 'default' }
        } catch {}
        try {
            $fvmVerDirs = & wsl.exe -d $distro -e bash -lc 'ls -1d ~/.fvm/versions/*/bin/flutter 2>/dev/null | sed "s|/bin/flutter||;s|.*/||" || true' 2>$null
            if ($fvmVerDirs) {
                foreach ($v in $fvmVerDirs) { if ($v.Trim()) { $fvmFound = $true; $fvmVersionsList += $v.Trim() } }
            }
        } catch {}
        if ($fvmFound) {
            Write-Host "  ✓ FVM" -ForegroundColor Green
            Write-Host "    Versions: $($fvmVersionsList -join ', ')" -ForegroundColor Gray
            # FVM global version
            try {
                $fvmGlobalVer = & wsl.exe -d $distro -e bash -lc 'fvm global 2>/dev/null || fvm list 2>/dev/null | grep -m1 "^[✓*]" | sed "s/[✓*] //;s/ .*//" || true' 2>$null
                $fvmGlobalVer = ($fvmGlobalVer -join '').Trim()
                if ($fvmGlobalVer) { Write-Host "    Global: $fvmGlobalVer" -ForegroundColor Gray }
            } catch {}
        } else {
            Write-Host "  ✗ FVM" -ForegroundColor DarkGray
        }
    }

    # Check manual (wrapper.yaml)
    $flutterExe = $config.flutter.executable
    if ($flutterExe) {
        $isProvider = $flutterExe -match 'vfox|fvm'
        if (-not $isProvider) {
            Write-Host "  ✓ Manual SDK" -ForegroundColor Green
            Write-Host "    Path: $flutterExe" -ForegroundColor Gray
        }
    }

    Write-Host ""
}

# ============================================================
# Path conversion (simple version for repair)
# ============================================================
function ConvertTo-WslPathSimple {
    param([string]$Path)
    if (-not $Path) { return $Path }
    if ($Path -match '^([A-Za-z]):[\\/](.*)$') {
        $drive = $Matches[1].ToLower()
        $rest = $Matches[2] -replace '\\', '/'
        return "/mnt/$drive/$rest"
    }
    if ($Path -match '^\\\\[wW][sS][lL]\.[^.]+?\\([^^]+)\\(.*)$') {
        return "/$($Matches[2] -replace '\\', '/')"
    }
    if ($Path -match '\\') { return ($Path -replace '\\', '/') }
    return $Path
}

# ============================================================
# Status summary
# ============================================================
function Show-Status {
    Require-Config
    Write-Host ""
    Write-Host "FlutterWrapper Status" -ForegroundColor Cyan
    Write-Host ('=' * 30) -ForegroundColor Cyan
    Write-Host ""

    Write-Host "  WSL:        $($config.wsl.distro)" -ForegroundColor White
    Write-Host "  Flutter:    $($config.flutter.executable)" -ForegroundColor White
    Write-Host "  Dart:       $($config.dart.executable)" -ForegroundColor White
    if ($config.java.home) {
        Write-Host "  JAVA_HOME:  $($config.java.home)" -ForegroundColor White
    } else {
        Write-Host "  JAVA_HOME:  (not set)" -ForegroundColor Yellow
    }
    if ($config.workspace.mappedDrive) {
        Write-Host "  Drive:      $($config.workspace.mappedDrive): -> $($config.workspace.uncPrefix)" -ForegroundColor White
    }
    Write-Host ""

    # Quick health check
    if ($distro) {
        $quick = & wsl.exe -d $distro -e bash -lc "test -f $($config.flutter.executable) && echo OK || echo MISSING" 2>$null
        if (($quick -join '').Trim() -eq 'OK') {
            Write-Host "  Status: Ready" -ForegroundColor Green
        } else {
            Write-Host "  Status: Flutter binary not found in WSL" -ForegroundColor Red
        }
    }
    Write-Host "  Run 'fw doctor' for full diagnostic" -ForegroundColor Gray
    Write-Host ""
}

# ============================================================
# Version
# ============================================================
function Show-Version {
    $verFile = Join-Path $rootDir 'VERSION'
    $ver = if (Test-Path $verFile) { (Get-Content $verFile -Raw).Trim() } else { '3.0.0' }
    Write-Host "FlutterWrapper v$ver" -ForegroundColor Cyan
    Write-Host "Compatibility Orchestration Layer for Windows AS + WSL Flutter" -ForegroundColor Gray
    if ($config) {
        Write-Host "Config: $configPath"
        Write-Host "Distro: $($config.wsl.distro)"
        $fv = $config.flutter.executable
        if ($fv) { Write-Host "Flutter: $fv" }
    }
}

# ============================================================
# Flutter helpers (proxy to provider)
# ============================================================
function Invoke-FlutterCurrent {
    Require-Config
    $winCwd = (Get-Location).Path
    
    # 1. Check project-level config first
    $fvmrc = Join-Path $winCwd '.fvmrc'
    $vfoxToml = Join-Path $winCwd '.vfox.toml'
    
    if (Test-Path $fvmrc) {
        $fvmContent = Get-Content $fvmrc -Raw -Encoding UTF8
        if ($fvmContent -match '"flutter"\s*:\s*"([^"]+)"' -or $fvmContent -match '"flutterSdkVersion"\s*:\s*"([^"]+)"') {
            Write-Host "Flutter $($Matches[1]) (FVM, project .fvmrc)" -ForegroundColor Green
        } else {
            Write-Host "FVM project (.fvmrc found, version auto-detected)" -ForegroundColor Green
        }
        return
    }
    if (Test-Path $vfoxToml) {
        $tomlContent = Get-Content $vfoxToml -Raw -Encoding UTF8
        if ($tomlContent -match 'flutter\s*=\s*"([^"]+)"') {
            Write-Host "Flutter $($Matches[1]) (vfox, project .vfox.toml)" -ForegroundColor Green
        } else {
            Write-Host "vfox project (.vfox.toml found)" -ForegroundColor Green
        }
        return
    }
    
    # 2. Try vfox global
    $vfoxExe = Get-Command vfox -ErrorAction SilentlyContinue
    if ($vfoxExe) {
        $out = & vfox current flutter 2>$null
        if ($LASTEXITCODE -eq 0 -and $out) {
            Write-Host ($out -join "`n")
            return
        }
    }
    
    # 3. Try FVM global
    if ($distro) {
        try {
            $fvmGlobal = & wsl.exe -d $distro -e bash -lc 'fvm flutter --version 2>/dev/null | head -1 || fvm list 2>/dev/null | grep -m1 "^[*✓]" | sed "s/[*✓] //;s/ .*//" || true' 2>$null
            $fvmGlobal = ($fvmGlobal -join '').Trim()
            if ($fvmGlobal) {
                Write-Host "Flutter $fvmGlobal (FVM, global)" -ForegroundColor Green
                return
            }
        } catch {}
    }
    
    # 4. Fallback: read from wrapper.yaml
    if ($config.flutter.executable) {
        Write-Host "Flutter (manual/config): $($config.flutter.executable)" -ForegroundColor Yellow
    } else {
        Write-Err "No Flutter SDK configured"
    }
}

function Invoke-FlutterUse {
    param([string]$Version)
    if (-not $Version) {
        Write-Err "Usage: fw flutter use <version>"
        Write-Host "  Example: fw flutter use 3.44.6" -ForegroundColor Gray
        exit 1
    }
    Require-Config
    $winCwd = (Get-Location).Path
    
    # 1. Project-level: .fvmrc → fvm use (project)
    if (Test-Path (Join-Path $winCwd '.fvmrc')) {
        if ($distro) {
            Write-Host "Routing to FVM: fvm use $Version (project .fvmrc)" -ForegroundColor Cyan
            & wsl.exe -d $distro --cd (ConvertTo-WslPathSimple $winCwd) -e bash -lc "fvm use $Version"
            if ($LASTEXITCODE -eq 0) {
                Write-OK "Switched project to Flutter $Version (via FVM)"
                return
            }
        }
    }
    
    # 2. Project-level: .vfox.toml → vfox use -p
    if (Test-Path (Join-Path $winCwd '.vfox.toml')) {
        $vfoxExe = Get-Command vfox -ErrorAction SilentlyContinue
        if ($vfoxExe) {
            Write-Host "Routing to vfox: vfox use -p flutter@$Version (project .vfox.toml)" -ForegroundColor Cyan
            & vfox use -p flutter@$Version
            if ($LASTEXITCODE -eq 0) {
                Write-OK "Switched project to Flutter $Version (via vfox)"
                return
            }
        }
    }
    
    # 3. Global: try vfox first, then FVM
    $vfoxExe = Get-Command vfox -ErrorAction SilentlyContinue
    if ($vfoxExe) {
        Write-Host "Routing to vfox: vfox use -g flutter@$Version" -ForegroundColor Cyan
        & vfox use -g flutter@$Version
        if ($LASTEXITCODE -eq 0) {
            Write-OK "Switched global Flutter to $Version (via vfox)"
            Write-Host "  Note: Restart Android Studio for Dart plugin to pick up the change." -ForegroundColor Yellow
            return
        }
    }
    
    # 4. Global FVM
    if ($distro) {
        Write-Host "Routing to FVM: fvm global $Version" -ForegroundColor Cyan
        & wsl.exe -d $distro -e bash -lc "fvm global $Version"
        if ($LASTEXITCODE -eq 0) {
            Write-OK "Switched global Flutter to $Version (via FVM)"
            return
        }
    }
    
    Write-Err "No SDK provider found. Install vfox or FVM in WSL."
}

# ============================================================
# Main router
# ============================================================
if ($args.Count -eq 0) {
    Write-Host "FlutterWrapper v3 — Compatibility Orchestration Layer" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage: fw <command> [options]" -ForegroundColor White
    Write-Host ""
    Write-Host "Commands:" -ForegroundColor Cyan
    Write-Host "  doctor              Full diagnostic check"
    Write-Host "  doctor --fix-safe   Auto-repair safe items only"
    Write-Host "  doctor --json       Machine-readable output"
    Write-Host "  doctor --quick      Fast check (skip version checks)"
    Write-Host "  repair <module>     Repair a specific component"
    Write-Host "  repair --list       List available repair modules"
    Write-Host "  provider            Show detected SDK providers (vfox/FVM/manual)"
    Write-Host "  flutter current     Show current Flutter version"
    Write-Host "  flutter use <ver>   Switch Flutter version (routes to vfox)"
    Write-Host "  status              Quick environment summary"
    Write-Host "  version             Show FlutterWrapper version"
    exit 0
}

$cmd = $args[0].ToLower()
$rest = $args[1..($args.Length - 1)]

switch ($cmd) {
    'doctor' {
        $doctorPath = Join-Path $scriptDir 'doctor.ps1'
        if (Test-Path $doctorPath) {
            & powershell -NoProfile -ExecutionPolicy Bypass -File $doctorPath @rest
            exit $LASTEXITCODE
        } else {
            Write-Err "doctor.ps1 not found at $doctorPath"
            exit 1
        }
    }

    'repair' {
        if ($rest.Count -eq 0 -or $rest[0] -eq '--list') {
            Write-Host "Available repair modules:" -ForegroundColor Cyan
            Write-Host ('─' * 50) -ForegroundColor Cyan
            foreach ($mod in $repairModules.GetEnumerator() | Sort-Object Name) {
                Write-Host "  $($mod.Name)" -ForegroundColor White -NoNewline
                Write-Host (" " * (20 - $mod.Name.Length)) -NoNewline
                Write-Host $mod.Value -ForegroundColor Gray
            }
            Write-Host ""
            Write-Host "Usage: fw repair <module>" -ForegroundColor Gray
            exit 0
        }
        $module = $rest[0].ToLower()
        if (-not $repairModules.ContainsKey($module)) {
            Write-Err "Unknown repair module: '$module'"
            Write-Host "  Run 'fw repair --list' to see available modules" -ForegroundColor Yellow
            exit 1
        }
        Write-Host ""; Write-Host "FlutterWrapper Repair" -ForegroundColor Cyan; Write-Host ('=' * 30) -ForegroundColor Cyan
        switch ($module) {
            'package-config' { Repair-PackageConfig }
            'dart-sdk'       { Repair-DartSdk }
            'symlinks'       { Repair-Symlinks }
            'config'         { Repair-Config }
            'vfox'           { Repair-Vfox }
            'daemon'         { Repair-Daemon }
            'cache'          { Repair-Cache }
        }
        Write-Host ""
    }

    'provider' {
        Detect-Provider
    }

    'flutter' {
        if ($rest.Count -eq 0) {
            Write-Err "Usage: fw flutter <current|use>"
            exit 1
        }
        $sub = $rest[0].ToLower()
        switch ($sub) {
            'current' { Invoke-FlutterCurrent }
            'use'     { Invoke-FlutterUse -Version $rest[1] }
            default   { Write-Err "Unknown: fw flutter $sub"; Write-Host "  Available: current, use" -ForegroundColor Gray }
        }
    }

    'status' {
        Show-Status
    }

    'version' {
        Show-Version
    }

    'setup' {
        Write-Step "Running setup (install.ps1 -Auto)"
        $installPath = Join-Path $rootDir 'install.ps1'
        if (-not (Test-Path $installPath)) {
            Write-Err "install.ps1 not found"
            exit 1
        }
        & powershell -NoProfile -ExecutionPolicy Bypass -File $installPath -Auto @rest
        exit $LASTEXITCODE
    }

    default {
        Write-Err "Unknown command: '$cmd'"
        Write-Host "  Run 'fw' without arguments to see available commands" -ForegroundColor Yellow
        exit 1
    }
}
