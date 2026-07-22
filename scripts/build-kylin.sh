#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BUNDLES="${KYLIN_BUNDLES:-deb}"
KYLIN_ARCH="${KYLIN_ARCH:-}"
EXTRA_ARGS=()
TARGET_ARGS=()
RUST_TARGET=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundles)
      BUNDLES="${2:-}"
      shift 2
      ;;
    --deb)
      BUNDLES="deb"
      shift
      ;;
    --appimage)
      BUNDLES="appimage"
      shift
      ;;
    --rpm)
      BUNDLES="rpm"
      shift
      ;;
    --all)
      BUNDLES="deb,rpm"
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
    --no-bundle)
      EXTRA_ARGS+=(--no-bundle)
      shift
      ;;
    *)
      EXTRA_ARGS+=("$1")
      shift
      ;;
  esac
done

normalize_arch() {
  case "$1" in
    aarch64|arm64) echo "arm64" ;;
    x86_64|amd64) echo "amd64" ;;
    *)
      echo "错误：无法识别 CPU 架构 \"${1}\"。" >&2
      exit 1
      ;;
  esac
}

if [[ -z "$KYLIN_ARCH" ]]; then
  KYLIN_ARCH="$(normalize_arch "$(uname -m)")"
fi

# macOS / Windows 无法本机打 Linux deb，优先走 Docker（必须在交叉编译逻辑之前）
if [[ "$(uname -s)" != "Linux" && -z "${KYLIN_IN_DOCKER:-}" ]]; then
  DOCKER_ARGS=()
  case "$BUNDLES" in
    deb) DOCKER_ARGS+=(--deb) ;;
    appimage) DOCKER_ARGS+=(--appimage) ;;
    rpm) DOCKER_ARGS+=(--rpm) ;;
    deb,rpm) DOCKER_ARGS+=(--all) ;;
  esac
  case "$KYLIN_ARCH" in
    arm64) DOCKER_ARGS+=(--arm64) ;;
    amd64) DOCKER_ARGS+=(--amd64) ;;
  esac
  if ((${#EXTRA_ARGS[@]} > 0)); then
    DOCKER_ARGS+=("${EXTRA_ARGS[@]}")
  fi
  exec "$ROOT_DIR/scripts/build-kylin-docker.sh" "${DOCKER_ARGS[@]}"
fi

HOST_ARCH="$(normalize_arch "$(uname -m)")"

setup_arm64_cross_compile() {
  if ! rustup target list --installed | grep -q '^aarch64-unknown-linux-gnu$'; then
    echo "安装 Rust 交叉编译目标 aarch64-unknown-linux-gnu..."
    rustup target add aarch64-unknown-linux-gnu
  fi

  if ! command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
    cat <<'EOF'
错误：未找到 aarch64-linux-gnu-gcc，无法在 x86_64 本机交叉编译 arm64 安装包。

推荐方案（任选其一）：
1. macOS / Windows 使用 Docker 打 arm64 deb：
     npm run tauri:build:kylin:deb:arm64

2. 在 arm64 麒麟终端本机执行：
     npm run tauri:build:kylin:deb:arm64

3. 在 x86 Linux 安装交叉编译工具链后重试：
     sudo apt install -y gcc-aarch64-linux-gnu g++-aarch64-linux-gnu
EOF
    exit 1
  fi

  export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc
  export PKG_CONFIG_ALLOW_CROSS=1

  cat <<'EOF'
警告：在 x86_64 上交叉编译 arm64 可能因 WebKitGTK 原生依赖失败。
若构建报错，请改用 Docker 或在 arm64 麒麟终端本机打包。
EOF
}

if [[ "$KYLIN_ARCH" != "$HOST_ARCH" ]]; then
  case "$KYLIN_ARCH" in
    arm64)
      RUST_TARGET="aarch64-unknown-linux-gnu"
      setup_arm64_cross_compile
      ;;
    amd64)
      RUST_TARGET="x86_64-unknown-linux-gnu"
      if ! rustup target list --installed | grep -q '^x86_64-unknown-linux-gnu$'; then
        echo "安装 Rust 交叉编译目标 x86_64-unknown-linux-gnu..."
        rustup target add x86_64-unknown-linux-gnu
      fi
      export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER=x86_64-linux-gnu-gcc
      export PKG_CONFIG_ALLOW_CROSS=1
      ;;
    *)
      echo "错误：不支持的架构 \"${KYLIN_ARCH}\"，可选：arm64、amd64"
      exit 1
      ;;
  esac

  TARGET_ARGS=(--target "$RUST_TARGET")
fi

missing_tools=()
for tool in cargo rustc node npm; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    missing_tools+=("$tool")
  fi
done

