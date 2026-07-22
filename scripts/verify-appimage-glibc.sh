#!/usr/bin/env bash
# 检查 AppImage 内主程序依赖的最高 GLIBC 符号版本（仅供参考；repack 后应通过 bundled glibc 运行）
set -euo pipefail

APPIMAGE="${1:?用法: $0 <AppImage>}"
if [[ ! -f "$APPIMAGE" ]]; then
  echo "错误：找不到 AppImage: $APPIMAGE" >&2
  exit 1
fi
APPIMAGE="$(readlink -f "$APPIMAGE")"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

chmod +x "$APPIMAGE"
cd "$WORKDIR"
APPIMAGE_EXTRACT_AND_RUN=1 "$APPIMAGE" --appimage-extract >/dev/null

MAIN_BIN="$(find "$WORKDIR/squashfs-root/usr/bin" -maxdepth 1 -type f -executable | head -n 1 || true)"
if [[ -z "$MAIN_BIN" ]]; then
  echo "错误：未找到主程序" >&2
  exit 1
fi

echo "主程序: $MAIN_BIN"
echo "GLIBC 符号版本需求："
objdump -T "$MAIN_BIN" 2>/dev/null | grep -o 'GLIBC_[0-9.]*' | sort -V | uniq | tail -n 5 || true

if [[ -f "$WORKDIR/squashfs-root/usr/lib/glibc-compat/libc.so.6" ]]; then
  echo "已检测到 bundled glibc-compat，可在 glibc 2.31 等旧系统上通过自带运行时启动。"
else
  echo "警告：未检测到 bundled glibc-compat，在 glibc 2.31 系统上可能无法运行。"
fi
