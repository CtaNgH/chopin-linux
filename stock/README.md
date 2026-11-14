# stock/ —— 原厂镜像（不随仓库分发）

把**你自己设备**的原厂分区备份放到这里，供 `07-mkbootimg.sh` 作为模板：

```
stock/
├── boot_a.img       # 必需：boot.img header v2 模板（kernel/ramdisk 地址、cmdline）
├── dtbo_a.img       # 可选：恢复原厂 dtbo
├── boot_b.img       # 可选：A/B 另一个 slot
└── dtbo_b.img
```

这些文件包含设备专有数据/厂商版权，已被 `.gitignore` 排除，不要提交。

备份方法（设备已 root 或有可用 dump 时）：

```bash
# 在设备上（示例，按实际分区名调整）
dd if=/dev/block/by-name/boot_a of=/sdcard/boot_a.img
dd if=/dev/block/by-name/dtbo_a of=/sdcard/dtbo_a.img
```

或从原厂 fastboot 包/已有 dump 中提取。恢复：

```powershell
fastboot flash boot stock\boot_a.img
fastboot flash dtbo stock\dtbo_a.img
fastboot reboot
```

没有 `boot_a.img` 时，仍可构建 rootfs 和 initramfs，只是 `make bootimg` 会失败并提示。
