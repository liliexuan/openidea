#!/usr/bin/env bash
# =============================================================================
# sync-upstream.sh — 将 OpenIDEA 官方上游同步到本地、CNB 与 GitHub fork
#
# 仓库拓扑（本机约定）：
#   push   -> cnb    (codingcn.cn/openidea)       默认推送目标
#   pull   -> origin (github fork liliexuan/openidea)  同步源
#   fetch  -> upstream (l0ng-ai/openidea)         官方只读主干
#
# 用法：
#   ./sync-upstream.sh            # 快进同步；若本地有独有提交(会分叉)则提示并退出
#   ./sync-upstream.sh --rebase   # 分叉时，把本地独有提交 rebase 到上游之上(推荐日常)
#   ./sync-upstream.sh --ff-only  # 仅允许快进，分叉直接失败
#
# 说明：
#   * 干净时做 fast-forward，本地独有提交会被重放在最新上游之上(线性历史，
#     比 merge 更少冲突)。
#   * rebase 中途冲突会停下，按提示解决后 git add <file> && git rebase --continue。
#   * 想放弃本次同步(rebase 过程中)：git rebase --abort。
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"

# GitHub 走用户代理；CNB 国内直连。若要改代理，改这一行即可。
GH_HTTP_PROXY="http://172.17.20.143:3128"
GH_PROXY_ARGS=(-c "http.proxy=$GH_HTTP_PROXY" -c "https.proxy=$GH_HTTP_PROXY")

MODE=auto
for a in "$@"; do
  case "$a" in
    --rebase) MODE=rebase ;;
    --ff-only) MODE=ff ;;
    *) echo "未知参数: $a（支持 --rebase / --ff-only）" >&2; exit 2 ;;
  esac
done

echo "==> 拉取上游/同步源(经代理)/目标(直连)"
git "${GH_PROXY_ARGS[@]}" fetch --prune upstream
git "${GH_PROXY_ARGS[@]}" fetch --prune origin
git fetch --prune cnb || true

behind=$(git rev-list --count HEAD..upstream/main 2>/dev/null || echo 0)
ahead=$(git rev-list --count upstream/main..HEAD 2>/dev/null || echo 0)
echo "   落后上游 ${behind} 提交, 本地独有 ${ahead} 提交"

if [ "$behind" -eq 0 ]; then
  echo "   已是最新，无需更新"
elif [ "$ahead" -eq 0 ]; then
  echo "==> 快进合并 upstream/main"
  git merge --ff-only upstream/main
else
  echo "!! 本地有 ${ahead} 个独有提交，且上游前进 ${behind} 个，将产生分叉"
  case "$MODE" in
    rebase)
      echo "==> 把本地独有提交 rebase 到最新上游之上："
      git log --oneline upstream/main..HEAD
      if ! git rebase upstream/main; then
        cat <<'EOF'
!! rebase 冲突，已停在此处。请手动解决后：
     git add <file>        # 逐个标记已解决
     git rebase --continue # 继续
   如需放弃本次同步：
     git rebase --abort
EOF
        exit 1
      fi
      ;;
    *)
      cat <<'EOF'
!! 检测到分叉，本脚本已暂停(避免在不了解本地改动时强推)。
   建议处理：
     1. git status          确认本地改动都在 feature/已提交
     2. ./sync-upstream.sh --rebase   重放本地提交到最新上游
     3. 或先提交到单独分支，再手动合并
EOF
      exit 1
      ;;
  esac
fi

echo "==> 推送到 CNB (默认目标)"
git push cnb HEAD:main

echo "==> 推送到 GitHub fork (origin)"
git "${GH_PROXY_ARGS[@]}" push origin HEAD:main

echo "==> 完成：HEAD=$(git rev-parse --short HEAD)"