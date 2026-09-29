#!/usr/bin/env bash
# 只按文件名和配置键名识别风险，不读取或打印 Secret 的值。
backup_secret_name(){
  local name="${1##*/}"
  case "$1" in
    /etc/shadow|/etc/gshadow|*/.ssh/id_*) return 0 ;;
  esac
  case "$name" in
    .env|.env.*|*.key|*.pem|id_rsa|id_dsa|id_ecdsa|id_ed25519|*.p12|*.pfx|*.jks|*.keystore|.pgpass|.my.cnf|credentials|config.json|auth.json|*secret*|*credential*) return 0 ;;
  esac
  return 1
}

backup_secret_config(){
  grep -Eiq 'password|token|secret|api[_-]?key|private[_-]?key|://[^[:space:]]+:[^[:space:]]+@' -- "$1"
}

backup_secret_config_possible(){
  local status
  if backup_secret_config "$1"; then return 0; else status=$?; fi
  (( status != 1 ))
}

backup_secret_file(){
  local file="$1"
  backup_secret_name "$file" && return 0
  case "$file" in
    *.conf|*.config|*.ini|*.json|*.toml|*.yaml|*.yml|*.properties|*.zshrc|*.bashrc)
      [[ "$(stat -c '%s' -- "$file" 2>/dev/null)" -le 1048576 ]] &&
        backup_secret_config_possible "$file" && return 0
      ;;
  esac
  return 1
}

backup_secret_tree(){
  local source="$1" file
  while IFS= read -r -d '' file; do
    if backup_secret_file "$file"; then
      printf '%s\n' "$file"
    fi
  done < <(find "$source" -xdev -type f -print0)
}

backup_secret_scan(){
  local mode="$1" snapshot="$2" path file volume mountpoint id config_files
  shift 2
  if [[ "$mode" == config || "$mode" == full ]]; then
    source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
    source "$(dirname -- "${BASH_SOURCE[0]}")/backup-config.sh"
    for path in "${user_files[@]}"; do
      file="$TARGET_HOME/$path"
      if [[ -f "$file" && ! -L "$file" ]] &&
         (backup_secret_name "$file" || backup_secret_config_possible "$file"); then
        printf '%s\n' "$file"
      fi
    done
    for file in "${system_files[@]}"; do
      if [[ -f "$file" && ! -L "$file" ]] &&
         (backup_secret_name "$file" || backup_secret_config_possible "$file"); then
        printf '%s\n' "$file"
      fi
    done
  fi
  [[ "$mode" == data || "$mode" == full ]] || return 0
  for path in "$@"; do
    [[ -e "$path" && ! -L "$path" ]] || continue
    backup_secret_tree "$path"
  done
  if [[ -f "$snapshot" ]] &&
     [[ "$(jq -r '.docker.status // "absent"' "$snapshot")" == available ]]; then
    while IFS= read -r volume; do
      [[ -n "$volume" ]] || continue
      mountpoint="$(docker volume inspect --format '{{.Mountpoint}}' "$volume" 2>/dev/null)" || continue
      [[ "$mountpoint" == /* && -d "$mountpoint" ]] || continue
      backup_secret_tree "$mountpoint"
    done < <(jq -r '.docker.volumes[]?.name' "$snapshot")
    while IFS= read -r id; do
      [[ -n "$id" ]] || continue
      config_files="$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.project.config_files" }}' "$id" 2>/dev/null)" || continue
      IFS=',' read -r -a compose_paths <<< "$config_files"
      for file in "${compose_paths[@]}"; do
        if [[ -f "$file" && ! -L "$file" ]] &&
           (backup_secret_name "$file" || backup_secret_config_possible "$file"); then
          printf '%s\n' "$file"
        fi
      done
    done < <(jq -r '.docker.containers[]?.id' "$snapshot")
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]] && (( ${#BASH_SOURCE[@]} == 1 )); then
  [[ $# -ge 2 ]] || exit 2
  backup_secret_scan "$@" | sort -u
fi
