param(
    [string]$Image = "D:\\chopin-linux\\out\\boot-chopin-debian.img",
    [string]$Out = "D:\\chopin-linux\\out\\serial-last.txt",
    [int]$TimeoutSec = 150,
    [int]$IdleStopSec = 20
)
$ErrorActionPreference = 'Continue'
$pt = "D:\\Program Files (x86)\\platform-tools"

# start the serial capture first so early boot output is not lost
$capArgs = @("-NoProfile","-ExecutionPolicy","Bypass","-File","D:\\chopin-linux\\scripts\\windows\\capture-serial.ps1","-Out",$Out,"-TimeoutSec","$TimeoutSec","-IdleStopSec","$IdleStopSec")
$cap = Start-Process -FilePath "powershell" -PassThru -WindowStyle Hidden -ArgumentList $capArgs

Start-Sleep -Milliseconds 800
Write-Host "== fastboot flash boot $Image"
& "$pt\fastboot.exe" flash boot "$Image" 2>&1 | Out-String | Write-Host
if ($LASTEXITCODE -ne 0) { Write-Host "FLASH FAILED"; try { $cap.Kill() } catch {}; exit 1 }
Write-Host "== fastboot reboot"
& "$pt\fastboot.exe" reboot 2>&1 | Out-String | Write-Host

Write-Host "== waiting for serial capture to finish ..."
$cap.WaitForExit()
Write-Host "---- capture: $Out ----"
if (Test-Path $Out) { Get-Content $Out -Raw } else { Write-Host "(no capture file: no COM port appeared)" }
