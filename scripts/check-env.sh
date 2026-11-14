#!/usr/bin/env bash
# 检查构建依赖；缺失 core 工具时返回非 0。
set -uo pipefail

TOP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
missing_core=0
missing_opt=0

say() { printf '%-28s %s\n' "$1" "$2"; }

check_core() {
    local c="$1"
    if command -v "$c" >/dev/null 2>&1; then
        say "[ok] $c" "$(command -v "$c")"
    else
        say "[MISSING] $c" "必需"
        missing_core=$((missing_core + 1))
    fi
}

check_opt() {
    local c="$1"
    if command -v "$c" >/dev/null 2>&1; then
        say "[ok] $c" "$(command -v "$c")"
    else
        say "[optional] $c" "缺失（只影响部分步骤）"
        missing_opt=$((missing_opt + 1))
    fi
}

echo "== 主机 =="
say "kernel" "$(uname -sr)"
say "distro" "$(grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release 2>/dev/null | tr '\n' ' ')"
if grep -qi microsoft /proc/version 2>/dev/null; then say "环境" "WSL"; else say "环境" "原生 Linux"; fi
say "CPU" "$(nproc) 核"
say "内存" "$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}')"
say "磁盘 /" "$(df -h / | awk 'NR==2 {print $4 " 可用"}')"
echo

echo "== 内核构建 =="
for c in git make gcc flex bison bc python3 dtc cpio gzip xz zstd depmod rsync curl sha256sum; do
    check_core "$c"
done
if command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
    say "[ok] aarch64-linux-gnu-gcc" "$(aarch64-linux-gnu-gcc --version | head -1)"
else
    say "[MISSING] aarch64-linux-gnu-gcc" "apt install gcc-aarch64-linux-gnu"
    missing_core=$((missing_core + 1))
fi
echo

echo "== Debian 用户空间（可选） =="
for c in mmdebstrap debootstrap mkfs.ext4 e2fsck resize2fs meson ninja; do
    check_opt "$c"
done
if command -v qemu-aarch64-static >/dev/null 2>&1; then
    say "[ok] qemu-aarch64-static" "$(command -v qemu-aarch64-static)"
elif command -v qemu-aarch64 >/dev/null 2>&1; then
    say "[ok] qemu-aarch64" "$(command -v qemu-aarch64)"
else
    say "[optional] qemu-aarch64" "arm64 chroot 需要 qemu-user-static"
    missing_opt=$((missing_opt + 1))
fi
if [ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
    say "[ok] binfmt qemu-aarch64" "已注册"
else
    say "[optional] binfmt qemu-aarch64" "未注册（update-binfmts --enable qemu-aarch64）"
    missing_opt=$((missing_opt + 1))
fi
echo

if [ "$missing_core" -ne 0 ]; then
    echo "缺少 $missing_core 个必需工具。Ubuntu 24.04 可执行："
    echo "  sudo apt-get install -y build-essential gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu \"
    echo "    flex bison bc libssl-dev libelf-dev libncurses-dev cpio kmod rsync \"
    echo "    device-tree-compiler python3 xz-utils zstd dwarves ccache lz4 curl"
    exit 1
fi
echo "内核构建依赖齐全。"
[ "$missing_opt" -eq 0 ] || echo "有 $missing_opt 个可选依赖缺失；只影响 Debian 构建。"
