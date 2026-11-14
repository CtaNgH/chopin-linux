param(
    [string]$Port = "COM11",
    [string]$Send = "",
    [int]$WaitMs = 1500
)
$ErrorActionPreference = "Stop"
$sp = New-Object System.IO.Ports.SerialPort($Port, 115200, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
$sp.ReadTimeout = 500
$sp.WriteTimeout = 1000
$sp.DtrEnable = $true
$sp.RtsEnable = $true
$sp.Open()
Start-Sleep -Milliseconds 300
if ($Send -ne "") {
    $sp.Write($Send + [char]13)
}
Start-Sleep -Milliseconds $WaitMs
$out = ""
try { $out = $sp.ReadExisting() } catch { }
$sp.Close()
Write-Output $out
