#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

updated=0
update_if_installed(){
  local source="$1" destination="$2" label="$3"
  if [[ -f "$destination" ]]; then
    install_config "$source" "$destination"
    printf '已更新：%s\n' "$label"
    updated=$((updated + 1))
  fi
}

update_if_installed "$REPO_DIR/configs/starship.toml" "$TARGET_HOME/.config/starship.toml" 'Starship 配置'
update_if_installed "$REPO_DIR/configs/aliases.zsh" "$TARGET_HOME/.config/zsh/server-shell-kit/aliases.zsh" '常用 Alias'
guard_dir="$TARGET_HOME/.config/zsh/plugins/dangerous-command-guard"
if [[ -f "$guard_dir/impact-guard.plugin.zsh" ]]; then
  install_config "$REPO_DIR/plugins/dangerous-command-guard.plugin.zsh" "$guard_dir/dangerous-command-guard.plugin.zsh"
  install_config "$REPO_DIR/plugins/impact-guard.plugin.zsh" "$guard_dir/impact-guard.plugin.zsh"
  install_config "$REPO_DIR/plugins/impact-guard-analysis.zsh" "$guard_dir/impact-guard-analysis.zsh"
  printf '已更新：Impact Guard\n'
  updated=$((updated + 1))
else
  update_if_installed "$REPO_DIR/plugins/dangerous-command-guard.plugin.zsh" "$guard_dir/dangerous-command-guard.plugin.zsh" '高危命令保护'
fi
if (( updated == 0 )); then
  echo '未找到已安装的工具配置。请先安装完整环境或在自选组件中安装。'
else
  echo '配置更新完成。重新打开 Zsh 后生效。'
fi
