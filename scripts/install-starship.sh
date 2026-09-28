#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
if ! command -v starship >/dev/null 2>&1; then curl -sS https://starship.rs/install.sh | sh -s -- -y; fi
ensure_dir "$TARGET_HOME/.config"
run_root install -m 0644 -o "$TARGET_USER" -g "$TARGET_GROUP" "$REPO_DIR/configs/starship.toml" "$TARGET_HOME/.config/starship.toml"
ensure_line "$TARGET_HOME/.zshrc" 'command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"' 'starship init zsh'
echo 'Starship 安装完成。'
