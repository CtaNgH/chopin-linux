# 项目状态

> 快照时间：2026-11-16 04:00
> 设备：Redmi Note 10 Pro 5G / POCO X3 GT（chopin，M2104K10AC，MT6891Z/CZA，Dimensity 1100）
> 内核：Linux 7.3.4 + **34 个补丁**；用户空间：Debian 13.7 + GNOME 48.7（Mesa 25.0.7-2+deb13u1）

## 0. 一句话

**这台手机已经可以当一台日常可用的 Linux 桌面**：GNOME 48.7 以 **Wayland** 运行在
Mali-G77（panfrost）上，1080×2400@120、缩放 2.5，触摸正常；USB 口同时提供 **CDC-NCM 网卡**
（usb0 = 192.168.42.2，SSH 免密）和串口控制台；**WiFi 已连 5 GHz**（apt 实测 1.8 MB/s）；
**扬声器出声**（MT6893/MT6359/CS35L41，模拟增益 +20.5 dB）；系统时间由 NTP 校准；**A78 集群从 729 MHz 提到 1.5 GHz**（×2.05）。
剩下的主要问题是 **P0 偶发 SError**（频率已大降、未根除），以及蓝牙 / 耳机 / 麦克风 / 相机。

## 1. 里程碑

| 里程碑 | 内容 | 状态 |
| --- | --- | --- |
| M0 构建链 | rootfs 可 chroot、可装包 | ✅ 完成 |
| M1 首启 | 内核 → initramfs → ext4 → systemd，串口可登录 | ✅ 完成（2026-11-15 00:10） |
| M2 图形 | KMS + EGL + GPU | ✅ 完成（panfrost + kmsro + G77） |
| M3 桌面 | GDM + GNOME 会话，可交互 | ✅ 完成（Wayland，触摸可用） |
| M4 日常 | 网络、WiFi、电源、音频 | 🔶 USB 网络/SSH、WiFi、扬声器、充电、NTP 已通；蓝牙/耳机/麦克风/相机未完成 |

## 2. 硬件矩阵

| 子系统 | 状态 | 证据 / 备注 |
| --- | --- | --- |
| 引导 | ✅ | LK 从 boot.img 的 DTBO 段 + dtbo 分区取 DT；内核用内嵌 `chopin-board.dtb` 覆盖 |
| 内核 | ✅ | 进入用户态；release `7.3.4-g5775fb2ac0a1-dirty` |
| 内存 | ✅ | 实配 6 GiB；静态预留 767 MiB（44 节点），**MemTotal 5.07 GiB**（改前 4.47）；1.5/3 GiB 触碰无 SError |
| 显示 | ✅ | DRM `card1-DSI-1` connected，1080×2400；vendor `mediatek-drm` |
| GPU | ✅ | panfrost 识别 `mali-g77 id 0x9080`，`/dev/dri/renderD128`；核心 650 MHz（chopin-gpu-freq） |
| 渲染 | ✅ | GLX/EGL/glamor 全部 `Mali-G77 (Panfrost)`；`glxgears` 122 FPS（vsync 120 Hz） |
| 桌面 | ✅ | gdm3 + GNOME 48.7 **Wayland** 会话；X11 下 mutter 不出帧（见 BRINGUP §12.6） |
| 触摸 | ✅ | NVT36672c：固件自愈 + lockdown 重试 + Y 轴修复；24 点网格校验无镜像 |
| 按键 | ✅ | mtk-pmic-keys / mtk-kpd |
| 存储 | ✅ | UFS，userdata = `/dev/sdc75`（107 GB） |
| USB UDC | ✅ | mtu3 注册 11201000.usb；configfs gadget = CDC-ACM + CDC-NCM，COM11 + usb0 |
| 串口控制台 | ✅ | `/dev/ttyGS0` + serial-getty；Windows COM11 115200 8N1 |
| 网络 | ✅ | CDC-NCM usb0 = 192.168.42.2/24（Windows 自动 DHCP，SSH 免密）；WiFi wlan0 连 5 GHz 5240 MHz / 780 Mbit/s |
| 充电/电量 | ✅ | bq27z561 电量/电压可读；MT6360 输入 900 mA、充电 1.5 A、终止 100 mA、CV 4.4 V；提前 EOC 由 recharge timer 兜底（实测 +296 mA） |
| 音频 | 🔶 | MT6893/MT6359/CS35L41 声卡（card 0），扬声器出声；模拟增益 +20.5 dB、左右声道已修正；耳机/听筒/麦克风未做 |
| 时间 | ✅ | RTC 无电池；systemd-timesyncd 启动后校准（否则 HTTPS 全挂） |
| 相机/视频 | ❌ | vendor 驱动在树内，未验证 |
| CPU 频率 | ✅ | A78 729 MHz → **1.5 GHz**（armpll_bl = 1499998780，依赖链基准实测 1497 MHz）；A55 1.773 GHz 不变；电压在 MT6315（SPMI）不可控，1.8 GHz 未验证 |
| 显示 DMA | ✅ | 34 位 mask（原 32 位）：SWIOTLB 单次上限 256 KiB，>4 GiB 的 scanout 全部映射失败（每启动 50–114 次）；修好后 0 次 |
| 崩溃 | 🔶 | Chrome/Nautilus 的 Wayland Error 71 已随 DMA mask 修复消失；Nautilus 重命名 + 屏幕键盘仍 100% 崩（Debian #1151025，上游问题） |
| 稳定性 | ⚠️ | Wayland 桌面连续 3.5 h 无 SError（含 40 min 压力）；P0 未根除。2026-11-16 把随机崩溃定位到显示 DMA mask（已修） |

