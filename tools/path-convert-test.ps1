# Phase 3: Path conversion module + test suite
# Pure string-rule implementation (no wslpath call) for performance.
# WSL path mapping rules (config-driven):
#   D:\path           -> /mnt/d/path          (drive letter lowercased, \ -> /)
#   \\wsl.localhost\<distro>\<path> -> /<path>  (prefix stripped, \ -> /)
#   \\wsl$\<distro>\<path>          -> /<path>
#   lib/main.dart     -> lib/main.dart        (relative, unchanged)
# Reverse:
#   /mnt/d/path       -> D:\path              (drive uppercased, / -> \)
#   /home/berial/demo -> \\wsl.localhost\<distro>\home\berial\demo
#   lib/main.dart     -> lib/main.dart        (relative, unchanged)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Config (would be read from config/wrapper.yaml in real wrapper)
$script:Config = @{
    distro     = 'Ubuntu-24.04'
    uncPrefix  = '\\wsl.localhost\Ubuntu-24.04'
    driveMount = '/mnt'
}

# ---------- Windows -> WSL ----------

function ConvertTo-WslPath {
    param([string]$Path)
    if (-not $Path) { return $Path }

    # UNC \\wsl.localhost\<distro>\<rest>  or  \\wsl$\<distro>\<rest>
    # Case-insensitive prefix match.
    if ($Path -match '^\\\\[wW][sS][lL]\.(?:[lL][oO][cC][aA][lL][hH][oO][sS][tT])\\([^\\]+)\\(.*)$') {
        $rest = $Matches[2] -replace '\\', '/'
        if ($rest) { return "/$rest" } else { return "/" }
    }
    if ($Path -match '^\\\\[wW][sS][lL]\$\\([^\\]+)\\(.*)$') {
        $rest = $Matches[2] -replace '\\', '/'
        if ($rest) { return "/$rest" } else { return "/" }
    }
    # UNC with only distro, no trailing path: \\wsl.localhost\Ubuntu-24.04
    if ($Path -match '^\\\\[wW][sS][lL]\.(?:[lL][oO][cC][aA][lL][hH][oO][sS][tT])\\([^\\]+)$') {
        return "/"
    }
    if ($Path -match '^\\\\[wW][sS][lL]\$\\([^\\]+)$') {
        return "/"
    }

    # Drive-letter path: D:\path  or  D:/path
    if ($Path -match '^([A-Za-z]):[\\/](.*)$') {
        $drive = $Matches[1].ToLower()
        $rest  = $Matches[2] -replace '\\', '/'
        if ($rest) { return "$($script:Config.driveMount)/$drive/$rest" }
        else       { return "$($script:Config.driveMount)/$drive/" }
    }

    # Relative path or anything else: unchanged
    return $Path
}

# ---------- WSL -> Windows ----------

