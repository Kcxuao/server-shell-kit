#!/usr/bin/env bash
set -Eeuo pipefail
COMMON_URL="https://raw.githubusercontent.com/${SERVER_SHELL_KIT_OWNER:-Kcxuao}/${SERVER_SHELL_KIT_REPO:-server-shell-kit}/${SERVER_SHELL_KIT_REF:-main}/scripts/common.sh"
TMP="$(mktemp)"; curl -fsSL "$COMMON_URL" -o "$TMP"; source "$TMP"; rm -f "$TMP"
command -v apt-get >/dev/null 2>&1 || { echo '当前仅支持 Debian/Ubuntu。'; exit 1; }
run_root apt-get update
run_root apt-get install -y zsh git curl ca-certificates
ZSH_PATH="$(command -v zsh)"
CURRENT="$(getent passwd "$TARGET_USER" | cut -d: -f7)"
if [[ "$CURRENT" != "$ZSH_PATH" ]]; then run_root chsh -s "$ZSH_PATH" "$TARGET_USER"; fi
echo "Zsh 安装完成：$ZSH_PATH"
echo '重新登录 SSH 后默认进入 Zsh。'
