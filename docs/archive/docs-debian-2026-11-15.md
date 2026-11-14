# chopin Debian 13（Trixie）+ GNOME 实施方案

> 设备：Redmi Note 10 Pro 5G / POCO X3 GT（chopin，M2104K10AC，MT6891Z/CZA，Dimensity 1100）
> 内核：Linux 7.3.4 + 参考项目 18 个补丁（分支 chopin，release 7.3.4-ga9777a8559e0-dirty）
> 目标系统：Debian 13.7 trixie（GNOME 48.7，Mesa 25.0.7-2+deb13u1）
> 文档版本：2026-11-14 v1
> 关联文档：[docs-kernel.md](docs-kernel.md)（内核状态）、[debian/README.md](debian/README.md)（构建手册）

> **2026-11-14 构建进展**：M0 完成。已产出 Debian 13.7 rootfs（GNOME 48.7 + gdm3，1067 包）、
> 内核模块、G77 版 libgallium、ext4/sparse 镜像与 boot.img；实机首启（M1）待设备连接。

---

## 0. 一页结论

chopin 的主线内核已经跨过"能启动"这条线：内核、DTB、模块编译通过，实机能进用户态，
DRM 出图、触摸、按键、UFS、USB UDC 都摸过一遍。本轮要补的是**用户空间**：
Debian 13 arm64 根文件系统、GNOME 桌面、Mesa/G77 图形栈、initramfs 与镜像打包。

**可行性判断：可行。** 关键路径上只剩两个需要实机验证的接口：

1. 厂商 mediatek_v2 KMS 驱动（DRIVER_MODESET | DRIVER_GEM | DRIVER_ATOMIC，支持 dumb buffer
   与 PRIME import）能否满足 mutter 的 atomic modeset + GBM 初始化要求；
2. panfrost（内核已带 MT6893/G77 支持与 chopin 时钟钩子）在 GNOME 负载下的稳定性。

两项都有降级路径：X11 + llvmpipe（GNOME Flashback）、或后续移植主线 mtk-drm。因此本方案按
"先能进桌面，再谈性能"的顺序排期，不把 GPU 当作首启的前置条件。

**关键路径（六步）：**

1. Debian 13.7 arm64 rootfs（mmdebstrap + qemu-user binfmt）；
2. 内核模块装入 rootfs，busybox initramfs，ext4 根镜像；
3. 首启到 multi-user：tty0 控制台 + USB ACM 串口可登录；
4. panfrost + Mesa G77 验证（eglinfo / kmscube）；
5. gdm3 + GNOME Wayland 会话；
6. 触摸、缩放、输入法、USB 网络、稳定性打磨。

**最大的两个不确定项：**

- **A. 显示栈**：vendor DRM 的 atomic/GBM 能力没有在 Wayland 合成器下验证过。若 mutter 起不来，
  退到 X11 + llvmpipe（能进桌面但慢）；若 KMS 本身不满足要求，才考虑主线 mtk-drm 移植（工作量大）。
- **B. GPU 稳定性**：panfrost 的 chopin 时钟/电源钩子是参考项目加的，尚未在持续渲染下跑过。
  需要 GPU 频率锁定、长时间 kmscube、dmesg 监控三件套。

---

## 1. 目标与验收标准

### 1.1 总目标

在 chopin 上得到一个**可日常使用的 Debian 13 + GNOME 桌面**：

- 从 LK 正常引导，不依赖 Android 用户空间；
- 1080x2400 DSI 屏点亮，GNOME 会话可登录、可交互；
- 触摸、电源/音量键、USB 串口控制台可用；
- 系统可重复构建（一条命令出 rootfs 镜像 + boot.img）；
- 内核与用户空间的版本、模块、Mesa 版本可追溯。

### 1.2 分阶段验收（M0–M4）

