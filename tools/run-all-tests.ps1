# run-all-tests.ps1 - FlutterWrapper automated test matrix (Phase 9)
#
# Runs all automatable tests and prints a summary matrix.
# Manual tests (Run/Hot Reload/Debug/Build) are listed but skipped.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-all-tests.ps1

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$rootDir = Split-Path -Parent $PSScriptRoot
$toolsDir = $PSScriptRoot

# Test results: @{ name; status; detail }
$results = @()

function Add-Result {
    param([string]$Name, [string]$Status, [string]$Detail = '')
    $script:results += [PSCustomObject]@{
        Name = $Name; Status = $Status; Detail = $Detail
    }
    $color = if ($Status -eq 'PASS') { 'Green' }
             elseif ($Status -eq 'FAIL') { 'Red' }
             elseif ($Status -eq 'SKIP') { 'Yellow' }
             else { 'Gray' }
    Write-Host ("  [{0}] {1} {2}" -f $Status, $Name, $Detail) -ForegroundColor $color
}

function Run-Test {
    param([string]$Name, [scriptblock]$Block)
    try {
        $output = & $Block
        Add-Result $Name 'PASS' $output
    } catch {
        Add-Result $Name 'FAIL' $_.Exception.Message
    }
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  FlutterWrapper Test Matrix" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# 1. SDK structure detection
# ============================================================
Write-Host "[1] SDK Structure Detection" -ForegroundColor Cyan

Run-Test 'bin/flutter.bat' {
    if (Test-Path (Join-Path $rootDir 'bin\flutter.bat')) { 'exists' } else { throw 'missing' }
}
Run-Test 'bin/flutter.ps1' {
    if (Test-Path (Join-Path $rootDir 'bin\flutter.ps1')) { 'exists' } else { throw 'missing' }
}
Run-Test 'bin/dart.bat' {
    if (Test-Path (Join-Path $rootDir 'bin\dart.bat')) { 'exists' } else { throw 'missing' }
}
Run-Test 'bin/dart.ps1' {
    if (Test-Path (Join-Path $rootDir 'bin\dart.ps1')) { 'exists' } else { throw 'missing' }
}
Run-Test 'bin/wrapper.ps1' {
    if (Test-Path (Join-Path $rootDir 'bin\wrapper.ps1')) { 'exists' } else { throw 'missing' }
}
Run-Test 'bin/cache/dart-sdk' {
    $p = Join-Path $rootDir 'bin\cache\dart-sdk'
    if (Test-Path $p) {
        $item = Get-Item $p -Force
        if ($item.LinkType -eq 'Junction') { "Junction -> $($item.Target)" } else { 'exists (not Junction)' }
    } else { throw 'missing' }
}
Run-Test 'bin/cache/flutter.version.json' {
    $p = Join-Path $rootDir 'bin\cache\flutter.version.json'
    if (Test-Path $p) {
        $v = (Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json).frameworkVersion
        "v$v"
    } else { throw 'missing' }
}
Run-Test 'packages/flutter/pubspec.yaml' {
    $p = Join-Path $rootDir 'packages\flutter\pubspec.yaml'
    if (Test-Path $p) { 'exists' } else { throw 'missing' }
}
Run-Test 'config/wrapper.yaml' {
    $p = Join-Path $rootDir 'config\wrapper.yaml'
    if (Test-Path $p) { 'exists' } else { throw 'missing' }
}

# ============================================================
# 2. Path conversion
# ============================================================
Write-Host ""
Write-Host "[2] Path Conversion (Phase 3)" -ForegroundColor Cyan

$pathTest = Join-Path $toolsDir 'path-convert-test.ps1'
Run-Test 'path-convert-test.ps1' {
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $pathTest
    $lastLine = ($out | Select-Object -Last 1).Trim()
    if ($LASTEXITCODE -eq 0) { $lastLine } else { throw "exit=$LASTEXITCODE $lastLine" }
}

# ============================================================
# 3. Plain command forwarding
# ============================================================
Write-Host ""
Write-Host "[3] Plain Command Forwarding" -ForegroundColor Cyan

$flutterBat = Join-Path $rootDir 'bin\flutter.bat'
$dartBat = Join-Path $rootDir 'bin\dart.bat'

Run-Test 'flutter --version' {
    $out = & cmd /c "$flutterBat --version 2>&1"
    if ($LASTEXITCODE -eq 0) {
        (($out | Out-String).Trim() -split "`n")[0].Trim()
    } else { throw "exit=$LASTEXITCODE" }
}
Run-Test 'flutter --version --machine' {
    $out = & cmd /c "$flutterBat --version --machine 2>&1"
    if ($LASTEXITCODE -eq 0) {
        $v = ($out | Out-String).Trim() | ConvertFrom-Json
        "frameworkVersion=$($v.frameworkVersion)"
    } else { throw "exit=$LASTEXITCODE" }
}
Run-Test 'flutter devices' {
    $out = & cmd /c "$flutterBat devices 2>&1"
    if ($LASTEXITCODE -eq 0) {
        $lines = ($out | Out-String).Trim() -split "`n"
        "first line: " + $lines[0].Trim()
    } else { throw "exit=$LASTEXITCODE" }
}
Run-Test 'dart --version' {
    $out = & cmd /c "$dartBat --version 2>&1"
    if ($LASTEXITCODE -eq 0) {
        (($out | Out-String).Trim() -split "`n")[0].Trim()
    } else { throw "exit=$LASTEXITCODE" }
}

# ============================================================
# 4. Daemon mode (TCP + path translation)
# ============================================================
Write-Host ""
Write-Host "[4] Daemon Mode (TCP + Translation)" -ForegroundColor Cyan

# Kill any leftover wsl.exe first
try { & taskkill /F /IM wsl.exe /T 2>$null | Out-Null } catch {}

Run-Test 'daemon.connected + daemon.version' {
    $t = Join-Path $toolsDir 'daemon-test.ps1'
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $t
    if ($LASTEXITCODE -eq 0) {
        $lastLine = ($out | Select-Object -Last 1).Trim()
        $lastLine
    } else { throw "exit=$LASTEXITCODE" }
}

try { & taskkill /F /IM wsl.exe /T 2>$null | Out-Null } catch {}

Run-Test 'daemon.getSupportedPlatforms path translation' {
    $t = Join-Path $toolsDir 'daemon-platforms-test.ps1'
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $t
    if ($LASTEXITCODE -eq 0) {
        $lastLine = ($out | Select-Object -Last 1).Trim()
        $lastLine
    } else { throw "exit=$LASTEXITCODE" }
}

try { & taskkill /F /IM wsl.exe /T 2>$null | Out-Null } catch {}

# ============================================================
# 5. Pub Get (in test project)
# ============================================================
Write-Host ""
Write-Host "[5] Pub Get" -ForegroundColor Cyan

$testProject = Join-Path $rootDir 'cache\wrapper_test'
Run-Test 'flutter pub get (wrapper_test)' {
    if (-not (Test-Path (Join-Path $testProject 'pubspec.yaml'))) {
        throw "test project not found: $testProject"
    }
    Push-Location $testProject
    try {
        $out = & cmd /c "$flutterBat pub get 2>&1" | Select-Object -Last 3
        if ($LASTEXITCODE -eq 0) { ($out | Out-String).Trim() } else { throw "exit=$LASTEXITCODE" }
    } finally {
        Pop-Location
    }
}

# ============================================================
# 6. Manual tests (require device/emulator, skip)
# ============================================================
Write-Host ""
Write-Host "[6] Manual Tests (require device/emulator - SKIP)" -ForegroundColor Cyan

Add-Result 'flutter run'         'SKIP' 'requires running device/emulator'
Add-Result 'Hot Reload'          'SKIP' 'requires running app'
Add-Result 'Debug (dart attach)' 'SKIP' 'requires debugger + device'
Add-Result 'flutter build apk'   'SKIP' 'requires Android SDK (slow)'
Add-Result 'flutter build web'   'SKIP' 'slow'
Add-Result 'flutter test'        'SKIP' 'requires test project setup'

# ============================================================
# Summary
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Summary" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$pass = ($results | Where-Object Status -eq 'PASS').Count
$fail = ($results | Where-Object Status -eq 'FAIL').Count
$skip = ($results | Where-Object Status -eq 'SKIP').Count
$total = $results.Count

Write-Host ("  Total: {0}    PASS: {1}    FAIL: {2}    SKIP: {3}" -f $total, $pass, $fail, $skip)
Write-Host ""

if ($fail -gt 0) {
    Write-Host "  Failed tests:" -ForegroundColor Red
    $results | Where-Object Status -eq 'FAIL' | ForEach-Object {
        Write-Host ("    - {0}: {1}" -f $_.Name, $_.Detail) -ForegroundColor Red
    }
    exit 1
} else {
    Write-Host "  All automated tests PASS" -ForegroundColor Green
    exit 0
}
