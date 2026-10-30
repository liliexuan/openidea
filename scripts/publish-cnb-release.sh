#!/usr/bin/env bash
# =============================================================================
# publish-cnb-release.sh — 在【本机构建机】构建 OpenIDEA 并发布到 CNB Release
#
# 用途：CNB 云构建是 Linux 容器，产不出 Windows(.msi/.exe) 安装包。
#       本脚本在 Windows/macOS 本机执行 `pnpm tauri build`（产出当前平台的
#       安装包），再用 cnb CLI 创建 Release 并把产物上传为附件，供下载。
#
# 用法：
#   ./scripts/publish-cnb-release.sh                    # 构建 msi/exe 并发布
#   ./scripts/publish-cnb-release.sh --tag v0.1.28       # 指定 tag（默认取最近 tag）
#   ./scripts/publish-cnb-release.sh --no-build          # 跳过构建，只上传已有产物
#   ./scripts/publish-cnb-release.sh --repo <org>/<repo> # 指定仓库（默认 codingcn.cn/openidea）
#
# 前置：已 `cnb login`；PowerShell/cmd 或 Git Bash 均可；python3 或 grep 用于解析响应。
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="codingcn.cn/openidea"
TAG=""
DO_BUILD=1

for a in "$@"; do
  case "$a" in
    --tag) TAG_NEXT=1 ;;
    --no-build) DO_BUILD=0 ;;
    --repo) REPO_NEXT=1 ;;
    *) 
      [ "${TAG_NEXT:-0}" = 1 ] && { TAG="$a"; TAG_NEXT=0; continue; }
      [ "${REPO_NEXT:-0}" = 1 ] && { REPO="$a"; REPO_NEXT=0; continue; }
      echo "未知参数: $a" >&2; exit 2 ;;
  esac
done

[ -z "$TAG" ] && TAG="$(git tag --sort=-version:refname | head -1 || true)"
[ -z "$TAG" ] && { echo "未指定 --tag 且无可用 tag" >&2; exit 1; }
APP_VERSION="v$(jq -r .version src-tauri/tauri.conf.json 2>/dev/null || echo '?')"
[ "$APP_VERSION" != "?" ] && [ "$APP_VERSION" != "$TAG" ] && \
  echo "警告: tag $TAG 与 tauri.conf.json 版本 $APP_VERSION 不一致" >&2

# ---------- 1. 构建当前平台安装包 ----------
if [ "$DO_BUILD" = 1 ]; then
  echo "==> pnpm build (当前平台)"
  pnpm install
  pnpm tauri build
fi

# 收集产物：Windows 优先，其次通用 bundle
BUNDLE=src-tauri/target/release/bundle
ASSETS=()
[ -d "$BUNDLE/nsis" ]     && mapfile -t _a < <(find "$BUNDLE/nsis" -name "*.exe");       ASSETS+=("${_a[@]:-}")
[ -d "$BUNDLE/msi" ]      && mapfile -t _b < <(find "$BUNDLE/msi" -name "*.msi");        ASSETS+=("${_b[@]:-}")
[ -d "$BUNDLE/dmg" ]      && mapfile -t _c < <(find "$BUNDLE/dmg" -name "*.dmg");        ASSETS+=("${_c[@]:-}")
[ -d "$BUNDLE/appimage" ] && mapfile -t _d < <(find "$BUNDLE/appimage" -name "*.AppImage"); ASSETS+=("${_d[@]:-}")
[ ${#ASSETS[@]} -eq 0 ] && { echo "!! bundle 目录为空，没有可上传产物" >&2; ls "$BUNDLE" 2>/dev/null || true; exit 1; }

# ---------- 2. 创建或复用 Release ----------
RELEASE_ID="$(cnb releases get-release-by-tag --repo "$REPO" --tag "$TAG" 2>/dev/null \
  | grep -o '"id"[[:space:]]*:[[:space:]]*[0-9]*' | grep -o '[0-9]*$' | head -1 || true)"
if [ -z "$RELEASE_ID" ]; then
  echo "==> 创建 Release $TAG"
  cnb releases post-release \
      --repo "$REPO" --tag-name "$TAG" \
      --name "OpenIDEA $TAG" --make-latest true \
      --body "OpenIDEA $TAG。构建产物见下方附件。" \
      > /tmp/cnb_release.json
  RELEASE_ID="$(grep -o '"id"[[:space:]]*:[[:space:]]*[0-9]*' /tmp/cnb_release.json | grep -o '[0-9]*$' | head -1)"
fi
[ -z "$RELEASE_ID" ] && { echo "!! 无法获取 release id，请检查 cnb login 与 --repo" >&2; exit 1; }
echo "     release-id = $RELEASE_ID"

# ---------- 3. 逐个上传附件 ----------
for f in "${ASSETS[@]}"; do
  name="$(basename "$f")"
  size="$(stat -c %s "$f" 2>/dev/null || stat -f %z "$f")"
  echo "==> 上传 $name ($size B)"
  url="$(cnb releases post-release-asset-upload-url \
      --repo "$REPO" --release-id "$RELEASE_ID" --asset-name "$name" --size "$size" \
      | grep -oE 'https?://[^" ]+' | head -1)"
  [ -z "$url" ] && { echo "!! 获取上传地址失败($name)" >&2; continue; }
  curl -sS -X PUT --upload-file "$f" "$url" -o /dev/null
  echo "     已上传: $name"
done

echo "==> 完成：CNB Release $TAG 已更新（$REPO）"
echo "    访问: https://cnb.cool/$REPO/-/releases"