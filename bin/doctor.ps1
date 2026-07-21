# doctor.ps1 - FlutterWrapper diagnostic tool (v3.1)
#
# Checks all components of the Windows-AS + WSL-Flutter bridge.
# Check logic lives in lib/doctor/check-*.ps1 (dot-sourced).
#
# Usage:
#   fw doctor              Full diagnostic check
#   fw doctor --fix-safe   Auto-repair safe items
#   fw doctor --json       Machine-readable output
#   fw doctor --quick      Fast check (skip version checks)
#   fw doctor --collect    Generate flutterwrapper-report.zip

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir   = Split-Path -Parent $scriptDir
$configPath = Join-Path $rootDir 'config\wrapper.yaml'

$quick = $args -contains '-quick' -or $args -contains '-q'
$jsonOut = $args -contains '-json' -or $args -contains '-j'
$fixSafe = $args -contains '--fix-safe'
$collect = $args -contains '--collect'

# Shared lib
. "$scriptDir/../lib/config.ps1"

# Output
$results = @()
$script:issueCount = 0
$script:warnCount = 0

function Write-Check {
    param([string]$Name, [string]$Status, [string]$Detail, [string]$Fix)
    $icon = switch ($Status) { 'PASS' { '[v]' } 'FAIL' { '[x]' } 'WARN' { '[!]' } 'SKIP' { '[?]' } }
    if ($jsonOut) { $results += @{ name=$Name; status=$Status; detail=$Detail; fix=$Fix } }
    else {
        $color = switch ($Status) { 'PASS' { 'Green' } 'FAIL' { 'Red' } 'WARN' { 'Yellow' } 'SKIP' { 'Gray' } }
        Write-Host "  $icon $Name" -NoNewline
        if ($Detail) { Write-Host ": $Detail" -NoNewline -ForegroundColor $color }
        if ($Fix -and $Status -eq 'FAIL') { Write-Host "  -> $Fix" -NoNewline -ForegroundColor Yellow }
        Write-Host ""
    }
    if ($Status -eq 'FAIL') { $script:issueCount++ }
    if ($Status -eq 'WARN') { $script:warnCount++ }
}
function Write-Section { param($t) if (-not $jsonOut) { Write-Host ""; Write-Host $t -ForegroundColor Cyan; Write-Host ('-' * $t.Length) -ForegroundColor Cyan } }

# Dynamic WSL user detection
$wslUser = $null; $wslHome = '/home/user'
try {
    $cfg = Read-WrapperConfigSafe $configPath
    if ($cfg -and $cfg.wsl.distro) {
        $u = (& wsl.exe -d $($cfg.wsl.distro) -e bash -lc 'whoami' 2>$null).Trim()
        if ($u) { $wslUser = $u; $wslHome = "/home/$u" }
    }
} catch {}

# Path conversion (used by check-paths)
function ConvertTo-WslPath { param([string]$Path, [string]$DriveMount, [string]$UncPrefix, [string]$MappedDrive)
    if (-not $Path) { return $Path }
    if ($MappedDrive -and $Path -match "^$($MappedDrive):[\\/](.*)$") { $r=$Matches[1] -replace '\\','/'; return if($r){"/$r"}else{'/'} }
    if ($MappedDrive -and $Path -match "^$($MappedDrive):$") { return '/' }
    if ($Path -match '^\\\\[wW][sS][lL]\.(?:[lL][oO][cC][aA][lL][hH][oO][sS][tT])\\([^\\]+)\\(.*)$') { $r=$Matches[2] -replace '\\','/'; return if($r){"/$r"}else{'/'} }
    if ($Path -match '^\\\\[wW][sS][lL]\.(?:[lL][oO][cC][aA][lL][hH][oO][sS][tT])\\([^\\]+)$') { return '/' }
    if ($Path -match '^\\\\[wW][sS][lL]\$\\([^\\]+)\\(.*)$') { $r=$Matches[2] -replace '\\','/'; return if($r){"/$r"}else{'/'} }
    if ($Path -match '^\\\\[wW][sS][lL]\$\\([^\\]+)$') { return '/' }
    if ($Path -match '^([A-Za-z]):[\\/](.*)$') { $d=$Matches[1].ToLower();$r=$Matches[2] -replace '\\','/'; return if($r){"$DriveMount/$d/$r"}else{"$DriveMount/$d/"} }
    if ($Path -match '\\') { return ($Path -replace '\\', '/') }
    return $Path
}

# ============================================================
# v3.1: Dot-source check modules from lib/doctor/
# ============================================================
. "$scriptDir/../lib/doctor/check-env.ps1"
. "$scriptDir/../lib/doctor/check-paths.ps1"
. "$scriptDir/../lib/doctor/check-tools.ps1"
. "$scriptDir/../lib/doctor/check-project.ps1"

# ============================================================
# Summary
# ============================================================
Write-Section "Summary"

if ($jsonOut) {
    $output = @{ results=$results; summary=@{ passed=($results|?{$_.status -eq 'PASS'}).Count; failed=$issueCount; warnings=$warnCount; total=$results.Count } }
    Write-Host (ConvertTo-Json -InputObject $output -Depth 3 -Compress)
} else {
    Write-Host ""
    $passed = ($results | Where-Object { $_.status -eq 'PASS' }).Count
    Write-Host "  Checks: $passed passed, $issueCount failed, $warnCount warnings" -ForegroundColor Cyan
    if ($issueCount -eq 0 -and $warnCount -eq 0) { Write-Host ""; Write-Host "  All checks passed! FlutterWrapper is ready." -ForegroundColor Green }
    elseif ($issueCount -gt 0) { Write-Host ""; Write-Host "  $issueCount issue(s) need attention." -ForegroundColor Red }
    else { Write-Host ""; Write-Host "  All passed with $warnCount warning(s)." -ForegroundColor Yellow }
}

