# dart.ps1 - FlutterWrapper Dart entry point
#
# Mirrors flutter.ps1 but invokes the Dart executable instead of Flutter.
# Android Studio Flutter plugin never calls <sdk>/bin/dart.bat directly
# (it uses bin/cache/dart-sdk/bin/dart.exe for the analysis server;
# see docs/flutter-plugin.md section 5.4). This wrapper only serves users
# or tools that explicitly invoke <sdk>/bin/dart.bat.
#
# Keep in sync with flutter.ps1; the only differences are:
#   - reads config.dart.executable instead of config.flutter.executable
#   - logs cmd=dart instead of cmd=flutter

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# --- Resolve script + project paths ---
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir   = Split-Path -Parent $scriptDir
$configPath = Join-Path $rootDir 'config\wrapper.yaml'
$logPath    = Join-Path $rootDir 'logs\dart.log'

# ============================================================
# Minimal YAML parser (supports 2-level nesting, key: value only)
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
        # Strip trailing comments (but keep # inside quoted values - simple version)
        $stripped = $line -replace '\s+#.*$', ''
        if ($stripped -match '^\s*$') { continue }
        # Top-level key: value  OR  top-level key: (starts a section)
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
        # Nested key: value (indented 2+ spaces)
        elseif ($stripped -match '^\s+([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$' -and $currentSection) {
            $key = $Matches[1]
            $val = $Matches[2].Trim().Trim('"').Trim("'")
            $config[$currentSection][$key] = $val
        }
    }
    return $config
}

# ============================================================
# Path conversion (from Phase 3, validated 40/40 PASS)
# Pure string rules, no wslpath call.
# ============================================================
function ConvertTo-WslPath {
    param([string]$Path)
    if (-not $Path) { return $Path }

    # UNC \\wsl.localhost\<distro>\<rest>
    if ($Path -match '^\\\\[wW][sS][lL]\.(?:[lL][oO][cC][aA][lL][hH][oO][sS][tT])\\([^\\]+)\\(.*)$') {
        $rest = $Matches[2] -replace '\\', '/'
        if ($rest) { return "/$rest" } else { return "/" }
    }
    if ($Path -match '^\\\\[wW][sS][lL]\.(?:[lL][oO][cC][aA][lL][hH][oO][sS][tT])\\([^\\]+)$') {
        return "/"
    }
    # UNC \\wsl$\<distro>\<rest>
    if ($Path -match '^\\\\[wW][sS][lL]\$\\([^\\]+)\\(.*)$') {
        $rest = $Matches[2] -replace '\\', '/'
        if ($rest) { return "/$rest" } else { return "/" }
    }
    if ($Path -match '^\\\\[wW][sS][lL]\$\\([^\\]+)$') {
        return "/"
    }
    # Drive-letter path: D:\path  or  D:/path
    if ($Path -match '^([A-Za-z]):[\\/](.*)$') {
        $drive = $Matches[1].ToLower()
        $rest  = $Matches[2] -replace '\\', '/'
        if ($rest) { return "$script:DriveMount/$drive/$rest" }
        else       { return "$script:DriveMount/$drive/" }
    }
    # Relative path or anything else: convert backslashes to forward slashes
    # (WSL convention; e.g. lib\main.dart -> lib/main.dart).
    if ($Path -match '\\') {
        return ($Path -replace '\\', '/')
    }
    return $Path
}

function Convert-ArgPath {
    param([string]$Arg)
    # Split --key=value, only convert the value part
    if ($Arg -match '^(-{1,2}[^=]+)=(.*)$') {
        $key   = $Matches[1]
        $value = $Matches[2]
        $conv  = ConvertTo-WslPath $value
        return "${key}=${conv}"
    }
    return ConvertTo-WslPath $Arg
}

# ============================================================
# Logging (minimal, Phase 8 will formalize)
# ============================================================
function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] $Message"
    try {
        $logDir = Split-Path -Parent $logPath
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        Add-Content -Path $logPath -Value $line -Encoding UTF8
    } catch {
        # Logging must never break the command
    }
}

# ============================================================
# Main
# ============================================================
$startTime = Get-Date
$rawArgs = $args -join ' '

try {
    $config = Read-WrapperConfig $configPath
} catch {
    Write-Error $_.Exception.Message
    exit 1
}

$distro  = $config.wsl.distro
$dartExe = $config.dart.executable
$script:DriveMount = $config.workspace.driveMount
if (-not $script:DriveMount) { $script:DriveMount = '/mnt' }

if (-not $distro -or -not $dartExe) {
    Write-Error "FlutterWrapper: config missing 'wsl.distro' or 'dart.executable'"
    exit 1
}

# Convert cwd (Windows -> WSL)
$winCwd = (Get-Location).Path
$wslCwd = ConvertTo-WslPath $winCwd

# Convert args (scan for path-like values)
$convertedArgs = @()
foreach ($a in $args) {
    $convertedArgs += (Convert-ArgPath $a)
}

# Build wsl.exe argument list
$wslArgs = @('-d', $distro, '--cd', $wslCwd, '-e', $dartExe) + $convertedArgs

# Execute (inherit stdin/stdout/stderr - UTF-8 safe, no PS string pipe)
& wsl.exe @wslArgs
$exitCode = $LASTEXITCODE

# Log
$elapsed = ((Get-Date) - $startTime).TotalMilliseconds
Write-Log "exit=$exitCode ${elapsed}ms cwd=$winCwd -> $wslCwd cmd=dart $rawArgs"

exit $exitCode
