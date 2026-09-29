#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

[[ $# -ge 2 && "$1" == /* ]] || {
  echo '用法：backup-files.sh 绝对备份目录 绝对源路径 [...]' >&2; exit 2;
}
bundle="$1"
shift
mkdir -p -- "$bundle/files"
index=0
failed=0
records='[]'
for requested in "$@"; do
  if [[ "$requested" != /* ]] || [[ -L "$requested" ]] ||
     ! source="$(realpath -e -- "$requested" 2>/dev/null)"; then
    printf '路径无效或是符号链接：%s\n' "$requested" >&2
    failed=1
    continue
  fi
  case "$source" in
    /|/var|/var/lib)
      printf '源路径范围过大，可能包含数据库数据目录：%s\n' "$requested" >&2
      failed=1
      continue
      ;;
  esac
  case "$source/" in
    "$bundle/"*|/var/lib/docker/*|/var/lib/postgresql/*|/var/lib/mysql/*|/var/lib/mariadb/*|/var/lib/redis/*)
      printf '不允许直接归档备份目录或数据库数据目录：%s\n' "$requested" >&2
      failed=1
      continue
      ;;
  esac
  case "$bundle/" in
    "$source/"*)
      printf '源路径包含备份目录，已跳过：%s\n' "$requested" >&2
      failed=1
      continue
      ;;
  esac
  if ! sensitive="$(find "$source" -xdev -type f \( -name '.env' -o -name '.env.*' \
      -o -name '*.key' -o -name '*.pem' -o -name 'id_rsa' -o -name 'id_ed25519' \
      -o -name 'credentials' -o -name 'config.json' -o -name 'PG_VERSION' \
      -o -name 'ibdata1' -o -name 'aria_log_control' -o -name 'dump.rdb' \
      -o -name 'appendonly.aof' \) -print -quit 2>/dev/null)"; then
    printf '无法完整检查目录中的敏感文件：%s\n' "$requested" >&2
    failed=1
    continue
  fi
  if [[ -n "$sensitive" ]]; then
    printf '发现可能包含敏感数据或数据库目录的文件，已跳过：%s\n' "$requested" >&2
    failed=1
    continue
  fi
  index=$((index + 1))
  archive="$bundle/files/$(printf '%03d' "$index").tar.gz"
  if tar --one-file-system -czf "$archive" -C "$(dirname -- "$source")" -- "$(basename -- "$source")"; then
    record="$(jq -nc --arg source "$source" --arg archive "files/$(basename -- "$archive")" \
      '{source:$source,archive:$archive}')"
    records="$(jq -nc --argjson records "$records" --argjson record "$record" '$records + [$record]')"
    printf '%s\t%s\n' "$archive" "$source"
  else
    printf '目录归档失败：%s\n' "$requested" >&2
    rm -f -- "$archive"
    failed=1
  fi
done
printf '%s\n' "$records" > "$bundle/files/paths.json"
(( failed == 0 ))