# ============================================================
# --fix-safe: auto-repair safe items
# ============================================================
if ($fixSafe -and $issueCount -gt 0) {
    Write-Host ""; Write-Host "--fix-safe: Repairing safe items..." -ForegroundColor Cyan
    $dsFail = $results | Where-Object { $_.name -eq 'dart-sdk Junction' -and $_.status -eq 'FAIL' }
    if ($dsFail) {
        Write-Host "  Repairing: dart-sdk Junction..."
        $lnk = Join-Path $rootDir 'bin\cache\dart-sdk'
        $tgt = Join-Path $env:USERPROFILE 'vfox-global\flutter\bin\cache\dart-sdk'
        if (Test-Path $tgt) {
            if (Test-Path $lnk) { Remove-Item $lnk -Force -Recurse -ErrorAction SilentlyContinue }
            $cd = Split-Path -Parent $lnk; if (-not (Test-Path $cd)) { New-Item -ItemType Directory -Path $cd -Force | Out-Null }
            cmd /c mklink /J "$lnk" "$tgt" 2>&1 | Out-Null
            if (Test-Path $lnk) { Write-Host "    [OK] Junction re-created" -ForegroundColor Green }
        }
    }
    $vfxJunction = Join-Path $env:USERPROFILE 'vfox-global\flutter'
    if (-not (Test-Path $vfxJunction)) {
        Write-Host "  Repairing: vfox global Junction..."
        $vfxTgt = Join-Path $env:USERPROFILE '.version-fox\sdks\flutter'
        if (Test-Path $vfxTgt) {
            $vd = Join-Path $env:USERPROFILE 'vfox-global'; if (-not (Test-Path $vd)) { New-Item -ItemType Directory -Path $vd -Force | Out-Null }
            New-Item -ItemType Junction -Path $vfxJunction -Target $vfxTgt -Force | Out-Null
            if (Test-Path $vfxJunction) { Write-Host "    [OK] Junction created" -ForegroundColor Green }
        }
    }
    $symFail = $results | Where-Object { $_.status -eq 'FAIL' -and $_.name -match '/w:|/W:|/blaze-out' }
    if ($symFail) {
        Write-Host "  Repairing: WSL symlinks..."
        $ss = Join-Path $rootDir 'tools\setup-wsl-symlink.sh'
        if (Test-Path $ss) {
            $sd = $ss.Substring(0,1).ToLower(); $sr = $ss.Substring(2) -replace '\\','/'; $ws = "/mnt/$sd$sr"
            $md = if ($config.workspace.mappedDrive) { $config.workspace.mappedDrive } else { 'W' }
            if ($distro) { & wsl.exe -d $distro -e bash -c "sudo bash $ws $distro $md 2>&1"; if ($LASTEXITCODE -eq 0) { Write-Host "    [OK] Repaired" -ForegroundColor Green } }
        }
    }
    Write-Host ""; Write-Host "  Re-run 'fw doctor' to verify." -ForegroundColor Gray
}

# ============================================================
# --collect: generate diagnostic report zip
# ============================================================
if ($collect) {
    Write-Host ""; Write-Host "Generating diagnostic report..." -ForegroundColor Cyan
    $tmpDir = Join-Path $env:TEMP "flutterwrapper-report"
    if (Test-Path $tmpDir) { Remove-Item $tmpDir -Force -Recurse -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    $output = @{ results=$results; summary=@{ passed=($results|?{$_.status -eq 'PASS'}).Count; failed=$issueCount; warnings=$warnCount; total=$results.Count } }
    (ConvertTo-Json -InputObject $output -Depth 3) | Out-File -FilePath (Join-Path $tmpDir 'doctor.json') -Encoding UTF8
    if ($config) { $sc = $config.Clone(); if ($sc.flutter) { $sc.flutter.executable='[REDACTED]' }; if ($sc.dart) { $sc.dart.executable='[REDACTED]' }; if ($sc.java) { $sc.java.home='[REDACTED]' }; ($sc|ConvertTo-Json -Depth 3) | Out-File -FilePath (Join-Path $tmpDir 'config.json') -Encoding UTF8 }
    foreach ($ln in @('flutter','dart','bridge')) {
        $lf = Join-Path $rootDir "logs\$ln.log"
        if (Test-Path $lf) { (Get-Content $lf -Tail 100) -replace '/home/\w+/','/home/<user>/' -replace 'cwd=[A-Za-z]:[^ ]+','cwd=[REDACTED]' | Out-File -FilePath (Join-Path $tmpDir "$ln.log") -Encoding UTF8 }
    }
    @"
Windows: $([Environment]::OSVersion.VersionString)
WSL Distro: $distro
Flutter: $($config.flutter.executable)
Config: $configPath
"@ | Out-File -FilePath (Join-Path $tmpDir 'environment.txt') -Encoding UTF8
    $zipPath = Join-Path (Get-Location).Path 'flutterwrapper-report.zip'
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($tmpDir, $zipPath)
    Remove-Item $tmpDir -Force -Recurse -ErrorAction SilentlyContinue
    Write-OK "Report saved: $zipPath"
}

exit $issueCount
