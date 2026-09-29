#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
if ! run_user zsh -ic 'command -v dcg >/dev/null && command -v jq >/dev/null' </dev/null >/dev/null 2>&1; then
  echo 'Impact Guard 需要目标用户可调用外部 dcg 和 jq；未切换启动入口。' >&2
  exit 1
fi
DIR="$TARGET_HOME/.config/zsh/plugins/dangerous-command-guard"; ensure_dir "$DIR"
install_config "$REPO_DIR/plugins/dangerous-command-guard.plugin.zsh" "$DIR/dangerous-command-guard.plugin.zsh"
install_config "$REPO_DIR/plugins/impact-guard.plugin.zsh" "$DIR/impact-guard.plugin.zsh"
install_config "$REPO_DIR/plugins/impact-guard-analysis.zsh" "$DIR/impact-guard-analysis.zsh"
old='[[ -f "$HOME/.config/zsh/plugins/dangerous-command-guard/dangerous-command-guard.plugin.zsh" ]] && source "$HOME/.config/zsh/plugins/dangerous-command-guard/dangerous-command-guard.plugin.zsh"'
new='[[ -f "$HOME/.config/zsh/plugins/dangerous-command-guard/impact-guard.plugin.zsh" ]] && source "$HOME/.config/zsh/plugins/dangerous-command-guard/impact-guard.plugin.zsh"'
if [[ -f "$TARGET_HOME/.zshrc" ]] && { grep -Fxq -- "$old" "$TARGET_HOME/.zshrc" || grep -Fxq -- "$new" "$TARGET_HOME/.zshrc"; }; then
  backup_file "$TARGET_HOME/.zshrc"
  temporary="$(run_user mktemp "$TARGET_HOME/.zshrc.server-shell-kit.XXXXXX")"
  run_user awk -v old="$old" -v new="$new" '($0 == old || $0 == new) {if (!done++) print new; next} {print}' "$TARGET_HOME/.zshrc" | run_user tee "$temporary" >/dev/null
  run_user chmod --reference="$TARGET_HOME/.zshrc" "$temporary"
  run_user mv -- "$temporary" "$TARGET_HOME/.zshrc"
else
  ensure_line "$TARGET_HOME/.zshrc" "$new" 'impact-guard.plugin.zsh'
fi
echo 'Impact Guard 安装完成。重新打开 Zsh 后生效。'
