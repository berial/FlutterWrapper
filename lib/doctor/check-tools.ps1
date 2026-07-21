# check-tools.ps1 — Checks 6-11: Android Studio, SDK, Analysis, Daemon, Gradle, NDK
# Dot-sourced by doctor.ps1. Uses script-scope variables.

Write-Section "6. Android Studio"
$asPaths = @("${env:ProgramFiles}\Android\Android Studio","${env:ProgramFiles(x86)}\Android\Android Studio","${env:LOCALAPPDATA}\Programs\Android Studio","C:\Program Files\Android\Android Studio","D:\Android\AndroidStudio")
$asFound = $false
foreach ($p in $asPaths) { if (Test-Path $p) { Write-Check 'Android Studio' 'PASS' "Found at $p"; $asFound = $true; break } }
if (-not $asFound) { Write-Check 'Android Studio' 'WARN' "Not found in common paths" "If installed elsewhere, this is expected" }

Write-Section "7. Android SDK"
$androidSdk = $config.android.sdkPath
if (-not $androidSdk) { $androidSdk = $env:ANDROID_HOME }
if (-not $androidSdk) { $androidSdk = $env:ANDROID_SDK_ROOT }
if (-not $androidSdk) { $androidSdk = 'D:\Android\Sdk' }
if (Test-Path $androidSdk) {
    Write-Check "Android SDK" 'PASS' $androidSdk
    foreach ($t in @('platform-tools\adb.exe','build-tools')) {
        $tp = Join-Path $androidSdk $t
        if (Test-Path $tp) { Write-Check "  $t" 'PASS' "Present" }
        else { Write-Check "  $t" 'WARN' "Missing" "Install via SDK Manager" }
    }
    if (-not $quick) {
        try { $av = & (Join-Path $androidSdk 'platform-tools\adb.exe') version 2>$null | Select -First 1; Write-Check '  adb version' 'PASS' $av } catch { Write-Check '  adb version' 'WARN' "Cannot run" }
    }
} else { Write-Check "Android SDK" 'FAIL' "Not found ($androidSdk)" "Set android.sdkPath or install SDK" }

Write-Section "8. Dart Analysis Layer"
$dartSdkLink = Join-Path $rootDir 'bin\cache\dart-sdk'
$dartExeWin = Join-Path $dartSdkLink 'bin\dart.exe'
if (Test-Path $dartExeWin) {
    if (Test-Path (Join-Path $dartSdkLink 'version')) { Write-Check 'dart-sdk Junction' 'PASS' "Valid Dart SDK" }
    else { Write-Check 'dart-sdk Junction' 'WARN' "Exists but version file missing" }
    if (Test-Path (Join-Path $rootDir 'bin\cache\flutter.version.json')) { Write-Check 'flutter.version.json' 'PASS' "Present" }
    else { Write-Check 'flutter.version.json' 'WARN' "Missing" "Run: install.ps1" }
    if (-not $quick) {
        try { $dv = & $dartExeWin --version 2>&1 | Select -First 1; Write-Check 'Windows dart.exe' 'PASS' ($dv -replace '\s+',' ') } catch { Write-Check 'Windows dart.exe' 'FAIL' "Cannot run" "Check vfox Windows global or re-create Junction" }
    }
} else { Write-Check 'dart-sdk Junction' 'FAIL' "Not found at bin/cache/dart-sdk" "Run install.ps1" }
if (-not $quick) {
    $vfg = Join-Path $env:USERPROFILE 'vfox-global\flutter'
    if (Test-Path $vfg) { Write-Check 'vfox global flutter' 'PASS' $vfg }
    else { Write-Check 'vfox global flutter' 'WARN' "Not found" "Run: vfox use -g flutter@<version>" }
}

Write-Section "9. Daemon Translation"
$wrapperPath = Join-Path $scriptDir 'wrapper.ps1'
if (Test-Path $wrapperPath) { Write-Check 'wrapper.ps1' 'PASS' "Found" }
else { Write-Check 'wrapper.ps1' 'FAIL' "Not found" "" }
$daemonPort = if ($config.daemon.tcpPort) { $config.daemon.tcpPort } else { '9876' }
Write-Check "Daemon TCP port" 'PASS' $daemonPort
if (-not $quick) {
    try {
        $pc = & wsl.exe -d $distro -e bash -lc "command -v fuser >/dev/null && fuser $daemonPort/tcp 2>/dev/null || echo NOT_INSTALLED" 2>$null
        $pc = ($pc -join '').Trim()
        if ($pc -eq 'NOT_INSTALLED') { Write-Check "TCP port $daemonPort" 'PASS' "Likely available" }
        elseif ($pc -match '\d+') { Write-Check "TCP port $daemonPort" 'WARN' "In use (stale daemon?)" "fuser -k $daemonPort/tcp" }
        else { Write-Check "TCP port $daemonPort" 'PASS' "Available" }
    } catch { Write-Check "TCP port $daemonPort" 'PASS' "Likely available" }
}

Write-Section "10. Gradle & Java"
$javaHome = $config.java.home
if ($javaHome) {
    try {
        $jc = & wsl.exe -d $distro -e bash -lc "test -d `"$javaHome`" && echo OK || echo MISSING" 2>$null
        if (($jc -join '').Trim() -eq 'OK') {
            Write-Check 'JAVA_HOME' 'PASS' $javaHome
            if (-not $quick) { try { $jv = & wsl.exe -d $distro -e "$javaHome/bin/java" -version 2>&1 | Select -First 1; Write-Check '  Java version' 'PASS' ($jv -replace '\s+',' ') } catch {} }
        } else { Write-Check 'JAVA_HOME' 'FAIL' "Not found in WSL" "Install JDK or update config" }
    } catch { Write-Check 'JAVA_HOME' 'WARN' "Cannot verify" }
} else { Write-Check 'JAVA_HOME' 'WARN' "Not configured" "Set java.home in config" }
try {
    $mp = "$wslHome/.gradle/init.d/mirror.gradle"
    $mc = & wsl.exe -d $distro -e bash -lc "test -f `"$mp`" && echo OK || echo MISSING" 2>$null
    if (($mc -join '').Trim() -eq 'OK') { Write-Check 'Gradle mirror' 'PASS' "mirror.gradle configured" }
    else { Write-Check 'Gradle mirror' 'WARN' "Not configured" "Run: bash tools/setup-gradle-mirror.sh" }
} catch { Write-Check 'Gradle mirror' 'SKIP' "Cannot check" }

Write-Section "11. Native Build Tools"
$wslSdk = $config.android.wslSdkPath
if ($wslSdk) {
    try {
        $nc = & wsl.exe -d $distro -e bash -lc "test -d `"$wslSdk/ndk`" && echo OK || echo MISSING" 2>$null
        if (($nc -join '').Trim() -eq 'OK') { Write-Check 'WSL NDK' 'PASS' "$wslSdk/ndk" }
        else { Write-Check 'WSL NDK' 'FAIL' "Not found" "Run: bash tools/setup-wsl-ndk.sh" }
        $cc = & wsl.exe -d $distro -e bash -lc "test -d `"$wslSdk/cmake`" && echo OK || echo MISSING" 2>$null
        if (($cc -join '').Trim() -eq 'OK') { Write-Check 'WSL cmake' 'PASS' "$wslSdk/cmake" }
        else { Write-Check 'WSL cmake' 'FAIL' "Not found" "Run: bash tools/setup-wsl-ndk.sh" }
    } catch { Write-Check 'Native build tools' 'SKIP' "Cannot check" }
} else { Write-Check 'Native build tools' 'SKIP' "wslSdkPath not configured" }
