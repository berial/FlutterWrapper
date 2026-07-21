# install.ps1 - FlutterWrapper installer
#
# One-shot setup script. Checks prerequisites, generates config,
# creates dart-sdk Junction, runs smoke test.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 -Auto
#   powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 -Auto -SkipSmoke
#   powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 -Distro Ubuntu-22.04
#
# Options:
#   -Auto       Non-interactive: fail instead of prompting for missing values.
#   -SkipSmoke  Skip the smoke test at the end.
#   -Distro <n> Override WSL distro selection.

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Parse command-line arguments
$Auto = $false
$SkipSmoke = $false
$UserDistro = $null
for ($i = 0; $i -lt $args.Count; $i++) {
    switch ($args[$i]) {
        '-Auto' { $Auto = $true }
        '-SkipSmoke' { $SkipSmoke = $true }
        '-Distro' { if ($i + 1 -lt $args.Count) { $UserDistro = $args[++$i] } }
    }
}
if ($Auto) { Write-Host "[AUTO MODE] Non-interactive - will fail if auto-detection fails" -ForegroundColor Yellow }

$rootDir = $PSScriptRoot
$configPath = Join-Path $rootDir 'config\wrapper.yaml'
$dartSdkLink = Join-Path $rootDir 'bin\cache\dart-sdk'

function Write-Step  { param($msg) Write-Host ("==> " + $msg) -ForegroundColor Cyan }
function Write-OK    { param($msg) Write-Host ("    OK  " + $msg) -ForegroundColor Green }
function Write-Warn  { param($msg) Write-Host ("    WARN " + $msg) -ForegroundColor Yellow }
function Write-Err   { param($msg) Write-Host ("    FAIL " + $msg) -ForegroundColor Red }

function Test-Command {
    param([string]$Name)
    $null = Get-Command $Name -ErrorAction SilentlyContinue
    return $?
}

# ============================================================
# Step 1: Check prerequisites on Windows
# ============================================================
Write-Step "Checking Windows prerequisites"

if (-not (Test-Command 'wsl.exe')) {
    Write-Err "wsl.exe not found. Install WSL2 first: wsl --install"
    exit 1
}
Write-OK "wsl.exe found"

if (-not (Test-Command 'powershell.exe')) {
    Write-Err "powershell.exe not found"
    exit 1
}
Write-OK "powershell.exe found"

# ============================================================
# Step 2: List WSL distros and pick one
# ============================================================
Write-Step "Checking WSL distros"

# wsl.exe --list --quiet outputs UTF-16LE, but PS 5.1 reads it as ANSI,
# so each UTF-16 char becomes "char + \0". Strip null chars to recover
# the actual distro name.
$distroList = @()
try {
    $raw = & wsl.exe --list --quiet 2>$null
    foreach ($line in $raw) {
        # Remove null chars (\0) and whitespace
        $clean = ($line -replace "`0", '').Trim()
        if ($clean -and $clean -match '^[A-Za-z0-9._-]+$') {
            $distroList += $clean
        }
    }
} catch {
    Write-Err "Failed to list WSL distros: $($_.Exception.Message)"
    exit 1
}

if (-not $distroList -or $distroList.Count -eq 0) {
    Write-Err "No WSL distros installed. Install one first: wsl --install -d Ubuntu-24.04"
    exit 1
}

Write-Host "    Available distros:"
foreach ($d in $distroList) { Write-Host "      - $d" }

# Pick distro: prefer Ubuntu-24.04, else first in list
$distro = $distroList | Where-Object { $_ -eq 'Ubuntu-24.04' } | Select-Object -First 1
if (-not $distro) { $distro = $distroList[0] }

# Allow override via -Distro parameter
if ($UserDistro) {
    $distro = $UserDistro
}

# Verify chosen distro exists
if ($distroList -notcontains $distro) {
    Write-Err "Selected distro '$distro' not in available list: $($distroList -join ', ')"
    exit 1
}
Write-OK "Using distro: $distro"

# ============================================================
# Step 3: Detect Flutter path inside WSL
# ============================================================
Write-Step "Detecting Flutter in WSL ($distro)"

