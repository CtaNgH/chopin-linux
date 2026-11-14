param(
    [string]$Out = "D:\\chopin-linux\\out\\serial-capture.txt",
    [int]$TimeoutSec = 150,
    [int]$IdleStopSec = 25
)
$ErrorActionPreference = 'Continue'

try { $null = New-Object System.IO.Ports.SerialPort } catch { try { Add-Type -AssemblyName System.IO.Ports } catch { } }

$deadline = (Get-Date).AddSeconds($TimeoutSec)
$port = $null
Write-Host "waiting for a COM port (up to $TimeoutSec s) ..."
while (-not $port -and (Get-Date) -lt $deadline) {
    $names = [System.IO.Ports.SerialPort]::GetPortNames()
    if ($names.Count -gt 0) { $port = $names[0] } else { Start-Sleep -Milliseconds 300 }
}
if (-not $port) { Write-Host "no serial port appeared"; exit 2 }
Write-Host "opening $port at 115200 8N1 (DTR+RTS on)"
$sp = New-Object System.IO.Ports.SerialPort($port, 115200, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
$sp.ReadTimeout = 500
$sp.WriteTimeout = 500
$sp.DtrEnable = $true
$sp.RtsEnable = $true
try { $sp.Open() } catch { Write-Host "open failed: $_"; exit 3 }

$fs = [System.IO.File]::Open($Out, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
$buf = New-Object byte[] 8192
$lastData = Get-Date
$total = 0
while ((Get-Date) -lt $deadline) {
    try {
        $n = $sp.Read($buf, 0, $buf.Length)
        if ($n -gt 0) { $fs.Write($buf, 0, $n); $fs.Flush(); $total += $n; $lastData = Get-Date }
    } catch [System.TimeoutException] {
        if ($total -gt 0 -and ((Get-Date) - $lastData).TotalSeconds -gt $IdleStopSec) { break }
    } catch {
        Write-Host "read error: $_"
        break
    }
}
$fs.Close(); $sp.Close()
Write-Host "captured $total bytes -> $Out"
