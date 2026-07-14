#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BUNDLES="${KYLIN_BUNDLES:-deb}"
EXTRA_ARGS=()

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
    --rpm)
      BUNDLES="rpm"
      shift
      ;;
    --all)
      BUNDLES="deb,rpm"
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

if [[ "$(uname -s)" != "Linux" && -z "${KYLIN_IN_DOCKER:-}" ]]; then
  exec "$ROOT_DIR/scripts/build-kylin-docker.sh" "$@"
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
    *)
      cat <<EOF
错误：不支持的安装包类型 "${bundle}"。

可选值：deb、rpm
示例：
  npm run tauri:build:kylin
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

echo "开始打包麒麟环境安装包（bundles: ${BUNDLES}）..."
npm run tauri -- build --bundles "$BUNDLES" "${EXTRA_ARGS[@]}"

cat <<EOF

打包完成，安装包输出目录：

  src-tauri/target/release/bundle/

常见产物：
  - deb: src-tauri/target/release/bundle/deb/
  - rpm: src-tauri/target/release/bundle/rpm/

安装示例（deb）：
  sudo dpkg -i src-tauri/target/release/bundle/deb/*.deb
  sudo apt install -f -y
EOF
