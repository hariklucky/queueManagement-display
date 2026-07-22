#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

KYLIN_ARCH="${KYLIN_ARCH:-amd64}"
IMAGE_NAME="${KYLIN_DOCKER_IMAGE:-}"
DOCKERFILE="$ROOT_DIR/docker/Dockerfile.kylin"
# 国内拉取 Docker Hub 超时时，可设置镜像基础镜像：
#   export KYLIN_DOCKER_BASE_IMAGE=docker.m.daocloud.io/library/ubuntu:22.04
BASE_IMAGE="${KYLIN_DOCKER_BASE_IMAGE:-ubuntu:22.04}"
REBUILD_IMAGE=0
PASSTHROUGH_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rebuild-image)
      REBUILD_IMAGE=1
      shift
      ;;
    --arm64)
      KYLIN_ARCH="arm64"
      shift
      ;;
    --amd64)
      KYLIN_ARCH="amd64"
      shift
      ;;
    --deb|--appimage)
      PASSTHROUGH_ARGS+=("$1")
      shift
      ;;
    --rpm|--all)
      cat <<'EOF'
错误：macOS / Windows 下 Docker 目前仅支持 deb 安装包。

请使用以下命令之一：
  npm run tauri:build:kylin
  npm run tauri:build:kylin:deb

rpm 包请在银河麒麟服务器版（RPM 系）本机执行：
  npm run tauri:build:kylin:rpm
EOF
      exit 1
      ;;
    *)
      PASSTHROUGH_ARGS+=("$1")
      shift
      ;;
  esac
done

case "$KYLIN_ARCH" in
  arm64)
    PLATFORM="${KYLIN_DOCKER_PLATFORM:-linux/arm64}"
    ;;
  amd64)
    PLATFORM="${KYLIN_DOCKER_PLATFORM:-linux/amd64}"
    ;;
  *)
    echo "错误：不支持的架构 \"${KYLIN_ARCH}\"，可选：arm64、amd64"
    exit 1
    ;;
esac

if [[ -z "$IMAGE_NAME" ]]; then
  IMAGE_NAME="qms-kylin-builder-${KYLIN_ARCH}"
fi

if [[ "$KYLIN_ARCH" == "arm64" && "$(uname -m)" == "x86_64" && -z "${KYLIN_ALLOW_INTEL_QEMU:-}" ]]; then
  cat <<'EOF'
错误：Intel Mac 无法可靠地通过 Docker/QEMU 构建 arm64 deb。
日志中若出现 "qemu: uncaught target signal 11" / "libc-bin" 即为该问题。

请改用以下方案之一：

【方案 1】在 arm64 麒麟终端本机打包（最推荐）
  npm install && npm run tauri:build:kylin:deb:arm64

【方案 2】GitHub Actions 云构建 arm64 deb
  1. 推送代码到 GitHub
  2. 打开 Actions → "Build Kylin ARM64 DEB" → Run workflow
  3. 在 Artifacts 中下载 .deb

【方案 3】Apple Silicon Mac 或云 ARM64 服务器

若仍要强行尝试 QEMU（通常仍会失败，每次约 8 分钟）：
  KYLIN_ALLOW_INTEL_QEMU=1 npm run tauri:build:kylin:deb:arm64:cn
EOF
  exit 1
fi

if [[ "$KYLIN_ARCH" == "arm64" && "$(uname -m)" == "x86_64" ]]; then
  cat <<'EOF'
警告：当前为 Intel Mac（x86_64），Docker 需通过 QEMU 模拟 arm64。
该方式构建极慢，且 apt 安装阶段可能出现 Segmentation fault（libc-bin 配置失败）。
EOF
fi

if ! command -v docker >/dev/null 2>&1; then
  cat <<'EOF'
错误：未找到 Docker，无法在 macOS / Windows 上打包麒麟 deb 安装包。

可选方案：
1. 安装 Docker Desktop 后重试：
     npm run tauri:build:kylin

2. 在银河麒麟桌面版 V10 本机执行：
     npm run tauri:build:kylin
EOF
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  cat <<'EOF'
错误：Docker 未运行或无权限访问。

