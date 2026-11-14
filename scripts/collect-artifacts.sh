#!/usr/bin/env bash
# 把内核/Debian 产物汇总到顶层 out/，并生成 SHA256SUMS。
set -euo pipefail

TOP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$TOP/out"
mkdir -p "$OUT"

copy() {
    local src="$1"
    if [ -f "$src" ]; then
        install -m644 "$src" "$OUT/"
        echo "  + $(basename "$src")"
    else
        echo "  ! 缺少 $src"
    fi
}

echo "== 汇总产物 =="
copy "$TOP/kernel/out/Image.gz"
copy "$TOP/kernel/out/Image"
copy "$TOP/kernel/out/mt6893-xiaomi-chopin.dtb"
copy "$TOP/debian/out/initramfs.cpio.gz"
copy "$TOP/debian/out/boot-chopin-debian.img"
copy "$TOP/debian/out/chopin-rootfs.img"
copy "$TOP/debian/out/chopin-rootfs.sparse.img"

if find "$OUT" -maxdepth 1 -type f ! -name SHA256SUMS | grep -q .; then
    rm -f "$OUT/SHA256SUMS"
    ( cd "$OUT" && sha256sum ./* > SHA256SUMS )
    echo "== SHA256SUMS =="
    cat "$OUT/SHA256SUMS"
else
    echo "没有可汇总的产物。先构建内核 / Debian。"
fi
