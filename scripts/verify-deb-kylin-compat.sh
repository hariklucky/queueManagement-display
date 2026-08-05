#!/usr/bin/env bash
# 检查 deb 是否包含 glibc-compat 运行时（适配 glibc 2.31 麒麟终端）
set -euo pipefail

DEB="${1:?用法: $0 <package.deb>}"
if [[ ! -f "$DEB" ]]; then
  echo "错误：找不到 deb: $DEB" >&2
  exit 1
fi

DEB="$(readlink -f "$DEB")"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "检查 deb: $DEB"

deb_members="$(ar t "$DEB")"
echo "deb 成员: $deb_members"
if grep -qE '\.(zst|zstd)$' <<< "$deb_members"; then
  echo "错误：deb 使用了 zstd 压缩（control/data.tar.zst），银河麒麟旧版 dpkg 无法安装。" >&2
  echo "请使用 dpkg-deb -Zgzip 重新打包。" >&2
  exit 1
fi
if ! grep -qE 'control\.tar\.(gz|xz)$' <<< "$deb_members"; then
  echo "错误：未检测到 gzip/xz 格式的 control.tar" >&2
  exit 1
fi

dpkg-deb -x "$DEB" "$WORKDIR/extract"

if [[ -f "$WORKDIR/extract/opt/qms/usr/lib/glibc-compat/libc.so.6" ]]; then
  echo "已检测到 bundled glibc-compat，可在 glibc 2.31 系统上运行。"
else
  echo "错误：deb 中缺少 opt/qms/usr/lib/glibc-compat/libc.so.6" >&2
  exit 1
fi

case "$(uname -m)" in
  aarch64|arm64) ld_linux="ld-linux-aarch64.so.1" ;;
  x86_64|amd64) ld_linux="ld-linux-x86-64.so.2" ;;
  *) ld_linux="ld-linux-aarch64.so.1" ;;
esac
loader="$WORKDIR/extract/opt/qms/usr/lib/glibc-compat/$ld_linux"
if [[ ! -f "$loader" ]]; then
  echo "错误：deb 中缺少 bundled loader: opt/qms/usr/lib/glibc-compat/$ld_linux" >&2
  exit 1
fi
chmod +x "$loader" 2>/dev/null || true
if [[ ! -x "$loader" ]]; then
  echo "错误：bundled loader 缺少可执行权限" >&2
  exit 1
fi
if [[ -f "$WORKDIR/extract/opt/qms/usr/lib/libfreetype.so.6" ]]; then
  freetype="$WORKDIR/extract/opt/qms/usr/lib/libfreetype.so.6"
  if objdump -T "$freetype" 2>/dev/null | grep -Fq 'FT_Get_Color_Glyph_Paint' \
    || nm -D --defined-only "$freetype" 2>/dev/null | grep -Fq 'FT_Get_Color_Glyph_Paint'; then
    echo "deb 已内置含 FT_Get_Color_Glyph_Paint 的 libfreetype.so.6。"
  else
    echo "错误：deb 中 libfreetype.so.6 缺少 FT_Get_Color_Glyph_Paint" >&2
    exit 1
  fi
else
  echo "错误：deb 中缺少 usr/lib/libfreetype.so.6" >&2
  exit 1
fi

if [[ -f "$WORKDIR/extract/opt/qms/usr/lib/libgbm.so.1" ]]; then
  gbm="$WORKDIR/extract/opt/qms/usr/lib/libgbm.so.1"
  if objdump -T "$gbm" 2>/dev/null | grep -Fq 'gbm_bo_create_with_modifiers2' \
    || nm -D --defined-only "$gbm" 2>/dev/null | grep -Fq 'gbm_bo_create_with_modifiers2'; then
    echo "deb 已内置含 gbm_bo_create_with_modifiers2 的 libgbm.so.1。"
  else
    echo "错误：deb 中 libgbm.so.1 缺少 gbm_bo_create_with_modifiers2" >&2
    exit 1
  fi
else
  echo "错误：deb 中缺少 usr/lib/libgbm.so.1" >&2
  exit 1
fi

if [[ -x "$WORKDIR/extract/usr/bin/"* ]] 2>/dev/null || find "$WORKDIR/extract/usr/bin" -maxdepth 1 -type f -executable | grep -q .; then
  launcher="$(find "$WORKDIR/extract/usr/bin" -maxdepth 1 -type f -executable | head -n 1)"
  if grep -q 'GDK_BACKEND=x11' "$launcher" && grep -q 'glibc-compat' "$launcher"; then
    echo "启动器包含 X11 与 bundled 运行时配置。"
  else
    echo "错误：启动器缺少麒麟 X11 / glibc-compat 配置" >&2
    exit 1
  fi
else
  echo "错误：deb 启动器结构不完整" >&2
  exit 1
fi

if dpkg-deb -I "$DEB" | grep -q 'libwebkit2gtk-4.1'; then
  echo "警告：deb 仍依赖 libwebkit2gtk-4.1，麒麟终端可能无法安装。" >&2
  exit 1
fi

echo "deb 依赖摘要："
dpkg-deb -f "$DEB" Depends

if dpkg-deb -f "$DEB" Depends | grep -qE 'libwebkit2gtk-4\.(0|1)'; then
  echo "警告：deb 声明了 WebKit 依赖，麒麟终端可能因包名不匹配安装失败。" >&2
  exit 1
fi

echo "验证通过。"
