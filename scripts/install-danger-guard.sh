#!/usr/bin/env bash
set -Eeuo pipefail
COMMON_URL="https://raw.githubusercontent.com/${SERVER_SHELL_KIT_OWNER:-Kcxuao}/${SERVER_SHELL_KIT_REPO:-server-shell-kit}/${SERVER_SHELL_KIT_REF:-main}/scripts/common.sh"
TMP="$(mktemp)"; curl -fsSL "$COMMON_URL" -o "$TMP"; source "$TMP"; rm -f "$TMP"
DIR="$TARGET_HOME/.config/zsh/plugins/dangerous-command-guard"; ensure_dir "$DIR"
TMP_PLUGIN="$(mktemp)"; fetch "$BASE_URL/plugins/dangerous-command-guard.plugin.zsh" "$TMP_PLUGIN"; run_root install -m 0644 -o "$TARGET_USER" -g "$TARGET_GROUP" "$TMP_PLUGIN" "$DIR/dangerous-command-guard.plugin.zsh"; rm -f "$TMP_PLUGIN"
ensure_line "$TARGET_HOME/.zshrc" '[[ -f "$HOME/.config/zsh/plugins/dangerous-command-guard/dangerous-command-guard.plugin.zsh" ]] && source "$HOME/.config/zsh/plugins/dangerous-command-guard/dangerous-command-guard.plugin.zsh"' 'dangerous-command-guard.plugin.zsh'
echo '高危命令保护安装完成。重新打开 Zsh 后生效。'