| 里程碑 | 验收内容 | 通过标准 |
| --- | --- | --- |
| M0 构建链 | rootfs 能 chroot、能装包 | qemu-aarch64 chroot 执行 /bin/true 成功；apt 可安装 GNOME 组件 |
| M1 首启 | 内核 → initramfs → ext4 rootfs → systemd | 串口/tty0 出现 login；systemctl is-system-running 为 running 或 degraded |
| M2 图形 | KMS + EGL + GPU | modetest 显示 DSI-1 1080x2400；eglinfo 显示 Mali-G77 (Panfrost)；kmscube 连续 10 分钟不崩 |
| M3 桌面 | GDM + GNOME 会话 | 自动登录进入 GNOME；触摸可点；屏幕键盘可弹出；30 分钟空闲不崩 |
| M4 可用 | 网络与日常 | RNDIS/SSH 可用；WiFi 尽力；音频尽力；电量显示尽力 |

验收命令见第 8 节。

---

## 2. 当前基线

### 2.1 内核侧（摘要，细节见 docs-kernel.md）

| 项 | 状态 |
| --- | --- |
| 内核 | Linux 7.3.4 + 18 个 MT6893/chopin 补丁；Image.gz 18 MB，dtb 281 KB，1641 个模块 |
| 引导链 | LK 从 boot.img 的 dtb 段取基础 DTB，再叠加 dtbo 分区；内核用内嵌 chopin-board.dtb 覆盖 |
| cmdline | CONFIG_CMDLINE_FORCE，包含 console=tty0、swiotlb=0、iommu.passthrough=1、loglevel=4 等 |
| 显示 | vendor mediatek_v2 DRM，card0-DSI-1 connected 1080x2400，fbcon 正常 |
| GPU | panfrost 模块已编译；内核已含 mt6893-mali 数据、G77 型号（0x9080）与 chopin 时钟钩子 |
| 存储 | UFS 内建，userdata = /dev/sdc75（107 GB） |
| 触摸/按键 | Novatek SPI 触摸、mtk-pmic-keys / mtk-kpd 正常 |
| USB | mtu3 UDC 可注册；g_multi probe -EINVAL；configfs + ACM 是已验证路径 |
| 电源 | MT6360 子设备部分注册失败，charger/otg_vbus 不完整 |
| WLAN/BT | 缺 mediatek/mt6893/WIFI NVRAM，未打通 |
| 音频/相机 | 驱动在树内，未验证 |

**与本方案直接相关的三个内核事实：**

1. mediatek_v2 的 drm_driver 是 MODESET | GEM | ATOMIC，提供 dumb_create、dumb_map_offset、
   prime_handle_to_fd / fd_to_handle、gem_prime_import 与 import_sg_table，并带
   DRM_FBDEV_DMA_DRIVER_OPS。也就是说 GBM 的 dumb-buffer 路径与 dma-buf 导入路径在内核侧是齐的。
2. panfrost 已匹配 compatible = "mediatek,mt6893-mali"，数据结构里 num_supplies = 0、
   num_pm_domains = 0，电源/时钟由 chopin 专用钩子处理；G77 的 GPU_MODEL 条目已在
   panfrost_gpu.c 中。
3. CONFIG_USB_LIBCOMPOSITE=y 且 configfs.c 编入 libcomposite，ACM 功能内建；initramfs
   阶段就能建 gadget，不依赖模块。

### 2.2 参考实现（GitHub MT6891-Mainline）

| 仓库 | 用途 | 本方案用法 |
| --- | --- | --- |
| linux | 7.3.3-mt6893-xiaomi-chopin 分支，18 个补丁 | 已移植到本地 7.3.4，内核不再改动 |
| mesa | Mesa 25.0.7 + G77 型号补丁 + chopin 交叉编译脚本 | 用 Debian orig tarball + 该仓库补丁/脚本，产出 libgallium 替换件 |
| Mu-Silicium | Project Mu UEFI 移植 | 备选引导方案，本轮不启用 |

