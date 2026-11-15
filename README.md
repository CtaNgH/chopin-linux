# chopin-linux

Redmi Note 10 Pro 5G / POCO X3 GT（**chopin**，M2104K10AC，MT6891Z/CZA，Dimensity 1100）的
Linux 主线移植：**Linux 7.3.4 内核 + Debian 13.7 + GNOME 48**。

这是一个**可复现**的开源工作区：内核只保留 27 个补丁和版本锚点，用户空间只保留构建配方；
源码树、rootfs、镜像、Mesa tarball 都可以从公开来源重新生成，并用 git tree 哈希校验结果。

> **当前状态（2026-11-15 16:00）**：这台手机已经能当日常 Linux 桌面用 ——
> GNOME 48.7 以 Wayland 跑在 Mali-G77（panfrost）上（1080×2400@120、缩放 2.5），触摸正常；
> USB 口同时提供 **CDC-NCM 网卡**（usb0 192.168.42.2，SSH 免密）和串口控制台；
> **WiFi 已连 5 GHz**（apt 实测 1.8 MB/s）；**扬声器出声**；NTP 校准系统时间。
> 未完成：P0 偶发 SError（频率已大降）、蓝牙 / 耳机 / 麦克风 / 相机。
> 详见 [docs/status.md](docs/status.md)，整轮适配记录见 [docs/bringup-2026-11-15.md](docs/bringup-2026-11-15.md)。

---

## 1. 仓库组成

三个独立 Git 仓库，顶层用 **submodule** 固定版本，可以分别 clone、分别提交、分别发布。

> 三个仓库必须同名、同 owner
> （`chopin-linux`、`chopin-kernel`、`chopin-debian`），`.gitmodules` 的相对 URL 才能解析。

