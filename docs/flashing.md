# 刷机、备份与恢复

> **警告**：刷写 `boot` 会替换启动内核；刷写 `userdata` 会**清空 Android 数据且不可恢复**。
> 这是实验性移植，可能变砖或损坏硬件。确认已解锁 bootloader、已备份原厂 boot/dtbo，
> 并接受风险后再操作。

## 1. 设备

| 项 | 值 |
| --- | --- |
| 型号 | Redmi Note 10 Pro 5G / POCO X3 GT（chopin，M2104K10AC） |
| SoC | MT6891Z/CZA（Dimensity 1100） |
| boot | A/B，当前 slot `_a` |
| rootfs | userdata，`/dev/sdc75`，ext4 LABEL=`chopinroot` |
| 串口 | USB ACM → Windows COMx，115200 8N1，DTR+RTS |

## 2. 备份原厂镜像

仓库不提供原厂镜像；请从自己的设备/线刷包获取。常见方式：

```bash
# 设备已 root / 有可用 shell 时（分区名按实际调整）
adb shell su -c 'dd if=/dev/block/by-name/boot_a of=/sdcard/boot_a.img'
adb shell su -c 'dd if=/dev/block/by-name/dtbo_a of=/sdcard/dtbo_a.img'
adb pull /sdcard/boot_a.img stock/
adb pull /sdcard/dtbo_a.img stock/
```

至少保留：

- `boot_a.img` —— mkbootimg 模板 + 恢复原厂启动；
- `dtbo_a.img` —— 恢复 dtbo overlay；
- 其他分区（lk、preloader、vbmeta 等）按需备份。

放到顶层 `stock/`，该目录被 `.gitignore` 排除。

## 3. 构建产物

```bash
make artifacts
ls -lh out/
```

| 文件 | 刷到 | 说明 |
| --- | --- | --- |
| `out/boot-chopin-debian.img` | `boot` | 内核 + initramfs，保留原厂 dtb 段 |
| `out/chopin-rootfs.sparse.img` | `userdata` | Android sparse，32 位 fastboot 可刷 |
| `out/Image.gz` | — | 只用于打包/调试 |

## 4. fastboot

Windows platform-tools 默认在：

```
D:\Program Files (x86)\platform-tools\fastboot.exe
```

它是 **32 位**程序，无法处理 >2 GB 的 raw 镜像（会 `std::bad_alloc`）。
所以 rootfs 必须用 sparse 镜像（`chopin-rootfs.sparse.img`，约 2.9 GB）。

进入 fastboot：关机后按住 **音量下 + 电源**，或：

```bash
adb reboot bootloader
fastboot devices
```

## 5. 刷写

### 5.1 只换内核（保留现有 rootfs）

```powershell
fastboot flash boot D:\chopin-linux\out\boot-chopin-debian.img
fastboot reboot
```

这是调试内核最常用的方式：rootfs 不动，只替换 boot。

### 5.2 刷 boot + rootfs

```powershell
cd D:\chopin-linux
.\scripts\windows\flash-debian.ps1
```

脚本等价于：

```powershell
fastboot flash boot out\boot-chopin-debian.img
fastboot flash userdata out\chopin-rootfs.sparse.img
fastboot reboot
```

**userdata 会被整段覆盖**；sparse 镜像约 2.9 GB，分 12 个 chunk，约 90 秒。

### 5.3 只刷 rootfs

```powershell
fastboot flash userdata out\chopin-rootfs.sparse.img
fastboot reboot
```

### 5.4 参数化

`flash-debian.ps1` 支持：

```powershell
.\scripts\windows\flash-debian.ps1 -SkipRootfs
.\scripts\windows\flash-debian.ps1 -SkipBoot
.\scripts\windows\flash-debian.ps1 -Boot D:\path\boot.img -Rootfs D:\path\rootfs.sparse.img
```

## 6. A/B slot

设备是 A/B。`fastboot flash boot` 写当前 slot（输出里看 `Sending 'boot_a'`）。
刷写中断可能让 LK 把该 slot 标成不可引导并切到 `_b`。处理：

```bash
fastboot getvar current-slot
fastboot --set-active=a
fastboot reboot
```

## 7. 首启与串口

刷完 boot 后，USB 应出现 `VID_1D6B/PID_0104` 的 ACM 设备，Windows 分配 COMx。
用 115200 8N1、DTR+RTS 打开：

```powershell
.\scripts\windows\serial-cmd.ps1 -Port COM11 -Send "id" -WaitMs 2000
```

登录：用户 `chopin` / 密码 `chopin`（root 同密码，构建时可用 `CHOPIN_PASSWORD` 改）。
如果看不到 login，先检查 `/sys/class/udc/*/state` 是否为 `configured`，
再看 `journalctl -b` / `dmesg`。

## 8. 恢复原厂

```powershell
fastboot flash boot D:\chopin-linux\stock\boot_a.img
fastboot flash dtbo D:\chopin-linux\stock\dtbo_a.img
fastboot reboot
```

如果 slot 被切到 `_b`：

```bash
fastboot --set-active=a
fastboot reboot
```

userdata 已被 Debian 覆盖，**Android 数据无法恢复**；要回 Android 需要重新线刷整包，
首次启动会重建 userdata。

## 9. 刷机前检查清单

- [ ] bootloader 已解锁；
- [ ] `stock/boot_a.img` 与 `stock/dtbo_a.img` 已备份并可读；
- [ ] 手机电量 > 50%，USB 线稳定；
- [ ] 使用 sparse rootfs（不要刷 raw `chopin-rootfs.img`）；
- [ ] 接受 userdata 被清空；
- [ ] 构建产物 `SHA256SUMS` 已核对。
