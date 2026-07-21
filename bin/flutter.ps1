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
$logPath    = Join-Path $rootDir 'logs\flutter.log'

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
$script:UncPrefix = $config.workspace.uncPrefix
$script:MappedDrive = $config.workspace.mappedDrive
if ($script:MappedDrive -and $script:MappedDrive -match '^([A-Za-z]):') {
    $script:MappedDrive = $Matches[1].ToUpper()
}

# Resolve Android SDK path for WSL (so flutter can find adb.exe on Windows side).
# This points to the WINDOWS SDK (build-tools have Linux shell wrappers that
# call .exe via WSL interop; platform-tools/adb.exe likewise). The WSL-local
# SDK (config.android.wslSdkPath) is only used for NDK + cmake, see below.
# Precedence: config.android.sdkPath > $env:ANDROID_HOME > $env:ANDROID_SDK_ROOT
# > default D:\Android\Sdk
$winAndroidSdk = $config.android.sdkPath
if (-not $winAndroidSdk) { $winAndroidSdk = $env:ANDROID_HOME }
if (-not $winAndroidSdk) { $winAndroidSdk = $env:ANDROID_SDK_ROOT }
if (-not $winAndroidSdk -and (Test-Path 'D:\Android\Sdk')) { $winAndroidSdk = 'D:\Android\Sdk' }
$wslAndroidSdk = if ($winAndroidSdk) { ConvertTo-WslPath $winAndroidSdk } else { $null }

