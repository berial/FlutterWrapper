# doctor.ps1 - FlutterWrapper diagnostic tool
#
# Checks all components of the Windows-AS + WSL-Flutter bridge and
# reports status with actionable fix suggestions.

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir   = Split-Path -Parent $scriptDir
$configPath = Join-Path $rootDir 'config\wrapper.yaml'

$quick = $args -contains '-quick' -or $args -contains '-q'
$jsonOut = $args -contains '-json' -or $args -contains '-j'
$fixSafe = $args -contains '--fix-safe'
$collect = $args -contains '--collect'

# Dynamic WSL user detection (for de-personalized checks)
$wslUser = $null
$wslHome = $null
try {
    if ($config -and $config.wsl.distro) {
        $wslUser = (& wsl.exe -d $($config.wsl.distro) -e bash -lc 'whoami' 2>$null).Trim()
        if ($wslUser) { $wslHome = "/home/$wslUser" }
    }
} catch {}
if (-not $wslHome) { $wslHome = '/home/user' }

# ============================================================
# Output helpers
# ============================================================
$results = @()
$issueCount = 0
$warnCount = 0

function Write-Check {
    param(
        [string]$Name,
        [string]$Status,  # PASS / FAIL / WARN / SKIP
        [string]$Detail,
        [string]$Fix
    )
    $icon = switch ($Status) {
        'PASS' { '[✓]' }
        'FAIL' { '[✗]' }
        'WARN' { '[!]' }
        'SKIP' { '[?]' }
    }
    if ($jsonOut) {
        $results += @{ name = $Name; status = $Status; detail = $Detail; fix = $Fix }
    } else {
        $color = switch ($Status) {
            'PASS' { 'Green' }
            'FAIL' { 'Red' }
            'WARN' { 'Yellow' }
            'SKIP' { 'Gray' }
        }
        Write-Host "  $icon $Name" -NoNewline
        if ($Detail) {
            Write-Host ": $Detail" -NoNewline -ForegroundColor $color
        }
        if ($Fix -and $Status -eq 'FAIL') {
            Write-Host "  -> $Fix" -NoNewline -ForegroundColor Yellow
        }
        Write-Host ""
    }
    if ($Status -eq 'FAIL') { $script:issueCount++ }
    if ($Status -eq 'WARN') { $script:warnCount++ }
}

function Write-Section {
    param([string]$Title)
    if (-not $jsonOut) {
        Write-Host ""
        Write-Host $Title -ForegroundColor Cyan
        Write-Host ('-' * $Title.Length) -ForegroundColor Cyan
    }
}

# ============================================================
# Shared helpers (dot-sourced from lib/config.ps1)
. "$PSScriptRoot/../lib/config.ps1"

# Path conversion (local copy for validation)
function ConvertTo-WslPath {
    param(
        [string]$Path,
        [string]$DriveMount,
        [string]$UncPrefix,
        [string]$MappedDrive
    )
    if (-not $Path) { return $Path }
    # Mapped drive
    if ($MappedDrive -and $Path -match "^$($MappedDrive):[\\/](.*)$") {
        $rest = $Matches[1] -replace '\\', '/'
        if ($rest) { return "/$rest" } else { return "/" }
    }
    if ($MappedDrive -and $Path -match "^$($MappedDrive):$") { return "/" }
    # UNC \\wsl.localhost\<distro>\<rest>
    if ($Path -match '^\\\\[wW][sS][lL]\.(?:[lL][oO][cC][aA][lL][hH][oO][sS][tT])\\([^\\]+)\\(.*)$') {
        $rest = $Matches[2] -replace '\\', '/'
        if ($rest) { return "/$rest" } else { return "/" }
    }
    if ($Path -match '^\\\\[wW][sS][lL]\.(?:[lL][oO][cC][aA][lL][hH][oO][sS][tT])\\([^\\]+)$') { return "/" }
    # UNC \\wsl$\<distro>\<rest>
    if ($Path -match '^\\\\[wW][sS][lL]\$\\([^\\]+)\\(.*)$') {
        $rest = $Matches[2] -replace '\\', '/'
        if ($rest) { return "/$rest" } else { return "/" }
    }
    if ($Path -match '^\\\\[wW][sS][lL]\$\\([^\\]+)$') { return "/" }
    # Drive letter
    if ($Path -match '^([A-Za-z]):[\\/](.*)$') {
        $drive = $Matches[1].ToLower()
        $rest  = $Matches[2] -replace '\\', '/'
        if ($rest) { return "$DriveMount/$drive/$rest" }
        else       { return "$DriveMount/$drive/" }
    }
    if ($Path -match '\\') { return ($Path -replace '\\', '/') }
    return $Path
}

# ============================================================
# Check 1: Config file
# ============================================================
Write-Section "1. Configuration"