mesa 仓库的关键约束：Mesa 的 VERSION 决定 libgallium-<version>.so 的 SONAME 与符号版本，
Debian 的 libEGL_mesa.so.0 以 DT_NEEDED 绑定该文件名。Debian 13.7 的
libgl1-mesa-dri 是 25.0.7-2+deb13u1，所以替换件的 VERSION 必须精确等于这个字符串。
apt 升级 Mesa 后需要按新版本重编，否则 EGL 加载失败。

### 2.3 构建主机

- WSL2 发行版 MT6891-Mainline，Ubuntu 24.04.5，16 核 / 7.2 GB / 948 GB 可用；
- qemu-user binfmt 已注册（qemu-aarch64），可直接 chroot arm64 rootfs；
- 可访问 mirrors.tuna.tsinghua.edu.cn 与 deb.debian.org；Debian 13.7 已发布；
- 工具链：aarch64-linux-gnu-gcc 13.3，可另装 g++-14-aarch64-linux-gnu 交叉编译器。

### 2.4 设备分区（已 dump）

boot_a/b、dtbo_a/b、lk、preloader、vbmeta 等都有原厂镜像；userdata 没有备份，
当前是 107 GB 的空分区。恢复 Android 需要整包线刷，因此 Debian 一旦覆盖 userdata，
Android 数据不可恢复——这一点在刷机前必须确认。

---

## 3. 总体架构

### 3.1 启动与图形数据流

~~~
LK (boot_a)
  └─ boot.img = Image.gz + busybox initramfs
       └─ initramfs/init
            ├─ 挂 pstore，打印上次启动 ramoops 摘要
            ├─ configfs 建 USB gadget（ACM 串口，RNDIS 可选）
            ├─ 等 UFS，按 LABEL=chopinroot 挂 /dev/sdc75
            └─ switch_root → systemd (Debian 13.7)

systemd
  ├─ gdm3 → gnome-shell (Wayland)
  │    └─ mutter
  │         ├─ KMS/atomic: /dev/dri/card0   (mediatek_v2, DSI-1 1080x2400)
  │         ├─ GBM/EGL:    /dev/dri/card0   (dumb buffer / dmabuf import)
  │         └─ render:     /dev/dri/renderD128 (panfrost, Mali-G77)
  ├─ NetworkManager → usb0 (RNDIS) / wlan0 (待固件)
  ├─ chopin-gadget.service（每次启动重建 gadget，幂等）
  ├─ chopin-diag.service（USB 状态写 /dev/kmsg，跨重启留存）
  └─ chopin-growroot.service（首次启动把 ext4 扩到分区大小）
~~~

### 3.2 为什么这套组合能成立

- **显示**： mediatek_v2 不走 mainline mtk-drm 的 atomic helper 那套，但驱动本身实现了 atomic
  commit、dumb buffer 与 PRIME import；mutter 需要的正是这三样，而不是某个特定驱动。
- **GPU**： panfrost 是独立平台设备，出 render node；合成器用 panfrost 渲染，再把 dma-buf
  导入 card0 扫描输出。两个驱动通过 dma-buf 解耦，不需要在 KMS 驱动里做 GPU 命令提交。
- **Mesa**： Debian 自带 Mesa 25.0.7 的 panfrost 驱动不认识 0x9080，会回落到 llvmpipe；
  参考仓库只加了一行型号表，替换 libgallium 即可，不需要重装整套 Mesa。
- **引导**： LK 路径是实机验证过的；UEFI（Mu-Silicium）虽然更"主线"，但会引入 ESP、
  UEFI 变量、显示初始化等一整套新变量，不适合作为首启方案。

### 3.3 启动时序（目标）

1. LK 加载 boot.img，读 dtb 段与 dtbo 分区；
2. 内核 setup_machine_fdt 用内嵌 chopin-board.dtb 覆盖，cmdline 由 CONFIG_CMDLINE_FORCE 提供；
3. mediatek_v2 点亮 DSI，fbcon 接管 tty0；
4. initramfs 起 gadget（约 1 s），打印上次启动摘要，挂 rootfs（UFS 枚举约 1–3 s）；
5. switch_root 进 systemd，udev 加载 panfrost，NetworkManager 起 usb0；
6. gdm3 起 Wayland，mutter 初始化 GBM/EGL，gnome-shell 出界面；
7. 自动登录 chopin，进入桌面；
8. 首次启动 growroot 把 ext4 扩到 107 GB。

