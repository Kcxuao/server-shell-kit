#!/usr/bin/env bash
set -Eeuo pipefail
TARGET_USER="${SUDO_USER:-$USER}"; TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
rm -rf "$TARGET_HOME/.config/zsh/server-shell-kit" "$TARGET_HOME/.config/zsh/plugins/dangerous-command-guard"
if [[ -f "$TARGET_HOME/.zshrc" ]]; then
  sed -i '/server-shell-kit\/aliases.zsh/d;/dangerous-command-guard.plugin.zsh/d;/zsh-autosuggestions.zsh/d;/zsh-syntax-highlighting.zsh/d;/starship init zsh/d' "$TARGET_HOME/.zshrc"
fi
echo '已移除 Server Shell Kit 配置。Zsh/Starship 软件本身未卸载。'
