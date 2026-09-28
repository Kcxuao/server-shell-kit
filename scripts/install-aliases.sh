#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
ensure_dir "$TARGET_HOME/.config/zsh/server-shell-kit"
run_root install -m 0644 -o "$TARGET_USER" -g "$TARGET_GROUP" "$REPO_DIR/configs/aliases.zsh" "$TARGET_HOME/.config/zsh/server-shell-kit/aliases.zsh"
ensure_line "$TARGET_HOME/.zshrc" '[[ -f "$HOME/.config/zsh/server-shell-kit/aliases.zsh" ]] && source "$HOME/.config/zsh/server-shell-kit/aliases.zsh"' 'server-shell-kit/aliases.zsh'
echo 'Alias 配置安装完成。'
