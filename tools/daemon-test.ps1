# Phase 6e: Verify wrapper.ps1 daemon mode (TCP)
# Uses StandardOutput.ReadLine() - DataAvailable on BaseStream is unreliable
# with PowerShell 5.1 host output buffering.

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=== Phase 6e: daemon startup + connected event + version ==="

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

$timeout = 20  # seconds (give wsl.exe time to start + TCP connect)
$deadline = (Get-Date).AddSeconds($timeout)
$gotConnected = $false
$gotVersionResponse = $false
$versionResult = $null

# Send daemon.version request (id=1) - buffered by OS pipe, wrapper reads when ready
$req = '[{"id":"1","method":"daemon.version"}]' + "`n"
$proc.StandardInput.Write($req)
$proc.StandardInput.Flush()
Write-Host "sent: daemon.version (id=1)"

# Drain stdout via ReadLine (TextReader) - reliable across PS host buffering
# Start ONE async read; if it doesn't complete in 5s, give up on that line.
# Don't create a new ReadLineAsync each iteration - the previous one is still
# pending and would consume the next line.
$readTask = $proc.StandardOutput.ReadLineAsync()
while ((Get-Date) -lt $deadline -and -not $proc.HasExited) {
    if ($readTask.IsCompleted) {
        $line = $readTask.Result
        if ($null -eq $line) { break }  # EOF
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
                    $gotVersionResponse = $true
                    $versionResult = $obj.result
                    Write-Host ("  -> daemon.version response: " + $obj.result)
                }
            } catch {
                Write-Host ("  -> parse error: " + $_.Exception.Message)
            }
        }
        if ($gotConnected -and $gotVersionResponse) { break }
        # Start next read
        $readTask = $proc.StandardOutput.ReadLineAsync()
    } else {
        # Wait a bit before checking again
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

# Wait briefly for exit
if (-not $proc.WaitForExit(5000)) {
    Write-Host "wrapper did not exit in 5s, killing..."
    $proc.Kill()
}

# Drain any remaining stderr
$err = $proc.StandardError.ReadToEnd()
if ($err) { Write-Host ("stderr: " + $err) }

Write-Host ""
Write-Host "=== Summary ==="
Write-Host ("  daemon.connected: " + $(if ($gotConnected) { 'PASS' } else { 'FAIL' }))
Write-Host ("  daemon.version:   " + $(if ($gotVersionResponse) { "PASS ($versionResult)" } else { 'FAIL' }))

if ($gotConnected -and $gotVersionResponse) {
    Write-Host "  ALL PASS"
    exit 0
} else {
    exit 1
}
