#!/usr/bin/env bash
set -Eeuo pipefail
COMMON_URL="https://raw.githubusercontent.com/${SERVER_SHELL_KIT_OWNER:-Kcxuao}/${SERVER_SHELL_KIT_REPO:-server-shell-kit}/${SERVER_SHELL_KIT_REF:-main}/scripts/common.sh"
TMP="$(mktemp)"; curl -fsSL "$COMMON_URL" -o "$TMP"; source "$TMP"; rm -f "$TMP"
if ! command -v starship >/dev/null 2>&1; then curl -sS https://starship.rs/install.sh | sh -s -- -y; fi
ensure_dir "$TARGET_HOME/.config"
TMP_CFG="$(mktemp)"; fetch "$BASE_URL/configs/starship.toml" "$TMP_CFG"; run_root install -m 0644 -o "$TARGET_USER" -g "$TARGET_GROUP" "$TMP_CFG" "$TARGET_HOME/.config/starship.toml"; rm -f "$TMP_CFG"
ensure_line "$TARGET_HOME/.zshrc" 'command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"' 'starship init zsh'
echo 'Starship 安装完成。'
