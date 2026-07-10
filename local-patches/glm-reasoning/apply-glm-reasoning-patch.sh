#!/usr/bin/env bash
#
# apply-glm-reasoning-patch.sh
#
# 为 oh-my-openagent 的 dist/index.js 添加 GLM 族 reasoningEfforts 支持
# 使得 GLM-5.2 的 reasoning_effort: "max" 参数能到达 API
#
# 用法:
#   ./apply-glm-reasoning-patch.sh          # 应用 patch
#   ./apply-glm-reasoning-patch.sh --check   # 仅检查是否已 patch（不修改）
#   ./apply-glm-reasoning-patch.sh --revert  # 从备份恢复原始文件
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 从 opencode.jsonc 自动提取当前 oh-my-openagent 版本号
extract_omo_version() {
  local config_file="$HOME/.config/opencode/opencode.jsonc"
  if [ ! -f "$config_file" ]; then
    echo "ERROR"
    return 1
  fi
  # 提取 oh-my-openagent@<version> 中的版本号
  local ver
  ver=$(grep -oP 'oh-my-openagent@\K(latest|[0-9.]+)' "$config_file")
  if [ -z "$ver" ]; then
    echo "ERROR"
    return 1
  fi
  echo "$ver"
}


# 从package.json 自动提取当前 oh-my-openagent 版本号
extract_omo_real_version() {
  local package_file=$HOME/.cache/opencode/packages/oh-my-openagent\@latest/package.json
  if [ ! -f "$package_file" ]; then
    echo "ERROR"
    return 1
  fi
  # 提取 oh-my-openagent@latest/package.json 中的版本号
  local ver
  ver=$(grep -oP '"oh-my-openagent":\s*"\^?\K[0-9.]+' "$package_file")
  if [ -z "$ver" ]; then
    echo "ERROR"
    return 1
  fi
  echo "$ver"
}


OMO_VERSION=$(extract_omo_version || true)
if [ "$OMO_VERSION" = "latest" ]; then
  OMO_REAL_VERSION=$(extract_omo_real_version || true)
  else
  OMO_REAL_VERSION=OMO_VERSION
fi
if [ "$OMO_VERSION" = "ERROR" ] || [ -z "$OMO_VERSION" ]; then
  echo "ERROR: 无法从 opencode.jsonc 提取 oh-my-openagent 版本号"
  exit 1
fi

echo "Detected oh-my-openagent version: $OMO_VERSION"

# 根据版本号定位 dist/index.js
OPENCODE_DIST="$HOME/.cache/opencode/packages/oh-my-openagent@${OMO_VERSION}/node_modules/oh-my-openagent/dist/index.js"

# bun cache 目录：优先环境变量 BUN_INSTALL_CACHE_DIR，回退默认 ~/.bun/install/cache
BUN_CACHE_DIR="${BUN_INSTALL_CACHE_DIR:-$HOME/.bun/install/cache}"
# bun cache 中的路径格式: oh-my-openagent@<ver>@@<registry>@@@<n>，用 glob 匹配
BUN_DIST=$(ls -1 "$BUN_CACHE_DIR"/oh-my-openagent@${OMO_REAL_VERSION}@@*/dist/index.js 2>/dev/null | head -1 || true)

# patch 前的原始代码（唯一匹配）
OLD_CODE='    family: "glm",
    includes: ["glm"],
    variants: ["low", "medium", "high"]
  },'

# patch 后的代码
NEW_CODE='    family: "glm",
    includes: ["glm"],
    variants: ["low", "medium", "high", "max"],
    reasoningEfforts: ["high", "max"],
    reasoningEffortAliases: {
      low: "high",
      medium: "high",
      xhigh: "max",
    },
  },'

MODE="${1:-apply}"