$config = Read-WrapperConfigSafe $configPath
if (-not $config) {
    Write-Check 'Config file (config/wrapper.yaml)' 'FAIL' `
        "Not found at $configPath" `
        "Run install.ps1 to generate configuration"
    if ($jsonOut) {
        $json = ConvertTo-Json -InputObject $results -Compress
        Write-Host $json
    }
    exit 1
}
Write-Check 'Config file (config/wrapper.yaml)' 'PASS' "Found"

# Validate required fields
$distro = $config.wsl.distro
$flutterExe = $config.flutter.executable
$dartExe = $config.dart.executable
$uncPrefix = $config.workspace.uncPrefix
$driveMount = $config.workspace.driveMount
$mappedDrive = $config.workspace.mappedDrive
if ($mappedDrive -and $mappedDrive -match '^([A-Za-z]):') {
    $mappedDrive = $Matches[1].ToUpper()
}

$missingFields = @()
if (-not $distro) { $missingFields += 'wsl.distro' }
if (-not $flutterExe) { $missingFields += 'flutter.executable' }
if (-not $dartExe) { $missingFields += 'dart.executable' }

if ($missingFields.Count -gt 0) {
    Write-Check 'Required config fields' 'FAIL' `
        "Missing: $($missingFields -join ', ')" `
        "Edit config/wrapper.yaml or re-run install.ps1"
} else {
    Write-Check 'Required config fields' 'PASS' "All present"
}

# ============================================================
# Check 2: WSL connectivity
# ============================================================
Write-Section "2. WSL Bridge"

if (-not (Get-Command 'wsl.exe' -ErrorAction SilentlyContinue)) {
    Write-Check 'wsl.exe' 'FAIL' `
        "wsl.exe not found" `
        "Install WSL2: wsl --install"
} else {
    Write-Check 'wsl.exe' 'PASS' "Available"

    # Check distro
    try {
        $raw = & wsl.exe --list --quiet 2>$null
        $distros = @()
        foreach ($line in $raw) {
            $clean = ($line -replace "`0", '').Trim()
            if ($clean -and $clean -match '^[A-Za-z0-9._-]+$') {
                $distros += $clean
            }
        }
        if ($distros -contains $distro) {
            Write-Check "WSL distro ($distro)" 'PASS' "Running"
            # Show other available distros (v2.3 multi-distro)
            $otherDistros = $distros | Where-Object { $_ -ne $distro }
            if ($otherDistros.Count -gt 0) {
                Write-Check "  Other distros available" 'SKIP' "$($otherDistros -join ', ') — edit config to switch"
            }
        } else {
            Write-Check "WSL distro ($distro)" 'FAIL' `
                "Not installed. Available: $($distros -join ', ')" `
                "Install with: wsl --install -d $distro"
        }
    } catch {
        Write-Check "WSL distro ($distro)" 'FAIL' `
            "Cannot list distros: $($_.Exception.Message)" `
            "Check WSL installation"
    }
}

# Check WSL version (should be 2)
if (-not $quick -and $distro) {
    try {
        $verRaw = & wsl.exe -l -v 2>$null
        $wsl2 = ($verRaw -join "`n") -match "^\s*\S+\s+Running\s+2"
        if ($wsl2) {
            Write-Check "WSL version (v2)" 'PASS' "WSL2 running"
        } else {
            Write-Check "WSL version (v2)" 'WARN' `
                "Not confirmed as WSL2" `
                "Run: wsl --set-version $distro 2"
        }
    } catch {
        Write-Check "WSL version (v2)" 'SKIP' "Cannot determine"
    }
}

# ============================================================
# Check 3: Flutter & Dart SDK in WSL
# ============================================================
Write-Section "3. Flutter & Dart SDK (WSL)"

