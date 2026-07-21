# config.ps1 - FlutterWrapper shared config & output helpers
#
# Dot-sourced by all scripts that need config parsing or colored output.
# Usage: . "$PSScriptRoot/../lib/config.ps1"   (from bin/ scripts)
#        . "$PSScriptRoot/lib/config.ps1"       (from root scripts)

# ============================================================
# YAML config parser (supports 2-level nesting, key: value only)
# ============================================================
function Read-WrapperConfig {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        throw "FlutterWrapper: config file not found: $Path"
    }
    $config = @{}
    $currentSection = $null
    # Force UTF-8: PS 5.1 defaults to system codepage (GBK on zh-CN),
    # which corrupts UTF-8 multi-byte chars and can eat newlines adjacent
    # to Chinese characters, merging comment lines with key:value lines.
    foreach ($line in Get-Content -Path $Path -Encoding UTF8) {
        $stripped = $line -replace '\s+#.*$', ''
        if ($stripped -match '^\s*$') { continue }
        if ($stripped -match '^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$') {
            $key = $Matches[1]
            $val = $Matches[2].Trim()
            if ($val) {
                $config[$key] = $val.Trim('"').Trim("'")
            } else {
                $currentSection = $key
                $config[$key] = @{}
            }
        }
        elseif ($stripped -match '^\s+([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$' -and $currentSection) {
            $key = $Matches[1]
            $val = $Matches[2].Trim().Trim('"').Trim("'")
            $config[$currentSection][$key] = $val
        }
    }
    return $config
}

# Non-throwing variant for diagnostic scripts (returns $null if not found)
function Read-WrapperConfigSafe {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    try { return Read-WrapperConfig $Path } catch { return $null }
}

# ============================================================
# Colored output helpers
# ============================================================
function Write-Step  { param($m) Write-Host ("==> " + $m) -ForegroundColor Cyan }
function Write-OK    { param($m) Write-Host ("    OK  " + $m) -ForegroundColor Green }
function Write-Warn  { param($m) Write-Host ("    WARN " + $m) -ForegroundColor Yellow }
function Write-Err   { param($m) Write-Host ("    FAIL " + $m) -ForegroundColor Red }

# ============================================================
# Require config (shared guard)
# ============================================================
function Require-Config {
    param([string]$ConfigPath)
    if (-not $config) {
        Write-Err "Config not found: $ConfigPath"
        Write-Host "  Run: fw setup  or  install.ps1" -ForegroundColor Yellow
        exit 1
    }
}

# ============================================================
# Version detection
# ============================================================
function Get-WrapperVersion {
    param([string]$RootDir)
    $verFile = Join-Path $RootDir 'VERSION'
    if (Test-Path $verFile) {
        return (Get-Content $verFile -Raw).Trim()
    }
    return '3.0.0'
}
