#!/usr/bin/env bash
# 校验仓库完整性：submodule、补丁数、SHA256SUMS、脚本语法、内核 tree。
set -euo pipefail

TOP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
ok()  { printf '[ok]   %s\n' "$*"; }
bad() { printf '[FAIL] %s\n' "$*"; fail=$((fail + 1)); }

echo "== 仓库 =="
for d in kernel debian; do
    if [ -e "$TOP/$d/.git" ]; then ok "$d/ 存在"; else bad "$d/ 缺失（git submodule update --init --recursive）"; fi
done
if [ -f "$TOP/kernel/base.env" ]; then ok "kernel/base.env"; else bad "kernel/base.env 缺失"; fi
# shellcheck source=../kernel/base.env
. "$TOP/kernel/base.env"

echo
echo "== 补丁 =="
n="$(find "$TOP/kernel/patches" -maxdepth 1 -type f -name '*.patch' | wc -l)"
if [ "$n" -eq "$PATCH_COUNT" ]; then ok "补丁数量 $n/$PATCH_COUNT"; else bad "补丁数量 $n != $PATCH_COUNT"; fi
if [ -f "$TOP/kernel/SHA256SUMS" ]; then
    if ( cd "$TOP/kernel" && sha256sum -c --quiet SHA256SUMS ); then ok "kernel/SHA256SUMS"; else bad "kernel/SHA256SUMS 不匹配"; fi
else
    bad "kernel/SHA256SUMS 缺失（make -C kernel sha256）"
fi

echo
echo "== Shell 语法 =="
while IFS= read -r -d '' f; do
    bash -n "$f" 2>/dev/null || bad "bash -n $f"
done < <(find "$TOP/kernel/scripts" "$TOP/debian/scripts" "$TOP/scripts" -type f -name '*.sh' -print0)
ok "已检查所有 .sh"

echo
echo "== Python 语法 =="
py_files="$(find "$TOP/kernel/scripts" "$TOP/debian/scripts" -type f -name '*.py')"
if [ -n "$py_files" ]; then
    if python3 -c 'import ast,sys; [ast.parse(open(f, encoding="utf-8").read(), f) for f in sys.argv[1:]]' $py_files; then
        ok "已检查 $(echo "$py_files" | wc -l) 个 .py"
    else
        bad "Python 语法错误"
    fi
fi

echo
echo "== 内核工作树 =="
if [ -d "$TOP/kernel/linux/.git" ]; then
    tree="$(git -C "$TOP/kernel/linux" rev-parse 'HEAD^{tree}' 2>/dev/null || true)"
    if [ "$tree" = "$CHOPIN_TREE" ]; then
        ok "tree = $tree"
    else
        bad "tree = ${tree:-<none>}，期望 $CHOPIN_TREE"
    fi
    if cmp -s "$TOP/kernel/configs/chopin_defconfig" "$TOP/kernel/linux/arch/arm64/configs/chopin_defconfig"; then
        ok "chopin_defconfig 一致"
    else
        bad "chopin_defconfig 与工作树不一致"
    fi
else
    echo "[skip] kernel/linux 尚未 bootstrap"
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "全部检查通过。"
else
    echo "有 $fail 项失败。"
    exit 1
fi
