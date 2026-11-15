# Windows 侧辅助脚本

这些是开发机上用到的 PowerShell / Python 工具，**不是构建流程的一部分**。默认把仓库放在
`D:\chopin-linux`，产物同步到 `D:\chopin-linux\out\`；路径不同就改参数或改默认值。

| 脚本 | 用途 |
| --- | --- |
| `flash-debian.ps1` | 刷 boot + userdata（sparse），会覆盖 Android 数据 |
| `boot-cycle.ps1` | 刷 boot → 重启 → 自动抓串口 |
| `flash-when-ready.ps1` | 等 fastboot 出现 → 刷 boot → 抓串口 |
| `capture-serial.ps1` | 打开第一个 COM 口，115200 8N1，DTR/RTS，抓日志 |
| `serial-cmd.ps1` | 向指定 COM 口发命令（CR 结尾），读回显 |
| `serial-run.ps1` | 串口控制台：自动登录 root、执行单行或多行命令、带 marker 校验回显 |
| `serial-xfer.ps1` | Windows → 设备传文件（base64 over USB ACM，实测 ~20 MB/s） |
| `serial-pull.ps1` | 设备 → Windows 取文件（同一通道，反向；带重试和大小校验） |
| `chopin-shot.py` | 设备上没有 xwd 时抓 X root 截图（ctypes + XGetImage → PNG，可降采样） |
| `xtap.py` | 在 Xwayland 上画一个已知位置的方块并打印点击坐标——触摸坐标校验用 |

典型用法：

```powershell
# 串口跑一条命令
.\serial-run.ps1 -Cmd "uname -r; ls /dev/dri"

# 批量命令（多行，支持 heredoc）
.\serial-run.ps1 -CmdFile .\cmds.txt -TimeoutSec 120

# 推 / 拉文件
.\serial-xfer.ps1 -File .\out\Image.gz -Remote /root/Image.gz
.\serial-pull.ps1 -Remote /tmp/shot.png -Out .\out\shot.png

# 触摸校准：设备上先跑 evtest 记录，再在 Xwayland 里画方块
#   python3 /tmp/xtap.py &   （窗口会出现在右上象限）
#   evtest /dev/input/event2 > /tmp/tap.log &
```

依赖：

- Windows platform-tools（默认 `D:\Program Files (x86)\platform-tools`，32 位 fastboot 不能刷 >2 GB raw 镜像）；
- USB ACM 串口驱动；设备侧 `/dev/ttyGS0` 有 getty 时才能登录；
- `chopin-shot.py` / `xtap.py` 在设备上跑，只要 python3 和 libX11（X11 或 Xwayland 均可）。

> 这些脚本含开发机专属路径，仓库只作为示例保留；跨机器使用前先改 `$pt` 和 `D:\chopin-linux`。
