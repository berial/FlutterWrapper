# wrapper.ps1 - FlutterWrapper daemon TCP-mode translator (text mode)
#
# Phase 6 (revised 2026-07-20): Text mode instead of byte stream.
# PowerShell 5.1 host's [Console]::OpenStandardInput()/Output() (Stream) is
# unreliable when stdin/stdout are redirected by parent process:
#   - OpenStandardInput().Read() blocks indefinitely
#   - OpenStandardOutput().Write() data doesn't reach parent's pipe reliably
# But [Console]::In/Out (TextReader/TextWriter) work correctly.
# Daemon protocol for normal IDE workflow is all JSON text (binary only in
# proxy domain, which we don't need). So text mode is safe.
#
# Architecture:
#   AS stdin  -> [Console]::In  -> wrapper -> StreamWriter -> TCP 9876 -> WSL daemon
#   AS stdout <- [Console]::Out <- wrapper <- StreamReader  <- TCP 9876 <- WSL daemon
#
# Encoding: UTF-8 (set via [Console]::InputEncoding/OutputEncoding)
# Line ending: LF (daemon protocol uses \n)

$ErrorActionPreference = 'Stop'
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir    = Split-Path -Parent $scriptDir
$configPath = Join-Path $rootDir 'config\wrapper.yaml'
$logPath    = Join-Path $rootDir 'logs\wrapper.log'

# ============================================================
# YAML parser (shared with flutter.ps1)
# ============================================================
function Read-WrapperConfig {
    param([string]$Path)
    if (-not (Test-Path $Path)) { throw "FlutterWrapper: config not found: $Path" }
    $config = @{}; $currentSection = $null
    foreach ($line in Get-Content -Path $Path -Encoding UTF8) {
        $stripped = $line -replace '\s+#.*$', ''
        if ($stripped -match '^\s*$') { continue }
        if ($stripped -match '^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$') {
            $key = $Matches[1]; $val = $Matches[2].Trim()
            if ($val) { $config[$key] = $val.Trim('"').Trim("'") }
            else { $currentSection = $key; $config[$key] = @{} }
        } elseif ($stripped -match '^\s+([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$' -and $currentSection) {
            $config[$currentSection][$Matches[1]] = $Matches[2].Trim().Trim('"').Trim("'")
        }
    }
    return $config
}

# ============================================================
# Path conversion (Phase 3, 40/40 PASS)
# ============================================================
function ConvertTo-WslPath {
    param([string]$Path)
    if (-not $Path) { return $Path }
    if ($script:MappedDrive -and $Path -match "^$($script:MappedDrive):[\\/](.*)$") {
        $rest = $Matches[1] -replace '\\', '/'
        if ($rest) { return "/$rest" } else { return "/" }
    }
    if ($script:MappedDrive -and $Path -match "^$($script:MappedDrive):$") { return "/" }
    if ($Path -match '^\\\\[wW][sS][lL]\.(?:[lL][oO][cC][aA][lL][hH][oO][sS][tT])\\([^\\]+)\\(.*)$') {
        $rest = $Matches[2] -replace '\\', '/'
        if ($rest) { return "/$rest" } else { return "/" }
    }
    if ($Path -match '^\\\\[wW][sS][lL]\.(?:[lL][oO][cC][aA][lL][hH][oO][sS][tT])\\([^\\]+)$') { return "/" }
    if ($Path -match '^\\\\[wW][sS][lL]\$\\([^\\]+)\\(.*)$') {
        $rest = $Matches[2] -replace '\\', '/'
        if ($rest) { return "/$rest" } else { return "/" }
    }
    if ($Path -match '^\\\\[wW][sS][lL]\$\\([^\\]+)$') { return "/" }
    if ($Path -match '^([A-Za-z]):[\\/](.*)$') {
        $drive = $Matches[1].ToLower()
        $rest  = $Matches[2] -replace '\\', '/'
        if ($rest) { return "$script:DriveMount/$drive/$rest" }
        else       { return "$script:DriveMount/$drive/" }
    }
    return $Path
}

