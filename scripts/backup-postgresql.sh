#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

[[ $# -ge 4 && "$1" == /* ]] || {
  echo '用法：backup-postgresql.sh 绝对备份目录 system|docker:容器 数据库用户 数据库名 [...]' >&2; exit 2;
}
bundle="$1" source_type="$2" database_user="$3"
shift 3
[[ "$database_user" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]] || { echo '数据库用户名称无效。' >&2; exit 2; }
case "$source_type" in
  system)
    command -v pg_dump >/dev/null 2>&1 || { echo '未找到 pg_dump。' >&2; exit 1; }
    command -v pg_dumpall >/dev/null 2>&1 || { echo '未找到 pg_dumpall。' >&2; exit 1; }
    ;;
  docker:*)
    container="${source_type#docker:}"
    [[ "$container" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || { echo '容器名称无效。' >&2; exit 2; }
    command -v docker >/dev/null 2>&1 || { echo '未找到 Docker。' >&2; exit 1; }
    ;;
  *) echo '数据库来源无效。' >&2; exit 2 ;;
esac

mkdir -p -- "$bundle/databases/postgresql"
results='[]'
failed=0
globals_file='databases/postgresql/globals.sql'
globals_temporary="$bundle/$globals_file.partial"
if [[ "$source_type" == system ]]; then
  if PGCONNECT_TIMEOUT=5 pg_dumpall -w -U "$database_user" --globals-only > "$globals_temporary"; then
    globals_status=SUCCESS
  else globals_status=FAILED; failed=1; fi
elif docker exec -i "$container" pg_dumpall -w -U "$database_user" --globals-only > "$globals_temporary"; then
  globals_status=SUCCESS
else
  globals_status=FAILED; failed=1
fi
if [[ "$globals_status" == SUCCESS ]]; then
  mv -- "$globals_temporary" "$bundle/$globals_file"
  globals_file_json="$(jq -nc --arg file "$globals_file" '$file')"
else
  rm -f -- "$globals_temporary"
  globals_file_json=null
fi
index=0
for database in "$@"; do
  [[ -n "$database" && "$database" != -* ]] || { echo '数据库名称无效。' >&2; exit 2; }
  index=$((index + 1))
  file="databases/postgresql/$(printf '%03d' "$index").dump"
  temporary="$bundle/$file.partial"
  if [[ "$source_type" == system ]]; then
    if PGCONNECT_TIMEOUT=5 pg_dump -w -U "$database_user" -Fc -- "$database" > "$temporary"; then
      state=SUCCESS
    else state=FAILED; failed=1; fi
  elif docker exec -i "$container" pg_dump -w -U "$database_user" -Fc -- "$database" > "$temporary"; then
    state=SUCCESS
  else
    state=FAILED; failed=1
  fi
  if [[ "$state" == SUCCESS ]]; then
    mv -- "$temporary" "$bundle/$file"
    file_json="$(jq -nc --arg file "$file" '$file')"
  else
    rm -f -- "$temporary"
    file_json=null
  fi
  result="$(jq -nc --arg name "$database" --arg status "$state" --argjson file "$file_json" \
    '{name:$name,status:$status,file:$file}')"
  results="$(jq -nc --argjson results "$results" --argjson result "$result" '$results + [$result]')"
done
jq -nc --arg status "$globals_status" --argjson file "$globals_file_json" \
  --argjson databases "$results" \
  '{globals:{status:$status,file:$file},databases:$databases}' \
  > "$bundle/databases/postgresql/index.json"
(( failed == 0 ))