| 目录 | 仓库 | 内容 | 体积 |
| --- | --- | --- | --- |
| `kernel/` | [chopin-kernel](https://github.com/CtaNgH/chopin-kernel) | 27 个补丁、defconfig、build/bootimg 脚本、内核文档 | ~36 MB |
| `debian/` | [chopin-debian](https://github.com/CtaNgH/chopin-debian) | Debian rootfs / GNOME / initramfs / 镜像脚本 | ~1 MB |
| 顶层 | [chopin-linux](https://github.com/CtaNgH/chopin-linux) | README、docs、Makefile、Windows 辅助脚本 | ~1 MB |

`kernel/linux/`（1.6 GB 源码）和 `debian/build/`、`debian/out/`（数 GB 产物）都在
`.gitignore` 里，由脚本重建，不进入 Git 历史。

```
chopin-linux/
├── kernel/                 # submodule: 补丁 + 构建脚本 + 内核文档
├── debian/                 # submodule: Debian 用户空间工程
├── docs/
│   ├── status.md           # 当前状态、已验证/阻塞、下一步
│   ├── bringup-2026-11-15.md  # 整轮适配记录（GPU/触摸/内存/刷机坑）
│   ├── reproduce.md        # 从零复现的完整步骤
│   ├── flashing.md         # 刷机、备份、恢复
│   └── archive/            # 2026-11-15 的原始资料（冻结）
├── scripts/
│   ├── bootstrap.sh        # 初始化 submodule + 内核源码
│   ├── check-env.sh        # 构建依赖检查
│   ├── check.sh            # 补丁数/校验和/语法/树哈希
│   ├── collect-artifacts.sh
│   └── windows/            # PowerShell 刷机/串口/截图/校准工具（示例）
├── stock/                  # 原厂 boot/dtbo（忽略，不随仓库分发）
├── out/                    # 汇总产物（忽略）
└── Makefile
```

## 2. 快速开始

### 2.1 克隆

三个仓库按 `chopin-linux` / `chopin-kernel` / `chopin-debian` 命名并放在同一 owner 下，
`.gitmodules` 使用相对 URL，因此：

```bash
git clone --recurse-submodules https://github.com/CtaNgH/chopin-linux.git
cd chopin-linux
./scripts/check-env.sh
```

如果只拿到源码压缩包，没有 submodule：

```bash
git clone https://github.com/CtaNgH/chopin-kernel.git kernel
git clone https://github.com/CtaNgH/chopin-debian.git debian
```

### 2.2 构建内核

```bash
make bootstrap     # 下载/校验 Linux 7.3.4，应用 27 个补丁，校验 tree
make kernel        # Image.gz + dtbs + modules
```

首次需要下载 ~162 MB tarball；离线时：

```bash
KERNEL_TARBALL=/path/linux-7.3.4.tar.xz make bootstrap
```

### 2.3 构建 Debian

```bash
sudo make debian           # rootfs + GNOME + initramfs + ext4/sparse + boot.img
```

需要 `stock/boot_a.img`（原厂 boot 镜像）作为 mkbootimg 模板。没有它也能先构建 rootfs，
只是最后一步 `07-mkbootimg.sh` 会报错并提示。

### 2.4 汇总与刷机

```bash
make artifacts             # 把 boot/rootfs/Image.gz 汇总到 out/，生成 SHA256SUMS
```

Windows 侧：

```powershell
D:\chopin-linux\scripts\windows\flash-debian.ps1
```

**刷机会覆盖 userdata，Android 数据不可恢复**；先读 [docs/flashing.md](docs/flashing.md)。

## 3. 可复现性契约

| 层 | 锚点 | 校验方式 |
| --- | --- | --- |
| 内核基线 | 官方 `linux-7.3.4.tar.xz` | SHA256 `b11b6df8…` |
| 内核补丁 | 20 个 `git am` 补丁 | 最终 tree = `ec46ef62…` |
| Debian | `trixie` + 固定 Mesa tarball | `versions.env` 单一版本源 |
| 产物 | 每次构建 | `out/SHA256SUMS` |

`make check` 会检查补丁数量、SHA256SUMS、脚本语法，以及 `kernel/linux` 的 tree 哈希。
详细原理和离线模式见 [docs/reproduce.md](docs/reproduce.md)。

## 4. 文档

| 文档 | 内容 |
| --- | --- |
| [docs/status.md](docs/status.md) | 当前状态、硬件矩阵、阻塞与下一步 |
| [docs/bringup-2026-11-15.md](docs/bringup-2026-11-15.md) | 整轮适配记录：GPU/Mesa/kmsro/Wayland、触摸三个根因、SError 内存布局、刷机两个坑 |
| [docs/reproduce.md](docs/reproduce.md) | 从零复现（含离线、校验、清理） |
| [docs/flashing.md](docs/flashing.md) | 备份、fastboot、A/B slot、恢复原厂 |
| [kernel/docs/kernel.md](kernel/docs/kernel.md) | 引导链、设备树、cmdline、驱动状态、已知问题 |
| [kernel/README.md](kernel/README.md) | 补丁系列、构建、打包 boot.img |
| [debian/README.md](debian/README.md) | rootfs/GNOME/initramfs 构建手册 |
| [debian/docs/PLAN.md](debian/docs/PLAN.md) | Debian 侧当前执行计划 |
| [docs/archive/](docs/archive/) | 2026-11-15 的原始 README/HANDOFF/技术文档（冻结） |

## 5. 硬件与法律注意事项

- 需要解锁 bootloader；刷机会清空 userdata，**先备份**。
- 仓库**不包含**原厂 boot/dtbo/分区 dump、WiFi/BT NVRAM、触摸固件等专有 blob；
  需要从自己的设备备份中提取（见 [docs/flashing.md](docs/flashing.md)）。
- 内核补丁包含 MediaTek/Xiaomi 厂商代码，按 GPL-2.0 分发，但厂商代码的再分发条件请自行确认；
  上游化前需要拆分补丁并补齐 binding 文档。
- 这是实验性移植，不保证设备安全、数据安全或硬件不损坏；自负风险。

## 6. 许可

- `kernel/`：GPL-2.0-only（见 [kernel/LICENSE](kernel/LICENSE)）；
- `debian/` 与顶层脚本/文档：MIT（见 [LICENSE](LICENSE)）；
- Debian 软件包、Mesa 源码、厂商固件保留各自许可。

详见 [LICENSING.md](LICENSING.md)。
