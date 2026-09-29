#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

config="$TARGET_HOME/.config/zsh/server-shell-kit/danger-guard.conf"
plugin="$TARGET_HOME/.config/zsh/plugins/dangerous-command-guard/impact-guard.plugin.zsh"
library="$TARGET_HOME/.config/zsh/plugins/dangerous-command-guard/dangerous-command-guard.plugin.zsh"
startup='[[ -f "$HOME/.config/zsh/plugins/dangerous-command-guard/impact-guard.plugin.zsh" ]] && source "$HOME/.config/zsh/plugins/dangerous-command-guard/impact-guard.plugin.zsh"'
case "${1:-}" in
  status)
    if [[ ! -f "$library" ]] || [[ ! -f "$TARGET_HOME/.zshrc" ]] || ! grep -Fxq -- "$startup" "$TARGET_HOME/.zshrc"; then
      echo 'Impact Guard 当前：未安装'
    elif [[ -f "$config" ]] && grep -Fxq 'enabled=0' "$config"; then
      echo 'Impact Guard 当前：已禁用'
    elif ! run_user zsh -ic 'command -v dcg >/dev/null && command -v jq >/dev/null' </dev/null >/dev/null 2>&1; then
      echo 'Impact Guard 当前：缺少外部 dcg 或 jq'
    else
      echo 'Impact Guard 当前：已启用'
    fi
    ;;
  enable|disable)
    if [[ "$1" == enable ]]; then
      bash "$REPO_DIR/scripts/install-danger-guard.sh"
      value=1
    else
      if [[ ! -f "$library" ]] && [[ ! -f "$plugin" ]]; then
        echo 'Danger Guard 尚未安装。'
        exit 0
      fi
      value=0
    fi
    ensure_dir "${config%/*}"
    backup_file "$config"
    printf 'enabled=%s\n' "$value" | run_user tee "$config" >/dev/null
    run_user chmod 600 "$config"
    printf 'Impact Guard 已%s，重新打开 Zsh 后生效。\n' "$([[ "$value" == 1 ]] && echo 启用 || echo 禁用)"
    ;;
  *) echo '用法：configure-danger-guard.sh status|enable|disable' >&2; exit 2 ;;
esac
