# 项目状态

> 快照时间：2026-11-15
> 设备：Redmi Note 10 Pro 5G / POCO X3 GT（chopin，M2104K10AC，MT6891Z/CZA，Dimensity 1100）
> 内核：Linux 7.3.4 + 20 个补丁；用户空间：Debian 13.7 + GNOME 48.7

## 0. 一句话

内核能启动，Debian 13.7 以 systemd running 状态运行，**X11 + llvmpipe 的 GNOME 桌面已可用**，
USB ACM 串口控制台正常。**触摸（NVT IRQ 不触发）和 GPU（panfrost 时钟/复位）仍是内核侧阻塞项**；
WiFi/充电/音频未打通。

## 1. 里程碑

| 里程碑 | 内容 | 状态 |
| --- | --- | --- |
| M0 构建链 | rootfs 可 chroot、可装包 | ✅ 完成 |
| M1 首启 | 内核 → initramfs → ext4 → systemd，串口可登录 | ✅ 完成（2026-11-15 00:10） |
| M2 图形 | KMS + EGL + GPU | 🔶 KMS ✅、llvmpipe ✅、panfrost ❌ |
| M3 桌面 | GDM + GNOME 会话，可交互 | 🔶 X11 桌面 ✅、触摸 ❌ |
| M4 日常 | 网络、WiFi、电源、音频 | ⬜ 未开始 |

## 2. 硬件矩阵

| 子系统 | 状态 | 证据 / 备注 |
| --- | --- | --- |
| 引导 | ✅ | LK 从 boot.img 的 DTBO 段 + dtbo 分区取 DT；内核用内嵌 chopin-board.dtb 覆盖 |
| 内核 | ✅ | 进入用户态；release 由 git describe 决定 |
| 显示 | ✅ | DRM card0-DSI-1 connected，1080×2400；vendor mediatek_v2，fbcon 正常 |
| 触摸 | ❌ | NVT36672c probe 成功、IRQ 33 注册，但触摸时中断计数 0 |
| 按键 | ✅ | mtk-pmic-keys / mtk-kpd |
| 存储 | ✅ | UFS，userdata = /dev/sdc75（107 GB） |
| USB UDC | ✅ | mtu3 注册 11201000.usb；configfs ACM 绑定成功，COM11 |
| 串口控制台 | ✅ | /dev/ttyGS0 + serial-getty；Windows COM11 115200 8N1 |
| GPU | ❌ | panfrost probe -110；bus_clock=0、reset timeout，无 renderD128 |
| 渲染 | ⚠️ | llvmpipe（LLVM 19.1.7）；X11 + GNOME 可用但慢 |
| 网络 | ❌ | 仅 lo；RNDIS 未启用、WiFi 缺 NVRAM |
| 充电/电量 | ❌ | MT6360 子设备注册失败；保持 USB 供电 |
| 音频 | ❌ | ASoC 驱动在树内，未验证 |
| 相机/视频 | ❌ | vendor 驱动在树内，未验证 |

## 3. 当前阻塞

### 3.1 触摸（决定“可交互”，最高优先）

- 驱动 probe 正常：chip id 读取、input 设备注册、IRQ 33 注册；
- 触摸时 `/proc/interrupts` IRQ 33 计数为 0，`evtest` / `libinput debug-events` 无事件；
- `/sys/kernel/debug/gpio`：`gpio-19 (NVT-int) in lo IRQ ACTIVE LOW`；
- DT：`novatek,irq-gpio = <&pio 0x13 0x2001>`，驱动 `int_trigger_type=1`。

方向：触发类型/极性 → EINT19 pinctrl 复用 → 固件
`novatek_nt36672c_k10a_fw01.bin` → SPI 读点。

### 3.2 GPU / panfrost

- 首次 probe mtcmos -517（audio-controller 未 probe）；重载后 -517 消失；
- 仍 `gpu soft/hard reset timed out`、`using only 1st core group`、
  `bus_clock rate = 0`、`chopin: no core_clk_rate knob` → probe -110；
- 结论：电源域已就绪，阻塞在 GPU 时钟/复位。

方向：对齐 mt6893 clk 驱动的 mfg/bus clock id；确认复位前 mfg 电源域已上电；
修好后重建全量 libgallium（panfrost + swrast）。

### 3.3 其他

- **i2c5 / MT6360**：subpmic_pmic@1a、subpmic_ldo@64、tcpc 注册失败，影响充电与 otg_vbus；
- **WiFi/BT**：`mediatek/mt6893/WIFI` NVRAM 在 nvdata 分区，内核取不到；
- **显示栈**：vendor mediatek_v2 只有 dumb-buffer/fbdev 级别，GBM/Wayland 未通；
- **g_multi**：内建 `CONFIG_USB_G_MULTI=y` 仍 probe -EINVAL，当前用 configfs ACM。

## 4. 下一步

1. 触摸：提取 NVT 固件 / 调 DT 触发类型 → 重建内核 → 只刷 boot → evtest 验证；
2. GPU：修 panfrost 时钟/电源 → renderD128 → eglinfo/kmscube；
3. Mesa 全量 libgallium（panfrost+swrast）→ 尝试 Wayland；
4. RNDIS/SSH 网络 → WiFi NVRAM → MT6360 充电 → 音频；
5. 桌面打磨、稳定性、内核告警清理、补丁上游化。

## 5. 构建与产物

```bash
cd chopin-linux
make bootstrap          # 内核源码 + 20 个补丁
make kernel             # Image.gz / dtb / modules
sudo make debian        # Debian rootfs + GNOME + 镜像
make artifacts          # 汇总到 out/ + SHA256SUMS
```

产物：`out/boot-chopin-debian.img`、`out/chopin-rootfs.sparse.img`、`out/Image.gz`、
`out/initramfs.cpio.gz`。

## 6. 文档

- 复现：[reproduce.md](reproduce.md)
- 刷机：[flashing.md](flashing.md)
- 内核：[../kernel/docs/kernel.md](../kernel/docs/kernel.md)
- Debian 计划：[../debian/docs/PLAN.md](../debian/docs/PLAN.md)
- 历史资料：[archive/](archive/)
