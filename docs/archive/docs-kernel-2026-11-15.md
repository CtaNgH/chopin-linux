# chopin 主线内核移植 — 技术文档

> 设备：Redmi Note 10 Pro 5G / POCO X3 GT（chopin，M2104K10AC，MT6891Z/CZA，Dimensity 1100）
> 内核基线：Linux v7.3.4（stable）
> 文档更新：2026-11-14

本文件只讲**内核**：引导链、设备树、cmdline、驱动状态、已知问题、构建与刷写、补丁系列。
用户空间（Debian / 桌面）相关内容与产物已从本工作区移除。

---

## 1. 仓库与构建环境

| 项 | 值 |
| --- | --- |
| 项目仓库 | `/root/MT6891-Mainline`（跟踪 `patches/`、`scripts/`、文档；`linux/` 被 .gitignore 排除） |
| 内核仓库 | `/root/MT6891-Mainline/linux`（独立 git 仓库，分支 `chopin`） |
| 交叉工具链 | `aarch64-linux-gnu-gcc` 13.3.0 |
| 构建机 | WSL2 Ubuntu 24.04，16 核 / 7 GB |
| 参考实现 | [MT6891-Mainline](https://github.com/MT6891-Mainline) 的 `7.3.3-mt6893-xiaomi-chopin`（18 个补丁） |

内核仓库历史（从旧到新）：

| commit | 内容 |
| --- | --- |
| `98385cc` | Linux v7.3.4 基线 |
| `e1069f8..e67a20d` | 参考项目的 18 个补丁（`git am`），标签 `chopin-v7.3.4-r1` |
| `a9777a855` | 实机首启修复：删 DT 的 bootargs、cmdline 加 `swiotlb=0` / `iommu.passthrough=1` |
| `1ebb5994c` | 控制台静音（loglevel=4、WLAN NVRAM 重试静音、pre-cal 等待 5 s）+ USB DT 调整 |

构建（产物全部在 `linux/arch/arm64/boot/` 和 `out/`）：

```bash
cd /root/MT6891-Mainline
./scripts/build.sh            # = make chopin_defconfig + Image.gz dtbs modules
```

构建时 release 字符串由 `git describe` 决定（例如 `7.3.4-ga9777a8559e0-dirty`）——
**装模块/刷机前先 `cat linux/include/config/kernel.release` 确认**，否则 `/lib/modules/<rel>` 对不上。

---

## 2. 引导链（实机实测）

1. **LK 从 boot.img 的 dtb 段读基础 DTB**。该段不是裸 FDT，而是一个 **DTBO 表**（magic `0xd7b7ab1e`，原厂 201,848 B）。
   LK 再叠加 **dtbo 分区**的 overlay（原厂 72,879 B）。
2. LK 校验并加载 kernel / ramdisk，跳到 `Image`。
3. **内核在 `setup_machine_fdt()`（`arch/arm64/kernel/setup.c`）用内嵌的
   `arch/arm64/kernel/chopin-board.dtb`（256,811 B）覆盖 LK 传来的 FDT**，日志里是：

       CHOPIN-DTB: overriding LK FDT with embedded board tree (256811 bytes)

4. **cmdline 由 `CONFIG_CMDLINE_FORCE=y` 强制**使用内核内置串；boot.img 头里的
   `bootopt=64S3,32N2,64N2 buildvariant=user` 只是给 LK 看的。

由此得到两条规则：

- 改 `arch/arm64/boot/dts/mediatek/mt6893-xiaomi-chopin.dts` 只影响 LK 阶段（以及你自己打包的 dtb 段）；
  运行时行为由**内嵌 DTB**决定。想让 LK 阶段也用新 dtb，得用 `mkbootimg.py --dtb ...` 重新封 boot.img。
- DT 里的 `/chosen/bootargs` **不能太长**，否则 LK 在 `load_lk_dtb` 阶段 panic
  （`expdb` 里可见 `panic: [ERROR] CMDLINE overflow`）。移植时已经把它删掉。

### 2.1 ⚠️ 一个必须知道的坑：`chopin-*.dtsi` 没有被编译

`arch/arm64/kernel/chopin-*.dtsi`（`chopin-usb.dtsi`、`chopin-reset.dtsi`、`chopin-pmic.dtsi` …）
**没有被任何文件 include**（全树 grep 没有任何 include 语句）—— 它们是移植过程中写的注释草稿/碎片。

运行时设备树真正的来源只有一条链：

    arch/arm64/kernel/chopin-board.dts
      └── ../boot/dts/mediatek/mt6893-xiaomi-chopin.dts
            └── mt6893.dtsi          (SoC 侧，vendor 生成，6000+ 行)

要改运行时行为：改 `mt6893.dtsi` 或 `mt6893-xiaomi-chopin.dts`，然后**必须重编 Image**
（DTB 通过 `chopin-dtb.o` 编进内核，只跑 `make dtbs` 不会更新内核里的那份）。

检查编译结果：

```bash
dtc -I dtb -O dts linux/arch/arm64/kernel/chopin-board.dtb | less
# 或者看内核里的：
dtc -I dtb -O dts /sys/firmware/fdt     # 设备上
```

---

## 3. 内核 cmdline

`arch/arm64/configs/chopin_defconfig` 里的 `CONFIG_CMDLINE`（由 `CONFIG_CMDLINE_FORCE` 强制）：

    console=tty0 swiotlb=0 iommu.passthrough=1 clk_ignore_unused regulator_ignore_unused \
    pd_ignore_unused loglevel=4 panic=0 printk.devkmsg=on chopinport=v2onehundredfifth \
    log_buf_len=4194304 pstore.kmsg_bytes=262144 \
    ramoops.mem_address=0x48090000 ramoops.mem_size=0x8f000 ramoops.record_size=0x1000 \
    ramoops.console_size=0x40000 ramoops.ftrace_size=0 ramoops.pmsg_size=0

| 参数 | 作用 / 为什么必须 |
| --- | --- |
| `console=tty0` | 用 fbcon（DRM fbdev emulation）做控制台 |
| `swiotlb=0` | **必须**。默认 bounce 区落在厂商固件保留内存，第一次 i2c DMA 就 async SError panic。见 `out/console-ramoops*.txt` |
| `iommu.passthrough=1` | 厂商 DTS 与主线 SMMU 描述符对不上，直接透传 |
| `clk_ignore_unused` `regulator_ignore_unused` `pd_ignore_unused` | 厂商电源树没完整描述，防止 unused 关断导致外设掉电 |
| `loglevel=4` | 原来是 `ignore_loglevel`，所有 INFO 都上屏把登录提示冲掉；4 仍保留 KERN_ERR 可见 |
| `panic=0` | panic 后挂住不重启，方便拍屏/取 pstore |
| `printk.devkmsg=on` | 允许 userspace 写 `/dev/kmsg`（取证通道要用） |
| `log_buf_len=4194304` | 4 MB ring buffer，够存一整次启动 |
| `ramoops.*` | pstore 后端，见 `6 节 |
| `chopinport=...` | 厂商驱动用的标识串 |

**不要加** `earlycon=mtk8250` / `console=ttyS0`：那个 UART 被 LK 关掉了
（`mtk_printk_ctrl.disable_uart=1`），往里写会直接卡死。要早期输出就用 `tty0` + pstore 回读。

---

## 4. 已验证的子系统（实机）

| 子系统 | 状态 | 备注 |
| --- | --- | --- |
| 内核启动 | ✅ | 进用户态，systemd 能到 multi-user（当时用的最小 rootfs） |
| DRM / 显示 | ✅ | `card0-DSI-1` connected，1080×2400；用的是 vendor `mediatek_v2` 栈（补丁 0012，~19 万行） |
| fbcon | ✅ | `mediatekdrmfb`，控制台正常 |
| 触摸 | ✅ | Novatek `NVTCapacitiveTouchScreen`，SPI，event2 |
| 按键 | ✅ | `mtk-pmic-keys` / `mtk-kpd` |
| 存储 | ✅ | UFS，userdata = `/dev/sdc75`（107 GB） |
| USB UDC | ⚠️ | mtu3 注册出 `11201000.usb`，但 gadget 绑定有问题，见 5.2 |
| PMIC / 充电 | ⚠️ | MT6360 部分子设备注册失败，见 5.1 |
| WLAN / BT | ⚠️ | 固件与 NVRAM 缺失，见 5.3 |
| 音频 / 相机 / 视频编解码 | ❌ | vendor 驱动在树里，但未验证 |

---

## 5. 已知问题（内核侧）

### 5.1 i2c5 上的 MT6360 子设备注册失败

- 现象：`subpmic_pmic@1a`、`subpmic_ldo@64`、`tcpc` 注册失败；dmesg 有
  `platform ... DMA mask not set` 一类信息。
- 线索：MT6360 挂在 **i2c5**（`&i2c5 { subpmic@34 { compatible = "mediatek,mt6360"; ... } }`），
  主 PMIC 本身能起来，但 i2c 走 PDMA 路径时描述符/节点与主线不匹配。
- 影响：charger 的 `otg_vbus` regulator 可能注册不出来 → 直接决定 USB 控制器能不能 probe
  （见 5.2）。这是当前最值得先修的一个点。
- 方向：对照 vendor 的 i2c PDMA 实现，检查 `dma-mask` / `mediatek,i2c-dma` 是否需要；或先用
  轮询模式（去掉 DMA）验证。

### 5.2 USB device controller（mtu3）

这是本轮查得最深、也最容易踩的地方，三个独立问题叠在一起：

**(a) 内建的 `g_multi` 根本 probe 不上（-EINVAL）**

    g_multi gadget.0: probe with driver g_multi failed with error -22
    UDC core: g_multi: couldn't find an available UDC
    udc 11201000.usb: state=not attached cur=UNKNOWN max=high-speed

`multi_bind()` 在 composite bind 路径里返回 `-EINVAL`（不是 `can_support_ecm()` 那条分支——
mtu3 没有设 `quirk_altset_not_supp`）。结果：没有任何 gadget 驱动绑到 UDC，pull-up 不拉，
**整机在 USB 上完全消失**（串口、RNDIS、adb 一起没）。

历史教训：早期"能用"的串口其实是 **`g_serial`**（Windows 设备 `USB\VID_0525&PID_A4A7`），
配置改成 `CONFIG_USB_G_MULTI=y` 之后就断了。

**(b) `dr_mode = "peripheral"` 时 mtu3 不切端口模式**

只有 otg 路径才会执行：

    ssusb_set_mode(DEVICE) → ssusb_set_force_mode(FORCE_DEVICE)
                          → switch_port_to_device()   // SSUSB_U2_PORT_HOST_SEL=0
                          → mtu3_start()

peripheral 模式直接 `ssusb_gadget_init()`，**不碰 IPPC 的端口选择**。实测：gadget 对象、
`/dev/ttyGS0` 都有，UDC 却永远 `not attached`（gadget 绑上了但 host 看不到）。

**(c) otg 模式又依赖 MT6360 的 `otg_vbus`**

`get_ssusb_rscs()` 在非 peripheral 模式下要求 `vbus` supply（`otg_vbus`，由 `mt6360-chg` 注册）。
i2c5 不稳（5.1）→ charger 没 probe → mtu3 无限 `-EPROBE_DEFER` → UDC 不注册 → 同样全无 USB。

**当前取舍**（`mt6893.dtsi` 里 `/usb@11201000`）：

    dr_mode = "otg";
    usb-role-switch;
    role-switch-default-mode = "peripheral";
    maximum-speed = "high-speed";
    vusb33-supply = <&vusb33>;      // regulator-fixed，永远在
    /* 故意不写 vbus-supply */

- otg → 走端口切换；(b) 解决
- 去掉 `vbus-supply` → regulator 核心给 dummy，`ssusb_set_vbus()` 变成 no-op；(c) 解决

**还没验证**：这套组合下 configfs ACM gadget 能不能真的枚举出来（最后一次刷机被我中途打断）。
验证方法（设备上，root）：

```sh
mount -t configfs configfs /sys/kernel/config
G=/sys/kernel/config/usb_gadget/g1
mkdir -p $G && echo 0x1d6b > $G/idVendor && echo 0x0104 > $G/idProduct
mkdir -p $G/strings/0x409 && echo chopin > $G/strings/0x409/serialnumber
echo Xiaomi > $G/strings/0x409/manufacturer && echo chopin > $G/strings/0x409/product
mkdir -p $G/configs/c.1/strings/0x409 && echo acm > $G/configs/c.1/strings/0x409/configuration
mkdir -p $G/functions/acm.usb0 && ln -s $G/functions/acm.usb0 $G/configs/c.1/
echo $(ls /sys/class/udc | head -1) > $G/UDC     # 失败时看 dmesg / 返回值
cat /sys/class/udc/*/state                        # 期望 configured
```

注意：**ACM 和 RNDIS 同时放进一个 config 会让 bind 失败**（实测）。要网络就单独试
`rndis.usb0`，不要和 ACM 混在一个 configuration 里排错。

**(d) UDC 状态语义**：`not attached` = 没有 gadget pull-up，或 host 侧没建立连接；
`configured` = 枚举完成。查 `/sys/class/udc/*/state` 比看 dmesg 快。

### 5.3 WLAN / conninfra

- `mediatek/mt6893/WIFI` 这个 NVRAM blob 在 **nvdata 分区**上，内核启动时取不到。
- `wlan_drv_gen4m` 早期会每 250 ms 重试、每次一条 KERN_ERR（把控制台冲掉）。本次已改：
  `firmware_request_nowarn()`、重试 60×500 ms、逐次打印降为 `pr_debug`。
- `wlanPreCalPwrOn()` 等 NVRAM 120 s → 触发 conninfra 消息线程 15 s 超时并打 backtrace。
  本次把 `MAX_NVRAM_READY_COUNT` 从 1200 改成 50（5 s）。
- **如果以后要让 WiFi 真正工作**，这两处要反过来：把 blob 放到 `/lib/firmware/mediatek/mt6893/WIFI`，
  并把 pre-cal 的等待恢复成长时间（RF 校准依赖它；不带 NVRAM 时扫描能跑但收不到东西）。

### 5.4 Novatek 触摸固件

启动约 21 s 时驱动会尝试从 `/lib/firmware` 加载新固件，缺失时打约 13 行
`[NVT-ts-spi] ... firmware load failed, ret=-2`（`drivers/input/touchscreen/NVT36672c/nt36xxx_fw_update.c`）。
**触摸本身是可用的**（控制器自带固件），这是纯噪声；要么提供 blob，要么把该路径的
`NVT_ERR` 降级。

### 5.5 显示栈

补丁 0012 带进来的是 **vendor 的 `mediatek_v2` 整套显示栈**（287 个文件、约 19 万行），
主线 DRM 的 `mtk_drm_drv.c` 只用来提供 fbdev emulation（`mediatekdrmfb`）。
目前是 dumb-buffer + fbcon 级别，**没有 GBM/EGL/GL 栈**，也没有原子 modeset 之外的保障；
任何需要 GPU 的用户空间（Wayland 合成器、GNOME/KDE）都要另做打算。

### 5.6 watchdog

`chopin-reset.dtsi` 里有说明：基线树里 `toprgu@10007000` 的 compatible 是
"mediatek,toprgu"，主线没有匹配的驱动 → LK 启动的 watchdog 没人接手，板子会自己复位。
现在覆盖成 `mediatek,mt6589-wdt` + `mediatek,toprgu`（最老的无数据绑定最安全），
配合 `CONFIG_WATCHDOG_HANDLE_BOOT_ENABLED` 由 watchdog core 自动喂狗。
`mediatek,disable-extrst` 故意不设 —— 喂狗才是该做的事，不要改复位语义。

---

## 6. 诊断与取证（内核侧）

**pstore / ramoops**：cmdline 已经把 `0x48090000` 起的 0x8f000 划给 ramoops，
`console_size=0x40000`（256 KB 控制台环）、`record_size=0x1000`（panic/oops 记录）、无 pmsg。
`panic=0` + ramoops 的组合让"抖动/死机现场"能跨重启保留。

读取：

```sh
mount -t pstore pstore /sys/fs/pstore
cat /sys/fs/pstore/console-ramoops     # 上一次启动的完整内核日志（截断到 256 KB）
ls  /sys/fs/pstore                      # panic/oops/console 各类记录
```

注意：
- userspace 里 `systemd-pstore.service` 会把 ramoops 搬走并**删除**，要留证据就先 mask 它。
- 控制台日志只记录"能上控制台"的等级：`loglevel=4` 时 INFO 不会进 ramoops。
  临时要全量日志就改回 `ignore_loglevel` 或 `loglevel=8`。
- 本目录里的 `out/console-ramoops.txt` / `out/console-ramoops2.txt` 是两次 SError panic 的现场，
  可以直接对照 `swiotlb=0` 修复前后的栈。

**把 ramoops 倒到串口/屏幕**：本工作区曾用一个专用 initramfs 做这件事（没有 USB 时的唯一通道）。
方法本身很简单：一个 busybox initramfs，挂 `pstore`，把 `/sys/fs/pstore/*` 打到 `/dev/ttyGS0`
（USB gadget ACM）或 `/dev/tty0`。相关脚本已随用户空间部分一起移除，需要时十行就能重写。

---

## 7. 打包与刷写

**boot.img**：`scripts/mkbootimg.py` 以原厂 `boot_a.img` 为模板，只替换 kernel（可选 ramdisk/dtb）。

- header v2，page size 2048
- kernel_addr `0x40080000`，ramdisk_addr `0x51100000`，tags_addr `0x47c80000`
- **dtb_size 在偏移 1648（u32），dtb_addr 在 1652（u64）** —— 早期写错这两个偏移导致 `dtb_addr` 变成垃圾
- `--dtb` 传入裸 FDT 时，若模板的 dtb 段是 DTBO 表（`0xd7b7ab1e`），脚本会自动封成同样的表结构

```bash
python3 scripts/mkbootimg.py \
  --stock /mnt/d/MT6891-Mainline/chopin/images/boot_a.img \
  --kernel linux/arch/arm64/boot/Image.gz \
  -o out/boot-chopin-mainline.img
```

**不要给这条命令加 `--dtb`**，除非你确实要让 LK 阶段也用新 DT：运行时 DT 来自内核内嵌的
`chopin-board.dtb`（第 2 节），而 boot.img 的 dtb 段只影响 LK。当前 `out/boot-chopin-mainline.img`
故意保留**原厂 dtb 段**，和实机验证过的组合一致；`out/mt6893-xiaomi-chopin.dtb` 只是构建产物，
拿去实验时用 `--dtb` 显式指定。

**fastboot 注意**：

- `D:\Program Files (x86)\platform-tools\fastboot.exe` 是 **32 位**程序（PE machine `0x014C`），
  >2 GB 的镜像必然 `std::bad_alloc` —— 这是 32 位地址空间的限制，不是镜像格式问题。
- 设备是 A/B：`fastboot flash boot` 写的是当前 slot（观察输出里的 `Sending 'boot_a'`）。
  刷写被中断后 LK 可能把该 slot 标成不可引导并切到 `_b`，此时要 `fastboot --set-active=a`。
- 想只换内核：用原厂 ramdisk 打包即可；要进用户空间还需要一个自己的 initramfs/rootfs。

**恢复原厂**：

```
fastboot flash boot D:\MT6891-Mainline\chopin\images\boot_a.img
fastboot flash dtbo D:\MT6891-Mainline\chopin\images\dtbo_a.img
```

---

## 8. 补丁系列（18 个）

| # | 补丁 | 文件 | 改动 |
| --- | --- | --- | --- |
| 0001 | dt-bindings: add MT6893 support | 3 | +125 |
| 0002 | clk: mediatek: add MT6893 clock controllers | 15 | +2364 |
| 0003 | soc: mediatek: MT6893 power, chipid, SMI | 10 | +2183 |
| 0004 | interconnect: mediatek: MT6893 | 7 | +1100 |
| 0005 | pinctrl: mediatek: MT6893 | 2 | +60 |
| 0006 | regulator: chopin PMIC regulators | 3 | +334 |
| 0007 | power: supply: chopin charger and gauge | 4 | +231 |
| 0008 | input: chopin touchscreen drivers | 17 | +9228 |
| 0009 | usb: chopin USB and PD support | 5 | +120 |
| 0010 | ASoC: mediatek: MT6893 audio | 8 | +492 |
| 0011 | net: chopin WLAN/BT hooks | 2 | +22 |
| 0012 | drm: mediatek: chopin display stack | 287 | +193027 |
| 0013 | arm64: mediatek: chopin board and DTS | 24 | +13238 |
| 0014 | misc: mediatek: chopin platform drivers | 922 | +794578 |
| 0015 | include: chopin driver interfaces | 21 | +5870 |
| 0016 | chopin: remaining platform bits | 12 | +2963 |
| 0017 | arm64: chopin: novatek touch firmware from /lib/firmware | 1 | ±2 |
| 0018 | drm/fbdev-dma: clear scanout buffer | 1 | +11 |

合计 1343 个文件、+1,025,944 / −1,444 行。0012 / 0014 是厂商显示栈与平台驱动，占绝大部分。
补丁原始 mbox 可以用 README 里的 URL 重新拉取（`patches/series.mbox` 未入库）。

---

## 9. 设备备份

`D:\MT6891-Mainline\chopin\images\` 是原厂分区 dump（boot_a/b、dtbo_a/b、lk、preloader、
vbmeta、userdata 以外的各分区……）。原厂 boot 是 Magisk 版（`magisk_patched-31100_BSRqI.img` 同源）。
恢复命令见第 7 节；userdata 没备份（当时已被 Debian 覆盖），要回 Android 只能让 Android 首次启动重建。

---

## 10. 待办（内核侧）

1. **USB**：确认 otg+no-vbus+configfs-ACM 能否枚举；不行就查 `mtu3_gadget_pullup` /
   `mtu3_start` 的实际寄存器状态（`/sys/kernel/debug/usb/mtu3` 需要 `CONFIG_USB_MTU3_DEBUG`）。
2. **g_multi 的 -EINVAL** 值得单独修（`drivers/usb/gadget/legacy/multi.c` 的 bind 路径），
   修好可以一次拿回 ACM+RNDIS+存储，不依赖 configfs。
3. **i2c5 / MT6360**：修好 PDMA 路径，顺带解决 `otg_vbus` 与 charger 的依赖。
4. **显示栈**：确认 vendor DRM 是否支持原子 modeset / dumb buffer 之外的能力，
   决定要不要换主线 `mtk-drm`。
5. **未验证硬件**：音频、相机、视频编解码、WiFi/BT 数据通路。

### 5.7 USB gadget 不枚举的真正根因（2026-11-15 确认）

`chopin-gadget.sh` 的"幂等"判断用了：

    if [ -s "$G/UDC" ]; then ... fi
    if [ -n "$UDC" ] && [ ! -s "$G/UDC" ]; then ... bind ... fi

**sysfs/configfs 属性文件的 stat 大小恒为 4096**，`test -s` 恒为真，于是脚本把
未绑定的 gadget 误判为已绑定：既跳过 bind，又立即 break 出 UDC 等待循环。
现象就是"gadget 对象、ttyGS0 都在，UDC 却永远 not attached，主机完全看不到设备"。

修复为读取属性内容：

    is_bound() { [ -n "$(cat "$G/UDC" 2>/dev/null)" ]; }

修复后 initramfs 绑定成功，systemd 的 `chopin-gadget.service` 正确 skip，
USB ACM 串口（COM11）与 Debian serial getty 正常工作。

### 5.8 触摸与 GPU 的当前内核状态（2026-11-15）

**触摸（NVT36672c / SPI）**
- probe 正常：chip id 读取成功、input 设备注册、IRQ 33 注册；
- 但触摸时 `/proc/interrupts` IRQ 33 计数为 0，evdev/libinput 无事件；
- `/sys/kernel/debug/gpio` 显示 `gpio-19 (NVT-int) in lo IRQ ACTIVE LOW`；
- DT：`novatek,irq-gpio = <&pio 0x13 0x2001>`。
- 方向：触发类型（edge/level、极性）、EINT19 pinctrl 复用、固件
  `novatek_nt36672c_k10a_fw01.bin`（原厂 /vendor/firmware 或 nvdata 提取）。

**GPU（panfrost / Mali-G77）**
- 首次 probe 时 mtcmos 电源域返回 -517（audio-controller 尚未 probe）；模块重载
  后 -517 消失，但仍 `gpu soft/hard reset timed out`、`using only 1st core group`
  `bus_clock rate = 0`、`chopin: no core_clk_rate knob` → probe -110。
- 结论：电源域已就绪，阻塞在 GPU 时钟/复位（bus clock 未开或 clock id 不匹配）。
- 方向：对齐 mt6893 clk 驱动的 mfg/bus clock、确认复位前 mfg 电源域已上电；
  修好后重建全量 libgallium（panfrost+swrast）。
