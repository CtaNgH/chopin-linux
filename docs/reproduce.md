# 从零复现

本文假设你有一台可解锁 bootloader 的 chopin（Redmi Note 10 Pro 5G / POCO X3 GT），
一台 Ubuntu 24.04 / WSL2 构建机，以及设备原厂 boot 镜像的备份。

## 1. 需要什么

| 项 | 要求 |
| --- | --- |
| 构建机 | Ubuntu 24.04（WSL2 可用），16 核 / 8 GB 内存 / 30 GB 磁盘 |
| 交叉编译器 | `aarch64-linux-gnu-gcc` 13.x |
| 设备 | chopin，bootloader 已解锁，slot `_a` |
| 原厂镜像 | `boot_a.img`（必需）、`dtbo_a.img`（恢复用） |
| 网络 | 首次下载 Linux tarball（162 MB）与 Debian 包（约 1.5 GB） |

## 2. 主机准备

```bash
sudo apt-get update
sudo apt-get install -y build-essential gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu \
  flex bison bc libssl-dev libelf-dev libncurses-dev cpio kmod rsync \
  device-tree-compiler python3 xz-utils zstd dwarves ccache lz4 curl

# Debian 用户空间
sudo apt-get install -y mmdebstrap qemu-user-static binfmt-support debootstrap \
  e2fsprogs mtools meson ninja-build pkg-config dpkg-dev python3-venv git \
  g++-14-aarch64-linux-gnu libstdc++-14-dev-arm64-cross
```

检查：

```bash
cd chopin-linux
./scripts/check-env.sh
```

## 3. 获取代码

三个仓库按 `chopin-linux` / `chopin-kernel` / `chopin-debian` 命名、放在同一 owner 下，
`.gitmodules` 用相对 URL：

```bash
git clone --recurse-submodules https://github.com/your-org/chopin-linux.git
cd chopin-linux
git submodule status
```

如果 submodule 没拉下来：

```bash
git submodule update --init --recursive
```

## 4. 原厂镜像

把自备份的 `boot_a.img` 放到 `stock/`：

```
chopin-linux/stock/boot_a.img
chopin-linux/stock/dtbo_a.img
```

`stock/` 被 `.gitignore` 排除，不会提交。没有 `boot_a.img` 时仍可构建 rootfs，
但 `07-mkbootimg.sh` 会失败。备份/恢复见 [flashing.md](flashing.md)。

## 5. 内核

### 5.1 重建源码

```bash
make bootstrap
```

它会：

1. 下载（或使用本地）官方 `linux-7.3.4.tar.xz`，校验 SHA256
   `b11b6df8295e8e991ff040b71aaa4994a8b55caa23b6b092907f195b5840fd1f`；
2. 导入 Git，校验基线 tree `2c295deceadadd06d5da1de5fc4f6c84690952a2`；
3. 依次 `git am` 28 个补丁；
4. 校验最终 tree **`bb745e0aecaea34daac9d43e4dc1b973a280b77b`**；
5. `git gc` 压缩对象。

三种基线来源：

```bash
# 默认：从 kernel.org 下载，失败切清华镜像
make bootstrap

# 离线：本地官方 tarball
KERNEL_TARBALL=/path/linux-7.3.4.tar.xz make bootstrap

# 本地已有 v7.3.4 Git 仓库（要求 main 分支树等于 BASE_TREE）
KERNEL_SRC=/path/linux make bootstrap

# 强制重建（删除 kernel/linux）
FORCE=1 make bootstrap
```

### 5.2 编译

```bash
make kernel          # 或 cd kernel && JOBS=12 make build
```

产物在 `kernel/out/`：

- `Image`（约 57 MB）、`Image.gz`（约 18 MB）
- `mt6893-xiaomi-chopin.dtb`（约 281 KB）
- `modules/lib/modules/<release>/`（1640 个 .ko）

`<release>` 由 `git describe` 决定。bootstrap 重新应用补丁后 commit hash 会变，
所以 release 不会等于原始开发机的 `7.3.4-ga9777a8559e0-dirty`，这是正常的。
Debian 的 `03-install-kernel.sh` 会动态读取。

### 5.3 单独打包 boot.img

```bash
cd kernel
python3 scripts/mkbootimg.py \
  --stock ../stock/boot_a.img \
  --kernel out/Image.gz \
  -o out/boot-chopin-mainline.img
```

**默认不加 `--dtb`**：运行时 DT 来自内核内嵌的 `chopin-board.dtb`，boot.img 的 dtb 段只影响 LK。

## 6. Debian 用户空间

```bash
sudo make debian
```

