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
# ============================================================
# v3.1 modular engine (dot-sourced)
# ============================================================
. "$PSScriptRoot/../lib/repair.ps1"
. "$PSScriptRoot/../lib/provider.ps1"

# Simple WSL path conversion (used by repair)
function ConvertTo-WslPathSimple {
    param([string]$Path)
    if (-not $Path) { return $Path }
    if ($Path -match '^([A-Za-z]):[\\/](.*)$') {
        return "/mnt/$($Matches[1].ToLower())/$($Matches[2] -replace '\\', '/')"
    }
    if ($Path -match '^\\\\[wW][sS][lL]\.[^.]+?\\([^^]+)\\(.*)$') {
        return "/$($Matches[2] -replace '\\', '/')"
    }
    if ($Path -match '\\') { return ($Path -replace '\\', '/') }
    return $Path
}

function Show-Version {
    $ver = Get-WrapperVersion $rootDir
    Write-Host "FlutterWrapper v$ver" -ForegroundColor Cyan
    Write-Host "Compatibility Orchestration Layer for Windows AS + WSL Flutter" -ForegroundColor Gray
    if ($config) { Write-Host "Distro: $($config.wsl.distro)"; if ($config.flutter.executable) { Write-Host "Flutter: $($config.flutter.executable)" } }
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
