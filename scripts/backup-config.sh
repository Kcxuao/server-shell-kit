#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/backup-secrets.sh"

user_files=(
  .zshrc .bashrc .gitconfig .vimrc .tmux.conf
  .config/starship.toml
  .config/zsh/server-shell-kit/aliases.zsh
  .config/zsh/plugins/dangerous-command-guard/dangerous-command-guard.plugin.zsh
  .config/zsh/plugins/dangerous-command-guard/impact-guard.plugin.zsh
  .config/zsh/plugins/dangerous-command-guard/impact-guard-analysis.zsh
  .ssh/authorized_keys
)
system_files=(/etc/os-release /etc/timezone /etc/default/locale /etc/apt/sources.list)
shopt -s nullglob
for file in /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/debian.sources; do
  [[ -f "$file" ]] && system_files+=("$file")
done
shopt -u nullglob

backup_config(){
  local bundle="$1" rel source destination file skipped='[]' failed=0
  run_user mkdir -p "$bundle/home" "$bundle/system"
  for rel in "${user_files[@]}"; do
    source="$TARGET_HOME/$rel"
    [[ -f "$source" && ! -L "$source" ]] || continue
    if [[ "${SERVER_SHELL_KIT_BACKUP_STRICT:-0}" == 1 &&
          "${SERVER_SHELL_KIT_BACKUP_SECRETS:-skip}" == skip ]] &&
       backup_secret_config_possible "$source"; then
      printf '配置文件可能包含敏感数据，已跳过：%s\n' "$rel" >&2
      skipped="$(jq -nc --argjson before "$skipped" --arg file "home/$rel" '$before + [$file]')"
      failed=1
      continue
    fi
    destination="$bundle/home/$rel"
    run_user mkdir -p "$(dirname "$destination")"
    run_user cp -p -- "$source" "$destination"
    if [[ "${SERVER_SHELL_KIT_BACKUP_STRICT:-0}" == 1 ]]; then
      run_user chmod 0600 "$destination"
    fi
  done
  for file in "${system_files[@]}"; do
    [[ -f "$file" && ! -L "$file" ]] || continue
    if [[ "${SERVER_SHELL_KIT_BACKUP_STRICT:-0}" == 1 &&
          "${SERVER_SHELL_KIT_BACKUP_SECRETS:-skip}" == skip ]] &&
       backup_secret_config_possible "$file"; then
      printf '系统配置可能包含敏感数据，已跳过：%s\n' "$file" >&2
      skipped="$(jq -nc --argjson before "$skipped" --arg file "system${file#/etc}" '$before + [$file]')"
      failed=1
      continue
    fi
    destination="$bundle/system${file#/etc}"
    run_user mkdir -p "$(dirname "$destination")"
    if [[ -r "$file" ]]; then
      cat -- "$file" | run_user tee "$destination" >/dev/null
    else
      run_root cat -- "$file" | run_user tee "$destination" >/dev/null
    fi
    run_user chmod 0600 "$destination"
  done
  dpkg-query -W -f='${Status} ${binary:Package}\n' |
    awk '$1 == "install" && $2 == "ok" && $3 == "installed" { print $4 }' |
    run_user tee "$bundle/packages.txt" >/dev/null
  if command -v systemctl >/dev/null 2>&1; then
    systemctl list-unit-files --state=enabled --no-legend 2>/dev/null |
      run_user tee "$bundle/enabled-services.txt" >/dev/null || true
  fi
  if [[ "${SERVER_SHELL_KIT_BACKUP_STRICT:-0}" == 1 ]]; then
    jq -nc --argjson skipped "$skipped" '{skipped_sensitive_files:$skipped}' > "$bundle/config-status.json"
  fi
  (( failed == 0 ))
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
  [[ $# == 1 && "$1" == /* ]] || { echo '用法：backup-config.sh 绝对备份目录' >&2; exit 2; }
  backup_config "$1"
fi
