# repair.ps1 - FlutterWrapper repair engine (v3.1)
#
# Dot-sourced by fw.ps1. Each function is idempotent — safe to run multiple times.
# Requires: $config, $distro, $rootDir (set by caller).

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
    if (Test-Path $pkgConfig) {
        try {
            $bytes = [System.IO.File]::ReadAllBytes($pkgConfig)
            if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
                $bytes = $bytes[3..($bytes.Length - 1)]
            }
            $content = [System.Text.Encoding]::UTF8.GetString($bytes)
            $mappedDrive = if ($config.workspace.mappedDrive) { $config.workspace.mappedDrive.ToLower() } else { 'w' }
            $translated = $content -replace 'file:///(?!/wsl\.|/W:/|/w:/)', "file:///$($mappedDrive):/"
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($pkgConfig, $translated, $utf8NoBom)
            Write-OK "package_config.json translated to $($mappedDrive): form"
        } catch {
            Write-Err "Failed to translate: $($_.Exception.Message)"
        }
    } else {
        Write-Warn "No package_config.json found after pub get"
    }
}

function Repair-DartSdk {
    Write-Step "Repairing dart-sdk Junction"
    $dartSdkLink = Join-Path $rootDir 'bin\cache\dart-sdk'
    $cacheDir = Split-Path -Parent $dartSdkLink
    if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
    if (Test-Path $dartSdkLink) {
        $existing = Get-Item $dartSdkLink -Force -ErrorAction SilentlyContinue
        if ($existing -and $existing.LinkType -ne 'Junction') {
            Remove-Item $dartSdkLink -Force -Recurse -ErrorAction SilentlyContinue
        } elseif ($existing) {
            Write-OK "Junction already exists: $($existing.Target)"
            return
        }
    }
    $vfoxDartSdk = Join-Path $env:USERPROFILE 'vfox-global\flutter\bin\cache\dart-sdk'
    $stdDartSdk = 'C:\flutter\bin\cache\dart-sdk'
    $target = if (Test-Path $vfoxDartSdk) { $vfoxDartSdk } elseif (Test-Path $stdDartSdk) { $stdDartSdk } else { $null }
    if ($target) {
        cmd /c mklink /J "$dartSdkLink" "$target" 2>&1 | Out-Null
        if (Test-Path $dartSdkLink) { Write-OK "Created Junction: $dartSdkLink -> $target" }
        else { Write-Err "Failed to create Junction (try running as Administrator)" }
    } else {
        Write-Err "No Windows-side dart-sdk found (vfox-global not set up?)"
    }
}

function Repair-Symlinks {
    Require-Config
    Write-Step "Repairing WSL path symlinks"
    $symlinkScript = Join-Path $rootDir 'tools\setup-wsl-symlink.sh'
    if (-not (Test-Path $symlinkScript)) { Write-Err "setup-wsl-symlink.sh not found"; return }
    $sDrive = $symlinkScript.Substring(0,1).ToLower()
    $sRest = $symlinkScript.Substring(2) -replace '\\', '/'
    $wslScript = "/mnt/$sDrive$sRest"
    $symDrive = if ($config.workspace.mappedDrive) { $config.workspace.mappedDrive } else { 'W' }
    Write-Host "    Running: bash $wslScript $distro $symDrive (may need sudo)"
    & wsl.exe -d $distro -e bash -c "sudo bash $wslScript $distro $symDrive 2>&1"
    if ($LASTEXITCODE -eq 0) { Write-OK "WSL symlinks repaired" }
    else { Write-Warn "Script returned non-zero. Run manually: wsl -e sudo bash $wslScript $distro $symDrive" }
}

function Repair-Config {
    Write-Step "Repairing config"
    Require-Config
    $installPath = Join-Path $rootDir 'install.ps1'
    if (-not (Test-Path $installPath)) { Write-Err "install.ps1 not found"; return }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $installPath -Auto -SkipSmoke -Distro $distro
    if ($LASTEXITCODE -eq 0) { Write-OK "Configuration regenerated" }
    else { Write-Err "install.ps1 failed (exit=$LASTEXITCODE)" }
}

function Repair-Vfox {
    Write-Step "Repairing vfox global Junction workaround"
    $vfoxGlobal = Join-Path $env:USERPROFILE 'vfox-global'
    if (-not (Test-Path $vfoxGlobal)) { New-Item -ItemType Directory -Path $vfoxGlobal -Force | Out-Null }
    foreach ($sdk in @('flutter', 'nodejs', 'java')) {
        $junctionPath = Join-Path $vfoxGlobal $sdk
        $targetPath = Join-Path $env:USERPROFILE ".version-fox\sdks\$sdk"
        if (-not (Test-Path $targetPath)) { continue }
        if (Test-Path $junctionPath) {
            $existing = Get-Item $junctionPath -Force -ErrorAction SilentlyContinue
            if ($existing.LinkType -eq 'Junction') { Write-OK "vfox-global/$sdk Junction OK"; continue }
        }
        try {
            Remove-Item $junctionPath -Force -Recurse -ErrorAction SilentlyContinue
            New-Item -ItemType Junction -Path $junctionPath -Target $targetPath -Force | Out-Null
            Write-OK "Created Junction: $junctionPath -> $targetPath"
        } catch { Write-Warn "Failed for $sdk`: $($_.Exception.Message)" }
    }
}

function Repair-Daemon {
    Require-Config
    Write-Step "Repairing daemon (killing stale processes)"
    $port = if ($config.daemon.tcpPort) { $config.daemon.tcpPort } else { '9876' }
    try { & wsl.exe -d $distro -e bash -lc "fuser -k $port/tcp 2>&1 || true" 2>$null } catch {}
    Write-OK "Daemon port $port cleaned"
}

function Repair-Cache {
    Write-Step "Cleaning build caches"
    $winCwd = (Get-Location).Path
    foreach ($dir in @('.dart_tool', '.cxx', 'build')) {
        $fullPath = Join-Path $winCwd $dir
        if (Test-Path $fullPath) {
            try { Remove-Item $fullPath -Force -Recurse -ErrorAction Stop; Write-OK "Removed $dir/" }
            catch { Write-Warn "Could not remove $dir/: $($_.Exception.Message)" }
        } else { Write-Host "    $dir/ not present (skip)" }
    }
}