if ((${#missing_tools[@]} > 0)); then
  cat <<EOF
错误：缺少构建工具：${missing_tools[*]}

请先安装 Rust、Node.js 与 npm，并执行：

  npm install
EOF
  exit 1
fi

IFS=',' read -r -a bundle_list <<< "$BUNDLES"
for bundle in "${bundle_list[@]}"; do
  bundle="$(echo "$bundle" | xargs)"
  case "$bundle" in
    deb)
      if ! command -v dpkg-deb >/dev/null 2>&1; then
        cat <<'EOF'
错误：未找到 dpkg-deb，无法生成 .deb 安装包。

银河麒麟桌面版（Debian 系）可执行：

  sudo apt update
  sudo apt install -y dpkg-dev
EOF
        exit 1
      fi
      ;;
    rpm)
      if ! command -v rpmbuild >/dev/null 2>&1; then
        cat <<'EOF'
错误：未找到 rpmbuild，无法生成 .rpm 安装包。

银河麒麟服务器版（RPM 系）可执行：

  sudo yum install -y rpm-build
  # 或
  sudo dnf install -y rpm-build
EOF
        exit 1
      fi
      ;;
    appimage)
      if ! command -v patchelf >/dev/null 2>&1; then
        cat <<'EOF'
错误：未找到 patchelf，无法生成 AppImage。

银河麒麟 / Ubuntu 系可执行：

  sudo apt update
  sudo apt install -y patchelf libfuse2
EOF
        exit 1
      fi
      ;;
    *)
      cat <<EOF
错误：不支持的安装包类型 "${bundle}"。

可选值：deb、appimage、rpm
示例：
  npm run tauri:build:kylin
  npm run tauri:build:kylin:appimage:arm64
  npm run tauri:build:kylin:rpm
  npm run tauri:build:kylin:all
EOF
      exit 1
      ;;
  esac
done

if [[ ! -f /usr/include/webkit2gtk-4.1/webkit2.h && ! -f /usr/include/webkit2gtk-4.0/webkit2.h ]]; then
  cat <<'EOF'
警告：未检测到 WebKitGTK 开发头文件，构建可能失败。

银河麒麟桌面版（apt）建议安装：

  sudo apt update
  sudo apt install -y \
    build-essential curl wget file libssl-dev \
    libgtk-3-dev libayatana-appindicator3-dev librsvg2-dev \
    libwebkit2gtk-4.1-dev

若仓库仅有 4.0 版本，可尝试：

  sudo apt install -y libwebkit2gtk-4.0-dev

银河麒麟服务器版（yum/dnf）建议安装：

  sudo yum install -y \
    webkit2gtk4.1-devel openssl-devel gtk3-devel \
    libappindicator-gtk3 librsvg2-devel
EOF
fi

if [[ -n "$RUST_TARGET" ]]; then
  BUNDLE_DIR="src-tauri/target/${RUST_TARGET}/release/bundle"
else
  BUNDLE_DIR="src-tauri/target/release/bundle"
fi

TAURI_BUNDLES="$BUNDLES"
KYLIN_DEB_FROM_APPIMAGE="${KYLIN_DEB_FROM_APPIMAGE:-1}"
if [[ "$BUNDLES" == "deb" && "$KYLIN_DEB_FROM_APPIMAGE" == "1" ]]; then
  echo "麒麟 deb 模式：先构建 AppImage（内置 WebKit + glibc 兼容），再封装 deb..."
  TAURI_BUNDLES="appimage"
fi

echo "开始打包麒麟环境安装包（arch: ${KYLIN_ARCH}, bundles: ${BUNDLES}）..."
npm run tauri -- build --bundles "$TAURI_BUNDLES" "${TARGET_ARGS[@]}" "${EXTRA_ARGS[@]}"

appimage_file="$(find "$ROOT_DIR/$BUNDLE_DIR" -name "*.AppImage" -type f | head -n 1 || true)"

if [[ -n "$appimage_file" && -f "$appimage_file" && "${KYLIN_APPIMAGE_GLIBC_COMPAT:-1}" == "1" ]]; then
  if [[ -f "$ROOT_DIR/scripts/repack-appimage-glibc-compat.sh" ]]; then
    echo "正在为 glibc 2.31 兼容重新打包 AppImage..."
    bash "$ROOT_DIR/scripts/repack-appimage-glibc-compat.sh" "$appimage_file" "$appimage_file"
  fi
fi

if [[ "$BUNDLES" == "deb" && "$KYLIN_DEB_FROM_APPIMAGE" == "1" ]]; then
  if [[ -z "$appimage_file" || ! -f "$appimage_file" ]]; then
    echo "错误：未找到 AppImage，无法生成麒麟 deb" >&2
    exit 1
  fi
  deb_dir="$ROOT_DIR/$BUNDLE_DIR/deb"
  mkdir -p "$deb_dir"
  bash "$ROOT_DIR/scripts/repack-deb-from-appimage.sh" "$appimage_file" "$deb_dir"
fi

cat <<EOF

打包完成，安装包输出目录：

  ${BUNDLE_DIR}/

常见产物：
  - deb: ${BUNDLE_DIR}/deb/
  - appimage: ${BUNDLE_DIR}/appimage/
  - rpm: ${BUNDLE_DIR}/rpm/

安装示例（deb）：
  sudo dpkg -i ${BUNDLE_DIR}/deb/*.deb
  sudo apt install -f -y

运行示例（AppImage，适合仅有 WebKit 4.0 的麒麟终端）：
  chmod +x ${BUNDLE_DIR}/appimage/*.AppImage
  ${BUNDLE_DIR}/appimage/*.AppImage

若双击无反应，请先安装 FUSE 2 或在终端运行：
  sudo apt install -y libfuse2
  APPIMAGE_EXTRACT_AND_RUN=1 ${BUNDLE_DIR}/appimage/*.AppImage
EOF
