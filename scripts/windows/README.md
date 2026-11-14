# Windows 侧辅助脚本

这些是开发机上用到的 PowerShell 工具，**不是构建流程的一部分**。默认把仓库放在
`D:\chopin-linux`，产物同步到 `D:\chopin-linux\out\`；路径不同就改参数或改默认值。

| 脚本 | 用途 |
| --- | --- |
| `flash-debian.ps1` | 刷 boot + userdata（sparse），会覆盖 Android 数据 |
| `boot-cycle.ps1` | 刷 boot → 重启 → 自动抓串口 |
| `flash-when-ready.ps1` | 等 fastboot 出现 → 刷 boot → 抓串口 |
| `capture-serial.ps1` | 打开第一个 COM 口，115200 8N1，DTR/RTS，抓日志 |
| `serial-cmd.ps1` | 向指定 COM 口发命令（CR 结尾），读回显 |

依赖：

- Windows platform-tools（默认 `D:\Program Files (x86)\platform-tools`，32 位 fastboot 不能刷 >2 GB raw 镜像）；
- USB ACM 串口驱动；设备侧 `/dev/ttyGS0` 有 getty 时才能登录。

> 这些脚本含开发机专属路径，仓库只作为示例保留；跨机器使用前先改 `$pt` 和 `D:\chopin-linux`。
