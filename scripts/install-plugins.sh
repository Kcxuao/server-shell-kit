#!/usr/bin/env bash
set -Eeuo pipefail
COMMON_URL="https://raw.githubusercontent.com/${SERVER_SHELL_KIT_OWNER:-Kcxuao}/${SERVER_SHELL_KIT_REPO:-server-shell-kit}/${SERVER_SHELL_KIT_REF:-main}/scripts/common.sh"
TMP="$(mktemp)"; curl -fsSL "$COMMON_URL" -o "$TMP"; source "$TMP"; rm -f "$TMP"
run_root apt-get update
run_root apt-get install -y zsh-autosuggestions zsh-syntax-highlighting
ensure_line "$TARGET_HOME/.zshrc" '[[ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh' 'zsh-autosuggestions.zsh'
ensure_line "$TARGET_HOME/.zshrc" '[[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh' 'zsh-syntax-highlighting.zsh'
echo 'Zsh 自动建议和语法高亮安装完成。'
