#!/usr/bin/env bash
set -Eeuo pipefail
COMMON_URL="https://raw.githubusercontent.com/${SERVER_SHELL_KIT_OWNER:-Kcxuao}/${SERVER_SHELL_KIT_REPO:-server-shell-kit}/${SERVER_SHELL_KIT_REF:-main}/scripts/common.sh"
TMP="$(mktemp)"; curl -fsSL "$COMMON_URL" -o "$TMP"; source "$TMP"; rm -f "$TMP"
ensure_dir "$TARGET_HOME/.config/zsh/server-shell-kit"
TMP_CFG="$(mktemp)"; fetch "$BASE_URL/configs/aliases.zsh" "$TMP_CFG"; run_root install -m 0644 -o "$TARGET_USER" -g "$TARGET_GROUP" "$TMP_CFG" "$TARGET_HOME/.config/zsh/server-shell-kit/aliases.zsh"; rm -f "$TMP_CFG"
ensure_line "$TARGET_HOME/.zshrc" '[[ -f "$HOME/.config/zsh/server-shell-kit/aliases.zsh" ]] && source "$HOME/.config/zsh/server-shell-kit/aliases.zsh"' 'server-shell-kit/aliases.zsh'
echo 'Alias 配置安装完成。'
