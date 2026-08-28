#!/bin/bash
# Build the managed WineHua DXVK Legacy fork for both PE architectures.
# This runs inside the canonical Docker build container; the Meson build
# directories are intentionally kept beside the fork so later DXVK changes
# can be rebuilt incrementally without touching the Wine tree.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"
source "$SCRIPT_DIR/build_cache.sh"

[ -d "$DXVK_SRC" ] || err "DXVK fork missing: $DXVK_SRC"

CACHE_COMPONENT="dxvk-legacy"
CACHE_MANIFEST="$BUILD_DIR/.cache-manifests/$CACHE_COMPONENT.manifest"
CACHE_ARTIFACTS=(
    "$DXVK_BUILD_ROOT/x64/bin/d3d9.dll"
    "$DXVK_BUILD_ROOT/x64/bin/d3d10core.dll"
    "$DXVK_BUILD_ROOT/x64/bin/d3d10.dll"
    "$DXVK_BUILD_ROOT/x64/bin/d3d10_1.dll"
    "$DXVK_BUILD_ROOT/x64/bin/d3d11.dll"
    "$DXVK_BUILD_ROOT/x64/bin/dxgi.dll"
    "$DXVK_BUILD_ROOT/x86/bin/d3d9.dll"
    "$DXVK_BUILD_ROOT/x86/bin/d3d10core.dll"
    "$DXVK_BUILD_ROOT/x86/bin/d3d10.dll"
    "$DXVK_BUILD_ROOT/x86/bin/d3d10_1.dll"
    "$DXVK_BUILD_ROOT/x86/bin/d3d11.dll"
    "$DXVK_BUILD_ROOT/x86/bin/dxgi.dll"
)
CACHE_FILES_DIGEST="$(winehua_cache_files_digest \
    "$SCRIPT_DIR/build_dxvk.sh" "$SCRIPT_DIR/build_cache.sh" "$SCRIPT_DIR/env.sh")"
CACHE_INPUT_KEY="$(winehua_cache_input_key \
    "$CACHE_COMPONENT" "$DXVK_SRC" "$CACHE_FILES_DIGEST" \
    'buildtype=release' 'architectures=x86_64,i686' 'managed-runtime=legacy')"

if winehua_cache_verify "$CACHE_MANIFEST" "$CACHE_COMPONENT" "$CACHE_INPUT_KEY" \
    "${CACHE_ARTIFACTS[@]}"; then
    log "DXVK Legacy content cache hit: ${CACHE_INPUT_KEY:0:12}"
    exit 0
fi
log "DXVK Legacy content cache miss: $WINEHUA_CACHE_MISS_REASON"

# 读取 meson 缓存里配置的源码绝对路径 (可能为空)
configured_source_of() {
    local build_dir="$1"
    [ -f "$build_dir/meson-info/meson-info.json" ] || { printf ''; return; }
    python3 - "$build_dir/meson-info/meson-info.json" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print(d["directories"]["source"])
except Exception:
    print("")
PY
}

setup_if_missing() {
    local build_dir="$1"
    local cross_file="$2"
    local prefix="$3"
    # 仓库被移动/换挂载路径时 (例如另一台机器 clone 到别处, 或经 symlink 挂载),
    # 旧 build 目录会把旧绝对路径缓存在 meson-info.json, 直接 ninja 会报 "Neither
    # source directory '<旧路径>' ... contain a build file meson.build"。检测到路径
    # 不一致就重建, 让构建与源码所在路径无关。
    # 注意 meson 缓存的是 realpath 归一化后的物理路径, 而 $DXVK_SRC 可能是逻辑
    # 路径 (含 symlink 组件), 比较前先 realpath 归一到同基准, 避免 symlink
    # 环境下每次误判重建 (全量重编)。
    if [ -f "$build_dir/build.ninja" ]; then
        local configured_src
        configured_src="$(configured_source_of "$build_dir")"
        if [ -n "$configured_src" ] && [ "$configured_src" != "$(realpath "$DXVK_SRC")" ]; then
            log "DXVK $(basename "$build_dir") 源码路径变化: $configured_src -> $DXVK_SRC, 重建 build 目录"
            rm -rf "$build_dir"
        fi
    fi
    if [ ! -f "$build_dir/build.ninja" ]; then
        log "Configuring DXVK $(basename "$build_dir")"
        meson setup "$build_dir" "$DXVK_SRC" \
            --cross-file "$DXVK_SRC/$cross_file" \
            --prefix "$prefix" -Dbuildtype=release
    fi
}

setup_if_missing "$DXVK_SRC/build.winehua64" build-win64.txt "$DXVK_BUILD_ROOT/x64"
setup_if_missing "$DXVK_SRC/build.winehua32" build-win32.txt "$DXVK_BUILD_ROOT/x86"

log "--- DXVK Legacy fork ($DXVK_SRC) ---"
ninja -C "$DXVK_SRC/build.winehua64" install
ninja -C "$DXVK_SRC/build.winehua32" install

for dll in d3d11.dll dxgi.dll; do
    [ -f "$DXVK_BUILD_ROOT/x64/bin/$dll" ] || \
        err "DXVK x64 artifact missing: $DXVK_BUILD_ROOT/x64/bin/$dll"
    [ -f "$DXVK_BUILD_ROOT/x86/bin/$dll" ] || \
        err "DXVK x86 artifact missing: $DXVK_BUILD_ROOT/x86/bin/$dll"
done

winehua_cache_write "$CACHE_MANIFEST" "$CACHE_COMPONENT" "$CACHE_INPUT_KEY" \
    "${CACHE_ARTIFACTS[@]}" || err "failed to record DXVK Legacy content cache"

log "DXVK Legacy ready: $(git -c safe.directory="$DXVK_SRC" -C "$DXVK_SRC" rev-parse --short HEAD)"