# Resolve WSL-local NDK path (for AGP NdkHandler).
# Windows NDK has only windows-x86_64 toolchain (.exe); WSL Linux gradle/cmake
# cannot execute .exe. We inject ANDROID_NDK_HOME/ROOT so AGP finds the Linux
# NDK. local.properties ndk.dir is also set by tools/fix-local-properties.sh
# (higher priority than env vars).
# AGP's NdkHandler lookup order:
#   1. android.ndkPath (build.gradle)
#   2. ndk.dir (local.properties, deprecated but honored)
#   3. $ANDROID_NDK_HOME / $ANDROID_NDK_ROOT env vars
#   4. $sdk.dir/ndk/<version> (if android.ndkVersion set)
#   5. $sdk.dir/ndk/<highest> (default)
# Access WSL filesystem via UNC path (Test-Path on /home/... is unreliable).
$wslNdkPath = $null
$wslSdkLocal = $config.android.wslSdkPath
if ($wslSdkLocal) {
    $uncSdk = $script:UncPrefix + ($wslSdkLocal -replace '/', '\')
    $uncNdkRoot = Join-Path $uncSdk 'ndk'
    if (Test-Path $uncNdkRoot) {
        $ndkVer = Get-ChildItem $uncNdkRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1
        if ($ndkVer) {
            $wslNdkPath = $wslSdkLocal + '/ndk/' + $ndkVer.Name
        }
    }
}

# Resolve JAVA_HOME for WSL (wsl.exe drops Windows env vars; gradle needs JDK)
$wslJavaHome = $config.java.home
if (-not $wslJavaHome) { $wslJavaHome = $env:JAVA_HOME }
if ($wslJavaHome -and $wslJavaHome -match '^([A-Za-z]:[\\/])') {
    $wslJavaHome = ConvertTo-WslPath $wslJavaHome
}

# Resolve CHROME_EXECUTABLE for WSL (flutter web device discovery)
$wslChrome = $config.chrome.executable
if (-not $wslChrome) { $wslChrome = $env:CHROME_EXECUTABLE }
if ($wslChrome -and $wslChrome -match '^([A-Za-z]:[\\/])') {
    $wslChrome = ConvertTo-WslPath $wslChrome
}

# Resolve PUB_CACHE for WSL (flutter pub / dart pub package cache).
# wsl.exe -e bypasses the shell, so .zshrc exports are invisible.
$wslPubCache = $config.pub.cache
if (-not $wslPubCache) { $wslPubCache = $env:PUB_CACHE }
if ($wslPubCache -and $wslPubCache -match '^([A-Za-z]:[\\/])') {
    $wslPubCache = ConvertTo-WslPath $wslPubCache
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
}

# Detect pub get: needs post-run package_config.json translation so Windows
# Dart analyzer (using Windows-side dart-sdk via Junction) can resolve packages.
$isPubGet = $false
for ($i = 0; $i -lt $args.Count; $i++) {
    if ($args[$i] -eq 'pub' -and $i + 1 -lt $args.Count -and $args[$i+1] -eq 'get') {
        $isPubGet = $true; break
    }
}

# package_config.json format strategy:
#   With the /wsl.localhost/<distro> -> / symlink (created by
#   tools/setup-wsl-symlink.sh), WSL Dart resolves Windows UNC URIs
#   (file://///wsl.localhost/<distro>/...) to real WSL paths via the symlink.
#   So a single Windows-UNC-format package_config.json works for BOTH:
#     - AS Dart analyzer on Windows (reads UNC directly)
#     - WSL flutter compiler (reads UNC via symlink)
#   No more swap/restore. Long-running commands (flutter run) no longer risk
#   leaving package_config.json in WSL format when killed.
#
#   After `flutter pub get`, we translate the freshly-generated WSL-format
#   file to Windows UNC format (strip BOM too — Dart's JSON parser fails
#   on BOM, see docs/troubleshooting-history.md §4.1).
$pkgConfigPath = Join-Path $winCwd '.dart_tool\package_config.json'

if ($isDaemon) {
    # Delegate to wrapper.ps1 which handles daemon byte-stream translation.
    $wrapperPath = Join-Path $scriptDir 'wrapper.ps1'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $wrapperPath
    $exitCode = $LASTEXITCODE
} else {
    # Plain command: forward directly. Use ProcessStartInfo to inject env vars
    # (ANDROID_HOME etc.) without polluting parent shell.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'wsl.exe'
    $psi.Arguments = ($wslArgs | ForEach-Object {
        if ($_ -match '\s') { '"' + $_ + '"' } else { $_ }
    }) -join ' '
    $psi.UseShellExecute = $false
    # wsl.exe does NOT forward Windows process env vars into WSL by default.
    # WSLENV declares which vars to forward (with path conversion via /u).
    # Without this, ANDROID_HOME/JAVA_HOME are empty inside WSL and flutter
    # cannot locate the Android SDK / adb / JDK.
    $wslenvParts = @()
    if ($wslAndroidSdk) {
        $psi.EnvironmentVariables['ANDROID_HOME'] = $wslAndroidSdk
        $psi.EnvironmentVariables['ANDROID_SDK_ROOT'] = $wslAndroidSdk
        $wslenvParts += 'ANDROID_HOME/u','ANDROID_SDK_ROOT/u'
    }
    if ($wslNdkPath) {
        # AGP's NdkHandler checks ANDROID_NDK_HOME/ROOT as fallback when
        # sdk.dir points to a SDK without NDK installed. Injecting these
        # forces AGP to use the WSL Linux NDK even if flutter rewrites
        # sdk.dir to the Windows SDK path (e.g. daemon with stale env).
        $psi.EnvironmentVariables['ANDROID_NDK_HOME'] = $wslNdkPath
        $psi.EnvironmentVariables['ANDROID_NDK_ROOT'] = $wslNdkPath
        $wslenvParts += 'ANDROID_NDK_HOME/u','ANDROID_NDK_ROOT/u'
    }
    if ($wslJavaHome) {
        $psi.EnvironmentVariables['JAVA_HOME'] = $wslJavaHome
        $wslenvParts += 'JAVA_HOME/u'
    }
    if ($wslChrome) {
        $psi.EnvironmentVariables['CHROME_EXECUTABLE'] = $wslChrome
        $wslenvParts += 'CHROME_EXECUTABLE/u'
    }
    if ($wslPubCache) {
        $psi.EnvironmentVariables['PUB_CACHE'] = $wslPubCache
        $wslenvParts += 'PUB_CACHE/u'
    }
    if ($wslenvParts.Count -gt 0) {
        $existingWslenv = $psi.EnvironmentVariables['WSLENV']
        $newWslenv = $wslenvParts -join ':'
        if ($existingWslenv) {
            $psi.EnvironmentVariables['WSLENV'] = "$existingWslenv`:$newWslenv"
        } else {
            $psi.EnvironmentVariables['WSLENV'] = $newWslenv
        }
    }

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    try {
        $null = $proc.Start()
        $proc.WaitForExit()
        $exitCode = $proc.ExitCode
    } finally {
        # Ensure wsl.exe is killed if still running (e.g. exception during WaitForExit)
        if (-not $proc.HasExited) {
            try { $proc.Kill() } catch {}
            $proc.WaitForExit(2000) | Out-Null
        }
    }

    # Post-pub-get: translate WSL-format package_config.json to mapped-drive
    # form (file:///W:/...) so both AS Dart analyzer (Windows) and WSL
    # flutter compiler can read the SAME file.
    #
    # Why mapped drive (not UNC):
    #   - UNC form (file://///wsl.localhost/...) triggers Blaze workspace
    #     detector in Windows analyzer, which stats "\\?\UNC\wsl.localhost\blaze-out"
    #     and crashes with "OS Error 67 找不到网络名".
    #   - Even with /blaze-out dummy dir, UNC form generates 3-backslash
    #     Windows path (\\\wsl.localhost\...) which path package's
    #     WindowsStyle.absolutePathToUri fails to convert back to URI
    #     (FormatException on '?' from \\?\UNC\ prefix).
    #   - Mapped drive form (file:///W:/...) generates standard Windows
    #     path (W:\...) that path package handles correctly.
    #
    # WSL side: /W:/home -> /home symlink (created by setup-wsl-symlink.sh)
    # lets WSL Dart resolve file:///W:/home/berial/... to /W:/home/berial/...
    # which then resolves to /home/berial/... via the symlink.
    #
    # Also strip BOM (Dart JSON parser fails on BOM).
    if ($isPubGet -and $exitCode -eq 0 -and (Test-Path $pkgConfigPath)) {
        try {
            $bytes = [System.IO.File]::ReadAllBytes($pkgConfigPath)
            if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
                $bytes = $bytes[3..($bytes.Length - 1)]
            }
            $content = [System.Text.Encoding]::UTF8.GetString($bytes)
            # file:///home/berial/... -> file:///W:/home/berial/...
            $mappedDriveLower = $script:MappedDrive.ToLower()
            $translated = $content -replace 'file:///(?!/wsl\.|/W:/|/w:/)', "file:///$($mappedDriveLower):/"
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($pkgConfigPath, $translated, $utf8NoBom)
            Write-Log "translated package_config.json -> mapped drive ($($script:MappedDrive):) form"
        } catch {
            Write-Log "warn: failed to translate package_config.json: $($_.Exception.Message)"
        }
    }
}

# Log
$elapsed = ((Get-Date) - $startTime).TotalMilliseconds
Write-Log "exit=$exitCode ${elapsed}ms cwd=$winCwd -> $wslCwd cmd=flutter $rawArgs"

exit $exitCode
