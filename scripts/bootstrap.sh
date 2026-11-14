#!/usr/bin/env bash
# 初始化 submodule 并重建内核源码。可重复执行。
set -euo pipefail

TOP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
log() { printf '==> %s\n' "$*"; }

if [ ! -d "$TOP/kernel/.git" ] || [ ! -d "$TOP/debian/.git" ]; then
    log "submodule 未初始化，执行 git submodule update --init --recursive"
    git -C "$TOP" submodule update --init --recursive
fi

if [ -x "$TOP/scripts/check-env.sh" ]; then
    "$TOP/scripts/check-env.sh" || log "依赖检查有缺失；内核 bootstrap 仍会继续"
fi

log "重建内核工作树"
"$TOP/kernel/scripts/bootstrap.sh"

log "完成。下一步：make kernel / sudo make debian"