function ConvertTo-WindowsPath {
    param([string]$Path)
    if (-not $Path) { return $Path }

    $mount = $script:Config.driveMount  # e.g. /mnt

    # /mnt/<drive>/<rest>  ->  D:\<rest>
    $mountRegex = '^' + [regex]::Escape($mount) + '/([A-Za-z])/(.*)$'
    if ($Path -match $mountRegex) {
        $drive = $Matches[1].ToUpper()
        $rest  = $Matches[2] -replace '/', '\'
        if ($rest) { return "${drive}:\$rest" }
        else       { return "${drive}:\" }
    }
    # /mnt/<drive>  (no trailing slash, no rest)  ->  D:\
    $mountRootRegex = '^' + [regex]::Escape($mount) + '/([A-Za-z])$'
    if ($Path -match $mountRootRegex) {
        $drive = $Matches[1].ToUpper()
        return "${drive}:\"
    }

    # Absolute WSL path (/home/..., /tmp, /, etc.) -> UNC
    if ($Path -match '^/(.*)$') {
        $rest = $Matches[1] -replace '/', '\'
        if ($rest) { return "$($script:Config.uncPrefix)\$rest" }
        else       { return "$($script:Config.uncPrefix)\" }
    }

    # Relative or anything else: unchanged
    return $Path
}

# ---------- Argument scanner ----------
# Scans a full arg list and converts any path-like values.
# Handles --key=value form by splitting and only converting the value.

function Convert-ArgPath {
    param([string]$Arg)
    # Split --key=value  or  --key:value  (only = is standard, but be lenient)
    if ($Arg -match '^(-{1,2}[^=]+)=(.*)$') {
        $key   = $Matches[1]
        $value = $Matches[2]
        $conv  = ConvertTo-WslPath $value
        return "${key}=${conv}"
    }
    return ConvertTo-WslPath $Arg
}

# ---------- Test runner ----------

function Assert-Equal {
    param([string]$Name, [string]$Expected, [string]$Actual)
    if ($Expected -eq $Actual) {
        Write-Host ("  PASS  {0,-45} -> {1}" -f $Name, $Actual)
        return $true
    } else {
        Write-Host ("  FAIL  {0}" -f $Name)
        Write-Host ("        expected: {0}" -f $Expected)
        Write-Host ("        actual:   {0}" -f $Actual)
        return $false
    }
}

$pass = 0; $fail = 0

Write-Host "=== Windows -> WSL ==="
Write-Host "-- drive-letter paths --"
$cases = @(
    @{n='D:\Android\FlutterWrapper';           e='/mnt/d/Android/FlutterWrapper'},
    @{n='D:/Android/FlutterWrapper';           e='/mnt/d/Android/FlutterWrapper'},
    @{n='D:\';                                  e='/mnt/d/'},
    @{n='C:\Windows\System32';                  e='/mnt/c/Windows/System32'},
    @{n='D:\My Projects\demo';                  e='/mnt/d/My Projects/demo'},
    @{n='D:\Android/FlutterWrapper\bin';        e='/mnt/d/Android/FlutterWrapper/bin'}
)
foreach ($c in $cases) {
    $got = ConvertTo-WslPath $c.n
    if (Assert-Equal $c.n $c.e $got) { $pass++ } else { $fail++ }
}

Write-Host "-- UNC wsl.localhost paths --"
$cases = @(
    @{n='\\wsl.localhost\Ubuntu-24.04\home\berial';          e='/home/berial'},
    @{n='\\wsl.localhost\Ubuntu-24.04\home\berial\demo';     e='/home/berial/demo'},
    @{n='\\wsl.localhost\Ubuntu-24.04\tmp';                   e='/tmp'},
    @{n='\\wsl.localhost\Ubuntu-24.04\';                      e='/'},
    @{n='\\wsl.localhost\Ubuntu-24.04';                       e='/'},
    @{n='\\WSL.LOCALHOST\Ubuntu-24.04\home\berial';          e='/home/berial'},
    @{n='\\Wsl.LocalHost\Ubuntu-24.04\tmp\foo';               e='/tmp/foo'}
)
foreach ($c in $cases) {
    $got = ConvertTo-WslPath $c.n
    if (Assert-Equal $c.n $c.e $got) { $pass++ } else { $fail++ }
}

Write-Host "-- UNC wsl$ paths --"
$cases = @(
    @{n='\\wsl$\Ubuntu-24.04\home\berial';                   e='/home/berial'},
    @{n='\\wsl$\Ubuntu-24.04\tmp\foo';                        e='/tmp/foo'},
    @{n='\\WSL$\Ubuntu-24.04\home';                           e='/home'}
)
foreach ($c in $cases) {
    $got = ConvertTo-WslPath $c.n
    if (Assert-Equal $c.n $c.e $got) { $pass++ } else { $fail++ }
}

Write-Host "-- relative paths (unchanged) --"
$cases = @(
    @{n='lib/main.dart';     e='lib/main.dart'},
    @{n='./lib';             e='./lib'},
    @{n='../test/foo.dart';  e='../test/foo.dart'},
    @{n='main.dart';         e='main.dart'}
)
foreach ($c in $cases) {
    $got = ConvertTo-WslPath $c.n
    if (Assert-Equal $c.n $c.e $got) { $pass++ } else { $fail++ }
}

Write-Host ""
Write-Host "=== WSL -> Windows ==="
Write-Host "-- /mnt/<drive> paths (drive form) --"
$cases = @(
    @{n='/mnt/d/Android/FlutterWrapper';    e='D:\Android\FlutterWrapper'},
    @{n='/mnt/c/Windows/System32';           e='C:\Windows\System32'},
    @{n='/mnt/d/';                            e='D:\'},
    @{n='/mnt/d';                             e='D:\'},
    @{n='/mnt/d/My Projects/demo';           e='D:\My Projects\demo'}
)
foreach ($c in $cases) {
    $got = ConvertTo-WindowsPath $c.n
    if (Assert-Equal $c.n $c.e $got) { $pass++ } else { $fail++ }
}

Write-Host "-- WSL-internal paths (UNC form) --"
$cases = @(
    @{n='/home/berial';                                              e='\\wsl.localhost\Ubuntu-24.04\home\berial'},
    @{n='/home/berial/demo';                                         e='\\wsl.localhost\Ubuntu-24.04\home\berial\demo'},
    @{n='/tmp';                                                       e='\\wsl.localhost\Ubuntu-24.04\tmp'},
    @{n='/';                                                          e='\\wsl.localhost\Ubuntu-24.04\'},
    @{n='/home/berial/.pub-cache/hosted/pub.flutter-io.cn';          e='\\wsl.localhost\Ubuntu-24.04\home\berial\.pub-cache\hosted\pub.flutter-io.cn'}
)
foreach ($c in $cases) {
    $got = ConvertTo-WindowsPath $c.n
    if (Assert-Equal $c.n $c.e $got) { $pass++ } else { $fail++ }
}

Write-Host "-- relative paths (unchanged) --"
$cases = @(
    @{n='lib/main.dart';     e='lib/main.dart'},
    @{n='./lib';             e='./lib'}
)
foreach ($c in $cases) {
    $got = ConvertTo-WindowsPath $c.n
    if (Assert-Equal $c.n $c.e $got) { $pass++ } else { $fail++ }
}

Write-Host ""
Write-Host "=== Argument scanner (--key=value form) ==="
$cases = @(
    @{n='--target=D:\demo\lib\main.dart';            e='--target=/mnt/d/demo/lib/main.dart'},
    @{n='--device-id=emulator-5554';                  e='--device-id=emulator-5554'},
    @{n='--dart-define=KEY=value';                    e='--dart-define=KEY=value'},
    @{n='--target=lib/main.dart';                     e='--target=lib/main.dart'},
    @{n='D:\workspace\new_app';                       e='/mnt/d/workspace/new_app'}
)
foreach ($c in $cases) {
    $got = Convert-ArgPath $c.n
    if (Assert-Equal $c.n $c.e $got) { $pass++ } else { $fail++ }
}

Write-Host ""
Write-Host "=== Round-trip (Win -> WSL -> Win should be identity for drive paths) ==="
$roundTrips = @(
    'D:\Android\FlutterWrapper',
    'C:\Windows\System32',
    'D:\My Projects\demo'
)
foreach ($orig in $roundTrips) {
    $wsl = ConvertTo-WslPath $orig
    $back = ConvertTo-WindowsPath $wsl
    if (Assert-Equal ("roundtrip: $orig") $orig $back) { $pass++ } else { $fail++ }
}

Write-Host ""
Write-Host "=== Summary ==="
Write-Host ("  PASS: $pass")
Write-Host ("  FAIL: $fail")
if ($fail -gt 0) { exit 1 } else { Write-Host "  ALL PASS" }
