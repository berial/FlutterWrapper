# check-paths.ps1 — Checks 4-5: Path Mapping, WSL Symlinks
# Dot-sourced by doctor.ps1. Uses script-scope variables.

Write-Section "4. Path Mapping"

# Test basic path conversions (uses ConvertTo-WslPath from doctor.ps1 scope)
$testCases = @(
    @{ Input = "D:\Android\FlutterWrapper"; Expected = "$driveMount/d/Android/FlutterWrapper"; Name = 'Drive letter -> WSL' },
    @{ Input = "D:/Android/FlutterWrapper"; Expected = "$driveMount/d/Android/FlutterWrapper"; Name = 'Forward-slash drive' },
    @{ Input = "lib\main.dart"; Expected = "lib/main.dart"; Name = 'Relative backslash swap' },
    @{ Input = "--target=lib\main.dart"; Expected = "--target=lib/main.dart"; Name = 'Arg path value' }
)
if ($uncPrefix) {
    $testCases += @{ Input = "$uncPrefix$wslHome\test" -replace '/', '\'; Expected = "$wslHome/test"; Name = 'UNC -> WSL' }
}
if ($mappedDrive) {
    $testCases += @{ Input = "$($mappedDrive):$wslHome\test" -replace '/', '\'; Expected = "$wslHome/test"; Name = 'Mapped drive -> WSL' }
}
foreach ($tc in $testCases) {
    $result = ConvertTo-WslPath -Path $tc.Input -DriveMount $driveMount -UncPrefix $uncPrefix -MappedDrive $mappedDrive
    if ($tc.Input -match '^(-{1,2}[^=]+)=(.*)$') {
        $result = "$($Matches[1])=$(ConvertTo-WslPath -Path $Matches[2] -DriveMount $driveMount -UncPrefix $uncPrefix -MappedDrive $mappedDrive)"
    }
    if ($result -eq $tc.Expected) { Write-Check $tc.Name 'PASS' "$($tc.Input) -> $($tc.Expected)" }
    else { Write-Check $tc.Name 'FAIL' "$($tc.Input) -> $result (expected: $($tc.Expected))" "" }
}

if ($mappedDrive) {
    if (Test-Path "$($mappedDrive):\") { Write-Check "Mapped drive ($($mappedDrive):)" 'PASS' "Accessible" }
    else { Write-Check "Mapped drive ($($mappedDrive):)" 'FAIL' "Not accessible" "Run: net use $($mappedDrive): $uncPrefix" }
}
if ($uncPrefix) {
    if (Test-Path $uncPrefix -ErrorAction SilentlyContinue) { Write-Check "UNC prefix" 'PASS' $uncPrefix }
    else { Write-Check "UNC prefix" 'FAIL' "Not accessible" "Check WSL distro is running" }
}

Write-Section "5. WSL Symlinks"

if ($distro) {
    $symlinks = @(
        @{ Path = '/w:'; Name = '/w: -> / (mapped drive lowercase)' },
        @{ Path = '/W:'; Name = '/W: -> / (mapped drive uppercase)' },
        @{ Path = '/blaze-out'; Name = '/blaze-out (Blaze detector guard)' }
    )
    foreach ($sl in $symlinks) {
        try {
            $lo = & wsl.exe -d $distro -e ls -la $sl.Path 2>$null
            if ($lo -and $lo -match '->') { Write-Check $sl.Name 'PASS' ($lo -join ' ').Trim() }
            elseif ($lo -and $lo -match '^d') { Write-Check $sl.Name 'PASS' "Directory exists" }
            else { Write-Check $sl.Name 'FAIL' "Symlink/dir missing" "Run: sudo tools/setup-wsl-symlink.sh" }
        } catch { Write-Check $sl.Name 'FAIL' "Cannot check: $($_.Exception.Message)" "Run: sudo tools/setup-wsl-symlink.sh" }
    }
} else { Write-Check 'WSL symlinks' 'SKIP' "No distro configured" }
