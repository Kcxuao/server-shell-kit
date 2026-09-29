#!/usr/bin/env bash
# 由 restore.sh 引入；只读预检必须先于任何恢复写入。

database_command(){
  local engine="$1" source="$2"
  shift 2
  if [[ "$source" == system ]]; then
    if [[ "$engine" == postgres && "$postgres_user" == postgres && $EUID -eq 0 ]] &&
       id postgres >/dev/null 2>&1; then
      runuser -u postgres -- "$@"
    else
      "$@"
    fi
  else
    docker exec -i "${source#docker:}" "$@"
  fi
}
postgres_exists(){
  local name="$1" result
  result="$(database_command postgres "$postgres_source" psql -X -w -A -t -U "$postgres_user" \
    -d postgres -c "SELECT 1 FROM pg_database WHERE datname = '$name'" 2>/dev/null)" || return 2
  [[ "$result" == 1 ]] && return 0
  [[ -z "$result" ]] && return 1
  return 2
}
mysql_exists(){
  local name="$1" result
  result="$(database_command mysql "$mysql_source" mysql --batch --skip-column-names \
    --user="$mysql_user" -e "SELECT 1 FROM information_schema.schemata WHERE schema_name = '$name'" \
    2>/dev/null)" || return 2
  [[ "$result" == 1 ]] && return 0
  [[ -z "$result" ]] && return 1
  return 2
}
preflight_databases(){
  local name file result engine source client
  for engine in postgresql mysql; do
    jq -e --arg engine "$engine" '.modules[$engine].status == "SUCCESS"' "$manifest" >/dev/null || continue
    if [[ "$engine" == postgresql ]]; then source="$postgres_source"; client=psql
    else source="$mysql_source"; client=mysql; fi
    if [[ "$source" == system ]]; then
      command -v "$client" >/dev/null || { echo "缺少数据库客户端：$client" >&2; return 1; }
      if [[ "$engine" == postgresql ]]; then
        command -v pg_restore >/dev/null || return 1
        [[ "$conflict_policy" != backup-replace ]] || command -v pg_dump >/dev/null || return 1
      elif [[ "$conflict_policy" == backup-replace ]]; then
        command -v mysqldump >/dev/null || return 1
      fi
      if [[ "$engine" == postgresql && "$postgres_user" == postgres && $EUID -eq 0 ]] &&
         id postgres >/dev/null 2>&1; then
        command -v runuser >/dev/null || return 1
      fi
    else
      command -v docker >/dev/null || return 1
      [[ "$(docker inspect --format '{{.State.Running}}' "${source#docker:}" 2>/dev/null)" == true ]] || {
        echo "数据库目标容器未运行：${source#docker:}" >&2; return 1;
      }
    fi
    if [[ "$engine" == postgresql ]]; then
      while IFS=$'\t' read -r name file; do
        [[ -n "$name" ]] || continue
        [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_.-]*$ ]] || { echo "数据库名不安全：$name" >&2; return 1; }
        [[ "$name" != postgres && "$name" != template0 && "$name" != template1 ]] || {
          echo "不允许恢复 PostgreSQL 系统数据库：$name" >&2; return 1;
        }
        bundle_file "$file" >/dev/null || { echo "数据库备份缺失：$file" >&2; return 1; }
        result=0; postgres_exists "$name" || result=$?
        case "$result" in
          0) add_conflict database "postgresql/$name" ;;
          1) ;;
          *) echo "无法确认 PostgreSQL 数据库是否存在：$name" >&2; return 1 ;;
        esac
      done < <(jq -r '.modules.postgresql.details.databases[]? | select(.status == "SUCCESS") | [.name,.file] | @tsv' "$manifest")
      if (( restore_globals )); then
        file="$(jq -r '.modules.postgresql.details.globals | select(.status == "SUCCESS") | .file // empty' "$manifest")"
        [[ -z "$file" ]] || bundle_file "$file" >/dev/null || return 1
      fi
    else
      file="$(jq -r '.modules.mysql.details.file // empty' "$manifest")"
      bundle_file "$file" >/dev/null || { echo 'MySQL 备份缺失。' >&2; return 1; }
      while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        [[ "$name" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || { echo "数据库名不安全：$name" >&2; return 1; }
        case "$name" in mysql|sys|performance_schema|information_schema)
          echo "不允许恢复 MySQL 系统数据库：$name" >&2; return 1 ;; esac
        result=0; mysql_exists "$name" || result=$?
        case "$result" in
          0) add_conflict database "mysql/$name" ;;
          1) ;;
          *) echo "无法确认 MySQL 数据库是否存在：$name" >&2; return 1 ;;
        esac
      done < <(jq -r '.modules.mysql.details.databases[]?' "$manifest")
    fi
  done
}
restore_databases(){
  local name file result any_existing=0 database
  local -a mysql_names=()
  if jq -e '.modules.postgresql.status == "SUCCESS"' "$manifest" >/dev/null; then
    if (( restore_globals )); then
      file="$(jq -r '.modules.postgresql.details.globals | select(.status == "SUCCESS") | .file // empty' "$manifest")"
      if [[ -n "$file" ]]; then
        database_command postgres "$postgres_source" psql -X -w -v ON_ERROR_STOP=1 \
          -U "$postgres_user" -d postgres < "$(bundle_file "$file")"
        echo 'RESTORED PostgreSQL 全局角色'
      fi
    fi
    while IFS=$'\t' read -r name file; do
      [[ -n "$name" ]] || continue
      result=0; postgres_exists "$name" || result=$?
      case "$result" in
        0)
          if [[ "$conflict_policy" == skip ]]; then
            printf 'SKIPPED PostgreSQL 数据库已存在：%s\n' "$name"; continue
          fi
          [[ "$conflict_policy" == backup-replace ]] || return 1
          ensure_backup_dir
          database_command postgres "$postgres_source" pg_dump -w -U "$postgres_user" \
            -Fc -- "$name" > "$backup_dir/postgresql-$name.dump"
          database_command postgres "$postgres_source" psql -X -w -v ON_ERROR_STOP=1 \
            -U "$postgres_user" -d postgres -c "DROP DATABASE \"$name\""
          ;;
        1) ;;
        *) echo "无法复查 PostgreSQL 数据库：$name" >&2; return 1 ;;
      esac
      database_command postgres "$postgres_source" psql -X -w -v ON_ERROR_STOP=1 \
        -U "$postgres_user" -d postgres -c "CREATE DATABASE \"$name\""
      database_command postgres "$postgres_source" pg_restore -w -U "$postgres_user" \
        --single-transaction --no-owner --no-acl -d "$name" < "$(bundle_file "$file")"
      printf 'RESTORED PostgreSQL 数据库：%s\n' "$name"
    done < <(jq -r '.modules.postgresql.details.databases[]? | select(.status == "SUCCESS") | [.name,.file] | @tsv' "$manifest")
  fi
  if jq -e '.modules.mysql.status == "SUCCESS"' "$manifest" >/dev/null; then
    while IFS= read -r name; do [[ -z "$name" ]] || mysql_names+=("$name"); done \
      < <(jq -r '.modules.mysql.details.databases[]?' "$manifest")
    for database in "${mysql_names[@]}"; do
      result=0; mysql_exists "$database" || result=$?
      case "$result" in
        0) any_existing=1 ;;
        1) ;;
        *) echo "无法复查 MySQL 数据库：$database" >&2; return 1 ;;
      esac
    done
    if (( any_existing )) && [[ "$conflict_policy" == skip ]]; then
      echo 'SKIPPED MySQL 合并归档：目标已有数据库'
      mysql_skipped=1
      return 0
    fi
    if (( any_existing )) && [[ "$conflict_policy" != backup-replace ]]; then return 1; fi
    if (( any_existing )); then
      ensure_backup_dir
      for database in "${mysql_names[@]}"; do
        if mysql_exists "$database"; then
          database_command mysql "$mysql_source" mysqldump --user="$mysql_user" \
            --single-transaction --quick --routines --events --triggers --databases \
            "$database" > "$backup_dir/mysql-$database.sql"
        fi
      done
      for database in "${mysql_names[@]}"; do
        if mysql_exists "$database"; then
          database_command mysql "$mysql_source" mysql --user="$mysql_user" \
            -e "DROP DATABASE \`$database\`"
        fi
      done
    fi
    file="$(jq -r '.modules.mysql.details.file' "$manifest")"
    database_command mysql "$mysql_source" mysql --user="$mysql_user" < "$(bundle_file "$file")"
    echo 'RESTORED MySQL 数据库归档'
  fi
}
verify_databases(){
  local name
  while IFS= read -r name; do
    [[ -z "$name" ]] || postgres_exists "$name" || {
      printf 'VERIFY FAILED PostgreSQL 数据库：%s\n' "$name" >&2; return 1;
    }
  done < <(jq -r '.modules.postgresql.details.databases[]? | select(.status == "SUCCESS") | .name' "$manifest")
  (( ${mysql_skipped:-0} == 0 )) || return 0
  while IFS= read -r name; do
    [[ -z "$name" ]] || mysql_exists "$name" || {
      printf 'VERIFY FAILED MySQL 数据库：%s\n' "$name" >&2; return 1;
    }
  done < <(jq -r 'if .modules.mysql.status == "SUCCESS" then .modules.mysql.details.databases[]? else empty end' "$manifest")
}
