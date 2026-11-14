param(
    [string]$Boot = "D:\chopin-linux\out\boot-chopin-debian.img",
    [string]$Rootfs = "D:\chopin-linux\out\chopin-rootfs.sparse.img",
    [switch]$SkipBoot,
    [switch]$SkipRootfs
)
$ErrorActionPreference = "Stop"
$pt = "D:\Program Files (x86)\platform-tools"
$fastboot = Join-Path $pt "fastboot.exe"
if (-not (Test-Path $fastboot)) { throw "fastboot not found: $fastboot" }

Write-Host "== fastboot devices =="
& $fastboot devices
if ($LASTEXITCODE -ne 0) { throw "no fastboot device (reboot bootloader first)" }

if (-not $SkipBoot) {
    if (-not (Test-Path $Boot)) { throw "boot image missing: $Boot" }
    Write-Host "== flash boot =="
    & $fastboot flash boot $Boot
    if ($LASTEXITCODE -ne 0) { throw "flash boot failed" }
}
if (-not $SkipRootfs) {
    if (-not (Test-Path $Rootfs)) { throw "rootfs image missing: $Rootfs" }
    Write-Host "== flash userdata (sparse, can take minutes) =="
    & $fastboot flash userdata $Rootfs
    if ($LASTEXITCODE -ne 0) { throw "flash userdata failed" }
}
Write-Host "== reboot =="
& $fastboot reboot
