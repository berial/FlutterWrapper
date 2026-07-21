# check-project.ps1 — Checks 12-13: Smoke Test, Project Config (.vfox.toml/.fvmrc)
# Dot-sourced by doctor.ps1. Uses script-scope variables.

Write-Section "12. Smoke Test"
if (-not $quick -and $distro -and $flutterExe) {
    try {
        Write-Host "  Running: flutter doctor (quiet)..."
        $smoke = & wsl.exe -d $distro --cd $wslHome -e $flutterExe doctor 2>&1
        $sl = $smoke | Where-Object { $_ -match '^\[[✓✗!?]\]' }
        $ok = ($sl | Where-Object { $_ -match '^\[✓\]' }).Count
        $fail = ($sl | Where-Object { $_ -match '^\[✗\]' }).Count
        if ($fail -eq 0) { Write-Check 'WSL flutter doctor' 'PASS' "$ok checks passed" }
        else { Write-Check 'WSL flutter doctor' 'WARN' "$ok passed, $fail failed"
            if (-not $jsonOut) { foreach ($l in $sl) { Write-Host "    $l" -ForegroundColor DarkGray } }
        }
    } catch { Write-Check 'WSL flutter doctor' 'FAIL' $_.Exception.Message "" }
} else { Write-Check 'WSL flutter doctor' 'SKIP' "Quick mode or config missing" }

Write-Section "13. Project Config (vfox/FVM)"
$winCwd = (Get-Location).Path
$vfoxToml = Join-Path $winCwd '.vfox.toml'
$fvmrc = Join-Path $winCwd '.fvmrc'
$projectVer = $null; $fvmVer = $null

if (Test-Path $vfoxToml) {
    Write-Check '.vfox.toml' 'PASS' "Found in project"
    try {
        $tc = Get-Content $vfoxToml -Raw -Encoding UTF8
        if ($tc -match 'flutter\s*=\s*"([^"]+)"') {
            $projectVer = $Matches[1]
            try { $vl = & vfox list flutter 2>$null; if (($vl -join "`n") -match [regex]::Escape($projectVer)) { $vi = $true } else { $vi = $false } } catch { $vi = $false }
            if ($vi) { Write-Check "  Flutter $projectVer" 'PASS' "Installed via vfox" }
            else { Write-Check "  Flutter $projectVer" 'WARN' "Not installed" "vfox install flutter@$projectVer" }
        } else { Write-Check '  Flutter version' 'WARN' "Could not parse" }
    } catch { Write-Check '.vfox.toml' 'WARN' "Parse error: $($_.Exception.Message)" }
} else { Write-Check '.vfox.toml' 'SKIP' "Not found" }

if (Test-Path $fvmrc) {
    Write-Check '.fvmrc' 'PASS' "Found in project"
    try {
        $fc = Get-Content $fvmrc -Raw -Encoding UTF8
        if ($fc -match '"flutter"\s*:\s*"([^"]+)"' -or $fc -match '"flutterSdkVersion"\s*:\s*"([^"]+)"') {
            $fvmVer = $Matches[1]
            try { $fi = & wsl.exe -d $distro -e bash -lc "test -d ~/.fvm/versions/$fvmVer && echo OK || echo MISSING" 2>$null; $fi = ($fi -join '').Trim() -eq 'OK' } catch { $fi = $false }
            if ($fi) { Write-Check "  Flutter $fvmVer" 'PASS' "Installed via FVM" }
            else { Write-Check "  Flutter $fvmVer" 'WARN' "Not installed" "fvm install $fvmVer" }
        } else { Write-Check '  Flutter version' 'WARN' "Could not parse" }
    } catch { Write-Check '.fvmrc' 'WARN' "Parse error: $($_.Exception.Message)" }
} else { Write-Check '.fvmrc' 'SKIP' "Not found" }

# Version consistency
if ((Test-Path $vfoxToml) -or (Test-Path $fvmrc)) {
    if ($flutterExe -and $distro) {
        try {
            $av = & wsl.exe -d $distro -e $flutterExe --version 2>$null | Select-Object -First 1
            if ($av -match 'Flutter\s+([\d.]+)') {
                $actualVer = $Matches[1]
                $declared = if ($projectVer) { $projectVer } else { $fvmVer }
                if ($declared -and $actualVer -ne $declared) { Write-Check '  Version consistency' 'WARN' "Project: $declared, wrapper: $actualVer" "fw flutter use $declared" }
                elseif ($declared) { Write-Check '  Version consistency' 'PASS' "Wrapper Flutter $actualVer matches project" }
            }
        } catch {}
    }
}
