#!/bin/bash
# Build the explicit x64-only VKD3D-Proton 2.6 limited-500K profile.
#
# The upstream submodule stays pinned and clean. WineHua patches are applied
# to an isolated build copy so normal DXVK and WineD3D paths cannot be
# modified as a side effect of this target.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"
source "$SCRIPT_DIR/build_cache.sh"

PATCH_ROOT="$ROOT/patches/vkd3d-proton"
SOURCE_ROOT="$VKD3D_PROTON_BUILD_ROOT/limited-500k-source"
MESON_ROOT="$VKD3D_PROTON_BUILD_ROOT/limited-500k-build"
OUTPUT_ROOT="$VKD3D_PROTON_BUILD_ROOT/limited-500k"
OUTPUT_X64="$OUTPUT_ROOT/x64"
SOURCE_STAMP="$SOURCE_ROOT/.winehua-source-id"
EXPECTED_BASE_COMMIT="3e5aab6fb3e18f81a71b339be4cb5cdf55140980"
GIT_SAFE=(git -c safe.directory="$VKD3D_PROTON_SRC" -C "$VKD3D_PROTON_SRC")

[ -f "$VKD3D_PROTON_SRC/meson.build" ] || \
    err "VKD3D-Proton source missing: $VKD3D_PROTON_SRC"
command -v x86_64-w64-mingw32-widl >/dev/null 2>&1 || \
    err "x86_64-w64-mingw32-widl missing; install mingw-w64-tools (required by VKD3D meson)"

# Nested Khronos/dxil-spirv checkouts are required before the isolated copy.
# actions/checkout recursive + fetch-depth:1 can leave these empty on CI.
"${GIT_SAFE[@]}" submodule update --init --recursive

[ -f "$VKD3D_PROTON_SRC/subprojects/Vulkan-Headers/include/vulkan/vulkan.h" ] || \
    err "VKD3D-Proton Vulkan-Headers submodule is missing"
[ -f "$VKD3D_PROTON_SRC/subprojects/SPIRV-Headers/include/spirv/unified1/spirv.h" ] || \
    err "VKD3D-Proton SPIRV-Headers submodule is missing"
[ -f "$VKD3D_PROTON_SRC/subprojects/dxil-spirv/meson.build" ] || \
    err "VKD3D-Proton dxil-spirv submodule is missing"
[ -f "$PATCH_ROOT/0001-probe-recover-validated-VKD3D-2.6-500K-profile.patch" ] || \
    err "VKD3D-Proton limited-500K patch series is missing"

base_commit="$("${GIT_SAFE[@]}" rev-parse HEAD)"
[ "$base_commit" = "$EXPECTED_BASE_COMMIT" ] || \
    err "VKD3D-Proton base drifted: expected $EXPECTED_BASE_COMMIT, got $base_commit"

# Ignore untracked wraplocks and dirty nested checkouts; still fail if vkd3d
# itself has tracked edits (patches must stay in patches/vkd3d-proton).
vkd3d_dirty="$("${GIT_SAFE[@]}" status --porcelain --untracked-files=no --ignore-submodules=dirty)"
if [ -n "$vkd3d_dirty" ]; then
    echo "$vkd3d_dirty" >&2
    err "VKD3D-Proton submodule is dirty; patches must stay outside the submodule"
fi

