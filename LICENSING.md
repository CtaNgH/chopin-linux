# 许可说明

本工作区按组件分别授权：

| 组件 | 许可 | 说明 |
| --- | --- | --- |
| `kernel/` | **GPL-2.0-only** | Linux 内核衍生作品；完整文本见 `kernel/LICENSE` |
| `debian/` 脚本、overlay、initramfs | **MIT** | 见 `debian/LICENSE` |
| 顶层 README、docs、scripts | **MIT** | 见 `LICENSE` |
| Debian 软件包 | 各自许可 | 通过 apt 安装，不随本仓库分发 |
| Mesa 源码 / G77 补丁 | MIT（Mesa） | 从 Debian 官方 tarball 获取，不随仓库分发 |
| 原厂 boot/dtbo、WiFi/BT NVRAM、触摸固件 | 厂商许可 | **不随仓库分发**，需自行从设备备份提取 |

## 厂商代码

内核补丁 0012（vendor display stack）和 0014（vendor platform drivers）包含大量
MediaTek/Xiaomi 代码。它们来自参考项目 `MT6891-Mainline/linux` 的公开发布，按 GPL-2.0
随内核分发；但其中可能夹杂第三方许可文件或没有明确 SPDX 头的代码。再分发或上游化前，
请逐文件确认许可，并补齐缺失的授权声明。

## 上游化建议

如果要提交到 Linux 上游：

1. 把 20 个补丁拆成可独立评审的小系列；
2. 为每个新 binding 补 `Documentation/devicetree/bindings/`；
3. 清理厂商代码的 `-Wmissing-prototypes` 等告警和 section mismatch；
4. 用 `git format-patch` + `git send-email`，不要直接提交 vendor dump。

本项目不是 Linux 内核官方项目，与 MediaTek、Xiaomi、Debian 无隶属关系。
