#!/usr/bin/env bash
# Explicit diagnostic packaging only. Restore production input even on failure.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
arch="${NATIVE_ARCH:?NATIVE_ARCH must be explicit}"
case "$arch" in arm64-v8a|x86_64) ;; *) exit 2 ;; esac
stage="$root/build/host-stage-timing/$arch"
production="$root/entry/libs/$arch/libwinehua_vtest_server.so"
candidate="$stage/libwinehua_vtest_server.so"
backup="$stage/production-baseline.so"
runtime="$root/entry/src/main/resources/rawfile/wine-data.zip"
test -f "$candidate" && test -f "$production" && test -f "$runtime"
test ! -L "$production" && test ! -L "$backup"
# package.sh removes other-ABI libraries; refuse instead of deleting such a tree.
other=x86_64
test "$arch" != x86_64 || other=arm64-v8a
test ! -e "$root/entry/libs/$other"
runtime_hash="$(sha256sum "$runtime" | cut -d' ' -f1)"
if test -e "$backup"; then
    cmp "$production" "$backup"
else
    cp -p "$production" "$backup"
fi
restore_production() {
    # Fresh mtime makes the next ordinary Hvigor run re-process this input.
    cp "$backup" "$production"
    cmp "$backup" "$production"
}
trap restore_production EXIT
cp "$candidate" "$production"
# Only the native prebuilt changed. Reuse the verified runtime, never assemble it
# again for this diagnostic package; ordinary builds still use normal make hap.
make -C "$root" -o assemble NATIVE_ARCH="$arch" GUEST_ARCH=x86_64 BUILD_GUEST_GFX=1 hap
test "$(sha256sum "$runtime" | cut -d' ' -f1)" = "$runtime_hash"
echo 'Host-stage diagnostic HAP built; production library restored on exit.'