# Helper: check if a string is a plausible absolute path (starts with /)
function Test-ValidPath {
    param([string]$s)
    return $s -and $s.StartsWith('/') -and -not $s.Contains(' ')
}

# Try several detection methods
$flutterExe = $null

# Method 1: command -v flutter (login shell so vfox/PATH is loaded)
$wslFlutterPath = $null
try {
    $wslFlutterPath = (& wsl.exe -d $distro -- bash -lc 'command -v flutter 2>/dev/null' 2>$null).Trim()
} catch {}
if (Test-ValidPath $wslFlutterPath) {
    Write-OK "Flutter found in PATH: $wslFlutterPath"
    $flutterExe = $wslFlutterPath
}

# Method 2: vfox default symlink location
if (-not $flutterExe) {
    Write-Warn "flutter not in WSL PATH (bash login shell)"
    $vfoxCandidate = $null
    try {
        $vfoxCandidate = (& wsl.exe -d $distro -- bash -lc 'readlink -f ~/.vfox/sdks/flutter/bin/flutter 2>/dev/null' 2>$null).Trim()
    } catch {}
    if (Test-ValidPath $vfoxCandidate) {
        # Use the symlink path (not resolved) so vfox version switching works
        $flutterExe = '/home/' + (& wsl.exe -d $distro -- bash -lc 'whoami' 2>$null).Trim() + '/.vfox/sdks/flutter/bin/flutter'
        Write-OK "Flutter found via vfox: $flutterExe"
    }
}

# Method 2b: FVM (Flutter Version Management) detection
if (-not $flutterExe) {
    Write-Host "    Checking FVM..."
    $fvmFound = $false
    # Check ~/fvm/default/bin/flutter (FVM global default)
    $fvmDefault = '/home/' + (& wsl.exe -d $distro -- bash -lc 'whoami' 2>$null).Trim() + '/fvm/default/bin/flutter'
    $fvmCheck = & wsl.exe -d $distro -- bash -c "test -f $fvmDefault && echo '-f' || echo ''" 2>$null
    if ($fvmCheck -match '-f') {
        $flutterExe = $fvmDefault
        Write-OK "Flutter found via FVM (default): $flutterExe"
        $fvmFound = $true
    } else {
        # Check ~/.fvm/versions/ for highest version
        try {
            $fvmVersions = & wsl.exe -d $distro -- bash -lc 'ls -1d ~/.fvm/versions/*/bin/flutter 2>/dev/null || true' 2>$null
            if ($fvmVersions -and $fvmVersions.Trim()) {
                $latest = ($fvmVersions | Sort-Object -Descending | Select-Object -First 1).Trim()
                if (Test-ValidPath $latest) {
                    $flutterExe = $latest
                    Write-OK "Flutter found via FVM (versions): $flutterExe"
                    $fvmFound = $true
                }
            }
        } catch {}
    }
    if (-not $flutterExe) {
        Write-Warn "FVM not detected"
    }
}

# Method 3: ask user (interactive) or fail (auto mode)
if (-not $flutterExe) {
    if ($Auto) {
        Write-Err "Auto-detection failed. Cannot proceed in -Auto mode."
        Write-Host "    Run without -Auto to enter path manually, or ensure Flutter is installed in WSL."
        Write-Host "    Detection tries: command -v flutter, vfox, FVM (~/fvm/), FVM (~/.fvm/versions/)"
        exit 1
    }
    Write-Host "    Could not auto-detect Flutter path in WSL."
    $userPath = Read-Host "    Enter absolute path to flutter executable in WSL (e.g. /home/user/flutter/bin/flutter)"
    if (-not (Test-ValidPath $userPath)) {
        Write-Err "Invalid path: '$userPath'"
        exit 1
    }
    $flutterExe = $userPath.Trim()
}

