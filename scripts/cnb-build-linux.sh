#!/usr/bin/env bash
# =============================================================================
# cnb-build-linux.sh — 在 CNB 云构建容器内编译 OpenIDEA Linux 安装包
#
# 供 .cnb.yml 的 tag_push 流水线调用（镜像: bring/environment/allinone）。
# 构建命令对齐上游 release.yml 的 Linux 分支。
#
# 产物: src-tauri/target/release/bundle/{deb,appimage,rpm}/*
# =============================================================================
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "==> 安装 Tauri Linux 系统依赖（对齐上游 release.yml）"
apt-get update
apt-get install -y \
  libwebkit2gtk-4.1-dev \
  libayatana-appindicator3-dev \
  librsvg2-dev \
  libxdo-dev \
  libssl-dev \
  patchelf

echo "==> 确保 Rust stable（OpenIDEA 需要 edition2024 / Rust≥1.96）"
rustup update stable || rustup toolchain install stable
rustup default stable

echo "==> 准备 pnpm (OpenIDEA 用 pnpm 11)"
npm install -g pnpm@11

echo "==> 安装前端依赖（冻结锁文件）并构建"
pnpm install --frozen-lockfile

echo "==> 构建 Linux 安装包 (deb/appimage/rpm) + 前端"
pnpm tauri build --bundles deb,appimage,rpm

echo "==> 产物清单"
ls -laR src-tauri/target/release/bundle/