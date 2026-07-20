# Phase 6f: Verify daemon.getSupportedPlatforms path translation
# - Send Windows projectRoot, wrapper should translate to WSL path before forwarding
# - Daemon should respond with supported platforms (proves path was valid WSL path)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=== Phase 6f: daemon.getSupportedPlatforms path translation ==="

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'powershell.exe'
$psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "d:\Android\FlutterWrapper\bin\wrapper.ps1"'
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$psi.WorkingDirectory = 'd:\Android\FlutterWrapper'

$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi
$null = $proc.Start()
Write-Host ("wrapper pid: $($proc.Id)")

$timeout = 30
$deadline = (Get-Date).AddSeconds($timeout)
$gotConnected = $false
$gotPlatformsResponse = $false
$platformsResult = $null

# Windows projectRoot - should be translated to /mnt/d/Android/FlutterWrapper
$winRoot = 'D:\Android\FlutterWrapper'
# Build JSON via ConvertTo-Json to properly escape backslashes
$reqObj = [PSCustomObject]@{
    id = '1'
    method = 'daemon.getSupportedPlatforms'
    params = [PSCustomObject]@{ projectRoot = $winRoot }
}
$reqJson = '[' + ($reqObj | ConvertTo-Json -Compress -Depth 10) + ']' + "`n"
$proc.StandardInput.Write($reqJson)
$proc.StandardInput.Flush()
Write-Host "sent: daemon.getSupportedPlatforms projectRoot=$winRoot"
Write-Host "  json: $reqJson".TrimEnd()

# Read responses (daemon.connected + getSupportedPlatforms response)
$readTask = $proc.StandardOutput.ReadLineAsync()
while ((Get-Date) -lt $deadline -and -not $proc.HasExited) {
    if ($readTask.IsCompleted) {
        $line = $readTask.Result
        if ($null -eq $line) { break }
        Write-Host ("recv: " + $line)
        if ($line -match '^\[\{.*\}\]$') {
            $inner = $line.Substring(1, $line.Length - 2)
            try {
                $obj = $inner | ConvertFrom-Json
                if ($obj.event -eq 'daemon.connected') {
                    $gotConnected = $true
                    Write-Host ("  -> daemon.connected, version=" + $obj.params.version + " pid=" + $obj.params.pid)
                }
                elseif ($obj.id -eq '1' -and $obj.PSObject.Properties.Name -contains 'result') {
                    $gotPlatformsResponse = $true
                    $platformsResult = $obj.result
                    Write-Host ("  -> getSupportedPlatforms response:")
                    if ($obj.result.PSObject.Properties.Name -contains 'platforms') {
                        foreach ($p in $obj.result.platforms) {
                            Write-Host ("      platform: " + $p)
                        }
                    }
                }
            } catch {
                Write-Host ("  -> parse error: " + $_.Exception.Message)
            }
        }
        if ($gotConnected -and $gotPlatformsResponse) { break }
        $readTask = $proc.StandardOutput.ReadLineAsync()
    } else {
        $readTask.Wait(200) | Out-Null
    }
}

# Send daemon.shutdown
$shutdownReq = '[{"id":"2","method":"daemon.shutdown"}]' + "`n"
try {
    $proc.StandardInput.Write($shutdownReq)
    $proc.StandardInput.Flush()
    Write-Host "sent: daemon.shutdown"
} catch {}

if (-not $proc.WaitForExit(5000)) {
    Write-Host "wrapper did not exit in 5s, killing..."
    $proc.Kill()
}

$err = $proc.StandardError.ReadToEnd()
if ($err) { Write-Host ("stderr: " + $err) }

Write-Host ""
Write-Host "=== Summary ==="
Write-Host ("  daemon.connected:     " + $(if ($gotConnected) { 'PASS' } else { 'FAIL' }))
Write-Host ("  getSupportedPlatforms: " + $(if ($gotPlatformsResponse) { 'PASS' } else { 'FAIL' }))
Write-Host ""
Write-Host "Check wrapper.log for translation entries:"
Write-Host '  grep "projectRoot" d:\Android\FlutterWrapper\logs\wrapper.log'

if ($gotConnected -and $gotPlatformsResponse) {
    Write-Host "  ALL PASS"
    exit 0
} else {
    exit 1
}
