# check-env.ps1 — Checks 1-3: Config, WSL, Flutter/Dart SDK
# Dot-sourced by doctor.ps1. Uses script-scope variables.

Write-Section "1. Configuration"

$script:config = Read-WrapperConfigSafe $configPath
if (-not $config) {
    Write-Check 'Config file' 'FAIL' "Not found at $configPath" "Run install.ps1 to generate"
    exit 1
}
Write-Check 'Config file' 'PASS' "Found"

$script:distro = $config.wsl.distro
$script:flutterExe = $config.flutter.executable
$script:dartExe = $config.dart.executable
$script:uncPrefix = $config.workspace.uncPrefix
$script:driveMount = $config.workspace.driveMount
$script:mappedDrive = $config.workspace.mappedDrive
if (-not $driveMount) { $script:driveMount = '/mnt' }
if ($mappedDrive -and $mappedDrive -match '^([A-Za-z]):') { $script:mappedDrive = $Matches[1].ToUpper() }

$missing = @()
if (-not $distro) { $missing += 'wsl.distro' }
if (-not $flutterExe) { $missing += 'flutter.executable' }
if (-not $dartExe) { $missing += 'dart.executable' }
if ($missing) { Write-Check 'Required fields' 'FAIL' "Missing: $($missing -join ', ')" "Edit config or re-run install.ps1" }
else { Write-Check 'Required fields' 'PASS' "All present" }

Write-Section "2. WSL Bridge"

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Write-Check 'wsl.exe' 'FAIL' "Not found" "Install WSL2: wsl --install"
} else {
    Write-Check 'wsl.exe' 'PASS' "Available"
    try {
        $raw = & wsl.exe --list --quiet 2>$null
        $distros = @()
        foreach ($l in $raw) { $c = ($l -replace "`0", '').Trim(); if ($c -and $c -match '^[A-Za-z0-9._-]+$') { $distros += $c } }
        if ($distros -contains $distro) {
            Write-Check "WSL distro ($distro)" 'PASS' "Running"
            $other = $distros | Where-Object { $_ -ne $distro }
            if ($other) { Write-Check '  Other distros' 'SKIP' "$($other -join ', ') — edit config to switch" }
        } else { Write-Check "WSL distro ($distro)" 'FAIL' "Not installed. Available: $($distros -join ', ')" "wsl --install -d $distro" }
    } catch { Write-Check "WSL distro ($distro)" 'FAIL' "Cannot list: $($_.Exception.Message)" "Check WSL installation" }
}
if (-not $quick -and $distro) {
    try {
        $vr = & wsl.exe -l -v 2>$null
        if (($vr -join "`n") -match "^\s*\S+\s+Running\s+2") { Write-Check 'WSL version' 'PASS' "WSL2 running" }
        else { Write-Check 'WSL version' 'WARN' "Not confirmed WSL2" "wsl --set-version $distro 2" }
    } catch { Write-Check 'WSL version' 'SKIP' "Cannot determine" }
}

Write-Section "3. Flutter & Dart SDK (WSL)"

if (-not $distro -or -not $flutterExe) {
    Write-Check 'Flutter SDK' 'SKIP' "WSL or config missing"
} else {
    try {
        $fc = & wsl.exe -d $distro -e bash -lc "test -f `"$flutterExe`" && echo OK || echo MISSING" 2>$null
        if (($fc -join '').Trim() -eq 'OK') {
            Write-Check "Flutter binary" 'PASS' $flutterExe
            if (-not $quick) {
                try { $fv = & wsl.exe -d $distro -e $flutterExe --version 2>$null | Select -First 1
                    Write-Check 'Flutter version' 'PASS' ($fv -replace '\s+',' ') } catch { Write-Check 'Flutter version' 'WARN' "Cannot determine" }
            }
        } else { Write-Check "Flutter binary" 'FAIL' "Not found at $flutterExe" "Install Flutter in WSL or update config" }
    } catch { Write-Check "Flutter binary" 'FAIL' "Cannot check: $($_.Exception.Message)" "Verify WSL distro is running" }
}
if (-not $distro -or -not $dartExe) {
    Write-Check 'Dart SDK' 'SKIP' "WSL or config missing"
} else {
    try {
        $dc = & wsl.exe -d $distro -e bash -lc "test -f `"$dartExe`" && echo OK || echo MISSING" 2>$null
        if (($dc -join '').Trim() -eq 'OK') {
            Write-Check "Dart binary" 'PASS' $dartExe
            if (-not $quick) {
                try { $dv = & wsl.exe -d $distro -e $dartExe --version 2>$null | Select -First 1
                    Write-Check 'Dart version' 'PASS' ($dv -replace '\s+',' ') } catch { Write-Check 'Dart version' 'WARN' "Cannot determine" }
            }
        } else { Write-Check "Dart binary" 'FAIL' "Not found at $dartExe" "Update config: dart.executable" }
    } catch { Write-Check "Dart binary" 'FAIL' "Cannot check: $($_.Exception.Message)" "Verify WSL distro is running" }
}
