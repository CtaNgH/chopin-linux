param(
    [string]$Cmd = "",
    [string]$CmdFile = "",
    [string]$Port = "COM11",
    [int]$TimeoutSec = 60,
    [string]$User = "root",
    [string]$Pass = "chopin"
)
$ErrorActionPreference = "Stop"
if ($CmdFile -ne "") { $Cmd = (Get-Content -Raw -Path $CmdFile).TrimEnd() }

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
function Strip-Ansi([string]$s) {
    if ($null -eq $s) { return "" }
    $s = $s -replace "\x1b\][^\x07]*\x07", ""
    $s = $s -replace "\x1b\[[0-9;?]*[a-zA-Z]", ""
    $s = $s -replace "\x1b\[!p", ""
    $s = $s -replace "\x08", ""
    return $s
}

$marker = "__SER_" + (Get-Random -Minimum 100000 -Maximum 999999) + "__"
$sp = New-Object System.IO.Ports.SerialPort($Port, 115200, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
$sp.ReadTimeout = 300
$sp.WriteTimeout = 2000
$sp.DtrEnable = $true
$sp.RtsEnable = $true
$sp.Open()
try {
    Start-Sleep -Milliseconds 300
    $pre = ""
    $sp.Write([char]13)
    $deadline = (Get-Date).AddSeconds(50)
    $logged = $false
    while ((Get-Date) -lt $deadline) {
        $chunk = Read-UntilQuiet $sp 500 1500
        $pre += $chunk
        # On ttyGS0 this login renders the password prompt as "????????? " (nine
        # question marks), so matching only "Password:" would hang at the prompt.
        if ($pre -match "Password:" -or $pre -match "\?{4,}\s*$") {
            $sp.Write($Pass + [char]13)
            $pre += Read-UntilQuiet $sp 800 8000
            $logged = $true
            break
        }
        if ($pre -match "login:") {
            $sp.Write($User + [char]13)
            $p2 = Read-UntilQuiet $sp 500 4000
            $pre += $p2
            if ($p2 -match "Password:" -or $p2 -match "\?{4,}") {
                $sp.Write($Pass + [char]13)
                $pre += Read-UntilQuiet $sp 800 8000
            }
            $logged = $true
            break
        }
        if ($pre -match "root@chopin:[^\r\n]*# $") { $logged = $true; break }
        if ($pre -match "chopin@chopin:[^\r\n]*\$ $") { $logged = $true; break }
    }
    if (-not $logged) { $pre += Read-UntilQuiet $sp 600 3000 }
    $sp.Write($Cmd + [char]10 + "echo " + $marker + [char]13)
    $sb = New-Object System.Text.StringBuilder
    $start = Get-Date
    while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSec) {
        try {
            $chunk = $sp.ReadExisting()
            if ($chunk -ne "") { [void]$sb.Append($chunk) }
        } catch { Start-Sleep -Milliseconds 100 }
        $raw = $sb.ToString()
        if (([regex]::Matches($raw, [regex]::Escape($marker))).Count -ge 2) { break }
        Start-Sleep -Milliseconds 50
    }
    Write-Output "=====BEGIN====="
    Write-Output (Strip-Ansi $pre)
    Write-Output (Strip-Ansi $sb.ToString())
    Write-Output "=====END====="
} finally {
    $sp.Close()
}