function ConvertTo-WindowsPath {
    param([string]$Path)
    if (-not $Path) { return $Path }
    $mount = $script:DriveMount
    $mountRegex = '^' + [regex]::Escape($mount) + '/([A-Za-z])/(.*)$'
    if ($Path -match $mountRegex) {
        $drive = $Matches[1].ToUpper()
        $rest  = $Matches[2] -replace '/', '\'
        if ($rest) { return "${drive}:\$rest" } else { return "${drive}:\" }
    }
    $mountRootRegex = '^' + [regex]::Escape($mount) + '/([A-Za-z])$'
    if ($Path -match $mountRootRegex) { return ($Matches[1].ToUpper()) + ':\' }
    if ($Path -match '^/(.*)$') {
        $rest = $Matches[1] -replace '/', '\'
        if ($rest) { return "$($script:UncPrefix)\$rest" }
        else       { return "$($script:UncPrefix)\" }
    }
    return $Path
}

function ConvertTo-WindowsFileUri {
    param([string]$Uri)
    if (-not $Uri) { return $Uri }
    if ($Uri -match '^file:///([^/].*)$') {
        $path = '/' + $Matches[1]
        $winPath = ConvertTo-WindowsPath $path
        $uriPath = $winPath -replace '\\', '/'
        return "file:///" + $uriPath.TrimStart('/')
    }
    return $Uri
}

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    try {
        $logDir = Split-Path -Parent $logPath
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        Add-Content -Path $logPath -Value "[$ts] [daemon] $Message" -Encoding UTF8
    } catch {}
}

# ============================================================
# Path translation for a single daemon frame (one JSON line)
# direction: 'in' = AS->WSL, 'out' = WSL->AS
# ============================================================
function Translate-Frame {
    param([string]$Line, [string]$Direction)
    try {
        if (-not ($Line -match '^\[\{.*\}\]$')) { return $Line }
        $inner = $Line.Substring(1, $Line.Length - 2)
        $obj = $inner | ConvertFrom-Json
        $modified = $false

        if ($Direction -eq 'in') {
            if ($obj.PSObject.Properties.Name -contains 'method') {
                $method = $obj.method
                if ($method -eq 'daemon.getSupportedPlatforms' -and
                    $obj.PSObject.Properties.Name -contains 'params' -and
                    $obj.params.PSObject.Properties.Name -contains 'projectRoot') {
                    $orig = $obj.params.projectRoot
                    $new = ConvertTo-WslPath $orig
                    if ($new -ne $orig) {
                        $obj.params.projectRoot = $new; $modified = $true
                        Write-Log "in  getSupportedPlatforms.projectRoot: $orig -> $new"
                    }
                } elseif ($method -eq 'device.startApp' -and
                    $obj.PSObject.Properties.Name -contains 'params' -and
                    $obj.params.PSObject.Properties.Name -contains 'mainPath') {
                    $orig = $obj.params.mainPath
                    if ($orig -and $orig -match '^([A-Za-z]:[\\/])|^(\\\\)') {
                        $new = ConvertTo-WslPath $orig
                        if ($new -ne $orig) {
                            $obj.params.mainPath = $new; $modified = $true
                            Write-Log "in  device.startApp.mainPath: $orig -> $new"
                        }
                    }
                }
            }
        } elseif ($Direction -eq 'out') {
            if ($obj.PSObject.Properties.Name -contains 'event') {
                $event = $obj.event
                if ($event -eq 'app.start' -and
                    $obj.PSObject.Properties.Name -contains 'params' -and
                    $obj.params.PSObject.Properties.Name -contains 'directory') {
                    $orig = $obj.params.directory
                    $new = ConvertTo-WindowsPath $orig
                    if ($new -ne $orig) {
                        $obj.params.directory = $new; $modified = $true
                        Write-Log "out app.start.directory: $orig -> $new"
                    }
                } elseif ($event -eq 'app.debugPort' -and
                    $obj.PSObject.Properties.Name -contains 'params' -and
                    $obj.params.PSObject.Properties.Name -contains 'baseUri') {
                    $orig = $obj.params.baseUri
                    if ($orig -and $orig.StartsWith('file://')) {
                        $new = ConvertTo-WindowsFileUri $orig
                        if ($new -ne $orig) {
                            $obj.params.baseUri = $new; $modified = $true
                            Write-Log "out app.debugPort.baseUri: $orig -> $new"
                        }
                    }
                }
            }
        }

        if ($modified) {
            return '[' + ($obj | ConvertTo-Json -Compress -Depth 100) + ']'
        }
    } catch {
        Write-Log ("warn translate failed: " + $_.Exception.Message)
    }
    return $Line
}

# ============================================================
# Main - TCP mode (text)
# ============================================================
$config = Read-WrapperConfig $configPath
$distro     = $config.wsl.distro
$flutterExe = $config.flutter.executable
$script:DriveMount = $config.workspace.driveMount
if (-not $script:DriveMount) { $script:DriveMount = '/mnt' }
$script:UncPrefix = $config.workspace.uncPrefix
$script:MappedDrive = $config.workspace.mappedDrive
if ($script:MappedDrive -and $script:MappedDrive -match '^([A-Za-z]):') {
    $script:MappedDrive = $Matches[1].ToUpper()
}
$tcpPort = if ($config.daemon.tcpPort) { [int]$config.daemon.tcpPort } else { 9876 }

# Resolve Android SDK path for WSL (points to WINDOWS SDK).
# build-tools have Linux shell wrappers that call .exe via WSL interop.
# platform-tools/adb.exe likewise. The WSL-local SDK (wslSdkPath) is only
# used for NDK + cmake (see $wslNdkPath below).
$winAndroidSdk = $config.android.sdkPath
if (-not $winAndroidSdk) { $winAndroidSdk = $env:ANDROID_HOME }
if (-not $winAndroidSdk) { $winAndroidSdk = $env:ANDROID_SDK_ROOT }
if (-not $winAndroidSdk -and (Test-Path 'D:\Android\Sdk')) { $winAndroidSdk = 'D:\Android\Sdk' }
$wslAndroidSdk = if ($winAndroidSdk) { ConvertTo-WslPath $winAndroidSdk } else { $null }

# Resolve WSL-local NDK path (for AGP NdkHandler).
# Accessed via UNC because Test-Path on /home/... is unreliable on Windows.
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

# Resolve JAVA_HOME for WSL (gradle needs JDK; wsl.exe drops Windows env vars)
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

$winCwd = (Get-Location).Path
$wslCwd = ConvertTo-WslPath $winCwd

# Start wsl.exe daemon in TCP mode.
# Use ProcessStartInfo with:
#   - RedirectStandardInput=true  (PREVENT wsl.exe from inheriting wrapper's stdin
#     pipe, which would consume daemon requests meant for wrapper)
#   - RedirectStandardOutput=false (let wsl.exe inherit console stdout; redirecting
#     it causes TTY detection issue and TCP EOF, see docs/daemon.md §8.3)
#   - RedirectStandardError=false  (same reason)
$wslArgs = "-d $distro --cd $wslCwd -e $flutterExe daemon --listen-on-tcp-port=$tcpPort"
Write-Log "starting daemon: wsl $wslArgs"

$wslPsi = New-Object System.Diagnostics.ProcessStartInfo
$wslPsi.FileName = 'wsl.exe'
$wslPsi.Arguments = $wslArgs
$wslPsi.UseShellExecute = $false
$wslPsi.RedirectStandardInput = $true   # prevent inheriting wrapper stdin
$wslPsi.RedirectStandardOutput = $false # inherit console (TTY detection safe)
$wslPsi.RedirectStandardError = $false
$wslPsi.CreateNoWindow = $true
$wslPsi.WorkingDirectory = $winCwd
# Inject ANDROID_HOME/JAVA_HOME so flutter daemon can find adb.exe and JDK.
# WSLENV is required: wsl.exe does NOT forward Windows process env vars
# into WSL by default. Without WSLENV, ANDROID_HOME/JAVA_HOME are empty.
$wslenvParts = @()
if ($wslAndroidSdk) {
    $wslPsi.EnvironmentVariables['ANDROID_HOME'] = $wslAndroidSdk
    $wslPsi.EnvironmentVariables['ANDROID_SDK_ROOT'] = $wslAndroidSdk
    $wslenvParts += 'ANDROID_HOME/u','ANDROID_SDK_ROOT/u'
}
if ($wslNdkPath) {
    # AGP NdkHandler falls back to ANDROID_NDK_HOME/ROOT when sdk.dir's SDK
    # has no NDK. Injecting these makes AGP find the WSL Linux NDK even if
    # flutter rewrites sdk.dir to the Windows SDK path.
    $wslPsi.EnvironmentVariables['ANDROID_NDK_HOME'] = $wslNdkPath
    $wslPsi.EnvironmentVariables['ANDROID_NDK_ROOT'] = $wslNdkPath
    $wslenvParts += 'ANDROID_NDK_HOME/u','ANDROID_NDK_ROOT/u'
}
if ($wslJavaHome) {
    $wslPsi.EnvironmentVariables['JAVA_HOME'] = $wslJavaHome
    $wslenvParts += 'JAVA_HOME/u'
}
if ($wslChrome) {
    $wslPsi.EnvironmentVariables['CHROME_EXECUTABLE'] = $wslChrome
    $wslenvParts += 'CHROME_EXECUTABLE/u'
}
if ($wslPubCache) {
    $wslPsi.EnvironmentVariables['PUB_CACHE'] = $wslPubCache
    $wslenvParts += 'PUB_CACHE/u'
}
if ($wslenvParts.Count -gt 0) {
    $existingWslenv = $wslPsi.EnvironmentVariables['WSLENV']
    $newWslenv = $wslenvParts -join ':'
    if ($existingWslenv) {
        $wslPsi.EnvironmentVariables['WSLENV'] = "$existingWslenv`:$newWslenv"
    } else {
        $wslPsi.EnvironmentVariables['WSLENV'] = $newWslenv
    }
}
if ($wslAndroidSdk) { Write-Log "ANDROID_HOME=$wslAndroidSdk (via WSLENV)" }
if ($wslJavaHome)   { Write-Log "JAVA_HOME=$wslJavaHome (via WSLENV)" }
if ($wslChrome)     { Write-Log "CHROME_EXECUTABLE=$wslChrome (via WSLENV)" }
if ($wslPubCache)   { Write-Log "PUB_CACHE=$wslPubCache (via WSLENV)" }

$wslProc = New-Object System.Diagnostics.Process
$wslProc.StartInfo = $wslPsi
$null = $wslProc.Start()
# Close wsl.exe stdin immediately (daemon doesn't read stdin, and closing it
# prevents wsl.exe from blocking on it)
try { $wslProc.StandardInput.Close() } catch {}
Write-Log "wsl.exe pid=$($wslProc.Id)"

# Wait for TCP port to be available
$maxWait = 45
$deadline = (Get-Date).AddSeconds($maxWait)
$connected = $false
$client = $null

Write-Log "waiting for TCP port $tcpPort (up to ${maxWait}s)..."
while ((Get-Date) -lt $deadline -and -not $wslProc.HasExited) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $client.Connect('127.0.0.1', $tcpPort)
        $connected = $true
        break
    } catch {
        Start-Sleep -Milliseconds 300
    }
}