请先启动 Docker Desktop，然后重试：
  npm run tauri:build:kylin
EOF
  exit 1
fi

if [[ "$REBUILD_IMAGE" -eq 1 ]] || ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
  echo "构建麒麟打包镜像（${IMAGE_NAME}，platform=${PLATFORM}，base=${BASE_IMAGE}）..."
  if ! docker build --platform "$PLATFORM" \
    --build-arg "BASE_IMAGE=${BASE_IMAGE}" \
    -t "$IMAGE_NAME" -f "$DOCKERFILE" "$ROOT_DIR"; then
    cat <<EOF

错误：构建 Docker 镜像失败。

常见原因：
1. 无法访问 Docker Hub（auth.docker.io 超时）
2. Intel Mac 通过 QEMU 模拟 arm64 时 apt 段错误（日志含 "qemu: uncaught target signal 11"）

若为 QEMU 段错误，请改用 arm64 麒麟终端 / Apple Silicon Mac / 云 ARM64 环境打包：
  npm run tauri:build:kylin:deb:arm64

若为 Docker Hub 超时，请任选一种方式解决后重试：

【方式 1】Docker Desktop 配置镜像加速（推荐，一次配置长期有效）
  1. 打开 Docker Desktop → Settings → Docker Engine
  2. 在 JSON 中加入 registry-mirrors，例如：
     {
       "registry-mirrors": [
         "https://docker.m.daocloud.io",
         "https://docker.1ms.run"
       ]
     }
  3. 点击 Apply & Restart，然后重试：
     npm run tauri:build:kylin:deb:${KYLIN_ARCH}

【方式 2】使用国内基础镜像直接打包
  npm run tauri:build:kylin:deb:${KYLIN_ARCH}:cn

【方式 3】手动指定基础镜像
  KYLIN_DOCKER_BASE_IMAGE=docker.m.daocloud.io/library/ubuntu:22.04 npm run tauri:build:kylin:deb:${KYLIN_ARCH}
EOF
    exit 1
  fi
fi

DOCKER_NODE_MODULES_VOLUME="qms-kylin-node-modules-${KYLIN_ARCH}"
DOCKER_NPM_CACHE_VOLUME="qms-kylin-npm-cache-${KYLIN_ARCH}"
DOCKER_CARGO_REGISTRY_VOLUME="qms-kylin-cargo-registry-${KYLIN_ARCH}"
DOCKER_CARGO_GIT_VOLUME="qms-kylin-cargo-git-${KYLIN_ARCH}"

DOCKER_BUILD_ARGS=(--"${KYLIN_ARCH}")
if ((${#PASSTHROUGH_ARGS[@]} > 0)); then
  DOCKER_BUILD_ARGS+=("${PASSTHROUGH_ARGS[@]}")
else
  DOCKER_BUILD_ARGS+=(--deb)
fi

echo "在 Docker 容器中打包（arch=${KYLIN_ARCH}, platform=${PLATFORM}, args=${DOCKER_BUILD_ARGS[*]}）..."
docker run --rm \
  --platform "$PLATFORM" \
  -v "$ROOT_DIR:/app" \
  -v "${DOCKER_NODE_MODULES_VOLUME}:/app/node_modules" \
  -v "${DOCKER_NPM_CACHE_VOLUME}:/root/.npm" \
  -v "${DOCKER_CARGO_REGISTRY_VOLUME}:/usr/local/cargo/registry" \
  -v "${DOCKER_CARGO_GIT_VOLUME}:/usr/local/cargo/git" \
  -w /app \
  -e KYLIN_IN_DOCKER=1 \
  -e KYLIN_ARCH="$KYLIN_ARCH" \
  "$IMAGE_NAME" \
  bash -c 'npm install && exec bash scripts/build-kylin.sh "$@"' _ "${DOCKER_BUILD_ARGS[@]}"

cat <<EOF

Docker 打包完成（${KYLIN_ARCH}），安装包输出目录：

  src-tauri/target/release/bundle/

AppImage 运行示例（麒麟终端）：
  chmod +x src-tauri/target/release/bundle/appimage/*.AppImage
  ./src-tauri/target/release/bundle/appimage/*.AppImage
EOF
