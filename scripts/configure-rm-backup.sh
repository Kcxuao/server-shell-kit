#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

config="$TARGET_HOME/.config/zsh/server-shell-kit/rm-backup.conf"
state=1
if [[ -f "$config" ]] && grep -Fxq 'enabled=0' "$config"; then state=0; fi
printf '\nrm -rf 自动备份当前：%s\n' "$([[ "$state" == 1 ]] && echo 已开启 || echo 已关闭)"
printf '1  开启（默认）\n2  关闭\n0  返回\n选择操作：'
IFS= read -r choice || exit 0
case "$choice" in
  1) value=1 ;;
  2) value=0 ;;
  0) exit 0 ;;
  *) echo '无效选项。'; exit 1 ;;
esac
ensure_dir "${config%/*}"
backup_file "$config"
printf 'enabled=%s\n' "$value" | run_user tee "$config" >/dev/null
run_user chmod 600 "$config"
printf 'rm -rf 自动备份已%s，重新打开 Zsh 后生效。\n' "$([[ "$value" == 1 ]] && echo 开启 || echo 关闭)"
