#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
run_root apt-get update
run_root apt-get install -y zsh-autosuggestions zsh-syntax-highlighting
ensure_line "$TARGET_HOME/.zshrc" '[[ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh' 'zsh-autosuggestions.zsh'
ensure_line "$TARGET_HOME/.zshrc" '[[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh' 'zsh-syntax-highlighting.zsh'
echo 'Zsh 自动建议和语法高亮安装完成。'
