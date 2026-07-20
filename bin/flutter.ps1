# flutter.ps1 - FlutterWrapper business logic
#
# Reads config/wrapper.yaml, converts cwd + args to WSL form,
# then invokes WSL flutter with inherited stdin/stdout/stderr.
#
# Phase 4: plain command forwarding (no daemon translation).
# Phase 6 will add wrapper.ps1 for daemon byte-stream translation.

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# --- Resolve script + project paths ---
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir   = Split-Path -Parent $scriptDir
$configPath = Join-Path $rootDir 'config\wrapper.yaml'
$logPath    = Join-Path $rootDir 'logs\wrapper.log'

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

    # Mapped drive (e.g. W: -> \\wsl.localhost\<distro>): W:\home\user -> /home/user
    # This handles the case where AS opens a project via a drive letter mapped
    # to a WSL UNC path (net use W: \\wsl.localhost\<distro>). CMD doesn't support
    # UNC as cwd, so users must map a drive letter first.
    if ($script:MappedDrive -and $Path -match "^$($script:MappedDrive):[\\/](.*)$") {
        $rest = $Matches[1] -replace '\\', '/'
        if ($rest) { return "/$rest" } else { return "/" }
    }
    if ($script:MappedDrive -and $Path -match "^$($script:MappedDrive):$") {
        return "/"
    }

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
    # (WSL convention; e.g. lib\main.dart -> lib/main.dart). Without this,
    # flutter inside WSL sees "lib\main.dart" as a single filename and reports
    # "Target file not found".
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

$distro     = $config.wsl.distro
$flutterExe = $config.flutter.executable
$script:DriveMount = $config.workspace.driveMount
if (-not $script:DriveMount) { $script:DriveMount = '/mnt' }
$script:MappedDrive = $config.workspace.mappedDrive
if ($script:MappedDrive -and $script:MappedDrive -match '^([A-Za-z]):') {
    $script:MappedDrive = $Matches[1].ToUpper()
}

if (-not $distro -or -not $flutterExe) {
    Write-Error "FlutterWrapper: config missing 'wsl.distro' or 'flutter.executable'"
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
$wslArgs = @('-d', $distro, '--cd', $wslCwd, '-e', $flutterExe) + $convertedArgs

# Detect daemon mode: needs byte-stream translation (Phase 6).
# `flutter daemon` and `flutter daemon <args>` both go through wrapper.ps1.
$isDaemon = $false
foreach ($a in $args) {
    if ($a -eq 'daemon') { $isDaemon = $true; break }
    # Stop scanning at first non-option (the subcommand position).
    # Actually daemon is the subcommand itself; just check if any arg equals 'daemon'.
}

if ($isDaemon) {
    # Delegate to wrapper.ps1 which handles daemon byte-stream translation.
    # Pass original (pre-translation) args + cwd via wrapper's own logic;
    # wrapper.ps1 re-reads config and does its own path conversion.
    $wrapperPath = Join-Path $scriptDir 'wrapper.ps1'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $wrapperPath
    $exitCode = $LASTEXITCODE
} else {
    # Plain command: forward directly (UTF-8 safe, wsl.exe inherits console IO).
    & wsl.exe @wslArgs
    $exitCode = $LASTEXITCODE
}

# Log
$elapsed = ((Get-Date) - $startTime).TotalMilliseconds
Write-Log "exit=$exitCode ${elapsed}ms cwd=$winCwd -> $wslCwd cmd=flutter $rawArgs"

exit $exitCode
