#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
DIR="$TARGET_HOME/.config/zsh/plugins/dangerous-command-guard"; ensure_dir "$DIR"
run_root install -m 0644 -o "$TARGET_USER" -g "$TARGET_GROUP" "$REPO_DIR/plugins/dangerous-command-guard.plugin.zsh" "$DIR/dangerous-command-guard.plugin.zsh"
ensure_line "$TARGET_HOME/.zshrc" '[[ -f "$HOME/.config/zsh/plugins/dangerous-command-guard/dangerous-command-guard.plugin.zsh" ]] && source "$HOME/.config/zsh/plugins/dangerous-command-guard/dangerous-command-guard.plugin.zsh"' 'dangerous-command-guard.plugin.zsh'
echo '高危命令保护安装完成。重新打开 Zsh 后生效。'