# Verify it actually runs
Write-Host "    Verifying: $flutterExe --version"
$versionOutput = & wsl.exe -d $distro -- $flutterExe --version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Err "Failed to run '$flutterExe --version' in WSL (exit=$LASTEXITCODE)"
    Write-Host ($versionOutput | Out-String)
    exit 1
}
$firstLine = ($versionOutput | Select-Object -First 1).Trim()
Write-OK "Flutter runs: $firstLine"

# ============================================================
# Step 4: Derive dart executable path
# ============================================================
Write-Step "Deriving dart executable path"
$dartExe = $flutterExe -replace '/flutter$', '/dart'
$dartCheck = & wsl.exe -d $distro -- test -f $dartExe 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Warn "dart not found at $dartExe (will configure anyway)"
} else {
    Write-OK "dart executable: $dartExe"
}

# ============================================================
# Step 4b: Detect Java (JDK) path inside WSL
# ============================================================
# Gradle needs JAVA_HOME. wsl.exe drops Windows env vars, so JAVA_HOME must
# be set explicitly via WSLENV. Detect from vfox, then JAVA_HOME, then PATH.
Write-Step "Detecting Java (JDK) in WSL ($distro)"
$javaHome = $null

# Method 1: vfox symlink (~/.vfox/sdks/java -> current version)
$vfoxJava = & wsl.exe -d $distro -- bash -lc 'readlink -f ~/.vfox/sdks/java 2>/dev/null' 2>$null
$vfoxJava = $vfoxJava.Trim()
if ($vfoxJava -and $vfoxJava.StartsWith('/')) {
    $javaCheck = & wsl.exe -d $distro -- test -f "$vfoxJava/bin/java" 2>$null
    if ($LASTEXITCODE -eq 0) {
        $javaHome = '/home/' + (& wsl.exe -d $distro -- bash -lc 'whoami' 2>$null).Trim() + '/.vfox/sdks/java'
        Write-OK "Java found via vfox: $javaHome"
    }
}

# Method 2: JAVA_HOME already set in WSL login shell
if (-not $javaHome) {
    $wslJavaHome = & wsl.exe -d $distro -- bash -lc 'echo $JAVA_HOME' 2>$null
    $wslJavaHome = $wslJavaHome.Trim()
    if ($wslJavaHome -and $wslJavaHome.StartsWith('/')) {
        $javaCheck = & wsl.exe -d $distro -- test -f "$wslJavaHome/bin/java" 2>$null
        if ($LASTEXITCODE -eq 0) {
            $javaHome = $wslJavaHome
            Write-OK "Java found via JAVA_HOME: $javaHome"
        }
    }
}

# Method 3: java in PATH
if (-not $javaHome) {
    $wslJavaPath = & wsl.exe -d $distro -- bash -lc 'readlink -f $(command -v java 2>/dev/null) 2>/dev/null' 2>$null
    $wslJavaPath = $wslJavaPath.Trim()
    if ($wslJavaPath -and $wslJavaPath -match '^(.+)/bin/java$') {
        $javaHome = $Matches[1]
        Write-OK "Java found in PATH: $javaHome"
    }
}

if (-not $javaHome) {
    Write-Warn "Java not found in WSL. Set java.home in config/wrapper.yaml manually."
}

# ============================================================
# Step 4c: Detect Chrome/Edge executable for flutter web
# ============================================================
# flutter web device discovery needs CHROME_EXECUTABLE. WSL has no Linux
# Chrome by default; reuse Windows Edge/Chrome via /mnt/c/... interop.
Write-Step "Detecting Chrome/Edge for flutter web"
$chromeExe = $null

# Search common Windows Edge/Chrome locations (visible from WSL as /mnt/c/...)
$winBrowserCandidates = @(
    'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
    'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
    'C:\Program Files\Google\Chrome\Application\chrome.exe',
    'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe'
)
foreach ($p in $winBrowserCandidates) {
    if (Test-Path $p) {
        # Convert to WSL path
        $drive = $p.Substring(0,1).ToLower()
        $rest = $p.Substring(2) -replace '\\', '/'
        $chromeExe = "/mnt/$drive$rest"
        Write-OK "Browser found: $chromeExe"
        break
    }
}