if (-not $distro -or -not $flutterExe) {
    Write-Check 'Flutter SDK' 'SKIP' "WSL or config not available"
} else {
    # Check flutter exists (bash -lc for shell operators)
    try {
        $flutterCheck = & wsl.exe -d $distro -e bash -lc "test -f `"$flutterExe`" && echo OK || echo MISSING" 2>$null
        $flutterCheck = ($flutterCheck -join '').Trim()
        if ($flutterCheck -eq 'OK') {
            Write-Check "Flutter binary ($flutterExe)" 'PASS' "Found"
        } else {
            Write-Check "Flutter binary ($flutterExe)" 'FAIL' `
                "Not found at $flutterExe" `
                "Install Flutter in WSL or update config: flutter.executable"
        }
    } catch {
        Write-Check "Flutter binary ($flutterExe)" 'FAIL' `
            "Cannot check: $($_.Exception.Message)" `
            "Verify WSL distro is running"
    }

    # Check flutter version (skip in quick mode)
    if (-not $quick -and $flutterCheck -eq 'OK') {
        try {
            $fv = & wsl.exe -d $distro -e $flutterExe --version 2>$null
            $fvLine = ($fv | Select-Object -First 1) -replace '\s+', ' '
            Write-Check "Flutter version" 'PASS' "$fvLine"
        } catch {
            Write-Check "Flutter version" 'WARN' "Cannot determine"
        }
    }

    # Check FVM detection (v2.3)
    if (-not $quick) {
        $fvmPaths = @()
        try {
            $fvmDefault = & wsl.exe -d $distro -e bash -lc "test -f ~/fvm/default/bin/flutter && echo ~/fvm/default" 2>$null
            if ($fvmDefault.Trim()) { $fvmPaths += $($fvmDefault.Trim()) }
            $fvmVersions = & wsl.exe -d $distro -e bash -lc 'ls -1d ~/.fvm/versions/*/bin/flutter 2>/dev/null | sed "s|/bin/flutter||" || true' 2>$null
            if ($fvmVersions) {
                foreach ($v in $fvmVersions) { if ($v.Trim()) { $fvmPaths += $v.Trim() } }
            }
        } catch {}
        if ($fvmPaths.Count -gt 0) {
            Write-Check "FVM (Flutter Version Mgmt)" 'PASS' "Detected: $($fvmPaths -join ', ')"
        } else {
            Write-Check "FVM (Flutter Version Mgmt)" 'SKIP' "Not found (ok if using vfox)"
        }
    }
}

if (-not $distro -or -not $dartExe) {
    Write-Check 'Dart SDK' 'SKIP' "WSL or config not available"
} else {
    # Check dart exists (bash -lc for shell operators)
    try {
        $dartCheck = & wsl.exe -d $distro -e bash -lc "test -f `"$dartExe`" && echo OK || echo MISSING" 2>$null
        $dartCheck = ($dartCheck -join '').Trim()
        if ($dartCheck -eq 'OK') {
            Write-Check "Dart binary ($dartExe)" 'PASS' "Found"
        } else {
            Write-Check "Dart binary ($dartExe)" 'FAIL' `
                "Not found at $dartExe" `
                "Update config: dart.executable"
        }
    } catch {
        Write-Check "Dart binary ($dartExe)" 'FAIL' `
            "Cannot check: $($_.Exception.Message)" `
            "Verify WSL distro is running"
    }

    # Check dart version (skip in quick mode)
    if (-not $quick -and $dartCheck -eq 'OK') {
        try {
            $dv = & wsl.exe -d $distro -e $dartExe --version 2>$null
            $dvLine = ($dv | Select-Object -First 1) -replace '\s+', ' '
            Write-Check "Dart version" 'PASS' "$dvLine"
        } catch {
            Write-Check "Dart version" 'WARN' "Cannot determine"
        }
    }
}

# ============================================================
# Check 4: Path mapping
# ============================================================
Write-Section "4. Path Mapping"

if (-not $driveMount) { $driveMount = '/mnt' }

# Test basic path conversions
$testCases = @(
    @{ Input = "D:\Android\FlutterWrapper"; Expected = "$driveMount/d/Android/FlutterWrapper"; Name = 'Drive letter -> WSL' },
    @{ Input = "D:/Android/FlutterWrapper"; Expected = "$driveMount/d/Android/FlutterWrapper"; Name = 'Forward-slash drive' },
    @{ Input = "lib\main.dart"; Expected = "lib/main.dart"; Name = 'Relative backslash swap' },
    @{ Input = "--target=lib\main.dart"; Expected = "--target=lib/main.dart"; Name = 'Arg path value' }
)

