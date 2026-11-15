param(
    [Parameter(Mandatory=$true)][string]$Remote,
    [Parameter(Mandatory=$true)][string]$Out,
    [string]$Port = "COM11",
    [int]$TimeoutSec = 300,
    [int]$Retries = 3
)
$ErrorActionPreference = "Stop"

function Read-Stream($sp, [string]$marker, [int]$timeoutSec) {
    $sb = New-Object System.Text.StringBuilder
    $buf = New-Object byte[] 4096
    $start = Get-Date
    while (((Get-Date) - $start).TotalSeconds -lt $timeoutSec) {
        try { $n = $sp.Read($buf, 0, $buf.Length) } catch { $n = 0 }
        if ($n -gt 0) { [void]$sb.Append([System.Text.Encoding]::ASCII.GetString($buf, 0, $n)) }
        if ($sb.ToString().Contains($marker + "E")) { break }
    }
    return $sb.ToString()
}

for ($attempt = 1; $attempt -le $Retries; $attempt++) {
    $marker = "__PULL_" + (Get-Random -Minimum 100000 -Maximum 999999) + "__"
    $sp = New-Object System.IO.Ports.SerialPort($Port, 115200, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
    $sp.ReadBufferSize = 65536
    $sp.ReadTimeout = 400
    $sp.WriteTimeout = 60000
    $sp.DtrEnable = $true
    $sp.RtsEnable = $true
    $sp.Open()
    try {
        Start-Sleep -Milliseconds 300
        $sp.Write([char]13)
        Start-Sleep -Milliseconds 900
        $pre = $sp.ReadExisting()
        if ($pre -match "login:") {
            $sp.Write("root" + [char]13)
            Start-Sleep -Milliseconds 900
            $p2 = $sp.ReadExisting()
            if ($p2 -match "Password:") {
                $sp.Write("chopin" + [char]13)
                Start-Sleep -Milliseconds 1800
                [void]$sp.ReadExisting()
            }
        }
        # echo off first: the command line itself contains the markers
        $sp.Write("stty -echo" + [char]13)
        Start-Sleep -Milliseconds 500
        [void]$sp.ReadExisting()

        $sp.Write("echo " + $marker + "B; base64 -w0 " + $Remote + "; echo; echo " + $marker + "E; stty echo" + [char]13)
        $txt = Read-Stream $sp $marker $TimeoutSec
    } finally {
        $sp.Close()
    }
    $b = $txt.IndexOf($marker + "B")
    $e = $txt.IndexOf($marker + "E")
    if ($b -lt 0 -or $e -le $b) { Write-Output ("attempt " + $attempt + ": markers missing"); continue }
    $b64 = $txt.Substring($b + ($marker + "B").Length, $e - $b - ($marker + "B").Length)
    $b64 = ($b64 -replace "[^A-Za-z0-9+/=]", "")
    try { $data = [Convert]::FromBase64String($b64) } catch { Write-Output ("attempt " + $attempt + ": bad base64"); continue }
    [System.IO.File]::WriteAllBytes($Out, $data)
    $sha = (Get-FileHash -Algorithm SHA256 -Path $Out).Hash.ToLower()
    Write-Output ("attempt " + $attempt + ": " + $data.Length + " bytes sha256=" + $sha)
    if ($data.Length -ge 8 -and $data[0] -eq 0x89 -and $data[$data.Length - 1] -eq 0x82) { break }
}
