# provider.ps1 - FlutterWrapper SDK provider facade (v3.1)
#
# Dot-sourced by fw.ps1. Dispatches to lib/providers/vfox.ps1 and fvm.ps1.
# Also provides Detect-Provider, Invoke-FlutterCurrent, Invoke-FlutterUse, Show-Status.
# Requires: $config, $distro, $rootDir, $configPath (set by fw.ps1).

. "$PSScriptRoot/providers/vfox.ps1"
. "$PSScriptRoot/providers/fvm.ps1"

function Detect-Provider {
    Require-Config
    Write-Host ""
    Write-Host "Detected providers:" -ForegroundColor Cyan
    Write-Host ('-' * 30) -ForegroundColor Cyan
    $vf = Write-ProviderVfox
    $fv = Write-ProviderFvm
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
    $vf = Get-VfoxCurrent; if ($vf) { Write-Host $vf; return }
    # 3. FVM global
    $fv = Get-FvmCurrent; if ($fv) { Write-Host $fv; return }
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
    if ((Test-Path (Join-Path $winCwd '.fvmrc')) -and (Set-FvmVersion $Version)) { Write-OK "Switched project to Flutter $Version (via FVM)"; return }
    if ((Test-Path (Join-Path $winCwd '.vfox.toml')) -and (Set-VfoxGlobalVersion $Version)) { Write-OK "Switched project to Flutter $Version (via vfox)"; return }
    # Global routing
    if (Set-VfoxGlobalVersion $Version) { Write-OK "Switched global Flutter to $Version (via vfox)"; Write-Host "  Note: Restart Android Studio for Dart plugin to pick up the change." -ForegroundColor Yellow; return }
    if (Set-FvmVersion $Version) { Write-OK "Switched global Flutter to $Version (via FVM)"; return }
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
    Write-Host "  JAVA_HOME:  $(if($config.java.home){$config.java.home}else{'(not set)'})"
    if ($config.workspace.mappedDrive) { Write-Host "  Drive:      $($config.workspace.mappedDrive): -> $($config.workspace.uncPrefix)" }
    Write-Host ""
    if ($distro) {
        $q = & wsl.exe -d $distro -e bash -lc "test -f $($config.flutter.executable) && echo OK || echo MISSING" 2>$null
        if (($q -join '').Trim() -eq 'OK') { Write-Host "  Status: Ready" -ForegroundColor Green }
        else { Write-Host "  Status: Flutter binary not found in WSL" -ForegroundColor Red }
    }
    Write-Host ""
}
