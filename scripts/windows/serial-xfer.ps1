param(
    [Parameter(Mandatory=$true)][string]$File,
    [string]$Remote = "/root/xfer.bin",
    [string]$Port = "COM11",
    [int]$TimeoutSec = 600
)
$ErrorActionPreference = "Stop"

function Read-UntilQuiet($sp, [int]$quietMs = 600, [int]$maxMs = 8000) {
    $sb = New-Object System.Text.StringBuilder
    $lastData = Get-Date
    $start = Get-Date
    while (((Get-Date) - $lastData).TotalMilliseconds -lt $quietMs -and ((Get-Date) - $start).TotalMilliseconds -lt $maxMs) {
        try {
            $chunk = $sp.ReadExisting()
            if ($chunk -ne "") { [void]$sb.Append($chunk); $lastData = Get-Date }
        } catch { Start-Sleep -Milliseconds 50 }
    }
    return $sb.ToString()
}

$bytes = [System.IO.File]::ReadAllBytes($File)
$b64 = [Convert]::ToBase64String($bytes)
$n = $b64.Length
Write-Output ("file=" + $File + " bytes=" + $bytes.Length + " b64=" + $n)

$marker = "__XFER_" + (Get-Random -Minimum 100000 -Maximum 999999) + "__"
$sp = New-Object System.IO.Ports.SerialPort($Port, 115200, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
$sp.ReadTimeout = 500
$sp.WriteTimeout = 60000
$sp.DtrEnable = $true
$sp.RtsEnable = $true
$sp.Open()
try {
    Start-Sleep -Milliseconds 300
    $sp.Write([char]13)
    $pre = Read-UntilQuiet $sp 600 4000
    if ($pre -match "login:") {
        $sp.Write("root" + [char]13)
        $p2 = Read-UntilQuiet $sp 600 4000
        if ($p2 -match "Password:") { $sp.Write("chopin" + [char]13); [void](Read-UntilQuiet $sp 800 8000) }
    }
    # make sure we are at a shell prompt
    $sp.Write([char]13)
    [void](Read-UntilQuiet $sp 500 3000)
    $cmd = "stty raw -echo; head -c " + $n + " | base64 -d > " + $Remote + "; stty sane; echo " + $marker
    $sp.Write($cmd + [char]13)
    Start-Sleep -Milliseconds 400
    $t0 = Get-Date
    # stream the base64 payload in 4 KiB slices so backpressure stays smooth
    $slice = 4096
    for ($i = 0; $i -lt $n; $i += $slice) {
        $len = [Math]::Min($slice, $n - $i)
        $sp.Write($b64.Substring($i, $len))
    }
    $dt = ((Get-Date) - $t0).TotalSeconds
    Write-Output ("payload written in " + [Math]::Round($dt, 2) + " s -> " + [Math]::Round($bytes.Length / $dt / 1024, 1) + " KiB/s")
    $sb = New-Object System.Text.StringBuilder
    $start = Get-Date
    while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSec) {
        try {
            $chunk = $sp.ReadExisting()
            if ($chunk -ne "") { [void]$sb.Append($chunk) }
        } catch { Start-Sleep -Milliseconds 100 }
        if ($sb.ToString() -match [regex]::Escape($marker)) { break }
        Start-Sleep -Milliseconds 100
    }
    Write-Output "=====REMOTE====="
    Write-Output $sb.ToString()
    Write-Output "=====END====="
} finally {
    $sp.Close()
}