patch_file() {
  local file="$1"
  local label="$2"

  if [ ! -f "$file" ]; then
    echo "  [$label] SKIP: file not found ($file)"
    return 0
  fi

  # 检查是否已经 patch（避免 pipefail+grep -q 的 SIGPIPE 问题）
  local a3_output
  a3_output=$(grep -A3 'family: "glm",$' "$file" 2>/dev/null || true)
  if echo "$a3_output" | grep -q '"max"' && \
     grep -q 'reasoningEfforts: \["high", "max"\]' "$file" 2>/dev/null; then
    echo "  [$label] ALREADY PATCHED"
    return 0
  fi

  # 检查是否官方已修复（GLM 族已有 reasoningEfforts 但不是我们 patch 的格式）
  if echo "$a3_output" | grep -q 'reasoningEfforts'; then
    echo "  [$label] OFFICIAL FIX DETECTED: GLM family already has reasoningEfforts, patch not needed"
    return 0
  fi

  # 检查原始代码是否存在（用 GLM 族上下文精确匹配，避免误匹配 minimax/kimi 族）
  # 注意：不能用管道 grep -A2 ... | grep -q ... —— pipefail+grep -q SIGPIPE 会误报
  local glm_a2
  glm_a2=$(grep -A2 'family: "glm",$' "$file" 2>/dev/null || true)
  if ! echo "$glm_a2" | grep -q 'variants: \["low", "medium", "high"\]'; then
    echo "  [$label] WARNING: Original GLM pattern not found. File structure may have changed."
    return 1
  fi

  if [ "$MODE" = "--check" ]; then
    echo "  [$label] NOT PATCHED (check mode, skipping)"
    return 0
  fi

  # 备份原始文件（文件名含版本号，避免版本升级后混淆）
  local backup="$SCRIPT_DIR/index.js.${label}.${OMO_REAL_VERSION}.original"
  if [ ! -f "$backup" ]; then
    cp "$file" "$backup"
    echo "  [$label] Backup saved: $(basename "$backup")"
  fi

  # 应用 patch
  python3 -c "
import sys
with open('$file', 'r') as f:
    content = f.read()
old = '''$OLD_CODE'''
new = '''$NEW_CODE'''
count = content.count(old)
if count != 1:
    print(f'  [$label] ERROR: pattern found {count} times, expected 1', file=sys.stderr)
    sys.exit(1)
patched = content.replace(old, new)
with open('$file', 'w') as f:
    f.write(patched)
print(f'  [$label] PATCHED')
"
}

revert_file() {
  local file="$1"
  local label="$2"
  local backup="$SCRIPT_DIR/index.js.${label}.${OMO_REAL_VERSION}.original"

  if [ ! -f "$backup" ]; then
    echo "  [$label] ERROR: backup not found ($backup)"
    return 1
  fi

  cp "$backup" "$file"
  echo "  [$label] REVERTED from backup"
}

echo "=== GLM Reasoning Patch ==="
echo "Mode: $MODE"
echo ""

case "$MODE" in
  --check)
    patch_file "$OPENCODE_DIST" "opencode-cache"
    if [ -n "$BUN_DIST" ]; then
      patch_file "$BUN_DIST" "bun-cache"
    else
      echo "  [bun-cache] SKIP: no matching version in bun cache"
    fi
    echo ""
    echo "Check complete."
    ;;
  --revert)
    revert_file "$OPENCODE_DIST" "opencode-cache"
    if [ -n "$BUN_DIST" ]; then
      revert_file "$BUN_DIST" "bun-cache"
    fi
    echo ""
    echo "Revert complete."
    ;;
  apply|"")
    patch_file "$OPENCODE_DIST" "opencode-cache"
    if [ -n "$BUN_DIST" ]; then
      patch_file "$BUN_DIST" "bun-cache"
    else
      echo "  [bun-cache] SKIP: no matching version in bun cache"
    fi
    echo ""
    echo "Patch complete."
    echo ""
    echo "To verify: bun run $SCRIPT_DIR/verify-patch.js"
    ;;
  *)
    echo "Unknown mode: $MODE"
    echo "Usage: $0 [--check|--revert]"
    exit 1
    ;;
esac
