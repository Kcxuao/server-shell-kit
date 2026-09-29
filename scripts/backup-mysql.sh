#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

[[ $# -ge 4 && "$1" == /* ]] || {
  echo '用法：backup-mysql.sh 绝对备份目录 system|docker:容器 数据库用户 数据库名 [...]' >&2; exit 2;
}
bundle="$1" source_type="$2" database_user="$3"
shift 3
[[ "$database_user" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]] || { echo '数据库用户名称无效。' >&2; exit 2; }
for database in "$@"; do
  [[ "$database" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || { echo '数据库名称无效。' >&2; exit 2; }
done
case "$source_type" in
  system)
    command -v mysqldump >/dev/null 2>&1 || { echo '未找到 mysqldump。' >&2; exit 1; }
    ;;
  docker:*)
    container="${source_type#docker:}"
    [[ "$container" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || { echo '容器名称无效。' >&2; exit 2; }
    command -v docker >/dev/null 2>&1 || { echo '未找到 Docker。' >&2; exit 1; }
    ;;
  *) echo '数据库来源无效。' >&2; exit 2 ;;
esac

mkdir -p -- "$bundle/databases/mysql"
temporary="$bundle/databases/mysql/databases.sql.partial"
file="$bundle/databases/mysql/databases.sql"
options=(--user="$database_user" --single-transaction --quick --routines --events --triggers --databases)
if [[ "$source_type" == system ]]; then
  if mysqldump "${options[@]}" "$@" > "$temporary"; then state=SUCCESS; else state=FAILED; fi
elif docker exec -i "$container" mysqldump "${options[@]}" "$@" > "$temporary"; then
  state=SUCCESS
else
  state=FAILED
fi
if [[ "$state" == SUCCESS ]]; then
  mv -- "$temporary" "$file"
  file_json='"databases/mysql/databases.sql"'
else
  rm -f -- "$temporary"
  file_json=null
fi
jq -nc --arg source "$source_type" --arg status "$state" --argjson file "$file_json" \
  '{source:$source,status:$status,file:$file,databases:$ARGS.positional}' --args "$@" \
  > "$bundle/databases/mysql/index.json"
[[ "$state" == SUCCESS ]]