if (-not $connected) {
    Write-Log "FAIL: could not connect to TCP $tcpPort in ${maxWait}s"
    Write-Error "FlutterWrapper: daemon TCP port $tcpPort not available"
    if (-not $wslProc.HasExited) { $wslProc.Kill() }
    exit 1
}

Write-Log "TCP connected to 127.0.0.1:$tcpPort"

# Wrap TCP stream with StreamReader/Writer (UTF-8, LF)
$tcpStream  = $client.GetStream()
$tcpReader  = New-Object System.IO.StreamReader($tcpStream, [System.Text.Encoding]::UTF8)
$tcpWriter  = New-Object System.IO.StreamWriter($tcpStream, [System.Text.Encoding]::UTF8)
$tcpWriter.NewLine = "`n"
$tcpWriter.AutoFlush = $true

# Helper functions stringified for runspaces
$helperFunctions = @'
function ConvertTo-WslPath {
    param([string]$Path)
    if (-not $Path) { return $Path }
    if ($MappedDrive -and $Path -match "^$($MappedDrive):[\\/](.*)$") {
        $rest = $Matches[1] -replace '\\', '/'
        if ($rest) { return "/$rest" } else { return "/" }
    }
    if ($MappedDrive -and $Path -match "^$($MappedDrive):$") { return "/" }
    if ($Path -match '^\\\\[wW][sS][lL]\.(?:[lL][oO][cC][aA][lL][hH][oO][sS][tT])\\([^\\]+)\\(.*)$') {
        $rest = $Matches[2] -replace '\\', '/'
        if ($rest) { return "/$rest" } else { return "/" }
    }
    if ($Path -match '^\\\\[wW][sS][lL]\.(?:[lL][oO][cC][aA][lL][hH][oO][sS][tT])\\([^\\]+)$') { return "/" }
    if ($Path -match '^\\\\[wW][sS][lL]\$\\([^\\]+)\\(.*)$') {
        $rest = $Matches[2] -replace '\\', '/'
        if ($rest) { return "/$rest" } else { return "/" }
    }
    if ($Path -match '^\\\\[wW][sS][lL]\$\\([^\\]+)$') { return "/" }
    if ($Path -match '^([A-Za-z]):[\\/](.*)$') {
        $drive = $Matches[1].ToLower()
        $rest  = $Matches[2] -replace '\\', '/'
        if ($rest) { return "$DriveMount/$drive/$rest" }
        else       { return "$DriveMount/$drive/" }
    }
    return $Path
}
function ConvertTo-WindowsPath {
    param([string]$Path)
    if (-not $Path) { return $Path }
    $mountRegex = '^' + [regex]::Escape($DriveMount) + '/([A-Za-z])/(.*)$'
    if ($Path -match $mountRegex) {
        $drive = $Matches[1].ToUpper()
        $rest  = $Matches[2] -replace '/', '\'
        if ($rest) { return "${drive}:\$rest" } else { return "${drive}:\" }
    }
    $mountRootRegex = '^' + [regex]::Escape($DriveMount) + '/([A-Za-z])$'
    if ($Path -match $mountRootRegex) { return ($Matches[1].ToUpper()) + ':\' }
    if ($Path -match '^/(.*)$') {
        $rest = $Matches[1] -replace '/', '\'
        if ($rest) { return "$UncPrefix\$rest" } else { return "$UncPrefix\" }
    }
    return $Path
}
function ConvertTo-WindowsFileUri {
    param([string]$Uri)
    if (-not $Uri) { return $Uri }
    if ($Uri -match '^file:///([^/].*)$') {
        $path = '/' + $Matches[1]
        $winPath = ConvertTo-WindowsPath $path
        $uriPath = $winPath -replace '\\', '/'
        return "file:///" + $uriPath.TrimStart('/')
    }
    return $Uri
}
function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    try { Add-Content -Path $LogPath -Value "[$ts] [daemon] $Message" -Encoding UTF8 } catch {}
}
function Translate-Frame {
    param([string]$Line, [string]$Direction)
    try {
        if (-not ($Line -match '^\[\{.*\}\]$')) { return $Line }
        $inner = $Line.Substring(1, $Line.Length - 2)
        $obj = $inner | ConvertFrom-Json
        $modified = $false
        if ($Direction -eq 'in') {
            if ($obj.PSObject.Properties.Name -contains 'method') {
                $method = $obj.method
                if ($method -eq 'daemon.getSupportedPlatforms' -and
                    $obj.PSObject.Properties.Name -contains 'params' -and
                    $obj.params.PSObject.Properties.Name -contains 'projectRoot') {
                    $orig = $obj.params.projectRoot
                    $new = ConvertTo-WslPath $orig
                    if ($new -ne $orig) { $obj.params.projectRoot = $new; $modified = $true; Write-Log "in  projectRoot: $orig -> $new" }
                } elseif ($method -eq 'device.startApp' -and
                    $obj.PSObject.Properties.Name -contains 'params' -and
                    $obj.params.PSObject.Properties.Name -contains 'mainPath') {
                    $orig = $obj.params.mainPath
                    if ($orig -and $orig -match '^([A-Za-z]:[\\/])|^(\\\\)') {
                        $new = ConvertTo-WslPath $orig
                        if ($new -ne $orig) { $obj.params.mainPath = $new; $modified = $true; Write-Log "in  mainPath: $orig -> $new" }
                    }
                }
            }
        } elseif ($Direction -eq 'out') {
            if ($obj.PSObject.Properties.Name -contains 'event') {
                $event = $obj.event
                if ($event -eq 'app.start' -and
                    $obj.PSObject.Properties.Name -contains 'params' -and
                    $obj.params.PSObject.Properties.Name -contains 'directory') {
                    $orig = $obj.params.directory
                    $new = ConvertTo-WindowsPath $orig
                    if ($new -ne $orig) { $obj.params.directory = $new; $modified = $true; Write-Log "out directory: $orig -> $new" }
                } elseif ($event -eq 'app.debugPort' -and
                    $obj.PSObject.Properties.Name -contains 'params' -and
                    $obj.params.PSObject.Properties.Name -contains 'baseUri') {
                    $orig = $obj.params.baseUri
                    if ($orig -and $orig.StartsWith('file://')) {
                        $new = ConvertTo-WindowsFileUri $orig
                        if ($new -ne $orig) { $obj.params.baseUri = $new; $modified = $true; Write-Log "out baseUri: $orig -> $new" }
                    }
                }
            }
        }
        if ($modified) {
            return '[' + ($obj | ConvertTo-Json -Compress -Depth 100) + ']'
        }
    } catch { Write-Log ("warn: " + $_.Exception.Message) }
    return $Line
}
'@

# Runspace 1: AS stdin -> TCP (translate 'in')
$inPumpBody = @'
Write-Log "in: pump start"
while ($true) {
    $line = [Console]::In.ReadLine()
    if ($null -eq $line) { Write-Log "in: stdin EOF"; break }
    $translated = Translate-Frame $line 'in'
    try { $tcpWriter.WriteLine($translated) } catch { Write-Log "in: tcp write err: $($_.Exception.Message)"; break }
}
Write-Log "in: pump exit"
'@

# Runspace 2: TCP -> AS stdout (translate 'out')
$outPumpBody = @'
Write-Log "out: pump start"
while ($true) {
    $line = $tcpReader.ReadLine()
    if ($null -eq $line) { Write-Log "out: tcp EOF"; break }
    $translated = Translate-Frame $line 'out'
    try {
        [Console]::Out.WriteLine($translated)
        [Console]::Out.Flush()
    } catch { Write-Log "out: console write err: $($_.Exception.Message)"; break }
}
Write-Log "out: pump exit"
'@

$inParamBlock  = 'param($tcpWriter, $logPath, $DriveMount, $UncPrefix, $MappedDrive)'
$outParamBlock = 'param($tcpReader, $logPath, $DriveMount, $UncPrefix, $MappedDrive)'
$inScript  = $inParamBlock + "`n" + $helperFunctions + "`n" + $inPumpBody
$outScript = $outParamBlock + "`n" + $helperFunctions + "`n" + $outPumpBody

# Runspace 1: stdin -> TCP
$rs1 = [runspacefactory]::CreateRunspace()
$rs1.Open()
$rs1.SessionStateProxy.SetVariable('DriveMount', $script:DriveMount)
$rs1.SessionStateProxy.SetVariable('UncPrefix', $script:UncPrefix)
$rs1.SessionStateProxy.SetVariable('MappedDrive', $script:MappedDrive)
$rs1.SessionStateProxy.SetVariable('LogPath', $logPath)
$ps1 = [powershell]::Create()
$ps1.Runspace = $rs1
$null = $ps1.AddScript($inScript)
$null = $ps1.AddParameters(@{tcpWriter=$tcpWriter; logPath=$logPath; DriveMount=$script:DriveMount; UncPrefix=$script:UncPrefix; MappedDrive=$script:MappedDrive})
$handle1 = $ps1.BeginInvoke()

# Runspace 2: TCP -> stdout
$rs2 = [runspacefactory]::CreateRunspace()
$rs2.Open()
$rs2.SessionStateProxy.SetVariable('DriveMount', $script:DriveMount)
$rs2.SessionStateProxy.SetVariable('UncPrefix', $script:UncPrefix)
$rs2.SessionStateProxy.SetVariable('MappedDrive', $script:MappedDrive)
$rs2.SessionStateProxy.SetVariable('LogPath', $logPath)
$ps2 = [powershell]::Create()
$ps2.Runspace = $rs2
$null = $ps2.AddScript($outScript)
$null = $ps2.AddParameters(@{tcpReader=$tcpReader; logPath=$logPath; DriveMount=$script:DriveMount; UncPrefix=$script:UncPrefix; MappedDrive=$script:MappedDrive})
$handle2 = $ps2.BeginInvoke()

# Wait for wsl.exe to exit OR TCP pump to exit (daemon shutdown closes TCP
# but doesn't always make wsl.exe exit promptly; if out pump is done, we
# treat it as daemon shutdown and force-kill wsl.exe)
while (-not $wslProc.HasExited) {
    if ($handle2.IsCompleted) {
        Write-Log "TCP closed, killing wsl.exe"
        try { $wslProc.Kill() } catch {}
        $wslProc.WaitForExit(2000) | Out-Null
        break
    }
    if ($wslProc.WaitForExit(200)) { break }
    if ($handle1.IsCompleted -and $handle2.IsCompleted) { break }
}

$exitCode = if ($wslProc.HasExited) { $wslProc.ExitCode } else { 0 }
Write-Log "exit code=$exitCode"

# Cleanup: in pump (Runspace 1) is blocked on [Console]::In.ReadLine() which
# is a native blocking call that PowerShell.Stop() cannot interrupt. PowerShell's
# `exit` waits for all runspaces to finish, so the process would hang. Use
# [Environment]::Exit() to forcibly terminate the process immediately.
try { $tcpReader.Close() } catch {}
try { $tcpWriter.Close() } catch {}
try { $tcpStream.Close() } catch {}
try { $client.Close() } catch {}
try { $ps2.EndInvoke($handle2) } catch {}
[System.Environment]::Exit($exitCode)
