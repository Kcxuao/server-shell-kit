#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

run_user rm -rf -- "$TARGET_HOME/.config/zsh/server-shell-kit" "$TARGET_HOME/.config/zsh/plugins/dangerous-command-guard"
if [[ -f "$TARGET_HOME/.zshrc" ]]; then
  temporary="$(run_user mktemp "$TARGET_HOME/.zshrc.server-shell-kit.XXXXXX")"
  trap 'run_user rm -f -- "$temporary"' EXIT
  run_user awk \
    -v aliases='[[ -f "$HOME/.config/zsh/server-shell-kit/aliases.zsh" ]] && source "$HOME/.config/zsh/server-shell-kit/aliases.zsh"' \
    -v guard='[[ -f "$HOME/.config/zsh/plugins/dangerous-command-guard/dangerous-command-guard.plugin.zsh" ]] && source "$HOME/.config/zsh/plugins/dangerous-command-guard/dangerous-command-guard.plugin.zsh"' \
    -v suggestions='[[ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh' \
    -v highlighting='[[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh' \
    -v starship='command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"' \
    '$0 != aliases && $0 != guard && $0 != suggestions && $0 != highlighting && $0 != starship' \
    "$TARGET_HOME/.zshrc" | run_user tee "$temporary" >/dev/null
  run_user chmod --reference="$TARGET_HOME/.zshrc" "$temporary"
  run_user mv -- "$temporary" "$TARGET_HOME/.zshrc"
fi
printf '已移除工具配置。原始备份保留在 *.server-shell-kit.bak；Zsh 和 Starship 软件未卸载。\n'