if (-not $chromeExe) {
    # Try CHROME_EXECUTABLE env var
    $envChrome = $env:CHROME_EXECUTABLE
    if ($envChrome -and (Test-Path $envChrome)) {
        $drive = $envChrome.Substring(0,1).ToLower()
        $rest = $envChrome.Substring(2) -replace '\\', '/'
        $chromeExe = "/mnt/$drive$rest"
        Write-OK "Browser via CHROME_EXECUTABLE: $chromeExe"
    }
}

if (-not $chromeExe) {
    Write-Warn "No Chrome/Edge found. Set chrome.executable in config/wrapper.yaml manually."
}

# ============================================================
# Step 5: Detect UNC prefix and drive mount
# ============================================================
Write-Step "Detecting WSL UNC prefix and drive mount"

# UNC prefix: \\wsl.localhost\<distro> (preferred) or \\wsl$\<distro>
$uncPrefix = "\\wsl.localhost\$distro"

# Verify UNC is accessible
$uncAccessible = Test-Path $uncPrefix
if (-not $uncAccessible) {
    $fallback = "\\wsl$\$distro"
    if (Test-Path $fallback) {
        $uncPrefix = $fallback
        Write-Warn "Using legacy UNC: $uncPrefix"
    } else {
        Write-Warn "Cannot access $uncPrefix (may still work later)"
    }
} else {
    Write-OK "UNC prefix: $uncPrefix"
}

# Drive mount: usually /mnt (WSL default), can be /mnt/c, /mnt/d, etc.
$driveMount = '/mnt'
Write-OK "Drive mount: $driveMount (WSL default)"

# ============================================================
# Step 5b: Map \\wsl.localhost\<distro> to a drive letter
# ============================================================
# CMD.EXE doesn't support UNC paths as current directory. When Android Studio
# opens a project via UNC (\\wsl.localhost\...), CMD silently falls back to
# C:\Windows, causing flutter to run in the wrong cwd. Map a drive letter
# (W:) so users can open projects as W:\home\user\project and CMD accepts it.
$mappedDrive = $null
$candidates = @('W:', 'V:', 'U:', 'T:', 'S:', 'R:')
foreach ($letter in $candidates) {
    $existing = $null
    try { $existing = net use $letter 2>$null } catch {}
    if (-not $existing) {
        # Drive letter is free
        if (-not (Test-Path "$letter\")) {
            $mappedDrive = $letter
            break
        }
    } elseif ($existing -match [regex]::Escape($uncPrefix)) {
        # Already mapped to our UNC, reuse
        $mappedDrive = $letter
        Write-OK "Drive $letter already mapped to $uncPrefix"
        break
    }
}

if ($mappedDrive) {
    # Verify drive is not already mapped
    $alreadyMapped = $false
    try {
        $check = net use $mappedDrive 2>$null
        if ($check -match [regex]::Escape($uncPrefix)) { $alreadyMapped = $true }
    } catch {}

    if (-not $alreadyMapped) {
        Write-Host "    Mapping $mappedDrive -> $uncPrefix"
        $result = net use $mappedDrive $uncPrefix 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-OK "Mapped $mappedDrive -> $uncPrefix"
        } else {
            Write-Warn "Failed to map $mappedDrive (may need admin): $result"
            $mappedDrive = $null
        }
    }
} else {
    Write-Warn "No free drive letter found for UNC mapping"
}