---

## 4. 关键技术决策

| # | 决策 | 备选 | 理由 |
| --- | --- | --- | --- |
| D1 | Debian 13.7 trixie | Debian 12 + backports；Ubuntu 24.04 | trixie 的 Mesa 25.0.7 与参考 mesa 树完全一致；GNOME 48.7 是当前稳定版；5 年支持 |
| D2 | 保留 LK + boot.img | Mu-Silicium UEFI | LK 路径已实测；UEFI 需要 ESP 分区与新的显示初始化，风险高，列为 P6 备选 |
| D3 | ext4 镜像写到 userdata（LABEL=chopinroot） | 新建分区表；SD 卡 | userdata 107 GB 已可用；镜像构建可重复；不动其他分区 |
| D4 | vendor mediatek_v2 + panfrost | 主线 mtk-drm；纯 fbdev | vendor 栈已出图且是唯一验证过的 KMS；mainline mtk-drm 无 MT6893 支持，移植成本高 |
| D5 | 替换 libgallium 单文件 | 重编 Mesa .deb | 参考仓库已验证文件名/符号版本约束；替换单个 .so 风险最小 |
| D6 | 自建 busybox initramfs | initramfs-tools / dracut | 设备需要 pstore 摘要、gadget、按 label 挂 rootfs；自建脚本只有几十行，行为可控 |
| D7 | 先 gnome-core，后 task-gnome-desktop | 一次装完整 task | 首启只验证会话；完整 task 体积大、依赖多，失败时难定位 |
| D8 | 固件后置（WiFi/BT/音频） | 首启即追 WiFi | 首启不依赖网络；RNDIS/串口足够调试；NVRAM 需要从原厂分区提取 |

### D1 补充：为什么不选 Debian 12

- Debian 12 是 GNOME 43 + Mesa 22.3，参考 mesa 树的 25.0.7 版本号对不上，libgallium 替换会失败；
- 若用 backports，等于把 trixie 的关键组件搬回 bookworm，维护成本更高；
- trixie 的安装器、systemd、pipewire 对手机形态更友好。

### D4 补充：display 的退路顺序

1. **首选**：mutter Wayland + GBM + panfrost；
2. **退路一**：mutter X11 + llvmpipe（egl 走 swrast，不需要 panfrost 成功）；
3. **退路二**：GNOME Flashback（metacity）+ X11 + llvmpipe；
4. **退路三**：Weston/cage 验证 KMS 本身，再决定是否移植 mainline mtk-drm。

只有退路三也失败，才说明 vendor KMS 不满足基本 atomic/GBM 接口，需要动内核。

---

## 5. 仓库与 Git 模型

### 5.1 目录

~~~
/root/MT6891-Mainline/
├── linux/                 内核源码（独立 Git 仓库，.gitignore 排除）
├── patches/               参考项目 18 个补丁
├── scripts/               内核构建、boot.img 打包、串口/刷机辅助
├── out/                   内核产物（忽略）
├── debian/                ★ Debian 13 + GNOME 用户空间项目
│   ├── README.md          构建手册（怎么用）
│   ├── config/            版本、镜像、软件包清单、keyring
│   ├── scripts/           00–07 构建脚本 + build-all.sh
│   ├── initramfs/         busybox init 与 gadget 脚本
│   ├── overlay/           直接覆盖进 rootfs 的 /etc、/usr/local 文件
│   ├── build/             rootfs 工作目录（忽略）
│   ├── out/               镜像产物（忽略）
│   └── third_party/       mesa 克隆（忽略，pin 在 lock 文件）
├── docs-kernel.md
├── docs-debian.md         ★ 本文件
├── HANDOFF.md
└── README.md
~~~

