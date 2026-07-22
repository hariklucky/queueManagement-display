#!/usr/bin/env bash
# 将已做 glibc 兼容的 AppImage 封装为 .deb，供 glibc 2.31 / WebKit 4.0 的麒麟终端安装。
# AppImage 已自带 WebKit 与 glibc 运行时，deb 不再依赖 libwebkit2gtk-4.1。
set -euo pipefail

APPIMAGE="${1:?用法: $0 <input.AppImage> [output_dir]}"
OUTPUT_DIR="${2:-$(dirname "$APPIMAGE")}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAURI_CONF="$ROOT_DIR/src-tauri/tauri.conf.json"
# shellcheck source=kylin-launcher.sh
source "$SCRIPT_DIR/kylin-launcher.sh"

if [[ ! -f "$APPIMAGE" ]]; then
  echo "错误：找不到 AppImage: $APPIMAGE" >&2
  exit 1
fi

if [[ ! -f "$TAURI_CONF" ]]; then
  echo "错误：找不到 $TAURI_CONF" >&2
  exit 1
fi

read_tauri_field() {
  node -pe "require('$TAURI_CONF').$1"
}

VERSION="$(read_tauri_field version)"
PRODUCT_NAME="$(read_tauri_field productName)"
SHORT_DESC="$(read_tauri_field 'bundle.shortDescription')"
LONG_DESC="$(read_tauri_field 'bundle.longDescription')"
PACKAGE_NAME="$(grep -E '^name\s*=' "$ROOT_DIR/src-tauri/Cargo.toml" | head -n1 | sed 's/.*"\(.*\)".*/\1/')"
if [[ -z "$PACKAGE_NAME" ]]; then
  PACKAGE_NAME="qms"
fi

case "$(uname -m)" in
  aarch64|arm64) DEB_ARCH="arm64" ;;
  x86_64|amd64) DEB_ARCH="amd64" ;;
  *)
    echo "错误：不支持的架构 \"$(uname -m)\"" >&2
    exit 1
    ;;
esac

LD_LINUX="$(kylin_ld_linux)"
INSTALL_ROOT="/opt/qms"

APPIMAGE="$(readlink -f "$APPIMAGE")"
mkdir -p "$OUTPUT_DIR"

WORKDIR="$(mktemp -d)"
PKG_ROOT="$(mktemp -d)"
trap 'rm -rf "$WORKDIR" "$PKG_ROOT"' EXIT

echo "=== 解压 AppImage ==="
echo "输入: $APPIMAGE"
cd "$WORKDIR"
chmod +x "$APPIMAGE"
APPIMAGE_EXTRACT_AND_RUN=1 "$APPIMAGE" --appimage-extract
APP_DIR="$WORKDIR/squashfs-root"

if [[ ! -f "$APP_DIR/AppRun" ]]; then
  echo "错误：AppDir 中缺少 AppRun" >&2
  exit 1
fi

if [[ ! -f "$APP_DIR/usr/lib/glibc-compat/libc.so.6" ]]; then
  echo "警告：未检测到 bundled glibc-compat，建议先执行 repack-appimage-glibc-compat.sh" >&2
fi

MAIN_BIN="$(kylin_detect_main_bin "$APP_DIR")"
INSTALL_PREFIX="opt/qms"
STAGING="$PKG_ROOT/$INSTALL_PREFIX"
mkdir -p "$STAGING"
cp -a "$APP_DIR/." "$STAGING/"

# /usr/bin 入口：完整启动脚本（固定 /opt/qms，适配 UKUI 双击启动）
LAUNCHER="$PKG_ROOT/usr/bin/$PACKAGE_NAME"
mkdir -p "$(dirname "$LAUNCHER")"
kylin_write_launcher "$LAUNCHER" "$INSTALL_ROOT" "$MAIN_BIN" "$LD_LINUX" 0

# /opt/qms/AppRun 同步为相同逻辑，便于终端直接调试
kylin_write_launcher "$STAGING/AppRun" "$INSTALL_ROOT" "$MAIN_BIN" "$LD_LINUX" 0

DESKTOP_ID="com.qms.desktop"
DESKTOP_FILE="$PKG_ROOT/usr/share/applications/${DESKTOP_ID}.desktop"
mkdir -p "$(dirname "$DESKTOP_FILE")"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Categories=Utility;
Comment=${SHORT_DESC}
Exec=/usr/bin/${PACKAGE_NAME}
Icon=${PACKAGE_NAME}
Name=${PRODUCT_NAME}
Terminal=false
Type=Application
StartupNotify=true
TryExec=/usr/bin/${PACKAGE_NAME}
EOF

if [[ -d "$APP_DIR/usr/share/icons" ]]; then
  mkdir -p "$PKG_ROOT/usr/share"
  cp -a "$APP_DIR/usr/share/icons" "$PKG_ROOT/usr/share/"
fi

mkdir -p "$PKG_ROOT/DEBIAN"
cat > "$PKG_ROOT/DEBIAN/control" <<EOF
Package: ${PACKAGE_NAME}
Version: ${VERSION}
Architecture: ${DEB_ARCH}
Maintainer: QMS <qms@local>
Depends: libc6 (>= 2.17)
Section: utils
Priority: optional
Description: ${SHORT_DESC}
 ${LONG_DESC}
 本包装内置 WebKit 与 glibc 运行时，适配 glibc 2.31 的银河麒麟桌面版。
EOF

cat > "$PKG_ROOT/DEBIAN/postinst" <<EOF
#!/bin/sh
set -e
chmod +x /opt/qms/AppRun /usr/bin/${PACKAGE_NAME} 2>/dev/null || true
find /opt/qms/usr/bin -type f -perm -111 -exec chmod +x {} + 2>/dev/null || true
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database /usr/share/applications 2>/dev/null || true
fi
exit 0
EOF
chmod 755 "$PKG_ROOT/DEBIAN/postinst"

DEB_FILE="$OUTPUT_DIR/${PACKAGE_NAME}_${VERSION}_${DEB_ARCH}.deb"
dpkg-deb -Zgzip --build --root-owner-group "$PKG_ROOT" "$DEB_FILE"

echo "=== 完成：已生成麒麟兼容 deb ==="
echo "  $DEB_FILE"
echo "  安装: sudo dpkg -i $(basename "$DEB_FILE") && sudo apt install -f -y"
echo "  若无法启动，请查看日志: ~/.cache/qms/launch.log"
