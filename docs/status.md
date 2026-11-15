# 项目状态

> 快照时间：2026-11-15 13:30
> 设备：Redmi Note 10 Pro 5G / POCO X3 GT（chopin，M2104K10AC，MT6891Z/CZA，Dimensity 1100）
> 内核：Linux 7.3.4 + **25 个补丁**；用户空间：Debian 13.7 + GNOME 48.7（Mesa 25.0.7-2+deb13u1）

## 0. 一句话

**桌面已经真正跑在 GPU 上**：GNOME 48.7 以 **Wayland** 会话运行在 Mali-G77（panfrost）上，
1080×2400@120、缩放 2.5，触摸已修复并在实机验证，USB ACM 串口控制台正常。
剩下的主要问题是 **P0 偶发 SError**（频率已大降、未根除）、充电（MT6360 子设备 -16）、
网络（RNDIS/WiFi）和音频/相机。

## 1. 里程碑

| 里程碑 | 内容 | 状态 |
| --- | --- | --- |
| M0 构建链 | rootfs 可 chroot、可装包 | ✅ 完成 |
| M1 首启 | 内核 → initramfs → ext4 → systemd，串口可登录 | ✅ 完成（2026-11-15 00:10） |
| M2 图形 | KMS + EGL + GPU | ✅ 完成（panfrost + kmsro + G77） |
| M3 桌面 | GDM + GNOME 会话，可交互 | ✅ 完成（Wayland，触摸可用） |
| M4 日常 | 网络、WiFi、电源、音频 | 🔶 电量可读；充电/网络/音频未完成 |

## 2. 硬件矩阵

| 子系统 | 状态 | 证据 / 备注 |
| --- | --- | --- |
| 引导 | ✅ | LK 从 boot.img 的 DTBO 段 + dtbo 分区取 DT；内核用内嵌 `chopin-board.dtb` 覆盖 |
| 内核 | ✅ | 进入用户态；release `7.3.4-g5775fb2ac0a1-dirty` |
| 显示 | ✅ | DRM `card1-DSI-1` connected，1080×2400；vendor `mediatek-drm` |
| GPU | ✅ | panfrost 识别 `mali-g77 id 0x9080`，`/dev/dri/renderD128`；`bus_clock rate = 349999848` |
| 渲染 | ✅ | GLX/EGL/glamor 全部 `Mali-G77 (Panfrost)`；`glxgears` 122 FPS（vsync 120 Hz） |
| 桌面 | ✅ | gdm3 + GNOME 48.7 **Wayland** 会话；X11 下 mutter 不出帧（见 BRINGUP §12.6） |
| 触摸 | ✅ | NVT36672c：固件自愈 + lockdown 重试 + Y 轴修复；24 点网格校验无镜像 |
| 按键 | ✅ | mtk-pmic-keys / mtk-kpd |
| 存储 | ✅ | UFS，userdata = `/dev/sdc75`（107 GB） |
| USB UDC | ✅ | mtu3 注册 11201000.usb；configfs ACM 绑定成功，COM11 |
| 串口控制台 | ✅ | `/dev/ttyGS0` + serial-getty；Windows COM11 115200 8N1 |
| 网络 | ❌ | 仅 lo；RNDIS 未启用、WiFi 缺 NVRAM |
| 充电/电量 | ⚠️ | 电量可读（bq27z561，4.3 V/89%）；状态 Not charging、current 0；MT6360 子设备 -16 |
| 音频 | ❌ | ASoC 驱动在树内，未验证 |
| 相机/视频 | ❌ | vendor 驱动在树内，未验证 |
| 稳定性 | ⚠️ | Wayland 桌面连续 3.5 h 无 SError（含 40 min 压力）；P0 未根除 |

## 3. 当前阻塞

### 3.1 P0：偶发 SError（`0xbe000411`）

- 现象：异步外部中止，栈在 `clear_page`（首次触碰新分配页）或 ext4 写路径；
- 根因方向：板级 DTS 的 reserved-memory 与 LK 真实布局不符，漏掉的 carve-out 被当成空闲 RAM；
- 已做：按 LK 的 `CHOPIN-LKDT` dump 修正 6 个 mblock 节点（0023），SError 频率从「X11 桌面
  1–3 分钟必崩」降到「3.5 小时不崩」；
- 未做：mblock-26/27 之间 237.25 MiB 的 `no-map` 保留对照镜像（0025）已构建、未长期验证；
  若仍复现，下一步用「按页扫内存 + pagemap 记录 PFN」定位坏页。

### 3.2 充电 / MT6360

- i2c5 上 `subpmic_pmic@1a`、`subpmic_ldo@64` 与 mt6360 MFD 抢地址（-16 EBUSY）；
- 电量 IC（bq27z561）正常，但充电状态 `Not charging`、`current_now=0`；
- 影响：长期只能靠电池，且 `otg_vbus` 不完整。

### 3.3 网络

- RNDIS/ECM 没加进 USB gadget，设备只有 lo；
- WiFi 的 `mediatek/mt6893/WIFI` NVRAM 在 nvdata 分区，内核取不到；
- 影响：只能靠 115200 串口传文件，开发效率受限。

### 3.4 其他

- 音频、相机、视频编解码未验证；
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
make bootstrap          # 内核源码 + 25 个补丁（校验 tree = ec46ef62…）
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