debian/ 是用户空间工程目录，不是 Debian 源码包的 debian/ 目录；将来若做 .deb 打包，
放到 packaging/ 下，避免混淆。

### 5.2 Git 约定

- 主分支 main 同时跟踪内核侧文档/脚本与 debian/ 用户空间工程；
- 内核历史仍在 linux/.git（main/chopin 分支），不并入本项目历史；
- 里程碑打标签：debian-v13-m0（构建链）、m1（首启）、m2（GPU）、m3（桌面）；
- 提交前缀：debian:、kernel:、docs:、scripts:；
- 大文件策略：rootfs、镜像、mesa 源码树、构建目录全部忽略；只提交脚本、配置、文档、
  必要的小体积二进制（busybox 若采用跟踪方案）；
- 第三方版本 pin 在 debian/config/versions.env：
  - Debian 13.7 / trixie
  - Mesa 25.0.7-2+deb13u1（必须与 rootfs 的 libgl1-mesa-dri 一致）
  - mesa 仓库 commit b52e2e3a（含 G77 与构建脚本）
  - 内核 release 从 linux/include/config/kernel.release 读取，不硬编码。

### 5.3 与旧用户空间材料的关系

e55032c 之前的 Debian 12 材料（docs-debian.md、initramfs 脚本、sparse/send-image 工具）
已从工作区移除，但仍在 Git 历史里。本轮**不直接复用 Debian 12 的 rootfs**，只复用
其中经过实机验证的 initramfs 思路（pstore 摘要、configfs gadget、switch_root）与
mk-sparse.py / send-image.ps1 两个工具，并按 Debian 13 重写。

---

## 6. 实施阶段

### P0 环境与骨架（0.5 人日）

任务：
- 建 debian/ 目录与 Git 忽略规则；
- 安装构建依赖（mmdebstrap、qemu-user、meson/ninja、交叉 g++ 14、debootstrap keyring）；
- 用 mmdebstrap 生成 Debian 13.7 arm64 minbase rootfs；
- 验证 chroot 可执行、apt 可更新。

产物：debian/build/rootfs（约 300 MB）。
验收：chroot rootfs /bin/true 成功；apt-get update 无 GPG 错误。

### P1 根文件系统与桌面包（0.5–1 人日）

任务：
- 写 sources.list（trixie / updates / security，main + contrib + non-free-firmware）；
- 安装 gnome-core、gdm3、NetworkManager、pipewire、字体、mesa-utils 等；
- 建用户 chopin、设密码、sudo、时区、locale；
- 安装内核模块到 /lib/modules/<release>，depmod；
- 写入 overlay（gadget、diag、growroot、gdm 自动登录、dconf 缩放）。

产物：可 chroot 的完整 rootfs。
验收：dpkg -l 中 gnome-shell/mutter/gdm3 版本正确；systemctl --root 能 enable 服务。

### P2 initramfs、镜像与首启（1 人日）

任务：
- 生成 busybox initramfs（init + gadget 脚本）；
- mkfs.ext4 -d rootfs，e2fsck，mk-sparse 转 Android sparse；
- mkbootimg.py 打包 boot.img（只换 kernel + ramdisk，保留原厂 dtb 段）；
- fastboot 刷 boot 与 userdata，抓串口/tty0；
- 修复首启问题（挂载、gadget、systemd 依赖）。

产物：debian/out/chopin-rootfs.img（sparse）、debian/out/boot-chopin-debian.img。
验收：M1。

### P3 图形栈与 GNOME 会话（1–2 人日）

任务：
- 验证 modetest / kmscube / eglinfo；
- 交叉编译 mesa 25.0.7 + G77，替换 libgallium，重启 gdm；
- 观察 mutter 日志（WAYLAND_DEBUG、journalctl -u gdm3）；
- 失败则依次尝试 X11、GNOME Flashback、Weston；
- 调整缩放、屏幕键盘、触摸映射。