等价于：

```bash
cd debian
sudo ./scripts/build-all.sh
```

首次约 30–90 分钟（qemu-user 下 apt 较慢）。

> Debian 镜像默认没有按 snapshot 锁定；如果要求逐字节一致的 rootfs，把 `DEBIAN_MIRROR` 指到
> snapshot.debian.org 的固定时间戳，或在 `versions.env` 里记录当天的 mirror 状态。

可选参数：

| 参数 | 作用 |
| --- | --- |
| `--skip-gnome` | 只做 minbase + 基础配置 |
| `--skip-mesa` | 跳过 G77 libgallium（默认就跳过） |
| `--rebuild` | 删除已有 rootfs 后从零构建 |

产物在 `debian/out/`：

- `chopin-rootfs.img`（ext4）
- `chopin-rootfs.sparse.img`（Android sparse，32 位 fastboot 可刷）
- `initramfs.cpio.gz`
- `boot-chopin-debian.img`
- `SHA256SUMS`

## 7. 汇总产物

```bash
make artifacts
```

把以下文件复制到 `out/` 并生成 `SHA256SUMS`：

```
out/
├── Image.gz
├── mt6893-xiaomi-chopin.dtb
├── initramfs.cpio.gz
├── boot-chopin-debian.img
├── chopin-rootfs.img
├── chopin-rootfs.sparse.img
└── SHA256SUMS
```

## 8. 刷机

见 [flashing.md](flashing.md)。最短路径：

```powershell
cd D:\chopin-linux
.\scripts\windows\flash-debian.ps1
```

## 9. 验证复现

```bash
make check
```

应看到：

```
[ok]   补丁数量 27/27
[ok]   kernel/SHA256SUMS
[ok]   tree = c660229f0d112c887af942dc98e1ff2d221ef033
[ok]   chopin_defconfig 一致
全部检查通过。
```

如果 tree 不匹配，说明基线或补丁被改动过；`FORCE=1 make bootstrap` 可重建。


### 9.1 网络 / WiFi / 音频（2026-11-15 实机）

    # USB 网络（CDC-NCM）+ SSH
    ip -br addr show usb0            # 192.168.42.2/24
    ssh -i out/chopin_key root@192.168.42.2 "uptime"

    # WiFi
    nmcli device status              # wlan0 connected
    iw dev wlan0 link                # SSID / 5240 MHz / 780 Mbit/s
    ping -c1 223.5.5.5

    # 音频
    cat /proc/asound/cards           # card 0 [mt6893mt6359]
    pactl list short sinks           # alsa_output.platform-sound.stereo-fallback
    speaker-test -D hw:0,0 -c 2 -t sine -f 440 -l 1

- WiFi 的固件/NVRAM 由 `chopin-wifi-firmware.service`（debian 仓库）在 sysinit 前安装；
- 音量必须走软件音量（`api.alsa.soft-mixer=true`），否则系统音量条不生效。


## 10. 清理与重置

```bash
make clean          # 删除内核/Debian 构建产物（保留源码）
make distclean      # 再删除 kernel/linux/
rm -rf out          # 删除顶层汇总
```

重新开始：

```bash
make bootstrap
make kernel
sudo make debian
make artifacts
```

## 11. 常见问题

| 现象 | 原因 / 处理 |
| --- | --- |
| `bootstrap` 下载失败 | 设置 `KERNEL_TARBALL=/path/linux-7.3.4.tar.xz` 离线构建 |
| tree 不匹配 | 基线 tarball 不对/被改；`FORCE=1 make bootstrap` |
| `git am` 冲突 | 基线不是纯净 v7.3.4；检查 `BASE_TREE` |
| 找不到 `aarch64-linux-gnu-gcc` | `apt install gcc-aarch64-linux-gnu` |
| `mmdebstrap` 失败 | 检查 qemu binfmt、Debian keyring、镜像网络 |
| `07` 找不到 stock | 放 `stock/boot_a.img` 或设 `STOCK_BOOT=` |
| 32 位 fastboot `bad_alloc` | 必须刷 sparse 镜像，不要刷 raw |

## 12. 时间与空间

| 步骤 | 时间（16 核 / 8 GB） | 磁盘 |
| --- | --- | --- |
| `make bootstrap` | 3–6 分钟（含下载） | 源码 1.6 GB + .git 300 MB |
| `make kernel` | 10–30 分钟 | 源码内中间文件 + out 约 4 GB |
| `sudo make debian` | 30–90 分钟 | rootfs 4 GB + out 7 GB |
| 总计 | 1–2 小时 | 预留 30 GB |
