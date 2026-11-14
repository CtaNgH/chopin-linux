param(
    [string]$Image = "D:\chopin-linux\out\boot-chopin-debian.img",
    [string]$Out = "D:\chopin-linux\out\serial-auto.txt",
    [int]$WaitFastbootSec = 600,
    [int]$SerialSec = 110,
    [int]$IdleStopSec = 30
)
$ErrorActionPreference = 'Continue'
$pt = "D:\Program Files (x86)\platform-tools"

Write-Host "== waiting for fastboot (up to $WaitFastbootSec s) ..."
$deadline = (Get-Date).AddSeconds($WaitFastbootSec)
$found = $false
while ((Get-Date) -lt $deadline) {
    $dev = & "$pt\fastboot.exe" devices 2>$null
    if ($dev -and ($dev -match "fastboot")) { $found = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $found) { Write-Host "NO_FASTBOOT"; exit 2 }
Write-Host "== fastboot device: $dev"

$capArgs = @("-NoProfile","-ExecutionPolicy","Bypass","-File","D:\chopin-linux\scripts\windows\capture-serial.ps1","-Out",$Out,"-TimeoutSec","$SerialSec","-IdleStopSec","$IdleStopSec")
$cap = Start-Process -FilePath "powershell" -PassThru -WindowStyle Hidden -ArgumentList $capArgs
Start-Sleep -Milliseconds 800

Write-Host "== fastboot flash boot $Image"
& "$pt\fastboot.exe" flash boot "$Image" 2>&1 | Out-String | Write-Host
if ($LASTEXITCODE -ne 0) { Write-Host "FLASH_FAILED"; try { $cap.Kill() } catch {}; exit 1 }
& "$pt\fastboot.exe" reboot 2>&1 | Out-String | Write-Host
Write-Host "== rebooting, capturing serial ..."
$cap.WaitForExit()
Write-Host "---- capture: $Out ----"
if (Test-Path $Out) { Get-Content $Out -Raw } else { Write-Host "NO_COM_PORT" }