产物：可登录的 GNOME 桌面；一份显示栈验证记录（追加到 debian/README.md）。
验收：M2 + M3。

### P4 USB、网络与诊断（0.5 人日）

任务：
- chopin-gadget.service 稳定拉起 ACM；serial-getty@ttyGS0 可登录；
- RNDIS 可选（/etc/chopin-gadget-rndis），SSH over usb0；
- chopin-diag 写 kmsg；mask systemd-pstore；确认 ramoops 可回读；
- fastboot 恢复流程演练。

验收：M4 的网络部分。

### P5 硬件补齐（2–3 人日，按需）

- WiFi/BT：从 nvdata/vendor 提取 mediatek/mt6893/WIFI 与 BT 固件，恢复 pre-cal 等待；
- 充电/电量：修 i2c5 MT6360 或改用轮询，接 upower；
- 音频：ASoC 声卡、UCM、pipewire；
- 相机/视频：暂不排期。

### P6 稳定化与上游（持续）

- 30 分钟/2 小时/过夜稳定性；
- 内核告警清理、section mismatch 修复；
- 显示栈结论：vendor 长期维护还是迁 mainline mtk-drm；
- 文档与脚本固化，考虑把内核补丁拆成可上游的小系列。

---

## 7. 构建流程（脚本对应）

debian/scripts 的编号即执行顺序，build-all.sh 负责串联：

| 脚本 | 作用 | 关键点 |
| --- | --- | --- |
| 00-mkrootfs.sh | mmdebstrap minbase | 指定 Debian 13 keyring；arm64 + qemu binfmt |
| 01-install-desktop.sh | chroot 内 apt 安装桌面 | policy-rc.d 阻止服务启动；重试 |
| 02-configure-rootfs.sh | 用户/网络/服务/overlay/dconf | systemctl --root 或 chroot enable |
| 03-install-kernel.sh | 模块 + Image + dtb | release 必须与 out/modules 一致 |
| 04-build-mesa.sh | 交叉编译 G77 libgallium | Debian orig tarball + 参考补丁；校验 VERSION |
| 05-mkinitramfs.sh | busybox cpio.gz | 从 rootfs 取 busybox，init 脚本在仓库 |
| 06-mkrootfs-image.sh | ext4 + sparse | mkfs.ext4 -d，e2fsck，mk-sparse |
| 07-mkbootimg.sh | boot.img | 不传 --dtb，保留原厂 dtb 段 |
| build-all.sh | 串联 + 校验 | --skip-gnome / --skip-mesa 便于分步 |

完整命令：

~~~bash
cd /root/MT6891-Mainline
sudo debian/scripts/build-all.sh            # 或分步执行 00..07
~~~

刷机（Windows，需先备份原厂 boot/dtbo）：

~~~powershell
cd D:\MT6891-Mainline
.\debian\scripts\flash.ps1 -Boot .\debian\out\boot-chopin-debian.img -Rootfs .\debian\out\chopin-rootfs.img
~~~

---

## 8. 测试矩阵

| 层 | 命令 | 期望 | 失败处置 |
| --- | --- | --- | --- |
| 构建 | qemu-aarch64-static chroot rootfs /bin/true | 返回 0 | 检查 binfmt、动态库 |
| 首启 | 串口/tty0 观察 | 出现 login | 看 initramfs 打印、ramoops |
| systemd | systemctl --failed | 无失败或已知白名单 | journalctl -xb |
| 显示 | modetest -M mediatek -c | DSI-1 1080x2400 connected | 检查 mediatek_v2 绑定 |
| EGL | eglinfo -B | Mali-G77 (Panfrost) | 未识别则查 libgallium 版本 |
| GPU | kmscube | 稳定 10 分钟 | 锁 GPU 频率、看 dmesg |
| 桌面 | loginctl session-status | wayland 会话 | 切 X11 / Flashback |
| 触摸 | evtest / libinput debug-events | 事件正常 | 查 NVT 驱动 |
| USB | ls /sys/class/udc；cat state | configured | 看 gadget 脚本日志 |
| 网络 | ip -br a；ssh chopin@192.168.42.2 | usb0 有地址 | 开 RNDIS 或查 DHCP |
| 稳定性 | 30 分钟 idle + 30 分钟 kmscube | 无 panic/复位 | ramoops + pstore |

