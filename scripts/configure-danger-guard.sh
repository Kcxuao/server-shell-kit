#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

config="$TARGET_HOME/.config/zsh/server-shell-kit/danger-guard.conf"
plugin="$TARGET_HOME/.config/zsh/plugins/dangerous-command-guard/dangerous-command-guard.plugin.zsh"
startup='[[ -f "$HOME/.config/zsh/plugins/dangerous-command-guard/dangerous-command-guard.plugin.zsh" ]] && source "$HOME/.config/zsh/plugins/dangerous-command-guard/dangerous-command-guard.plugin.zsh"'
case "${1:-}" in
  status)
    if [[ ! -f "$plugin" ]] || [[ ! -f "$TARGET_HOME/.zshrc" ]] || ! grep -Fxq -- "$startup" "$TARGET_HOME/.zshrc"; then
      echo 'Danger Guard 当前：未安装'
    elif [[ -f "$config" ]] && grep -Fxq 'enabled=0' "$config"; then
      echo 'Danger Guard 当前：已禁用'
    else
      echo 'Danger Guard 当前：已启用'
    fi
    ;;
  enable|disable)
    if [[ "$1" == enable ]]; then
      bash "$REPO_DIR/scripts/install-danger-guard.sh"
      value=1
    else
      if [[ ! -f "$plugin" ]]; then
        echo 'Danger Guard 尚未安装。'
        exit 0
      fi
      bash "$REPO_DIR/scripts/install-danger-guard.sh"
      value=0
    fi
    ensure_dir "${config%/*}"
    backup_file "$config"
    printf 'enabled=%s\n' "$value" | run_user tee "$config" >/dev/null
    run_user chmod 600 "$config"
    printf 'Danger Guard 已%s，重新打开 Zsh 后生效。\n' "$([[ "$value" == 1 ]] && echo 启用 || echo 禁用)"
    ;;
  *) echo '用法：configure-danger-guard.sh status|enable|disable' >&2; exit 2 ;;
esac