# UNC test (from uncPrefix)
if ($uncPrefix) {
    $testCases += @{ Input = "$uncPrefix$wslHome\test" -replace '/', '\'; Expected = "$wslHome/test"; Name = 'UNC -> WSL' }
}

# Mapped drive test
if ($mappedDrive) {
    $testCases += @{ Input = "$($mappedDrive):$wslHome\test" -replace '/', '\'; Expected = "$wslHome/test"; Name = 'Mapped drive -> WSL' }
}

$pathOk = $true
foreach ($tc in $testCases) {
    $result = ConvertTo-WslPath -Path $tc.Input -DriveMount $driveMount -UncPrefix $uncPrefix -MappedDrive $mappedDrive
    $argResult = ConvertTo-WslPath -Path $tc.Input -DriveMount $driveMount -UncPrefix $uncPrefix -MappedDrive $mappedDrive
    # For arg path test, we need to handle --key=value
    if ($tc.Input -match '^(-{1,2}[^=]+)=(.*)$') {
        $key = $Matches[1]
        $value = $Matches[2]
        $convVal = ConvertTo-WslPath -Path $value -DriveMount $driveMount -UncPrefix $uncPrefix -MappedDrive $mappedDrive
        $argResult = "${key}=${convVal}"
    }
    if ($argResult -eq $tc.Expected) {
        Write-Check $tc.Name 'PASS' "$($tc.Input) -> $($tc.Expected)"
    } else {
        Write-Check $tc.Name 'FAIL' "$($tc.Input) -> $argResult (expected: $($tc.Expected))" ""
        $pathOk = $false
    }
}

# Check W: drive mapping
if ($mappedDrive) {
    $wDrivePath = "${mappedDrive}:\"
    if (Test-Path $wDrivePath) {
        Write-Check "Mapped drive ($($mappedDrive):)" 'PASS' "Accessible"
    } else {
        Write-Check "Mapped drive ($($mappedDrive):)" 'FAIL' `
            "${mappedDrive}: not accessible" `
            "Run: net use ${mappedDrive}: \\wsl.localhost\$distro"
    }
}

# Check UNC prefix accessibility
if ($uncPrefix) {
    $uncExists = Test-Path $uncPrefix -ErrorAction SilentlyContinue
    if ($uncExists) {
        Write-Check "UNC prefix ($uncPrefix)" 'PASS' "Accessible"
    } else {
        Write-Check "UNC prefix ($uncPrefix)" 'FAIL' `
            "Not accessible" `
            "Check WSL distro is running"
    }
}

# ============================================================
# Check 5: WSL symlinks (needed for package_config.json compatibility)
# ============================================================
Write-Section "5. WSL Symlinks"

if ($distro) {
    $symlinks = @(
        @{ Path = '/w:'; Name = '/w: -> / (mapped drive lowercase)' },
        @{ Path = '/W:'; Name = '/W: -> / (mapped drive uppercase)' },
        @{ Path = '/blaze-out'; Name = '/blaze-out (Blaze detector guard)' }
    )
    foreach ($sl in $symlinks) {
        try {
            $lsOutput = & wsl.exe -d $distro -e ls -la $sl.Path 2>$null
            if ($lsOutput -and $lsOutput -match '->') {
                Write-Check $sl.Name 'PASS' ($lsOutput -join ' ').Trim()
            } elseif ($lsOutput -and $lsOutput -match '^d') {
                Write-Check $sl.Name 'PASS' "Directory exists"
            } else {
                Write-Check $sl.Name 'FAIL' `
                    "Symlink/dir missing" `
                    "Run: sudo tools/setup-wsl-symlink.sh"
            }
        } catch {
            Write-Check $sl.Name 'FAIL' `
                "Cannot check: $($_.Exception.Message)" `
                "Run: sudo tools/setup-wsl-symlink.sh"
        }
    }
} else {
    Write-Check 'WSL symlinks' 'SKIP' "No distro configured"
}

# ============================================================
# Check 6: Android Studio
# ============================================================
Write-Section "6. Android Studio"

# Check common installation paths
$asPaths = @(
    "${env:ProgramFiles}\Android\Android Studio",
    "${env:ProgramFiles(x86)}\Android\Android Studio",
    "${env:LOCALAPPDATA}\Programs\Android Studio",
    "C:\Program Files\Android\Android Studio",
    "D:\Android\AndroidStudio"
)

$asFound = $false
foreach ($p in $asPaths) {
    if (Test-Path $p) {
        Write-Check 'Android Studio' 'PASS' "Found at $p"
        $asFound = $true
        break
    }
}
if (-not $asFound) {
    Write-Check 'Android Studio' 'WARN' `
        "Not found in common paths" `
        "If installed elsewhere, this is expected"
}

# ============================================================
# Check 7: Android SDK
# ============================================================
Write-Section "7. Android SDK"

$androidSdk = $config.android.sdkPath
if (-not $androidSdk) { $androidSdk = $env:ANDROID_HOME }
if (-not $androidSdk) { $androidSdk = $env:ANDROID_SDK_ROOT }
if (-not $androidSdk) { $androidSdk = 'D:\Android\Sdk' }

if (Test-Path $androidSdk) {
    Write-Check "Android SDK ($androidSdk)" 'PASS' "Found"

    # Check key tools
    $tools = @('platform-tools\adb.exe', 'build-tools')
    foreach ($t in $tools) {
        $tp = Join-Path $androidSdk $t
        if (Test-Path $tp) {
            Write-Check "  $t" 'PASS' "Present"
        } else {
            Write-Check "  $t" 'WARN' "Missing" "Install via SDK Manager"
        }
    }

    # Check adb works
    if (-not $quick) {
        try {
            $adbPath = Join-Path $androidSdk 'platform-tools\adb.exe'
            $adbVer = & $adbPath version 2>$null | Select-Object -First 1
            Write-Check "  adb version" 'PASS' $adbVer
        } catch {
            Write-Check "  adb version" 'WARN' "Cannot run"
        }
    }
} else {
    Write-Check "Android SDK ($androidSdk)" 'FAIL' `
        "Not found" `
        "Set android.sdkPath in config/wrapper.yaml or install Android SDK"
}

# ============================================================
# Check 8: Dart Analysis Layer
# ============================================================
Write-Section "8. Dart Analysis Layer"

$dartSdkLink = Join-Path $rootDir 'bin\cache\dart-sdk'
$dartExeWin = Join-Path $dartSdkLink 'bin\dart.exe'

if (Test-Path $dartExeWin) {
    # Check it's a valid Dart SDK (has version file)
    $dartVerFile = Join-Path $dartSdkLink 'version'
    if (Test-Path $dartVerFile) {
        $dartVerContent = Get-Content $dartVerFile -Raw
        Write-Check 'dart-sdk Junction' 'PASS' "Valid Dart SDK at bin/cache/dart-sdk"
    } else {
        Write-Check 'dart-sdk Junction' 'WARN' "Directory exists but version file missing"
    }

    # Check flutter.version.json
    $fvPath = Join-Path $rootDir 'bin\cache\flutter.version.json'
    if (Test-Path $fvPath) {
        Write-Check 'flutter.version.json' 'PASS' "Present"
    } else {
        Write-Check 'flutter.version.json' 'WARN' "Missing" "Run: install.ps1"
    }

    # Check Windows dart.exe works
    if (-not $quick) {
        try {
            $dartVer = & $dartExeWin --version 2>&1 | Select-Object -First 1
            Write-Check "Windows dart.exe" 'PASS' ($dartVer -replace '\s+', ' ')
        } catch {
            Write-Check "Windows dart.exe" 'FAIL' `
                "Cannot run" `
                "Check vfox Windows global current or re-create Junction"
        }
    }
} else {
    Write-Check 'dart-sdk Junction' 'FAIL' `
        "Not found at bin/cache/dart-sdk" `
        "Run install.ps1 to create Junction"
}

# Check vfox Windows global current (source of Junction target)
if (-not $quick) {
    $vfoxGlobal = Join-Path $env:USERPROFILE 'vfox-global\flutter'
    if (Test-Path $vfoxGlobal) {
        Write-Check 'vfox Windows global flutter' 'PASS' "Found at $vfoxGlobal"
    } else {
        Write-Check 'vfox Windows global flutter' 'WARN' `
            "Not found" `
            "Run: vfox use -g flutter@<version>"
    }
}

# ============================================================
# Check 9: Daemon Translator
# ============================================================
Write-Section "9. Daemon Translation"

$wrapperPath = Join-Path $scriptDir 'wrapper.ps1'
if (Test-Path $wrapperPath) {
    Write-Check 'wrapper.ps1' 'PASS' "Found"
} else {
    Write-Check 'wrapper.ps1' 'FAIL' "Not found at $wrapperPath" ""
}

# Check daemon TCP port (config)
$daemonPort = $config.daemon.tcpPort
if (-not $daemonPort) { $daemonPort = '9876' }
Write-Check "Daemon TCP port ($daemonPort)" 'PASS' "Configured"

# Check if port is available
if (-not $quick) {
    try {
        $portCheck = & wsl.exe -d $distro -e bash -lc "command -v fuser >/dev/null && fuser $daemonPort/tcp 2>/dev/null || echo NOT_INSTALLED" 2>$null
        $portCheck = ($portCheck -join '').Trim()
        if ($portCheck -eq 'NOT_INSTALLED') {
            Write-Check "TCP port $daemonPort" 'PASS' "Likely available (fuser not found)"
        } elseif ($portCheck -match '\d+') {
            Write-Check "TCP port $daemonPort" 'WARN' "In use (stale daemon?)" "Run: wsl -e 'fuser -k $daemonPort/tcp'"
        } else {
            Write-Check "TCP port $daemonPort" 'PASS' "Available"
        }
    } catch {
        Write-Check "TCP port $daemonPort" 'PASS' "Likely available"
    }
}

# ============================================================
# Check 10: Gradle & Java
# ============================================================
Write-Section "10. Gradle & Java"

# Check JAVA_HOME in WSL
$javaHome = $config.java.home
if ($javaHome) {
    try {
        $javaCheck = & wsl.exe -d $distro -e bash -lc "test -d `"$javaHome`" && echo OK || echo MISSING" 2>$null
        $javaCheck = ($javaCheck -join '').Trim()
        if ($javaCheck -eq 'OK') {
            Write-Check "JAVA_HOME ($javaHome)" 'PASS' "Found in WSL"

            # Check java version
            if (-not $quick) {
                $javaBin = "$javaHome/bin/java"
                $jVer = & wsl.exe -d $distro -e $javaBin -version 2>&1 | Select-Object -First 1
                Write-Check "  Java version" 'PASS' ($jVer -replace '\s+', ' ')
            }
        } else {
            Write-Check "JAVA_HOME ($javaHome)" 'FAIL' `
                "Not found in WSL" `
                "Install JDK in WSL or update config: java.home"
        }
    } catch {
        Write-Check "JAVA_HOME ($javaHome)" 'WARN' "Cannot verify"
    }
} else {
    Write-Check "JAVA_HOME" 'WARN' "Not configured" "Set java.home in config/wrapper.yaml"
}

# Check Gradle mirror
try {
    $mirrorPath = "$wslHome/.gradle/init.d/mirror.gradle"
    $mirrorCheck = & wsl.exe -d $distro -e bash -lc "test -f `"$mirrorPath`" && echo OK || echo MISSING" 2>$null
    $mirrorCheck = ($mirrorCheck -join '').Trim()
    if ($mirrorCheck -eq 'OK') {
        Write-Check "Gradle Maven mirror" 'PASS' "init.d/mirror.gradle configured"
    } else {
        Write-Check "Gradle Maven mirror" 'WARN' `
            "Not configured" `
            "Run: bash tools/setup-gradle-mirror.sh"
    }
} catch {
    Write-Check "Gradle Maven mirror" 'SKIP' "Cannot check"
}

# ============================================================
# Check 11: Native build tools (NDK + cmake)
# ============================================================
Write-Section "11. Native Build Tools"

$wslSdkLocal = $config.android.wslSdkPath
if ($wslSdkLocal) {
    try {
        $ndkPath = "$wslSdkLocal/ndk"
        $ndkCheck = & wsl.exe -d $distro -e bash -lc "test -d `"$ndkPath`" && echo OK || echo MISSING" 2>$null
        $ndkCheck = ($ndkCheck -join '').Trim()
        if ($ndkCheck -eq 'OK') {
            Write-Check "WSL NDK ($ndkPath)" 'PASS' "Present"
        } else {
            Write-Check "WSL NDK ($ndkPath)" 'FAIL' `
                "Not found" `
                "Run: bash tools/setup-wsl-ndk.sh"
        }

        $cmakePath = "$wslSdkLocal/cmake"
        $cmakeCheck = & wsl.exe -d $distro -e bash -lc "test -d `"$cmakePath`" && echo OK || echo MISSING" 2>$null
        $cmakeCheck = ($cmakeCheck -join '').Trim()
        if ($cmakeCheck -eq 'OK') {
            Write-Check "WSL cmake ($cmakePath)" 'PASS' "Present"
        } else {
            Write-Check "WSL cmake ($cmakePath)" 'FAIL' `
                "Not found" `
                "Run: bash tools/setup-wsl-ndk.sh"
        }
    } catch {
        Write-Check "WSL native build tools" 'SKIP' "Cannot check"
    }
} else {
    Write-Check "WSL native build tools" 'SKIP' "wslSdkPath not configured"
}

# ============================================================
# Check 12: Smoke test (flutter doctor in WSL)
# ============================================================
Write-Section "12. Smoke Test"

if (-not $quick -and $distro -and $flutterExe) {
    try {
        Write-Host "  Running: flutter doctor --android-licenses (quiet)..."
        $smoke = & wsl.exe -d $distro --cd $wslHome -e $flutterExe doctor 2>&1
        $smokeLines = $smoke | Where-Object { $_ -match '^\[[✓✗!?]\]' }
        $okCount = ($smokeLines | Where-Object { $_ -match '^\[✓\]' }).Count
        $failCount = ($smokeLines | Where-Object { $_ -match '^\[✗\]' }).Count
        if ($failCount -eq 0) {
            Write-Check "WSL flutter doctor" 'PASS' "$okCount checks passed"
        } else {
            Write-Check "WSL flutter doctor" 'WARN' "$okCount passed, $failCount failed"
            foreach ($line in $smokeLines) {
                if (-not $jsonOut) {
                    Write-Host "    $line" -ForegroundColor DarkGray
                }
            }
        }
    } catch {
        Write-Check "WSL flutter doctor" 'FAIL' $_.Exception.Message ""
    }
} else {
    Write-Check "WSL flutter doctor" 'SKIP' "Quick mode or config missing"
}

# ============================================================
# Check 13: Project config (.vfox.toml / .fvmrc) — v3.0
# ============================================================
Write-Section "13. Project Config (vfox/FVM)"

$winCwd = (Get-Location).Path
$vfoxToml = Join-Path $winCwd '.vfox.toml'
$fvmrc = Join-Path $winCwd '.fvmrc'

if (Test-Path $vfoxToml) {
    Write-Check ".vfox.toml" 'PASS' "Found in project"
    try {
        $tomlContent = Get-Content $vfoxToml -Raw -Encoding UTF8
        if ($tomlContent -match 'flutter\s*=\s*"([^"]+)"') {
            $projectVer = $Matches[1]
            # Check if this version is installed in vfox
            $vfoxInstalled = $false
            try {
                $vfoxList = & vfox list flutter 2>$null
                if (($vfoxList -join "`n") -match [regex]::Escape($projectVer)) {
                    $vfoxInstalled = $true
                }
            } catch {}
            if ($vfoxInstalled) {
                Write-Check "  Flutter $projectVer" 'PASS' "Installed via vfox"
            } else {
                Write-Check "  Flutter $projectVer" 'WARN' `
                    "Not installed in vfox" `
                    "Run: vfox install flutter@$projectVer"
            }
        } else {
            Write-Check "  Flutter version" 'WARN' "Could not parse version from .vfox.toml"
        }
    } catch {
        Write-Check ".vfox.toml" 'WARN' "Could not parse: $($_.Exception.Message)"
    }
} else {
    Write-Check ".vfox.toml" 'SKIP' "Not found (project may use FVM or manual)"
}

if (Test-Path $fvmrc) {
    Write-Check ".fvmrc" 'PASS' "Found in project"
    try {
        $fvmContent = Get-Content $fvmrc -Raw -Encoding UTF8
        if ($fvmContent -match '"flutter"\s*:\s*"([^"]+)"' -or $fvmContent -match '"flutterSdkVersion"\s*:\s*"([^"]+)"') {
            $fvmVer = $Matches[1]
            $fvmInstalled = $false
            try {
                $fvmCheck = & wsl.exe -d $distro -e bash -lc "test -d ~/.fvm/versions/$fvmVer && echo OK || echo MISSING" 2>$null
                if (($fvmCheck -join '').Trim() -eq 'OK') { $fvmInstalled = $true }
            } catch {}
            if ($fvmInstalled) {
                Write-Check "  Flutter $fvmVer" 'PASS' "Installed via FVM"
            } else {
                Write-Check "  Flutter $fvmVer" 'WARN' `
                    "Not installed in FVM" `
                    "Run: fvm install $fvmVer"
            }
        } else {
            Write-Check "  Flutter version" 'WARN' "Could not parse version from .fvmrc"
        }
    } catch {
        Write-Check ".fvmrc" 'WARN' "Could not parse: $($_.Exception.Message)"
    }
} else {
    Write-Check ".fvmrc" 'SKIP' "Not found"
}

# Version consistency: compare project config with wrapper config
if ((Test-Path $vfoxToml) -or (Test-Path $fvmrc)) {
    if ($flutterExe -and $distro) {
        try {
            $actualVer = & wsl.exe -d $distro -e $flutterExe --version 2>$null | Select-Object -First 1
            if ($actualVer -match 'Flutter\s+([\d.]+)') {
                $actualFlutterVer = $Matches[1]
                $projectVerDeclared = if ($projectVer) { $projectVer } else { $fvmVer }
                if ($projectVerDeclared -and $actualFlutterVer -ne $projectVerDeclared) {
                    Write-Check "  Version consistency" 'WARN' `
                        "Project declares $projectVerDeclared, but wrapper uses Flutter $actualFlutterVer" `
                        "Run: fw flutter use $projectVerDeclared"
                } elseif ($projectVerDeclared) {
                    Write-Check "  Version consistency" 'PASS' "Wrapper Flutter $actualFlutterVer matches project"
                }
            }
        } catch {}
    }
}

# ============================================================
# Summary
# ============================================================
Write-Section "Summary"

if ($jsonOut) {
    $output = @{
        results = $results
        summary = @{
            passed = ($results | Where-Object { $_.status -eq 'PASS' }).Count
            failed = $issueCount
            warnings = $warnCount
            total = $results.Count
        }
    }
    $json = ConvertTo-Json -InputObject $output -Depth 3 -Compress
    Write-Host $json
} else {
    Write-Host ""
    $total = ($results | Where-Object { $_.status -ne 'SKIP' }).Count
    $passed = ($results | Where-Object { $_.status -eq 'PASS' }).Count
    Write-Host "  Checks: $passed passed, $issueCount failed, $warnCount warnings" -ForegroundColor Cyan

    if ($issueCount -eq 0 -and $warnCount -eq 0) {
        Write-Host ""
        Write-Host "  All checks passed! FlutterWrapper is ready." -ForegroundColor Green
    } elseif ($issueCount -gt 0) {
        Write-Host ""
        Write-Host "  $issueCount issue(s) need attention. See FAIL items above for fix suggestions." -ForegroundColor Red
    } else {
        Write-Host ""
        Write-Host "  All checks passed with $warnCount warning(s). Wrapper should work." -ForegroundColor Yellow
    }
}

# --fix-safe: auto-repair safe items
if ($fixSafe -and $issueCount -gt 0) {
    Write-Host ""
    Write-Host "--fix-safe: Repairing safe items..." -ForegroundColor Cyan
    $safeRepairs = @()
    # dart-sdk junction repair
    $dartSdkFail = $results | Where-Object { $_.name -eq 'dart-sdk Junction' -and $_.status -eq 'FAIL' }
    if ($dartSdkFail) {
        Write-Host "  Repairing: dart-sdk Junction..."
        $dartSdkLink = Join-Path $rootDir 'bin\cache\dart-sdk'
        $vfoxDartSdk = Join-Path $env:USERPROFILE 'vfox-global\flutter\bin\cache\dart-sdk'
        if (Test-Path $vfoxDartSdk) {
            if (Test-Path $dartSdkLink) { Remove-Item $dartSdkLink -Force -Recurse -ErrorAction SilentlyContinue }
            $cacheDir = Split-Path -Parent $dartSdkLink
            if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
            cmd /c mklink /J "$dartSdkLink" "$vfoxDartSdk" 2>&1 | Out-Null
            if (Test-Path $dartSdkLink) {
                Write-Host "    [OK] Junction re-created" -ForegroundColor Green
            } else {
                Write-Host "    [FAIL] Could not create Junction" -ForegroundColor Red
            }
        }
    }
    # vfox Junction workaround
    $vfoxFail = $results | Where-Object { $_.name -eq 'vfox Windows global flutter' -and $_.status -eq 'WARN' } | Select-Object -First 1
    $vfoxGlobalFlutter = Join-Path $env:USERPROFILE 'vfox-global\flutter'
    if (-not (Test-Path $vfoxGlobalFlutter)) {
        Write-Host "  Repairing: vfox global Junction..."
        $vfoxTarget = Join-Path $env:USERPROFILE '.version-fox\sdks\flutter'
        if (Test-Path $vfoxTarget) {
            $vfoxGlobalDir = Join-Path $env:USERPROFILE 'vfox-global'
            if (-not (Test-Path $vfoxGlobalDir)) { New-Item -ItemType Directory -Path $vfoxGlobalDir -Force | Out-Null }
            New-Item -ItemType Junction -Path $vfoxGlobalFlutter -Target $vfoxTarget -Force | Out-Null
            if (Test-Path $vfoxGlobalFlutter) {
                Write-Host "    [OK] Junction created: $vfoxGlobalFlutter" -ForegroundColor Green
            }
        }
    }
    # WSL symlinks
    $symFail = $results | Where-Object { $_.status -eq 'FAIL' -and $_.name -match '/w:|/W:|/blaze-out' }
    if ($symFail) {
        Write-Host "  Repairing: WSL symlinks (may need sudo)..."
        $symScript = Join-Path $rootDir 'tools\setup-wsl-symlink.sh'
        if (Test-Path $symScript) {
            $sDrive = $symScript.Substring(0,1).ToLower()
            $sRest = $symScript.Substring(2) -replace '\\', '/'
            $wslScript = "/mnt/$sDrive$sRest"
            $symDrive = if ($config.workspace.mappedDrive) { $config.workspace.mappedDrive } else { 'W' }
            $symResult = & wsl.exe -d $distro -e bash -c "sudo bash $wslScript $distro $symDrive 2>&1"
            if ($LASTEXITCODE -eq 0) {
                Write-Host "    [OK] Symlinks repaired" -ForegroundColor Green
            } else {
                Write-Host "    [WARN] May need manual run" -ForegroundColor Yellow
            }
        }
    }
    Write-Host ""
    Write-Host "  Re-run 'fw doctor' to verify repairs." -ForegroundColor Gray
}

# --collect: generate diagnostic report zip
if ($collect) {
    Write-Host ""
    Write-Host "Generating diagnostic report..." -ForegroundColor Cyan
    $tmpDir = Join-Path $env:TEMP "flutterwrapper-report"
    if (Test-Path $tmpDir) { Remove-Item $tmpDir -Force -Recurse -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    # doctor.json
    $output = @{ results = $results; summary = @{ passed = ($results | Where-Object { $_.status -eq 'PASS' }).Count; failed = $issueCount; warnings = $warnCount; total = $results.Count } }
    $json | Out-File -FilePath (Join-Path $tmpDir 'doctor.json') -Encoding UTF8
    # config (anonymized — strip executable paths)
    if ($config) {
        $safeConfig = $config.Clone()
        if ($safeConfig.flutter) { $safeConfig.flutter.executable = '[REDACTED]' }
        if ($safeConfig.dart) { $safeConfig.dart.executable = '[REDACTED]' }
        if ($safeConfig.java) { $safeConfig.java.home = '[REDACTED]' }
        ($safeConfig | ConvertTo-Json -Depth 3) | Out-File -FilePath (Join-Path $tmpDir 'config.json') -Encoding UTF8
    }
    # logs (last 100 lines each, truncated for privacy)
    foreach ($logName in @('flutter', 'dart', 'bridge')) {
        $logFile = Join-Path $rootDir "logs\$logName.log"
        if (Test-Path $logFile) {
            $lines = Get-Content $logFile -Tail 100
            # Redact user paths
            $redacted = $lines -replace '/home/\w+/', '/home/<user>/' -replace 'cwd=[A-Za-z]:[^ ]+', 'cwd=[REDACTED]'
            $redacted | Out-File -FilePath (Join-Path $tmpDir "$logName.log") -Encoding UTF8
        }
    }
    # environment summary
    $envInfo = @"
Windows: $([Environment]::OSVersion.VersionString)
WSL Distro: $distro
Flutter Provider: $(if (Get-Command vfox -ErrorAction SilentlyContinue) { 'vfox' } elseif ($distro) { 'FVM/manual' } else { 'unknown' })
Flutter Executable: $($config.flutter.executable)
Config Path: $configPath
"@
    $envInfo | Out-File -FilePath (Join-Path $tmpDir 'environment.txt') -Encoding UTF8
    # zip
    $zipPath = Join-Path (Get-Location).Path 'flutterwrapper-report.zip'
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($tmpDir, $zipPath)
    Remove-Item $tmpDir -Force -Recurse -ErrorAction SilentlyContinue
    Write-OK "Report saved: $zipPath"
    Write-Host "  Attach this file when submitting GitHub issues." -ForegroundColor Gray
}

exit $issueCount
