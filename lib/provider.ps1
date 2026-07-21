# provider.ps1 - FlutterWrapper SDK provider detection & helpers (v3.1)
#
# Dot-sourced by fw.ps1. Detects vfox/FVM/manual SDK providers,
# provides fw flutter current/use routing, and status summary.
# Requires: $config, $distro, $rootDir, $configPath (set by caller).

function Detect-Provider {
    Require-Config
    Write-Host ""
    Write-Host "Detected providers:" -ForegroundColor Cyan
    Write-Host ('─' * 30) -ForegroundColor Cyan

    # vfox
    $vfoxExe = Get-Command vfox -ErrorAction SilentlyContinue
    if ($vfoxExe) {
        $vfoxCurrent = $null
        try { $vfoxCurrent = (& vfox current flutter 2>$null | Select-String 'flutter' | Select-Object -First 1) -replace '\s+', ' ' } catch {}
        Write-Host "  ✓ vfox" -ForegroundColor Green
        if ($vfoxCurrent) { Write-Host "    $vfoxCurrent" -ForegroundColor Gray }
        $jPath = Join-Path $env:USERPROFILE 'vfox-global\flutter'
        if (Test-Path $jPath) { Write-Host "    Junction workaround: active" -ForegroundColor Green }
        else { Write-Host "    Junction workaround: missing (run: fw repair vfox)" -ForegroundColor Yellow }
    } else { Write-Host "  ✗ vfox" -ForegroundColor DarkGray }

    # FVM
    if ($distro) {
        $fvmFound = $false; $fvmVersionsList = @()
        try { $fvmDefault = & wsl.exe -d $distro -e bash -lc "test -f ~/fvm/default/bin/flutter && echo 'default' || true" 2>$null; if ($fvmDefault.Trim()) { $fvmFound = $true; $fvmVersionsList += 'default' } } catch {}
        try { $fvmVerDirs = & wsl.exe -d $distro -e bash -lc 'ls -1d ~/.fvm/versions/*/bin/flutter 2>/dev/null | sed "s|/bin/flutter||;s|.*/||" || true' 2>$null
            if ($fvmVerDirs) { foreach ($v in $fvmVerDirs) { if ($v.Trim()) { $fvmFound = $true; $fvmVersionsList += $v.Trim() } } }
        } catch {}
        if ($fvmFound) {
            Write-Host "  ✓ FVM" -ForegroundColor Green
            Write-Host "    Versions: $($fvmVersionsList -join ', ')" -ForegroundColor Gray
            try { $fvmGlobalVer = & wsl.exe -d $distro -e bash -lc 'fvm global 2>/dev/null || fvm list 2>/dev/null | grep -m1 "^[✓*]" | sed "s/[✓*] //;s/ .*//" || true' 2>$null
                if (($fvmGlobalVer -join '').Trim()) { Write-Host "    Global: $($fvmGlobalVer -join '').Trim()" -ForegroundColor Gray } } catch {}
        } else { Write-Host "  ✗ FVM" -ForegroundColor DarkGray }
    }

    # Manual
    if ($config.flutter.executable -and $config.flutter.executable -notmatch 'vfox|fvm') {
        Write-Host "  ✓ Manual SDK" -ForegroundColor Green
        Write-Host "    Path: $($config.flutter.executable)" -ForegroundColor Gray
    }
    Write-Host ""
}

