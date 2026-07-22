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
dpkg-deb -x "$DEB" "$WORKDIR/extract"

if [[ -f "$WORKDIR/extract/opt/qms/usr/lib/glibc-compat/libc.so.6" ]]; then
  echo "已检测到 bundled glibc-compat，可在 glibc 2.31 系统上运行。"
else
  echo "错误：deb 中缺少 opt/qms/usr/lib/glibc-compat/libc.so.6" >&2
  exit 1
fi

if [[ -x "$WORKDIR/extract/opt/qms/AppRun" ]] && find "$WORKDIR/extract/usr/bin" -maxdepth 1 -type f -executable | grep -q .; then
  echo "启动器结构正常（/opt/qms/AppRun + /usr/bin 入口）。"
else
  echo "错误：deb 启动器结构不完整" >&2
  exit 1
fi

if dpkg-deb -I "$DEB" | grep -q 'libwebkit2gtk-4.1'; then
  echo "警告：deb 仍依赖 libwebkit2gtk-4.1，麒麟终端可能无法安装。" >&2
  exit 1
fi

echo "deb 依赖摘要："
dpkg-deb -f "$DEB" Depends Recommends

echo "验证通过。"
