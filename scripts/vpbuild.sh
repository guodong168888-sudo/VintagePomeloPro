#!/usr/bin/env bash
# 复用同一个持久容器 vp-build 执行编译命令，避免每次构建都 docker run 新建容器
# 吃磁盘。首次调用自动创建；后续直接 docker exec 复用。
#
# 用法（在 WSL 内）：
#   scripts/vpbuild.sh make hap
#   scripts/vpbuild.sh bash scripts/run_catalog_unit_tests.cjs .hvigor/outputs/unit-model-current/js
#
# 环境变量（可选）：
#   VP_IMAGE     镜像名（默认 winehua-dev）
#   VP_TOOLS     工具链 Linux 路径（默认 /mnt/f/command-line-tools）
#   VP_CONTAINER 容器名（默认 vp-build）
# 重建容器：docker rm -f vp-build 后重新运行本脚本即可。
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="${VP_IMAGE:-winehua-dev}"
TOOLS="${VP_TOOLS:-/mnt/f/command-line-tools}"
CT="${VP_CONTAINER:-vp-build}"

ENV_FLAGS=(
  -e NATIVE_ARCH="${NATIVE_ARCH:-arm64-v8a}"
  -e GUEST_ARCH=x86_64
  -e BUILD_GUEST_GFX=1
  -e BUILD_WINE_MONO="${BUILD_WINE_MONO:-1}"
  -e "TARGET_SDK_VERSION=${TARGET_SDK_VERSION:-6.1.0(23)}"
  -e "COMPATIBLE_SDK_VERSION=${COMPATIBLE_SDK_VERSION:-6.1.0(23)}"
  -e TOOL_HOME=/apps/harmony
  -e OHOS_SDK=/apps/harmony/sdk/default/openharmony
  -e WAYLAND_SCANNER=/data/src/winehua/build/host-tools/bin/wayland-scanner
)

need_create=0
if ! docker inspect "$CT" >/dev/null 2>&1; then
  need_create=1
else
  # 仓库 worktree 或工具链路径变了 → 重建容器（bind mount 不能热改）
  mounted="$(docker inspect "$CT" --format '{{range .Mounts}}{{if eq .Destination "/data/src/winehua"}}{{.Source}}{{end}}{{end}}')"
  if [ "$mounted" != "$REPO" ]; then
    echo "[vpbuild] 检测到仓库路径变化 ($mounted -> $REPO)，重建容器 $CT"
    docker rm -f "$CT" >/dev/null 2>&1 || true
    need_create=1
  fi
fi

if [ "$need_create" = "1" ]; then
  echo "[vpbuild] 创建持久容器 $CT (镜像 $IMAGE)"
  docker create --name "$CT" \
    --mount "type=bind,src=$REPO,dst=/data/src/winehua" \
    --mount "type=bind,src=$TOOLS,dst=/apps/harmony,readonly" \
    -w /data/src/winehua \
    "${ENV_FLAGS[@]}" \
    "$IMAGE" bash -c 'sleep infinity'
fi

# 容器可能因 WSL/Docker Desktop 重启而停止；保证运行中再 exec。
if [ "$(docker inspect "$CT" --format '{{.State.Running}}')" != "true" ]; then
  docker start "$CT" >/dev/null
fi

echo "[vpbuild] exec $CT: $*"
exec docker exec -i "${ENV_FLAGS[@]}" -w /data/src/winehua "$CT" "$@"
