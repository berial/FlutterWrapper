# Test: Windows -> WSL TCP daemon connection (via localhost forwarding)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=== Windows -> WSL TCP daemon test ==="
Write-Host "Assumes daemon already running on 127.0.0.1:9876 in WSL"
Write-Host "(run: wsl -d Ubuntu-24.04 -e flutter daemon --listen-on-tcp-port=9876)"
Write-Host ""

try {
    $client = New-Object System.Net.Sockets.TcpClient
    $client.Connect('127.0.0.1', 9876)
    Write-Host "connected to 127.0.0.1:9876"

    $stream = $client.GetStream()
    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
    $writer = New-Object System.IO.StreamWriter($stream, [System.Text.Encoding]::UTF8)
    $writer.NewLine = "`n"  # LF, not CRLF

    # Read daemon.connected
    $line = $reader.ReadLine()
    Write-Host ("recv1: " + $line)

    # Send daemon.version
    $writer.WriteLine('[{"id":"1","method":"daemon.version"}]')
    $writer.Flush()
    Write-Host "sent: daemon.version"

    $line = $reader.ReadLine()
    Write-Host ("recv2: " + $line)

    # Send daemon.shutdown
    $writer.WriteLine('[{"id":"2","method":"daemon.shutdown"}]')
    $writer.Flush()
    Write-Host "sent: daemon.shutdown"

    $client.Close()
    Write-Host ""
    Write-Host "PASS: Windows can connect to WSL TCP daemon"
} catch {
    Write-Host ("FAIL: " + $_.Exception.Message)
    exit 1
}
