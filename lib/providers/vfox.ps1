# providers/vfox.ps1 — vfox SDK provider (v3.1)
# Dot-sourced by lib/provider.ps1. Uses: $config, $distro

function Write-ProviderVfox {
    $vfoxExe = Get-Command vfox -ErrorAction SilentlyContinue
    if ($vfoxExe) {
        $vfoxCurrent = $null
        try { $vfoxCurrent = (& vfox current flutter 2>$null | Select-String 'flutter' | Select-Object -First 1) -replace '\s+', ' ' } catch {}
        Write-Host "  ✓ vfox" -ForegroundColor Green
        if ($vfoxCurrent) { Write-Host "    $vfoxCurrent" -ForegroundColor Gray }
        $jPath = Join-Path $env:USERPROFILE 'vfox-global\flutter'
        if (Test-Path $jPath) { Write-Host "    Junction workaround: active" -ForegroundColor Green }
        else { Write-Host "    Junction workaround: missing (run: fw repair vfox)" -ForegroundColor Yellow }
        return $true
    } else {
        Write-Host "  ✗ vfox" -ForegroundColor DarkGray
        return $false
    }
}

function Get-VfoxCurrent {
    $vfoxExe = Get-Command vfox -ErrorAction SilentlyContinue
    if ($vfoxExe) {
        $out = & vfox current flutter 2>$null
        if ($LASTEXITCODE -eq 0 -and $out) { return ($out -join "`n") }
    }
    return $null
}

function Set-VfoxGlobalVersion {
    param([string]$Version)
    $vfoxExe = Get-Command vfox -ErrorAction SilentlyContinue
    if ($vfoxExe) {
        if ((Get-Location).Path | Join-Path -ChildPath '.vfox.toml' | Test-Path) { & vfox use -p flutter@$Version }
        else { & vfox use -g flutter@$Version }
        return ($LASTEXITCODE -eq 0)
    }
    return $false
}
