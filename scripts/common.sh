#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $EUID -eq 0 ]]; then TARGET_USER="${SUDO_USER:-root}"; else TARGET_USER="$(id -un)"; fi
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
[[ -n "$TARGET_HOME" && "$TARGET_HOME" != / ]] || { echo '无法确定目标用户的 HOME。' >&2; exit 1; }
TARGET_GROUP="$(id -gn "$TARGET_USER")"

run_root(){ if [[ $EUID -eq 0 ]]; then "$@"; else sudo "$@"; fi; }
run_user(){ if [[ $EUID -eq 0 && "$TARGET_USER" != root ]]; then sudo -u "$TARGET_USER" -H "$@"; else "$@"; fi; }
ensure_dir(){ run_user mkdir -p -- "$1"; }
backup_file(){
  local file="$1" backup="$1.server-shell-kit.bak"
  if [[ -f "$file" && ! -e "$backup" ]]; then
    run_user cp -p -- "$file" "$backup"
    printf '已备份：%s\n' "$backup"
  fi
}
ensure_line(){
  local file="$1" line="$2"
  if [[ -f "$file" ]] && grep -Fxq -- "$line" "$file"; then return 0; fi
  backup_file "$file"
  run_user touch -- "$file"
  printf '\n%s\n' "$line" | run_user tee -a "$file" >/dev/null
}
install_config(){
  local source="$1" destination="$2"
  backup_file "$destination"
  run_root install -m 0644 -o "$TARGET_USER" -g "$TARGET_GROUP" "$source" "$destination"
}
