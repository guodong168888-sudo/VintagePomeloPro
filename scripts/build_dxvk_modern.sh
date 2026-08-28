#!/bin/bash
# Build the WineHua DXVK 2.6.2 compatibility profile for the isolated Modern runtime.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"
source "$SCRIPT_DIR/build_cache.sh"

[ -f "$DXVK_MODERN_SRC/meson.build" ] || err "DXVK Modern source missing: $DXVK_MODERN_SRC"
[ -f "$DXVK_MODERN_SRC/include/vulkan/include/vulkan/vulkan.h" ] || \
    err "DXVK Modern Vulkan-Headers submodule is missing"
[ -f "$DXVK_MODERN_SRC/include/spirv/include/spirv/unified1/spirv.hpp" ] || \
    err "DXVK Modern SPIRV-Headers submodule is missing"

CACHE_COMPONENT="dxvk-modern-2.6"
CACHE_MANIFEST="$BUILD_DIR/.cache-manifests/$CACHE_COMPONENT.manifest"
CACHE_ARTIFACTS=(
    "$DXVK_MODERN_BUILD_ROOT/x64/bin/d3d11.dll"
    "$DXVK_MODERN_BUILD_ROOT/x64/bin/dxgi.dll"
    "$DXVK_MODERN_BUILD_ROOT/x86/bin/d3d11.dll"
    "$DXVK_MODERN_BUILD_ROOT/x86/bin/dxgi.dll"
)
CACHE_FILES_DIGEST="$(winehua_cache_files_digest \
    "$SCRIPT_DIR/build_dxvk_modern.sh" "$SCRIPT_DIR/build_cache.sh" "$SCRIPT_DIR/env.sh")"
CACHE_INPUT_KEY="$(winehua_cache_input_key \
    "$CACHE_COMPONENT" "$DXVK_MODERN_SRC" "$CACHE_FILES_DIGEST" \
    'buildtype=release' 'architectures=x86_64,i686' 'runtime=2.6.2')"

if winehua_cache_verify "$CACHE_MANIFEST" "$CACHE_COMPONENT" "$CACHE_INPUT_KEY" \
    "${CACHE_ARTIFACTS[@]}"; then
    log "DXVK Modern content cache hit: ${CACHE_INPUT_KEY:0:12}"
    exit 0
fi
log "DXVK Modern content cache miss: $WINEHUA_CACHE_MISS_REASON"

configured_source_of() {
    local build_dir="$1"
    [ -f "$build_dir/meson-info/meson-info.json" ] || { printf ''; return; }
    python3 - "$build_dir/meson-info/meson-info.json" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as stream:
        print(json.load(stream)["directories"]["source"])
except Exception:
    print("")
PY
}

reset_build_dir() {
    local build_dir="$1"
    case "$(realpath -m "$build_dir")" in
        "$(realpath -m "$DXVK_MODERN_BUILD_ROOT")"/*) rm -rf "$build_dir" ;;
        *) err "refusing to reset unexpected DXVK Modern build directory: $build_dir" ;;
    esac
}

setup_if_missing() {
    local build_dir="$1"
    local cross_file="$2"
    local prefix="$3"
    local configured_src=""
    local cached_glslang=""
    if [ -f "$build_dir/build.ninja" ]; then
        configured_src="$(configured_source_of "$build_dir")"
        if [ -n "$configured_src" ] && \
           [ "$(realpath -m "$configured_src")" != "$(realpath "$DXVK_MODERN_SRC")" ]; then
            log "DXVK Modern source path changed: $configured_src -> $DXVK_MODERN_SRC"
            reset_build_dir "$build_dir"
        fi
    fi
    if [ -f "$build_dir/build.ninja" ]; then
        cached_glslang="$(grep -oE '/[^[:space:]'\''"]+/glslangValidator' \
            "$build_dir/build.ninja" | head -n 1 || true)"
        if [ -n "$cached_glslang" ] && [ ! -x "$cached_glslang" ]; then
            log "DXVK Modern cached glslangValidator disappeared: $cached_glslang"
            reset_build_dir "$build_dir"
        fi
    fi
    if [ ! -f "$build_dir/build.ninja" ]; then
        log "Configuring DXVK Modern $(basename "$build_dir")"
        meson setup "$build_dir" "$DXVK_MODERN_SRC" \
            --cross-file "$DXVK_MODERN_SRC/$cross_file" \
            --prefix "$prefix" -Dbuildtype=release
    fi
}

setup_if_missing "$DXVK_MODERN_BUILD_ROOT/build.winehua64" build-win64.txt \
    "$DXVK_MODERN_BUILD_ROOT/x64"
setup_if_missing "$DXVK_MODERN_BUILD_ROOT/build.winehua32" build-win32.txt \
    "$DXVK_MODERN_BUILD_ROOT/x86"

log "--- DXVK Modern profile ($DXVK_MODERN_SRC) ---"
ninja -C "$DXVK_MODERN_BUILD_ROOT/build.winehua64" install
ninja -C "$DXVK_MODERN_BUILD_ROOT/build.winehua32" install

for dll in d3d11.dll dxgi.dll; do
    [ -f "$DXVK_MODERN_BUILD_ROOT/x64/bin/$dll" ] || \
        err "DXVK Modern x64 artifact missing: $DXVK_MODERN_BUILD_ROOT/x64/bin/$dll"
    [ -f "$DXVK_MODERN_BUILD_ROOT/x86/bin/$dll" ] || \
        err "DXVK Modern x86 artifact missing: $DXVK_MODERN_BUILD_ROOT/x86/bin/$dll"
done

winehua_cache_write "$CACHE_MANIFEST" "$CACHE_COMPONENT" "$CACHE_INPUT_KEY" \
    "${CACHE_ARTIFACTS[@]}" || err "failed to record DXVK Modern content cache"

log "DXVK Modern profile ready: $(git -c safe.directory="$DXVK_MODERN_SRC" -C "$DXVK_MODERN_SRC" rev-parse --short HEAD)"
