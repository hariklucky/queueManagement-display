#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

IMAGE_NAME="${KYLIN_DOCKER_IMAGE:-qms-kylin-builder}"
DOCKERFILE="$ROOT_DIR/docker/Dockerfile.kylin"
# 国内拉取 Docker Hub 超时时，可设置镜像基础镜像：
#   export KYLIN_DOCKER_BASE_IMAGE=docker.m.daocloud.io/library/ubuntu:22.04
BASE_IMAGE="${KYLIN_DOCKER_BASE_IMAGE:-ubuntu:22.04}"
# 麒麟终端多为 x86_64；Apple Silicon Mac 需显式指定 amd64
PLATFORM="${KYLIN_DOCKER_PLATFORM:-linux/amd64}"
REBUILD_IMAGE=0
PASSTHROUGH_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rebuild-image)
      REBUILD_IMAGE=1
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

错误：构建 Docker 镜像失败，常见原因是无法访问 Docker Hub（auth.docker.io 超时）。

请任选一种方式解决后重试：

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
     npm run tauri:build:kylin

【方式 2】使用国内基础镜像直接打包
  npm run tauri:build:kylin:cn

【方式 3】手动指定基础镜像
  KYLIN_DOCKER_BASE_IMAGE=docker.m.daocloud.io/library/ubuntu:22.04 npm run tauri:build:kylin
EOF
    exit 1
  fi
fi

echo "在 Docker 容器中打包 deb 安装包（platform=${PLATFORM}）..."
if ((${#PASSTHROUGH_ARGS[@]} > 0)); then
  docker run --rm \
    --platform "$PLATFORM" \
    -v "$ROOT_DIR:/app" \
    -v qms-kylin-node-modules:/app/node_modules \
    -v qms-kylin-npm-cache:/root/.npm \
    -v qms-kylin-cargo-registry:/usr/local/cargo/registry \
    -v qms-kylin-cargo-git:/usr/local/cargo/git \
    -w /app \
    -e KYLIN_IN_DOCKER=1 \
    -e KYLIN_BUNDLES=deb \
    "$IMAGE_NAME" \
    bash -c 'npm install && exec bash scripts/build-kylin.sh --deb "$@"' _ "${PASSTHROUGH_ARGS[@]}"
else
  docker run --rm \
    --platform "$PLATFORM" \
    -v "$ROOT_DIR:/app" \
    -v qms-kylin-node-modules:/app/node_modules \
    -v qms-kylin-npm-cache:/root/.npm \
    -v qms-kylin-cargo-registry:/usr/local/cargo/registry \
    -v qms-kylin-cargo-git:/usr/local/cargo/git \
    -w /app \
    -e KYLIN_IN_DOCKER=1 \
    -e KYLIN_BUNDLES=deb \
    "$IMAGE_NAME" \
    bash -c 'npm install && exec bash scripts/build-kylin.sh --deb'
fi

cat <<EOF

Docker 打包完成，安装包输出目录：

  src-tauri/target/release/bundle/deb/

安装示例（在麒麟终端上）：
  sudo dpkg -i src-tauri/target/release/bundle/deb/*.deb
  sudo apt install -f -y
EOF