function Invoke-FlutterCurrent {
    Require-Config
    $winCwd = (Get-Location).Path
    $fvmrc = Join-Path $winCwd '.fvmrc'
    $vfoxToml = Join-Path $winCwd '.vfox.toml'

    # 1. Project-level config first
    if (Test-Path $fvmrc) {
        $c = Get-Content $fvmrc -Raw -Encoding UTF8
        if ($c -match '"flutter"\s*:\s*"([^"]+)"' -or $c -match '"flutterSdkVersion"\s*:\s*"([^"]+)"') {
            Write-Host "Flutter $($Matches[1]) (FVM, project .fvmrc)" -ForegroundColor Green
        } else { Write-Host "FVM project (.fvmrc found)" -ForegroundColor Green }
        return
    }
    if (Test-Path $vfoxToml) {
        $c = Get-Content $vfoxToml -Raw -Encoding UTF8
        if ($c -match 'flutter\s*=\s*"([^"]+)"') { Write-Host "Flutter $($Matches[1]) (vfox, project .vfox.toml)" -ForegroundColor Green }
        else { Write-Host "vfox project (.vfox.toml found)" -ForegroundColor Green }
        return
    }
    # 2. vfox global
    $vfoxExe = Get-Command vfox -ErrorAction SilentlyContinue
    if ($vfoxExe) { $out = & vfox current flutter 2>$null; if ($LASTEXITCODE -eq 0 -and $out) { Write-Host ($out -join "`n"); return } }
    # 3. FVM global
    if ($distro) {
        try { $fvmGlobal = & wsl.exe -d $distro -e bash -lc 'fvm flutter --version 2>/dev/null | head -1 || fvm list 2>/dev/null | grep -m1 "^[*✓]" | sed "s/[*✓] //;s/ .*//" || true' 2>$null
            if (($fvmGlobal -join '').Trim()) { Write-Host "Flutter $($fvmGlobal -join '').Trim() (FVM, global)" -ForegroundColor Green; return } } catch {}
    }
    # 4. Fallback
    if ($config.flutter.executable) { Write-Host "Flutter (manual): $($config.flutter.executable)" -ForegroundColor Yellow }
    else { Write-Err "No Flutter SDK configured" }
}

function Invoke-FlutterUse {
    param([string]$Version)
    if (-not $Version) { Write-Err "Usage: fw flutter use <version>"; exit 1 }
    Require-Config
    $winCwd = (Get-Location).Path
    # Project-level routing
    if (Test-Path (Join-Path $winCwd '.fvmrc') -and $distro) {
        & wsl.exe -d $distro --cd (ConvertTo-WslPathSimple $winCwd) -e bash -lc "fvm use $Version"
        if ($LASTEXITCODE -eq 0) { Write-OK "Switched project to Flutter $Version (via FVM)"; return }
    }
    if (Test-Path (Join-Path $winCwd '.vfox.toml')) {
        $v = Get-Command vfox -ErrorAction SilentlyContinue
        if ($v) { & vfox use -p flutter@$Version; if ($LASTEXITCODE -eq 0) { Write-OK "Switched project to Flutter $Version (via vfox)"; return } }
    }
    # Global routing
    $vfoxExe = Get-Command vfox -ErrorAction SilentlyContinue
    if ($vfoxExe) { & vfox use -g flutter@$Version; if ($LASTEXITCODE -eq 0) { Write-OK "Switched global Flutter to $Version (via vfox)"; return } }
    if ($distro) { & wsl.exe -d $distro -e bash -lc "fvm global $Version"; if ($LASTEXITCODE -eq 0) { Write-OK "Switched global Flutter to $Version (via FVM)"; return } }
    Write-Err "No SDK provider found. Install vfox or FVM in WSL."
}

function Show-Status {
    Require-Config
    Write-Host ""
    Write-Host "FlutterWrapper Status" -ForegroundColor Cyan
    Write-Host ('=' * 30) -ForegroundColor Cyan; Write-Host ""
    Write-Host "  WSL:        $($config.wsl.distro)"
    Write-Host "  Flutter:    $($config.flutter.executable)"
    Write-Host "  Dart:       $($config.dart.executable)"
    $jh = if ($config.java.home) { $config.java.home } else { '(not set)' }
    Write-Host "  JAVA_HOME:  $jh"
    if ($config.workspace.mappedDrive) { Write-Host "  Drive:      $($config.workspace.mappedDrive): -> $($config.workspace.uncPrefix)" }
    Write-Host ""
    if ($distro) {
        $quick = & wsl.exe -d $distro -e bash -lc "test -f $($config.flutter.executable) && echo OK || echo MISSING" 2>$null
        if (($quick -join '').Trim() -eq 'OK') { Write-Host "  Status: Ready" -ForegroundColor Green }
        else { Write-Host "  Status: Flutter binary not found in WSL" -ForegroundColor Red }
    }
    Write-Host ""
}
