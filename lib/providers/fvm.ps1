# providers/fvm.ps1 — FVM SDK provider (v3.1)
# Dot-sourced by lib/provider.ps1. Uses: $config, $distro

function Write-ProviderFvm {
    if (-not $distro) { Write-Host "  ✗ FVM" -ForegroundColor DarkGray; return $false }
    $fvmFound = $false; $fvmVersionsList = @()
    try { $fd = & wsl.exe -d $distro -e bash -lc "test -f ~/fvm/default/bin/flutter && echo 'default' || true" 2>$null; if ($fd.Trim()) { $fvmFound = $true; $fvmVersionsList += 'default' } } catch {}
    try { $fv = & wsl.exe -d $distro -e bash -lc 'ls -1d ~/.fvm/versions/*/bin/flutter 2>/dev/null | sed "s|/bin/flutter||;s|.*/||" || true' 2>$null
        if ($fv) { foreach ($v in $fv) { if ($v.Trim()) { $fvmFound = $true; $fvmVersionsList += $v.Trim() } } }
    } catch {}
    if ($fvmFound) {
        Write-Host "  ✓ FVM" -ForegroundColor Green
        Write-Host "    Versions: $($fvmVersionsList -join ', ')" -ForegroundColor Gray
        try { $fg = & wsl.exe -d $distro -e bash -lc 'fvm global 2>/dev/null || fvm list 2>/dev/null | grep -m1 "^[✓*]" | sed "s/[✓*] //;s/ .*//" || true' 2>$null
            if (($fg -join '').Trim()) { Write-Host "    Global: $($fg -join '').Trim()" -ForegroundColor Gray } } catch {}
        return $true
    } else { Write-Host "  ✗ FVM" -ForegroundColor DarkGray; return $false }
}

function Get-FvmCurrent {
    if (-not $distro) { return $null }
    try {
        $fvmGlobal = & wsl.exe -d $distro -e bash -lc 'fvm flutter --version 2>/dev/null | head -1 || fvm list 2>/dev/null | grep -m1 "^[*✓]" | sed "s/[*✓] //;s/ .*//" || true' 2>$null
        $v = ($fvmGlobal -join '').Trim()
        if ($v) { return "Flutter $v (FVM, global)" }
    } catch {}
    return $null
}

function Set-FvmVersion {
    param([string]$Version)
    if (-not $distro) { return $false }
    $winCwd = (Get-Location).Path
    if (Test-Path (Join-Path $winCwd '.fvmrc')) {
        & wsl.exe -d $distro --cd (ConvertTo-WslPathSimple $winCwd) -e bash -lc "fvm use $Version"
    } else {
        & wsl.exe -d $distro -e bash -lc "fvm global $Version"
    }
    return ($LASTEXITCODE -eq 0)
}