mapfile -t patches < <(find "$PATCH_ROOT" -maxdepth 1 -type f -name '*.patch' -print | sort)
[ "${#patches[@]}" -gt 0 ] || err "VKD3D-Proton patch series is empty"
patch_series_sha="$(sha256sum "${patches[@]}" | sha256sum | awk '{print $1}')"
patch_head="$(sed -n '1s/^From \([0-9a-f]\{40\}\) .*/\1/p' "${patches[${#patches[@]}-1]}")"
[ -n "$patch_head" ] || err "Cannot read VKD3D-Proton patch-series head"
source_id="$base_commit-$patch_series_sha"
deterministic_build_id="${base_commit:0:15}"

CACHE_COMPONENT="vkd3d-proton-limited-500k"
CACHE_MANIFEST="$BUILD_DIR/.cache-manifests/$CACHE_COMPONENT.manifest"
CACHE_ARTIFACTS=(
    "$OUTPUT_X64/d3d12.dll"
    "$OUTPUT_X64/winehua-d3d12-smoke.exe"
    "$OUTPUT_X64/triangle.exe"
    "$OUTPUT_X64/gears.exe"
    "$OUTPUT_ROOT/manifest.json"
)
CACHE_FILES_DIGEST="$(winehua_cache_files_digest \
    "$SCRIPT_DIR/build_vkd3d_proton.sh" "$SCRIPT_DIR/build_cache.sh" \
    "$SCRIPT_DIR/env.sh" "${patches[@]}")"
CACHE_INPUT_KEY="$(winehua_cache_input_key \
    "$CACHE_COMPONENT" "$VKD3D_PROTON_SRC" "$CACHE_FILES_DIGEST" \
    'buildtype=release' 'architecture=x86_64' 'limited-resource-view-heaps=1' \
    'trace=0' 'tests=1' 'extras=1' "build-id=$deterministic_build_id")"

if winehua_cache_verify "$CACHE_MANIFEST" "$CACHE_COMPONENT" "$CACHE_INPUT_KEY" \
    "${CACHE_ARTIFACTS[@]}"; then
    log "VKD3D-Proton content cache hit: ${CACHE_INPUT_KEY:0:12}"
    exit 0
fi
log "VKD3D-Proton content cache miss: $WINEHUA_CACHE_MISS_REASON"

if [ ! -f "$SOURCE_STAMP" ] || [ "$(cat "$SOURCE_STAMP")" != "$source_id" ]; then
    log "Refreshing isolated VKD3D-Proton source"
    rm -rf "$SOURCE_ROOT" "$MESON_ROOT" "$OUTPUT_ROOT"
    mkdir -p "$SOURCE_ROOT"
    tar -C "$VKD3D_PROTON_SRC" --exclude='.git' -cf - . | tar -C "$SOURCE_ROOT" -xf -
    if find "$SOURCE_ROOT" -name .git -print -quit | grep -q .; then
        err "Isolated VKD3D-Proton source unexpectedly contains Git metadata"
    fi
    for patch_file in "${patches[@]}"; do
        log "Applying $(basename "$patch_file")"
        patch -d "$SOURCE_ROOT" -p1 --forward --batch < "$patch_file"
    done
    printf '%s\n' "$source_id" > "$SOURCE_STAMP"
fi

# Meson's vcs_tag falls back to project_version ("2.6") when the isolated
# source intentionally has no .git directory. The upstream template prefixes
# that value with 0x, producing invalid C (0x2.6). Materialize a stable numeric
# build id from the locked upstream commit before Meson/Ninja sees the template.
build_id_template="$SOURCE_ROOT/vkd3d_build.h.in"
expected_build_id_line="static const uint64_t vkd3d_build = 0x$deterministic_build_id;"
if grep -Fq 'static const uint64_t vkd3d_build = 0x@VCS_TAG@;' "$build_id_template"; then
    sed_i "s/0x@VCS_TAG@/0x$deterministic_build_id/" "$build_id_template"
elif ! grep -Fqx "$expected_build_id_line" "$build_id_template"; then
    err "unexpected VKD3D build-id template: $build_id_template"
fi

meson_args=(
    --cross-file "$SOURCE_ROOT/build-win64.txt"
    -Denable_d3d12=true
    -Denable_tests=true
    -Denable_extras=true
    -Denable_limited_resource_view_heaps=true
    -Denable_trace=false
    -Dbuildtype=release
)
if [ ! -f "$MESON_ROOT/build.ninja" ]; then
    log "Configuring VKD3D-Proton x64 limited-500K"
    meson setup "$MESON_ROOT" "$SOURCE_ROOT" "${meson_args[@]}"
elif ! grep -q 'demos/triangle' "$MESON_ROOT/build.ninja"; then
    log "Reconfiguring VKD3D-Proton x64 limited-500K with extras/demos"
    meson setup --reconfigure "$MESON_ROOT" "$SOURCE_ROOT" "${meson_args[@]}"
fi

log "Building VKD3D-Proton x64 limited-500K"
ninja -C "$MESON_ROOT"

dll="$MESON_ROOT/libs/d3d12/d3d12.dll"
smoke="$MESON_ROOT/tests/vkd3d-graphics-smoketest.exe"
triangle=""
gears=""
for candidate in "$MESON_ROOT/demos/triangle.exe" "$MESON_ROOT/triangle.exe"; do
    if [ -s "$candidate" ]; then
        triangle="$candidate"
        break
    fi
done
for candidate in "$MESON_ROOT/demos/gears.exe" "$MESON_ROOT/gears.exe"; do
    if [ -s "$candidate" ]; then
        gears="$candidate"
        break
    fi
done
[ -s "$dll" ] || err "VKD3D-Proton d3d12.dll missing: $dll"
[ -s "$smoke" ] || err "VKD3D-Proton graphics smoke missing: $smoke"
[ -n "$triangle" ] || err "VKD3D-Proton triangle demo missing after extras build"
[ -n "$gears" ] || err "VKD3D-Proton gears demo missing after extras build"
mkdir -p "$OUTPUT_X64"
install -m 0644 "$dll" "$OUTPUT_X64/d3d12.dll"
install -m 0755 "$smoke" "$OUTPUT_X64/winehua-d3d12-smoke.exe"
install -m 0755 "$triangle" "$OUTPUT_X64/triangle.exe"
install -m 0755 "$gears" "$OUTPUT_X64/gears.exe"

dll_sha="$(sha256sum "$OUTPUT_X64/d3d12.dll" | awk '{print $1}')"
smoke_sha="$(sha256sum "$OUTPUT_X64/winehua-d3d12-smoke.exe" | awk '{print $1}')"
triangle_sha="$(sha256sum "$OUTPUT_X64/triangle.exe" | awk '{print $1}')"
gears_sha="$(sha256sum "$OUTPUT_X64/gears.exe" | awk '{print $1}')"
cat > "$OUTPUT_ROOT/manifest.json" <<EOF
{
  "schemaVersion": 1,
  "profile": "limited-500k",
  "defaultEnabled": true,
  "architecture": "x86_64-windows",
  "version": "2.6",
  "upstreamCommit": "$base_commit",
  "buildId": "$deterministic_build_id",
  "patchSeriesHead": "$patch_head",
  "patchSeriesSha256": "$patch_series_sha",
  "maximumShaderVisibleResourceDescriptors": 500000,
  "maximumShaderVisibleSamplerDescriptors": 2048,
  "files": {
    "x64/d3d12.dll": "$dll_sha",
    "x64/winehua-d3d12-smoke.exe": "$smoke_sha",
    "x64/triangle.exe": "$triangle_sha",
    "x64/gears.exe": "$gears_sha"
  }
}
EOF

winehua_cache_write "$CACHE_MANIFEST" "$CACHE_COMPONENT" "$CACHE_INPUT_KEY" \
    "${CACHE_ARTIFACTS[@]}" || err "failed to record VKD3D-Proton content cache"

log "VKD3D-Proton ready: base=${base_commit:0:8} patch=${patch_head:0:8} dll=$dll_sha"