---

## 9. 风险登记

| # | 风险 | 概率 | 影响 | 触发信号 | 缓解 / 兜底 |
| --- | --- | --- | --- | --- | --- |
| R1 | mutter 无法在 vendor KMS 上初始化 GBM/atomic | 中 | 无 Wayland 桌面 | gdm 日志 EGL/GBM 失败 | X11 + llvmpipe；GNOME Flashback；Weston 验证 KMS |
| R2 | panfrost 在 chopin 上不稳定/复位 | 中 | 桌面崩溃 | dmesg GPU fault / 设备重启 | 锁 GPU 频率；禁用 GPU 用 llvmpipe；查 chopin 钩子 |
| R3 | 2 GB 内存（或 6/8 GB）不够 GNOME | 低 | OOM | OOM killer | zram；关 tracker；gnome-core 精简 |
| R4 | WiFi NVRAM 缺失 | 高 | 无 WiFi | wlan0 不出现 | RNDIS/SSH；后续提取固件 |
| R5 | 32 位 fastboot 刷大镜像失败 | 中 | 刷机中断 | std::bad_alloc | sparse 镜像；RNDIS 推送；64 位 fastboot |
| R6 | qemu-user 下 apt 安装失败 | 中 | rootfs 不完整 | dpkg 错误 | 分步重试；--skip 已装包；换 debootstrap 变体 |
| R7 | 模块 release 与内核不匹配 | 中 | 无 GPU/外设 | modprobe 失败 | 03 脚本校验 kernel.release；重编后重装 |
| R8 | 充电/电量不工作 | 高 | 断电风险 | 无电池图标 | 保持 USB 供电；修 i2c5；降级为台面使用 |
| R9 | Mesa 版本漂移导致 EGL 失败 | 中 | 黑屏/软件渲染 | eglinfo 报错 | apt-mark hold libgl1-mesa-dri；重编 |
| R10 | 触摸固件缺失噪声 | 低 | 日志刷屏 | NVT 报错 | 忽略或提供 blob |

---

## 10. 诊断与恢复

- **串口**：USB ACM（/dev/ttyGS0 → Windows COMx，115200 8N1，DTR+RTS）；
  现有 scripts/capture-serial.ps1 与 boot-cycle.ps1 可复用。
- **pstore/ramoops**：cmdline 已划 0x48090000 起 0x8f000；initramfs 启动时打印摘要；
  rootfs 内 mask systemd-pstore.service，避免日志被搬走删除。
- **恢复原厂**：fastboot flash boot chopin/images/boot_a.img；dtbo 同理；slot 被切到 b 时
  fastboot --set-active=a。userdata 一旦覆盖无法恢复 Android 数据。
- **重刷 rootfs**：只刷 userdata；boot 分区不用动。
- **无 USB 时**：tty0 拍照 + 下次启动 initramfs 摘要；必要时用 dump-init 变体。

---

## 11. 时间表（人日，按顺序）

| 阶段 | 内容 | 估计 |
| --- | --- | --- |
| P0 | 环境、骨架、minbase rootfs | 0.5 |
| P1 | GNOME core、用户、服务、模块 | 0.5–1 |
| P2 | initramfs、镜像、首启 | 1 |
| P3 | GPU/Mesa、GNOME 会话、缩放 | 1–2 |
| P4 | USB 网络、诊断、恢复演练 | 0.5 |
| P5 | WiFi/BT、电源、音频 | 2–3 |
| P6 | 稳定化、文档、上游化 | 持续 |

首启（M1）预计 2 人日内；桌面（M3）预计 4 人日内；日常可用（M4）视 WiFi/电源进展 1 周左右。

---

## 12. 待确认问题