## 3. 当前阻塞

### 3.1 P0：偶发 SError（`0xbe000411`）

- 现象：异步外部中止，栈在 `clear_page`（首次触碰新分配页）或 ext4 写路径；
- 根因方向：板级 DTS 的 reserved-memory 与 LK 真实布局不符，漏掉的 carve-out 被当成空闲 RAM；
- 已做：按 LK 的 `CHOPIN-LKDT` dump 修正 6 个 mblock 节点（0023），SError 频率从「X11 桌面
  1–3 分钟必崩」降到「3.5 小时不崩」；
- 2026-11-15 晚：实机 memblock 已确认 237.25 MiB 的 md gap 作为 `0xe2000000..0xfc000000` 一整段
  NOMAP 生效；同时删掉 848 MiB 的 `zone_movable_cma`（0028），MemTotal 4.47 → 5.07 GiB；
  3 GiB 触碰无 SError，P0 仍需长稳观察。

### 3.2 充电 / MT6360 ✅ 已可用

- MT6360 充电器正常：`POWER_SUPPLY_STATUS=Full/Charging`、`ONLINE=1`、输入限流 500 mA（SDP）；
- bq27z561 电量计可读（电压/容量/电流）；
- i2c5 上 `subpmic_pmic@1a`、`subpmic_ldo@64` 仍报 -16 EBUSY——它们是原厂 DTS 的遗留节点，
  与 MT6360 MFD 抢地址，不影响功能（可后续删掉）。

### 3.3 网络 ✅ 已可用

- **USB 网络**：gadget 用 CDC-NCM（Windows 11 自带 `usbncm.inf` 驱动；RNDIS 在这台机器上没有驱动），
  设备 usb0 = 192.168.42.2/24 + dnsmasq，Windows 自动 DHCP；SSH 免密；
- **WiFi**：WLAN-GEN4 内置驱动 + vendor 分区固件 + nvdata 里的 `APCFG/APRDEB/WIFI`，
  `chopin-wifi-firmware.service` 在 sysinit 前装好；wlan0 连 5 GHz，apt 1.8 MB/s；
- 遗留：蓝牙（vendor BT 驱动未编入）、耳机/麦克风。

### 3.4 其他

- 耳机/听筒/麦克风、蓝牙、相机、视频编解码未验证；
- X11 下 mutter 不出帧（DRI2 GLX 的 present 路径），桌面只能走 Wayland；
- 触摸空闲时 IRQ 仍以 ~2/s 触发（驱动打印 "finger leave"），不影响功能。

## 4. 下一步

1. **P0**：刷 gap 保留镜像做长稳对照；不行就做按页扫描定位坏页；
2. **网络**：RNDIS/CDC-ECM 加进 configfs gadget → SSH/scp → 再提 WiFi NVRAM 固件；
3. **充电**：修 MT6360 地址冲突/charger 参数；
4. **音频/相机**：逐个点亮；
5. **上游化**：拆分补丁、补 binding 文档、清 vendor 告警。

## 5. 构建与产物

```bash
cd chopin-linux
make bootstrap          # 内核源码 + 28 个补丁（校验 tree = bb745e0a…）
make kernel             # Image.gz / dtb / modules
sudo make debian        # Debian rootfs + GNOME + 镜像
make artifacts          # 汇总到 out/ + SHA256SUMS
```

产物：`out/boot-chopin-debian.img`、`out/chopin-rootfs.sparse.img`、`out/Image.gz`、
`out/initramfs.cpio.gz`。

> 刷机两个必须知道的坑：**boot.img 的 dtb 段必须保留原厂 201,848 B blob**（换掉会 LK 反复重启）；
> **只换 Image.gz 时 release 必须和已装模块一致**（用 `CHOPIN_LOCALVERSION` 钉住）。

## 6. 文档

- 本次适配全记录：[bringup-2026-11-15.md](bringup-2026-11-15.md)
- 复现：[reproduce.md](reproduce.md)
- 刷机：[flashing.md](flashing.md)
- 内核：[../kernel/docs/kernel.md](../kernel/docs/kernel.md)
- Debian 现场记录：[../debian/docs/BRINGUP.md](../debian/docs/BRINGUP.md)
- Debian 计划：[../debian/docs/PLAN.md](../debian/docs/PLAN.md)
- 历史资料：[archive/](archive/)
