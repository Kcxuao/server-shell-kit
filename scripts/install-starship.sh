#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
if ! run_user sh -c 'command -v starship >/dev/null 2>&1'; then
  installer="$(mktemp)"
  trap 'rm -f -- "$installer"' EXIT
  curl -fsSL --retry 3 --connect-timeout 10 --max-time 120 -o "$installer" https://starship.rs/install.sh
  run_root sh "$installer" -y
fi
ensure_dir "$TARGET_HOME/.config"
install_config "$REPO_DIR/configs/starship.toml" "$TARGET_HOME/.config/starship.toml"
ensure_line "$TARGET_HOME/.zshrc" 'command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"' 'starship init zsh'
echo 'Starship 安装完成。'
