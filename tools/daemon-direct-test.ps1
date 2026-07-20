# Direct wsl.exe daemon test using BaseStream byte-level writes
# Ensures LF (not CRLF) and UTF-8 encoding for stdin.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=== Direct daemon test (BaseStream byte-level) ==="

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'wsl.exe'
$psi.Arguments = '-d Ubuntu-24.04 --cd /mnt/d/Android/FlutterWrapper -e /home/berial/.vfox/sdks/flutter/bin/flutter daemon'
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true

$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi
$null = $proc.Start()
Write-Host ("wsl pid: " + $proc.Id)

# Use BaseStream for stdin (byte-level, UTF-8, LF only)
$inStream = $proc.StandardInput.BaseStream
$outStream = $proc.StandardOutput.BaseStream

# Wait for daemon.connected (up to 30s - first run compiles flutter_tools)
$ms = New-Object System.IO.MemoryStream
$deadline = (Get-Date).AddSeconds(45)
$gotConnected = $false
$gotVersion = $false

Write-Host "waiting for daemon.connected..."
while ((Get-Date) -lt $deadline -and -not $proc.HasExited -and -not $gotConnected) {
    while ($outStream.DataAvailable) {
        $b = $outStream.ReadByte()
        if ($b -lt 0) { break }
        if ($b -eq 0x0A) {
            $lineBytes = $ms.ToArray()
            $ms.SetLength(0)
            $line = [System.Text.Encoding]::UTF8.GetString($lineBytes)
            Write-Host ("recv: " + $line)
            if ($line -match '^\[\{.*\}\]$') {
                $inner = $line.Substring(1, $line.Length - 2)
                try {
                    $obj = $inner | ConvertFrom-Json
                    if ($obj.event -eq 'daemon.connected') {
                        $gotConnected = $true
                        Write-Host ("  -> connected v=" + $obj.params.version + " pid=" + $obj.params.pid)
                    }
                } catch {}
            }
        } else {
            $ms.WriteByte($b)
        }
    }
    Start-Sleep -Milliseconds 100
}

if (-not $gotConnected) {
    Write-Host "FAIL: no daemon.connected in 45s"
    # Drain stderr
    while ($proc.StandardError.BaseStream.DataAvailable) {
        $b = $proc.StandardError.BaseStream.ReadByte()
        if ($b -lt 0) { break }
        Write-Host -NoNewline ([char]$b)
    }
    if (-not $proc.HasExited) { $proc.Kill() }
    exit 1
}

# Send daemon.version via BaseStream (UTF-8 bytes, LF only)
$req = '[{"id":"1","method":"daemon.version"}]' + "`n"
$reqBytes = [System.Text.Encoding]::UTF8.GetBytes($req)
$inStream.Write($reqBytes, 0, $reqBytes.Length)
$inStream.Flush()
Write-Host "sent: daemon.version (via BaseStream)"

# Wait for response
$deadline2 = (Get-Date).AddSeconds(15)
while ((Get-Date) -lt $deadline2 -and -not $proc.HasExited -and -not $gotVersion) {
    while ($outStream.DataAvailable) {
        $b = $outStream.ReadByte()
        if ($b -lt 0) { break }
        if ($b -eq 0x0A) {
            $lineBytes = $ms.ToArray()
            $ms.SetLength(0)
            $line = [System.Text.Encoding]::UTF8.GetString($lineBytes)
            Write-Host ("recv: " + $line)
            if ($line -match '^\[\{.*\}\]$') {
                $inner = $line.Substring(1, $line.Length - 2)
                try {
                    $obj = $inner | ConvertFrom-Json
                    if ($obj.id -eq '1') {
                        $gotVersion = $true
                        Write-Host ("  -> version result: " + $obj.result)
                    }
                } catch {}
            }
        } else {
            $ms.WriteByte($b)
        }
    }
    Start-Sleep -Milliseconds 50
}

# Send daemon.shutdown
$shutdown = '[{"id":"2","method":"daemon.shutdown"}]' + "`n"
$shutBytes = [System.Text.Encoding]::UTF8.GetBytes($shutdown)
try {
    $inStream.Write($shutBytes, 0, $shutBytes.Length)
    $inStream.Flush()
} catch {}

if (-not $proc.WaitForExit(3000)) { $proc.Kill() }

Write-Host ""
Write-Host ("connected: " + $(if ($gotConnected) { 'PASS' } else { 'FAIL' }))
Write-Host ("version:   " + $(if ($gotVersion) { 'PASS' } else { 'FAIL' }))