1. 是否需要保留 Android 双系统？（当前 userdata 已被覆盖，双系统需要重新分区）
2. WiFi 是否为首启必需？若必须，需要先从原厂固件包/手机分区提取 NVRAM。
3. 桌面定位：手机形态（大图标、屏幕键盘）还是桌面形态（鼠标键盘、外接屏）？
4. 是否接受 llvmpipe 的软件渲染作为兜底（性能约 5–15 fps）？
5. 是否需要在设备上保留 SSH/串口登录（默认 root 密码 chopin）？

---

## 13. 参考

- 内核参考：<https://github.com/MT6891-Mainline/linux>（分支 7.3.3-mt6893-xiaomi-chopin）
- Mesa 参考：<https://github.com/MT6891-Mainline/mesa>（25.0.7 + G77，chopin/build.sh）
- UEFI 备选：<https://github.com/MT6891-Mainline/Mu-Silicium>
- Debian 13 发布说明：<https://www.debian.org/releases/trixie/>
- Debian 软件包：<https://packages.debian.org/trixie/>
- 内核文档：docs-kernel.md（引导链、cmdline、驱动状态、已知问题）

---

## 14. 实机 bring-up 记录（2026-11-14 晚）

- 刷入 boot + userdata 成功：sparse 2.9 GB，fastboot 分 12 个 chunk，共 89 s。
- Debian 13.7 能到 multi-user：UFS rootfs 挂载、systemd 起来、DRM card0-DSI-1 正常。
- gdm3 进入约 0.6 s 一次的重启循环，屏幕闪烁，tty0 被日志淹没；已暂时 mask gdm3、
  默认 multi-user.target，留串口 getty 继续调试。
- USB gadget 第一次失败：configfs-gadget 报 "Need at least one configuration in g1" → EINVAL。
  根因是 initramfs 用 `[ ! -s idVendor ]` 判断是否初始化，而 configfs 的 idVendor 默认非空，
  导致 configs/c.1 从未创建。改为 `rm -rf g1` + 无条件创建后，debug3 镜像成功枚举出
  VID_1D6B/PID_0104，Windows 出现 COM11。
- 正常 initramfs/rootfs 启动时 UDC 仍偶发 `state=not attached`、主机无枚举；正在把
  gadget 初始化收敛到与 debug3 相同的无条件流程，并保留 pstore + 串口诊断。
- 23:19 刷入关闭 gdm 的镜像：到 multi-user，gdm 不再循环；gadget 仍 `not attached`、
  主机无 COM。
- 23:28 构建幂等 gadget 修复（UDC 已绑定时 systemd 服务直接跳过，不再 `rm -rf g1`），
  但尚未刷入。
- 关键对照：debug3（不 switch_root、不跑 systemd）能枚举 COM11；正常启动不能。
  需要验证的假设：systemd 服务拆 gadget，或 switch_root 后 mtu3 端口状态。
- 详细记录：[debian/BRINGUP.md](debian/BRINGUP.md)。

---

## 15. 2026-11-15 实机验证补充（M1/M2/M3）

- **M1 完成**：USB gadget 绑定 bug 修复后串口控制台打通，Debian 13.7 以
  `systemd running` 状态运行，`udc state=configured`，无失败单元。
- **M2 部分**：KMS 正常（1080×2400 DSI-1），EGL/llvmpipe 可用；GPU panfrost
  因时钟/复位问题 probe 失败（`bus_clock rate = 0`、reset timeout），暂无 renderD128。
  GBM 平台无 Mesa 驱动 → 暂不启用 Wayland。
- **M3 部分**：GDM 以 X11 会话运行（需补 `/usr/share/xsessions/gnome.desktop`），
  Xorg + gnome-shell 48.7 自动登录 chopin，桌面可见；触摸暂未工作（NVT IRQ 不触发）。
- 具体根因、修复与后续方案见 [debian/PLAN.md](debian/PLAN.md) 与
  [debian/BRINGUP.md](debian/BRINGUP.md)。