# Test mapped drive is accessible
if ($mappedDrive -and (Test-Path "$mappedDrive\")) {
    Write-OK "$mappedDrive accessible"
}

# ============================================================
# Step 6: Write config/wrapper.yaml
# ============================================================
Write-Step "Writing config/wrapper.yaml"

$configDir = Split-Path -Parent $configPath
if (-not (Test-Path $configDir)) {
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
}

# Preserve existing version if present
$existingVersion = 1
if (Test-Path $configPath) {
    $oldContent = Get-Content $configPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if ($oldContent -match 'version:\s*(\d+)') { $existingVersion = [int]$Matches[1] }
}

$configContent = @"
# FlutterWrapper configuration
# Auto-generated by install.ps1 on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# Edit manually if needed; scripts do not hardcode paths.

version: $existingVersion

wsl:
  # WSL distro name (wsl.exe -d <distro>)
  distro: $distro

flutter:
  # Absolute path to flutter executable inside WSL.
  # If using vfox, this points to the version-agnostic symlink
  # (~/.vfox/sdks/flutter -> ~/.vfox/cache/flutter/v-<ver>/...).
  executable: $flutterExe

dart:
  # Absolute path to dart executable inside WSL (same SDK as flutter).
  executable: $dartExe

java:
  # Absolute path to JDK inside WSL (for flutter doctor / gradle).
  # wsl.exe does not forward Windows env vars, so JAVA_HOME must be set
  # explicitly via WSLENV. Point this to your JDK install (vfox symlink OK).
  home: $javaHome

chrome:
  # Path to Chrome/Edge executable for `flutter run -d web-server` / `chrome`.
  # WSL has no Linux Chrome installed; point this to Windows Edge/Chrome
  # (accessible via /mnt/c/...). Forwarded via WSLENV as CHROME_EXECUTABLE.
  executable: $chromeExe

workspace:
  # UNC prefix for WSL->Windows path translation.
  # e.g. /home/user/demo -> \\wsl.localhost\$distro\home\user\demo
  uncPrefix: $uncPrefix

  # Where WSL mounts Windows drives, for Windows->WSL path translation.
  # e.g. D:\demo -> /mnt/d/demo
  driveMount: $driveMount
"@

# Append mappedDrive if configured
if ($mappedDrive) {
    $configContent += @"

  # Drive letter mapped to UNC prefix (via net use).
  # Use this drive letter to open WSL projects in Android Studio:
  #   $mappedDrive\home\user\project
  # CMD.EXE does not support UNC as cwd, so this mapping is required
  # for AS-launched flutter.bat to find the project directory.
  mappedDrive: $($mappedDrive.TrimEnd(':'))
"@
}

Set-Content -Path $configPath -Value $configContent -Encoding UTF8
Write-OK "Wrote $configPath"

# ============================================================
# Step 7: Create dart-sdk Junction (for Android Studio Dart plugin)
# ============================================================
Write-Step "Setting up bin/cache/dart-sdk"

$cacheDir = Split-Path -Parent $dartSdkLink
if (-not (Test-Path $cacheDir)) {
    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
}

if (Test-Path $dartSdkLink) {
    $linkInfo = Get-Item $dartSdkLink -Force
    if ($linkInfo.LinkType -eq 'Junction') {
        Write-OK "Junction already exists: $dartSdkLink -> $($linkInfo.Target)"
    } else {
        Write-Warn "$dartSdkLink exists but is not a Junction (skipping)"
    }
} else {
    # Find Windows-side dart-sdk to link to
    # 1. Try vfox global cache: C:\Users\<user>\vfox-global\flutter\bin\cache\dart-sdk
    $vfoxDartSdk = Join-Path $env:USERPROFILE 'vfox-global\flutter\bin\cache\dart-sdk'
    # 2. Try standard Flutter install: C:\flutter\bin\cache\dart-sdk
    $stdDartSdk = 'C:\flutter\bin\cache\dart-sdk'

    $dartSdkTarget = $null
    if (Test-Path $vfoxDartSdk) {
        $dartSdkTarget = $vfoxDartSdk
    } elseif (Test-Path $stdDartSdk) {
        $dartSdkTarget = $stdDartSdk
    }

    if ($dartSdkTarget) {
        try {
            cmd /c mklink /J "$dartSdkLink" "$dartSdkTarget" | Out-Null
            if (Test-Path $dartSdkLink) {
                Write-OK "Created Junction: $dartSdkLink -> $dartSdkTarget"
            } else {
                Write-Warn "mklink did not create Junction (run as Administrator?)"
            }
        } catch {
            Write-Warn "Failed to create Junction: $($_.Exception.Message)"
        }
    } else {
        Write-Warn "No Windows-side dart-sdk found to link to."
        Write-Host "    Install Flutter on Windows (or copy dart-sdk folder) if AS needs Dart analysis."
        Write-Host "    Or run: mklink /J `"$dartSdkLink`" `"<path-to-windows-dart-sdk>`""
    }
}

# Also ensure bin/cache/flutter.version.json exists (so AS sees a versioned SDK)
$versionJson = Join-Path $rootDir 'bin\cache\flutter.version.json'
if (-not (Test-Path $versionJson)) {
    # Try to fetch version info from WSL flutter --version --machine
    Write-Host "    Fetching flutter --version --machine ..."
    $versionJsonRaw = & wsl.exe -d $distro -- $flutterExe --version --machine 2>$null
    if ($LASTEXITCODE -eq 0 -and $versionJsonRaw) {
        try {
            $versionObj = $versionJsonRaw | ConvertFrom-Json
            # Rewrite flutterRoot to a WSL-style path (informational only)
            Set-Content -Path $versionJson -Value ($versionObj | ConvertTo-Json -Depth 10) -Encoding UTF8
            Write-OK "Wrote $versionJson"
        } catch {
            Write-Warn "Could not parse version JSON: $($_.Exception.Message)"
        }
    } else {
        Write-Warn "Could not fetch flutter --version --machine"
    }
} else {
    Write-OK "flutter.version.json already exists"
}

# ============================================================
# Step 7b: Create Linux wrappers for Windows SDK tools (adb, aapt, aapt2, ...)
# ============================================================
# Flutter on Linux looks for tools without .exe extension (e.g. adb, aapt).
# Windows SDK only ships .exe versions. We create shell wrappers that delegate
# to the .exe, which runs via WSL interop and shares Windows adb server state.
Write-Step "Creating Linux wrappers for Windows SDK tools"

$setupScript = Join-Path $rootDir 'tools\setup-build-tools-wrappers.sh'
if (-not (Test-Path $setupScript)) {
    Write-Warn "setup-build-tools-wrappers.sh not found (skipping)"
} else {
    # Detect Windows Android SDK path (must match what flutter.ps1 resolves)
    $winAndroidSdkPath = $null
    if (Test-Path 'D:\Android\Sdk') { $winAndroidSdkPath = 'D:\Android\Sdk' }
    if (-not $winAndroidSdkPath) { $winAndroidSdkPath = $env:ANDROID_HOME }
    if (-not $winAndroidSdkPath) { $winAndroidSdkPath = $env:ANDROID_SDK_ROOT }

    if ($winAndroidSdkPath -and (Test-Path $winAndroidSdkPath)) {
        # Convert to WSL path
        $drive = $winAndroidSdkPath.Substring(0,1).ToLower()
        $rest = $winAndroidSdkPath.Substring(2) -replace '\\', '/'
        $wslSdkPath = "/mnt/$drive$rest"

        # Create adb wrapper in platform-tools
        $adbWrapper = "$winAndroidSdkPath\platform-tools\adb"
        $adbExe = "$winAndroidSdkPath\platform-tools\adb.exe"
        if ((Test-Path $adbExe) -and -not (Test-Path $adbWrapper)) {
            $adbContent = @"
#!/bin/bash
# FlutterWrapper: Linux-side adb wrapper that delegates to Windows adb.exe.
# adb.exe runs via WSL interop and connects to the Windows adb server
# (127.0.0.1:5037), sharing the device list with Android Studio.
exec "$wslSdkPath/platform-tools/adb.exe" "`$@"
"@
            Set-Content -Path $adbWrapper -Value $adbContent -Encoding UTF8 -NoNewline
            & wsl.exe -d $distro -- chmod +x "$wslSdkPath/platform-tools/adb" 2>$null
            Write-OK "Created adb wrapper: $adbWrapper"
        } elseif (Test-Path $adbWrapper) {
            Write-OK "adb wrapper already exists"
        }

        # Create build-tools wrappers (aapt, aapt2, zipalign, ...)
        $wslSdkEnv = "ANDROID_HOME=$wslSdkPath"
        $result = & wsl.exe -d $distro -- bash -c "export $wslSdkEnv; bash /mnt/d/Android/FlutterWrapper/tools/setup-build-tools-wrappers.sh" 2>&1
        Write-Host ($result | Where-Object { $_ -match '^(==>|created|Done)' }) -ForegroundColor White
    } else {
        Write-Warn "Windows Android SDK not found (skipping build-tools wrappers)"
        Write-Host "    Install Android SDK first, then re-run install.ps1"
    }
}

# ============================================================
# Step 7c: Setup WSL symlinks so package_config.json (W: form) resolves
# ============================================================
# wrapper writes package_config.json in mapped-drive (W:) form
# (file:///w:/home/user/...). The Dart compiler/analyzer running INSIDE WSL
# parses that as /w:/home/user/..., which does not exist unless we create
# /w:/<dir> -> /<dir> (and /W:/<dir> -> /<dir>) symlinks. Without them,
# WSL-side `flutter run`/`flutter build` (including web) fail with
# 'Error when reading /w:/.../foundation.dart: No such file'.
# tools/setup-wsl-symlink.sh creates those plus a /blaze-out dir and, for
# legacy UNC support, /wsl.localhost/<distro> -> /. Requires sudo.
Write-Step "Setting up WSL path symlinks (package_config W: form)"

$symlinkScript = Join-Path $rootDir 'tools\setup-wsl-symlink.sh'
if (-not (Test-Path $symlinkScript)) {
    Write-Warn "setup-wsl-symlink.sh not found (skipping)"
} else {
    # Convert Windows path of the script to a WSL path (/mnt/x/...)
    $sDrive = $symlinkScript.Substring(0,1).ToLower()
    $sRest  = $symlinkScript.Substring(2) -replace '\\', '/'
    $wslSymlinkScript = "/mnt/$sDrive$sRest"

    # Pass detected distro and mapped drive letter (strip the trailing ':')
    $symDrive = if ($mappedDrive) { $mappedDrive.TrimEnd(':') } else { 'W' }
    Write-Host "    Running: bash $wslSymlinkScript $distro $symDrive (may prompt for sudo password)"
    $symResult = & wsl.exe -d $distro -- bash -c "bash $wslSymlinkScript $distro $symDrive" 2>&1
    if ($LASTEXITCODE -eq 0) {
        $upperDrive = $symDrive.ToUpper()
        Write-OK "WSL path symlinks configured (drive form: /${symDrive}:/ and /${upperDrive}:/)"
    } else {
        Write-Warn "setup-wsl-symlink.sh returned non-zero (exit=$LASTEXITCODE)"
        Write-Host ($symResult | Where-Object { $_ -match '^(===|already|created|w: form|DONE|ERROR|SKIP)' } | Out-String)
        Write-Host "    If it failed due to sudo (no password / no tty), create the symlinks manually in WSL:" -ForegroundColor Yellow
        Write-Host "      bash $wslSymlinkScript $distro $symDrive" -ForegroundColor Yellow
    }
}

# ============================================================
# Step 7d: Disable Linux desktop (WSL has no display for it)
# ============================================================
Write-Step "Disabling Linux desktop platform (WSL has no display)"

$disableLinuxResult = & wsl.exe -d $distro -- bash -c "flutter config --no-enable-linux-desktop 2>&1"
if ($LASTEXITCODE -eq 0) {
    Write-OK "Linux desktop platform disabled"
} else {
    Write-Warn "Failed to disable Linux desktop platform (non-fatal)"
    Write-Host ($disableLinuxResult -join "`n")
}

# ============================================================
# Step 8: Smoke test
# ============================================================
Write-Step "Smoke test: flutter --version"

if ($SkipSmoke) {
    Write-Warn "Smoke test skipped (-SkipSmoke)"
} else {
    $flutterBat = Join-Path $rootDir 'bin\flutter.bat'
    if (-not (Test-Path $flutterBat)) {
        Write-Err "Missing $flutterBat (project structure incomplete)"
        exit 1
    }

    $smoke = & cmd /c "$flutterBat --version 2>&1"
    if ($LASTEXITCODE -eq 0) {
        $firstLine = ($smoke | Select-Object -First 1).Trim()
        Write-OK "Smoke test PASS: $firstLine"
    } else {
        Write-Warn "Smoke test returned non-zero exit code ($LASTEXITCODE)"
        Write-Host ($smoke -join "`n")
    }
}

# ============================================================
# Step 9: Final summary
# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  FlutterWrapper installation complete!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Flutter SDK Path (set in Android Studio > Settings > Languages & Frameworks > Flutter):"
Write-Host "    $rootDir" -ForegroundColor White
Write-Host ""
Write-Host "  Dart SDK Path (Settings > Languages & Frameworks > Dart):"
Write-Host "    $dartSdkLink" -ForegroundColor White
Write-Host ""
Write-Host "  Configuration:"
Write-Host "    $configPath" -ForegroundColor White
Write-Host ""
Write-Host "  Logs:"
Write-Host "    $rootDir\logs\flutter.log" -ForegroundColor White
Write-Host "    $rootDir\logs\dart.log" -ForegroundColor White
Write-Host "    $rootDir\logs\bridge.log (daemon)" -ForegroundColor White
Write-Host ""
if ($Auto) {
    Write-Host "  Run diagnostics to verify installation:"
    Write-Host "    flutter-wrapper doctor" -ForegroundColor Yellow
    Write-Host ""
}
Write-Host "  Next steps:"
Write-Host "    1. Open Android Studio"
Write-Host "    2. Settings > Languages & Frameworks > Flutter > Flutter SDK Path"
Write-Host "       -> $rootDir"
Write-Host "    3. Settings > Languages & Frameworks > Dart > Dart SDK Path"
Write-Host "       -> $dartSdkLink"
Write-Host "    4. IMPORTANT: Open WSL projects via the mapped drive letter:"
if ($mappedDrive) {
    Write-Host "       Use:  $mappedDrive\home\<user>\<project>" -ForegroundColor Yellow
    Write-Host "       Not:  \\wsl.localhost\$distro\home\<user>\<project>" -ForegroundColor Gray
    Write-Host ""
    Write-Host "       CMD.EXE doesn't support UNC paths as cwd. If you open a"
    Write-Host "       project via \\\\wsl.localhost\..., flutter.bat will run in"
    Write-Host "       C:\Windows instead of your project dir and fail with"
    Write-Host "       'No pubspec.yaml file found'."
} else {
    Write-Host "       (No drive letter mapped - UNC projects may fail to run)"
}
    Write-Host "    5. Restart Android Studio"
    Write-Host ""
    Write-Host "    Notes:"
    Write-Host "    - Linux desktop platform is disabled (WSL has no display). The run"
    Write-Host "      dropdown will show Android / web devices only. To re-enable, run"
    Write-Host "      'flutter config --enable-linux-desktop' in WSL."
    Write-Host "    - WSL path symlinks (package_config W: form) are configured"
Write-Host "    automatically during install, so WSL-side flutter run/build (incl."
Write-Host "    web) can resolve dependency paths. If a sudo prompt was skipped or"
Write-Host "    failed, re-run manually in WSL: bash tools/setup-wsl-symlink.sh"
Write-Host ""
Write-Host "  Note: Drive mapping is per-user and not persistent across reboots."
Write-Host "        Re-run install.ps1 after reboot, or run:"
Write-Host "          net use $mappedDrive $uncPrefix /persistent:yes"
Write-Host ""

# In auto mode, run diagnostics to verify installation
if ($Auto) {
    Write-Step "Running flutter-wrapper doctor (auto mode)"
    $doctorPath = Join-Path $rootDir 'bin\doctor.ps1'
    if (Test-Path $doctorPath) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $doctorPath -quick
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Doctor reported $LASTEXITCODE issue(s). Run 'flutter-wrapper doctor' for details."
        } else {
            Write-OK "All doctor checks passed"
        }
    } else {
        Write-Warn "doctor.ps1 not found (skipping auto-diagnostic)"
    }
}
