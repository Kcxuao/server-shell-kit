#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

usage(){
  echo '用法：restore.sh --bundle 绝对备份目录 [--target-snapshot 快照.json --dry-run | --apply] [--conflict skip|backup-replace|abort] [--restore-globals] [--postgres-source system|docker:容器] [--mysql-source system|docker:容器] [--postgres-user 用户] [--mysql-user 用户]；或 restore.sh resume JOB_ID [--conflict skip|backup-replace|abort]' >&2
}
resume_id='' resume_conflict_override=''
if [[ "${1:-}" == resume ]]; then
  [[ ( $# -eq 2 || ( $# -eq 4 && "$3" == --conflict ) ) &&
     "$2" =~ ^[0-9]{8}-[0-9]{6}-[A-Za-z0-9]{8}$ ]] || { usage; exit 2; }
  resume_id="$2"
  if (( $# == 4 )); then resume_conflict_override="$4"; fi
  shift "$#"
fi
bundle='' target_snapshot='' apply=0 conflict_policy=ask
restore_globals=0
postgres_source=system mysql_source=system postgres_user=postgres mysql_user=root
while (( $# > 0 )); do
  case "$1" in
    --apply) apply=1; shift ;;
    --dry-run) apply=0; shift ;;
    --restore-globals) restore_globals=1; shift ;;
    --bundle|--target-snapshot|--conflict|--postgres-source|--mysql-source|--postgres-user|--mysql-user)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      case "$1" in
        --bundle) bundle="$2" ;;
        --target-snapshot) target_snapshot="$2" ;;
        --conflict) conflict_policy="$2" ;;
        --postgres-source) postgres_source="$2" ;;
        --mysql-source) mysql_source="$2" ;;
        --postgres-user) postgres_user="$2" ;;
        --mysql-user) mysql_user="$2" ;;
      esac
      shift 2 ;;
    *) usage; exit 2 ;;
  esac
done
job_file='' job_dir='' job_root='' job_lock_fd='' current_step=''
job_write(){
  local temporary
  temporary="$(mktemp "$job_dir/.job.XXXXXXXX")" || return 1
  if jq "$@" "$job_file" > "$temporary"; then
    chmod 0600 -- "$temporary"
    mv -- "$temporary" "$job_file"
  else
    rm -f -- "$temporary"
    return 1
  fi
}
job_update_step(){
  local step="$1" status="$2" reason="$3" now
  now="$(date -u +%FT%TZ)"
  job_write --arg step "$step" --arg status "$status" --arg reason "$reason" \
    --arg now "$now" '
    .current_stage = $step |
    .status = (if $status == "FAILED" then "FAILED" else "RUNNING" end) |
    .steps[$step].status = $status |
    .steps[$step].started_at = (if $status == "RUNNING" then $now
      else .steps[$step].started_at end) |
    .steps[$step].completed_at = (if $status == "RUNNING" then null else $now end) |
    .steps[$step].reason = $reason'
}
job_mark_failed(){
  local exit_code="$1" step="${current_step:-preflight}"
  [[ -n "$job_file" && -f "$job_file" ]] || return 0
  job_update_step "$step" FAILED "退出码 $exit_code"
}
if [[ -n "$resume_id" ]]; then
  [[ $EUID -eq 0 ]] || { echo '续跑需要 root 权限。' >&2; exit 1; }
  command -v jq >/dev/null 2>&1 || { echo '续跑需要 jq。' >&2; exit 1; }
  command -v flock >/dev/null 2>&1 || { echo '续跑需要 flock。' >&2; exit 1; }
  root_home="$(getent passwd 0 | cut -d: -f6)"
  [[ "$root_home" == /* ]] || { echo '无法确定 root HOME。' >&2; exit 1; }
  job_root="$root_home/.local/state/server-shell-kit/jobs"
  job_dir="$job_root/$resume_id"
  job_file="$job_dir/job.json"
  [[ -d "$job_dir" && ! -L "$job_dir" && -f "$job_file" && ! -L "$job_file" &&
     "$(stat -c %u "$job_dir")" == 0 && "$(stat -c %u "$job_file")" == 0 ]] || {
    echo '任务状态不存在或不安全。' >&2; exit 2;
  }
  exec {job_lock_fd}> "$job_dir/lock"
  flock -n "$job_lock_fd" || { echo '任务正在由其他进程执行。' >&2; exit 1; }
  jq -e '.schema_version == 1 and (.status == "FAILED" or .status == "RUNNING") and
    (.bundle | type == "string") and (.options | type == "object") and
    (.steps | type == "object") and (.manifest_sha256 | type == "string")' \
    "$job_file" >/dev/null || { echo '任务状态格式无效或已完成。' >&2; exit 2; }
  bundle="$(jq -r '.bundle' "$job_file")"
  conflict_policy="$(jq -r '.options.conflict_policy' "$job_file")"
  [[ -z "$resume_conflict_override" ]] || conflict_policy="$resume_conflict_override"
  postgres_source="$(jq -r '.options.postgres_source' "$job_file")"
  mysql_source="$(jq -r '.options.mysql_source' "$job_file")"
  postgres_user="$(jq -r '.options.postgres_user' "$job_file")"
  mysql_user="$(jq -r '.options.mysql_user' "$job_file")"
  restore_globals="$(jq -r '.options.restore_globals' "$job_file")"
  [[ "$restore_globals" == 0 || "$restore_globals" == 1 ]] || { echo '任务选项无效。' >&2; exit 2; }
  apply=1
fi
[[ "$bundle" == /* && -d "$bundle" ]] || { usage; exit 2; }
case "$conflict_policy" in ask|skip|backup-replace|abort) ;; *) usage; exit 2 ;; esac
for source in "$postgres_source" "$mysql_source"; do
  [[ "$source" == system || "$source" =~ ^docker:[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || {
    echo '数据库目标来源无效。' >&2; exit 2;
  }
done
[[ "$postgres_user" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ &&
   "$mysql_user" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]] || {
  echo '数据库用户名称无效。' >&2; exit 2;
}
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bundle="$(cd -- "$bundle" && pwd -P)"
manifest="$bundle/manifest.json"
source_snapshot="$bundle/snapshot.json"
if [[ -n "$resume_id" ]]; then
  expected_manifest_sha="$(jq -r '.manifest_sha256' "$job_file")"
  [[ "$(sha256sum "$manifest" 2>/dev/null | cut -d' ' -f1)" == "$expected_manifest_sha" ]] || {
    echo '备份 Manifest 已变化，不能续跑。' >&2; exit 1;
  }
fi
[[ -f "$manifest" && -f "$source_snapshot" ]] || {
  echo '备份目录缺少 Manifest 或来源快照。' >&2; exit 2;
}
command -v jq >/dev/null 2>&1 || { echo '恢复需要 jq。' >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo '恢复需要 sha256sum。' >&2; exit 1; }
jq -e '.schema_version == 1 and (.files | type == "array") and
  (.modules | type == "object") and
  all(.files[]; (.path | type == "string") and (.size_bytes | type == "number") and
    (.size_bytes >= 0) and (.sha256 | type == "string" and test("^[0-9a-fA-F]{64}$")))' \
  "$manifest" >/dev/null || {
  echo 'Manifest 格式无效。' >&2; exit 2;
}

valid_relative(){
  local relative="$1"
  [[ -n "$relative" && "$relative" != /* && "$relative" != *$'\n'* &&
     "$relative" != .. && "$relative" != ../* && "$relative" != */../* &&
     "$relative" != */.. && "$relative" != *'/./'* ]]
}
bundle_file(){
  local relative="$1" resolved
  valid_relative "$relative" || return 1
  jq -e --arg path "$relative" 'any(.files[]; .path == $path)' "$manifest" >/dev/null || return 1
  [[ -f "$bundle/$relative" && ! -L "$bundle/$relative" ]] || return 1
  resolved="$(realpath -e -- "$bundle/$relative")" || return 1
  [[ "$resolved" == "$bundle/"* ]] || return 1
  printf '%s\n' "$resolved"
}
verify_backup(){
  local relative expected_size expected_hash file actual_size actual_hash
  while IFS=$'\t' read -r relative expected_size expected_hash; do
    [[ -n "$relative" ]] || continue
    file="$(bundle_file "$relative")" || { echo "备份路径不安全：$relative" >&2; return 1; }
    actual_size="$(stat -c '%s' -- "$file")"
    actual_hash="$(sha256sum -- "$file")"
    actual_hash="${actual_hash%% *}"
    [[ "$actual_size" == "$expected_size" && "$actual_hash" == "$expected_hash" ]] || {
      echo "备份文件校验失败：$relative" >&2; return 1;
    }
  done < <(jq -r '.files[] | [.path,(.size_bytes|tostring),.sha256] | @tsv' "$manifest")
}
verify_backup || exit 1

if (( apply )); then
  [[ $EUID -eq 0 ]] || { echo '实际恢复需要 root 权限。' >&2; exit 1; }
  [[ -z "$target_snapshot" ]] || {
    echo '实际恢复必须使用实时环境快照，不接受外部目标快照。' >&2; exit 2;
  }
  target_snapshot="$(mktemp /tmp/server-shell-kit-restore-target-XXXXXXXX.json)"
  active_stage=''
  cleanup(){
    local exit_code=$?
    if (( exit_code != 0 )); then job_mark_failed "$exit_code" || true; fi
    rm -f -- "$target_snapshot"
    if [[ -n "$active_stage" && -d "$active_stage" ]]; then
      rm -rf -- "$active_stage"
    fi
  }
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  if [[ -n "$resume_id" ]]; then
    current_step=preflight
    job_update_step preflight RUNNING ''
  fi
  bash "$script_dir/discover.sh" > "$target_snapshot"
else
  [[ -f "$target_snapshot" ]] || { usage; exit 2; }
fi
plan_text="$(bash "$script_dir/plan.sh" --manifest "$manifest" --source "$source_snapshot" \
  --target "$target_snapshot" --dry-run)"
printf '%s\n' "$plan_text"
if (( restore_globals == 0 )) &&
   jq -e '.modules.postgresql.details.globals.status == "SUCCESS"' "$manifest" >/dev/null; then
  echo '[WARNING] 默认不导入 PostgreSQL 全局角色；需显式指定 --restore-globals。'
fi
(( apply )) || exit 0

source_user="$(jq -r '.source_user // empty' "$manifest")"
[[ "$source_user" =~ ^[a-z_][a-z0-9_-]*$ || "$source_user" == root ]] || {
  echo 'Manifest 缺少有效的来源用户名。' >&2; exit 2;
}
source_arch="$(jq -r '.system.architecture // empty' "$source_snapshot")"
target_arch="$(jq -r '.system.architecture // empty' "$target_snapshot")"
[[ -n "$source_arch" && "$source_arch" == "$target_arch" ]] || {
  echo '来源与目标架构不兼容。' >&2; exit 1;
}
source_os="$(jq -r '.system.distribution // empty' "$source_snapshot")"
target_os="$(jq -r '.system.distribution // empty' "$target_snapshot")"
case "$source_os:$target_os" in
  ubuntu:ubuntu|debian:debian|ubuntu:debian|debian:ubuntu) ;;
  *) echo '仅支持 Debian/Ubuntu 之间恢复。' >&2; exit 1 ;;
esac
available_kb="$(jq -r '.system.disks | if type == "array" then
  [.[] | select(.mountpoint == "/") | .available_kb] | first // empty else empty end' "$target_snapshot")"
needed_bytes="$(jq '[.files[].size_bytes] | add // 0' "$manifest")"
[[ "$available_kb" =~ ^[0-9]+$ ]] || { echo '目标磁盘空间不可确认。' >&2; exit 1; }
(( available_kb * 1024 >= needed_bytes * 2 )) || {
  echo '目标磁盘空间可能不足，已中止。' >&2; exit 1;
}
jq -e '
  (.modules.files.status != "SUCCESS" or (.modules.files.details | type) == "array") and
  (.modules.docker.status != "SUCCESS" or
    ((.modules.docker.inventory | type) == "object" and
     (.modules.docker.details | type) == "object")) and
  (.modules.postgresql.status != "SUCCESS" or
    (.modules.postgresql.details.databases | type) == "array") and
  (.modules.mysql.status != "SUCCESS" or
    (.modules.mysql.details.databases | type) == "array")' "$manifest" >/dev/null || {
  echo 'Manifest 缺少恢复所需清单，请使用新版备份。' >&2; exit 1;
}

for command_name in tar realpath stat install getent useradd flock; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf '缺少恢复所需命令：%s\n' "$command_name" >&2; exit 1;
  }
done
port_conflict=0
while IFS= read -r line; do
  [[ "$line" == '[CONFLICT] target port already in use: '* ]] || continue
  port="${line#'[CONFLICT] target port already in use: '}"
  if [[ -n "$resume_id" ]] &&
     jq -e --arg port "$port" '(.confirmed_ports // []) | index($port) != null' \
       "$job_file" >/dev/null; then
    continue
  fi
  port_conflict=1
done <<< "$plan_text"
job_step_success(){
  [[ -n "$job_file" ]] &&
    jq -e --arg step "$1" '.steps[$step].status == "SUCCESS"' "$job_file" >/dev/null
}

source_home="$(jq -r --arg user "$source_user" \
  '.users | if type == "array" then [.[] | select(.name == $user) | .home] | first // empty
  else empty end' "$source_snapshot")"
if [[ "$source_user" == root ]]; then source_home=/root; fi
[[ "$source_home" == /* && "$source_home" != / ]] || source_home="/home/$source_user"
if getent passwd "$source_user" >/dev/null; then
  target_home="$(getent passwd "$source_user" | cut -d: -f6)"
else
  target_home="$source_home"
fi
[[ "$target_home" == /* && "$target_home" != / ]] || {
  echo '目标 HOME 无效。' >&2; exit 1;
}
case "$target_home" in
  /etc|/etc/*|/usr|/usr/*|/bin|/bin/*|/boot|/boot/*|/dev|/dev/*|/proc|/proc/*|/sys|/sys/*|/run|/run/*|/var/lib|/var/lib/*)
    echo '目标 HOME 位于系统目录，已中止。' >&2; exit 1 ;;
esac

safe_parent(){
  local path="$1" current='' part
  local -a parts=()
  [[ "$path" == /* && "$path" != *$'\n'* &&
     "$path" != *'/../'* && "$path" != */.. ]] || return 1
  IFS='/' read -r -a parts <<< "${path#/}"
  for part in "${parts[@]}"; do
    [[ -n "$part" && "$part" != . && "$part" != .. ]] || return 1
    current="${current}/$part"
    [[ ! -L "$current" ]] || return 1
  done
}
archive_safe(){
  local archive="$1" entry
  while IFS= read -r entry; do
    case "$entry" in
      /*|../*|*/../*|*/..|*'/./'*) return 1 ;;
    esac
  done < <(tar -tzf "$archive")
  tar -tvzf "$archive" | awk 'substr($0,1,1) !~ /^[-d]$/ { bad=1 } END { exit bad }'
}
declare -a conflicts=()
declare -A seen_conflict=()
add_conflict(){
  local kind="$1" name="$2" key="$1:$2"
  if [[ -n "$resume_id" ]] && job_step_success "$conflict_step"; then return 0; fi
  [[ -n "${seen_conflict[$key]:-}" ]] && return 0
  seen_conflict[$key]=1
  conflicts+=("$key")
}
conflict_step=config
while IFS= read -r relative; do
  [[ -n "$relative" ]] || continue
  valid_relative "$relative" || { echo '配置路径无效。' >&2; exit 1; }
  destination="$target_home/${relative#home/}"
  safe_parent "$destination" || { echo "配置目标路径不安全：$destination" >&2; exit 1; }
  if [[ -e "$destination" || -L "$destination" ]]; then
    source_file="$(bundle_file "$relative")"
    if [[ -f "$destination" && ! -L "$destination" ]] &&
       cmp -s -- "$source_file" "$destination"; then continue; fi
    add_conflict file "$destination"
  fi
done < <(jq -r '.files[] | .path | select(startswith("home/"))' "$manifest")
conflict_step=files
while IFS=$'\t' read -r archive source; do
  [[ -n "$archive" ]] || continue
  archive_file="$(bundle_file "$archive")" || { echo '自定义归档缺失。' >&2; exit 1; }
  archive_safe "$archive_file" || { echo '自定义归档包含不安全条目。' >&2; exit 1; }
  [[ "$source" == /* && "$source" != / ]] || { echo '自定义恢复路径无效。' >&2; exit 1; }
  case "$source/" in "$bundle/"*)
    echo '自定义恢复路径指向备份目录，已中止。' >&2; exit 1 ;;
  esac
  case "$bundle/" in "$source/"*)
    echo '自定义恢复路径包含备份目录，已中止。' >&2; exit 1 ;;
  esac
  case "$source" in /etc|/etc/*|/usr|/usr/*|/bin|/bin/*|/boot|/boot/*|/dev|/dev/*|/proc|/proc/*|/sys|/sys/*|/run|/run/*|/var/lib|/var/lib/*)
    echo '自定义恢复路径涉及系统目录，已中止。' >&2; exit 1 ;;
  esac
  safe_parent "$source" || { echo "自定义目标路径不安全：$source" >&2; exit 1; }
  [[ ! -e "$source" && ! -L "$source" ]] || add_conflict file "$source"
done < <(jq -r '.modules.files.details[]? | [.archive,.source] | @tsv' "$manifest")
conflict_step=compose
while IFS=$'\t' read -r archive source; do
  [[ -n "$archive" ]] || continue
  archive_file="$(bundle_file "$archive")" || { echo 'Compose 文件缺失。' >&2; exit 1; }
  [[ "$source" == /* && "$source" != / ]] || { echo 'Compose 恢复路径无效。' >&2; exit 1; }
  case "$source/" in "$bundle/"*)
    echo 'Compose 恢复路径指向备份目录，已中止。' >&2; exit 1 ;;
  esac
  safe_parent "$source" || { echo "Compose 目标路径不安全：$source" >&2; exit 1; }
  [[ ! -e "$source" && ! -L "$source" ]] || add_conflict file "$source"
done < <(jq -r '.modules.docker.details.compose_files[]? |
  select(.status == "SUCCESS") | [.file,.source] | @tsv' "$manifest")
conflict_step=volumes
if jq -e '.modules.docker.details.volumes[]? | select(.status == "SUCCESS")' \
  "$manifest" >/dev/null; then
  if command -v docker >/dev/null 2>&1; then
    docker info >/dev/null 2>&1 || { echo 'Docker 状态不可确认。' >&2; exit 1; }
  else
    jq -e '.docker.status == "absent"' "$target_snapshot" >/dev/null || {
      echo '目标 Docker 状态不可确认。' >&2; exit 1;
    }
  fi
  while IFS=$'\t' read -r volume archive; do
    [[ -n "$volume" ]] || continue
    [[ "$volume" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || {
      echo 'Volume 名称无效。' >&2; exit 1;
    }
    archive_file="$(bundle_file "$archive")" || { echo 'Volume 归档缺失。' >&2; exit 1; }
    archive_safe "$archive_file" || { echo 'Volume 归档包含不安全条目。' >&2; exit 1; }
    if command -v docker >/dev/null 2>&1 &&
       docker volume inspect "$volume" >/dev/null 2>&1; then
      add_conflict volume "$volume"
    fi
  done < <(jq -r '.modules.docker.details.volumes[]? |
    select(.status == "SUCCESS") | [.name,.archive] | @tsv' "$manifest")
fi

# 数据库存在性检查在所有文件与 Volume 预检之后进行。
conflict_step=database
source "$script_dir/restore-databases.sh"
preflight_databases

backup_dir=''
backup_index=0
restored_config_paths=()
restored_compose_paths=()
restored_volume_names=()
restored_custom_paths=()
ensure_backup_dir(){
  if [[ -z "$backup_dir" ]]; then
    backup_dir="$(mktemp -d /root/server-shell-kit-pre-restore-XXXXXXXX)"
    chmod 0700 -- "$backup_dir"
    if [[ -n "$job_file" ]]; then
      job_write --arg dir "$backup_dir" '.backup_dirs = ((.backup_dirs // []) + [$dir])'
    fi
    printf '原有数据备份目录：%s\n' "$backup_dir"
  fi
}
backup_existing(){
  local existing="$1" label="$2" archive
  ensure_backup_dir
  backup_index=$((backup_index + 1))
  archive="$backup_dir/$(printf '%03d' "$backup_index")-$label.tar.gz"
  tar -C "$(dirname -- "$existing")" -czf "$archive" -- "$(basename -- "$existing")"
  printf '已备份目标数据：%s -> %s\n' "$existing" "$archive"
}
restore_home_config(){
  local relative source_file destination target_group
  target_group="$(id -gn "$source_user")"
  while IFS= read -r relative; do
    [[ -n "$relative" ]] || continue
    source_file="$(bundle_file "$relative")"
    destination="$target_home/${relative#home/}"
    if [[ -f "$destination" && ! -L "$destination" ]] &&
       cmp -s -- "$source_file" "$destination"; then
      printf 'SKIPPED 已一致：%s\n' "$destination"
      continue
    fi
    if [[ -e "$destination" || -L "$destination" ]]; then
      if [[ "$conflict_policy" == skip ]]; then
        printf 'SKIPPED 已存在：%s\n' "$destination"
        continue
      fi
      [[ "$conflict_policy" == backup-replace ]] || {
        echo "目标配置在预检后发生变化：$destination" >&2; return 1;
      }
      backup_existing "$destination" config
      rm -rf -- "$destination"
    fi
    if [[ ! -d "$(dirname -- "$destination")" ]]; then
      install -d -m 0700 -o "$source_user" -g "$target_group" -- "$(dirname -- "$destination")"
    fi
    if [[ "$relative" == home/.ssh/* ]]; then
      chmod 0700 -- "$target_home/.ssh"
    fi
    install -m 0600 -o "$source_user" -g "$target_group" -- "$source_file" "$destination"
    restored_config_paths+=("$relative")
    printf 'RESTORED 配置：%s\n' "$destination"
  done < <(jq -r '.files[] | .path | select(startswith("home/"))' "$manifest")
}
restore_compose(){
  local archive source file
  while IFS=$'\t' read -r archive source; do
    [[ -n "$archive" ]] || continue
    file="$(bundle_file "$archive")"
    if [[ -f "$source" && ! -L "$source" ]] && cmp -s -- "$file" "$source"; then
      printf 'SKIPPED 已一致：%s\n' "$source"
      continue
    fi
    if [[ -e "$source" || -L "$source" ]]; then
      if [[ "$conflict_policy" == skip ]]; then
        printf 'SKIPPED 已存在：%s\n' "$source"
        continue
      fi
      [[ "$conflict_policy" == backup-replace ]] || {
        echo "Compose 目标在预检后发生变化：$source" >&2; return 1;
      }
      backup_existing "$source" compose
      rm -rf -- "$source"
    fi
    mkdir -p -- "$(dirname -- "$source")"
    install -m 0600 -- "$file" "$source"
    restored_compose_paths+=("$source")
    printf 'RESTORED Compose：%s\n' "$source"
  done < <(jq -r '.modules.docker.details.compose_files[]? |
    select(.status == "SUCCESS") | [.file,.source] | @tsv' "$manifest")
}
restore_custom_files(){
  local archive source file expected
  while IFS=$'\t' read -r archive source; do
    [[ -n "$archive" ]] || continue
    if [[ -e "$source" || -L "$source" ]]; then
      if [[ "$conflict_policy" == skip ]]; then
        printf 'SKIPPED 已存在：%s\n' "$source"
        continue
      fi
      [[ "$conflict_policy" == backup-replace ]] || {
        echo "自定义目标在预检后发生变化：$source" >&2; return 1;
      }
    fi
    file="$(bundle_file "$archive")"
    expected="$(basename -- "$source")"
    if tar -tzf "$file" | awk -v expected="$expected" '
      $0 != expected && index($0, expected "/") != 1 { bad=1 } END { exit bad }'; then :
    else echo '自定义归档与目标路径不匹配。' >&2; return 1; fi
    mkdir -p -- "$(dirname -- "$source")"
    active_stage="$(mktemp -d "$(dirname -- "$source")/.server-shell-kit-restore-XXXXXXXX")"
    if ! tar --no-same-owner -xzf "$file" -C "$active_stage"; then
      return 1
    fi
    if [[ -e "$source" || -L "$source" ]]; then
      backup_existing "$source" files
      rm -rf -- "$source"
    fi
    mv -- "$active_stage/$expected" "$source"
    rmdir -- "$active_stage"
    active_stage=''
    restored_custom_paths+=("$source")
    printf 'RESTORED 自定义路径：%s\n' "$source"
  done < <(jq -r '.modules.files.details[]? | [.archive,.source] | @tsv' "$manifest")
}
restore_docker_metadata(){
  local image name
  while IFS= read -r image; do
    [[ -n "$image" ]] || continue
    if docker image inspect "$image" >/dev/null 2>&1; then
      printf 'SKIPPED Docker 镜像已存在：%s\n' "$image"
    else
      docker pull "$image"
    fi
  done < <(jq -r '.modules.docker.inventory.images[]? |
    select(.repository != null and .repository != "<none>") |
    if .digest != null and .digest != "<none>" then
      "\(.repository)@\(.digest)"
    elif .tag != null and .tag != "<none>" then
      "\(.repository):\(.tag)" else empty end' "$manifest")
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || {
      echo 'Docker 网络名无效。' >&2; return 1;
    }
    if docker network inspect "$name" >/dev/null 2>&1; then
      printf 'SKIPPED Docker 网络已存在：%s\n' "$name"
    else
      docker network create "$name"
    fi
  done < <(jq -r '.modules.docker.inventory.networks[]? | .name |
    select(. != "bridge" and . != "host" and . != "none")' "$manifest")
}
restore_volumes(){
  local volume archive file mountpoint driver options in_use id mounts
  while IFS=$'\t' read -r volume archive; do
    [[ -n "$volume" ]] || continue
    if docker volume inspect "$volume" >/dev/null 2>&1; then
      if [[ "$conflict_policy" == skip ]]; then
        printf 'SKIPPED Docker Volume 已存在：%s\n' "$volume"
        continue
      fi
      [[ "$conflict_policy" == backup-replace ]] || {
        echo "Volume 在预检后出现：$volume" >&2; return 1;
      }
      in_use=0
      while IFS= read -r id; do
        [[ -n "$id" ]] || continue
        mounts="$(docker inspect --format '{{json .Mounts}}' "$id")"
        if jq -e --arg name "$volume" 'any(.[]?; .Type == "volume" and .Name == $name)' \
          <<< "$mounts" >/dev/null; then in_use=1; break; fi
      done < <(docker ps -q)
      (( in_use == 0 )) || { echo "Volume 正被运行中容器使用：$volume" >&2; return 1; }
    else
      docker volume create "$volume" >/dev/null
    fi
    driver="$(docker volume inspect --format '{{.Driver}}' "$volume")"
    options="$(docker volume inspect --format '{{json .Options}}' "$volume")"
    mountpoint="$(docker volume inspect --format '{{.Mountpoint}}' "$volume")"
    [[ "$driver" == local && "$mountpoint" == /* && -d "$mountpoint" &&
       ! -L "$mountpoint" ]] || { echo 'Volume 挂载路径不安全。' >&2; return 1; }
    jq -e 'type == "null" or (type == "object" and length == 0)' \
      <<< "$options" >/dev/null || { echo '不支持自定义挂载的 Volume。' >&2; return 1; }
    if [[ -n "$(find "$mountpoint" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
      if [[ "$conflict_policy" == skip ]]; then
        printf 'SKIPPED Docker Volume 有数据：%s\n' "$volume"
        continue
      fi
      [[ "$conflict_policy" == backup-replace ]] || {
        echo "Volume 在预检后出现数据：$volume" >&2; return 1;
      }
      backup_existing "$mountpoint" volume
      find "$mountpoint" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
    fi
    file="$(bundle_file "$archive")"
    tar -xzf "$file" -C "$mountpoint"
    restored_volume_names+=("$volume")
    printf 'RESTORED Docker Volume：%s\n' "$volume"
  done < <(jq -r '.modules.docker.details.volumes[]? |
    select(.status == "SUCCESS") | [.name,.archive] | @tsv' "$manifest")
}

restore_system_base(){
  local timezone current
  timezone="$(jq -r '.system.timezone // empty' "$source_snapshot")"
  [[ -n "$timezone" ]] || return 0
  [[ "$timezone" != /* && "$timezone" != *'..'* &&
     -f "/usr/share/zoneinfo/$timezone" ]] || {
    echo '来源时区无效，跳过时区设置。' >&2; return 0;
  }
  if command -v timedatectl >/dev/null 2>&1; then
    current="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
    if [[ "$current" != "$timezone" ]]; then
      timedatectl set-timezone "$timezone"
      printf 'RESTORED 时区：%s\n' "$timezone"
    fi
  fi
}
restore_user(){
  local shell sudo_member
  [[ "$source_user" != root ]] || return 0
  if id "$source_user" >/dev/null 2>&1; then
    printf 'SKIPPED 用户已存在：%s\n' "$source_user"
  else
    shell="$(jq -r --arg user "$source_user" '.users | if type == "array" then
      [.[] | select(.name == $user) | .shell] | first // empty else empty end' "$source_snapshot")"
    [[ "$shell" == /* && -x "$shell" ]] || shell=/bin/bash
    useradd -m -d "$target_home" -s "$shell" "$source_user"
    printf 'CREATED 用户：%s\n' "$source_user"
  fi
  sudo_member="$(jq -r --arg user "$source_user" '.users | if type == "array" then
    [.[] | select(.name == $user) | .sudo] | first // false else false end' "$source_snapshot")"
  if [[ "$sudo_member" == true ]] && getent group sudo >/dev/null &&
     ! id -nG "$source_user" | grep -qw sudo; then
    usermod -aG sudo "$source_user"
  fi
}
restore_dependencies(){
  local source_shell target_shell language
  local -a languages=()
  source_shell="$(jq -r --arg user "$source_user" '.users | if type == "array" then
    [.[] | select(.name == $user) | .shell] | first // empty else empty end' "$source_snapshot")"
  target_shell="$(getent passwd "$source_user" | cut -d: -f7)"
  if [[ "$source_shell" == */zsh && "$target_shell" != */zsh ]]; then
    SUDO_USER="$source_user" bash "$script_dir/install-zsh.sh"
  fi
  for language in java python node rust; do
    if jq -e --arg name "$language" '.development[$name].status == "available"' \
         "$source_snapshot" >/dev/null &&
       jq -e --arg name "$language" '.development[$name].status == "absent"' \
         "$target_snapshot" >/dev/null; then
      languages+=("$language")
    fi
  done
  if (( ${#languages[@]} > 0 )); then
    SUDO_USER="$source_user" bash "$script_dir/install-language-manager.sh" "${languages[@]}"
  fi
}
restore_docker_service(){
  if jq -e '.modules.docker.status == "SUCCESS"' "$manifest" >/dev/null; then
    if ! command -v docker >/dev/null 2>&1; then
      bash "$script_dir/install-docker.sh"
    fi
    docker info >/dev/null
    restore_docker_metadata
  fi
}
start_supported_services(){
  local unit
  command -v systemctl >/dev/null 2>&1 || return 0
  for unit in docker.service postgresql.service mysql.service mariadb.service; do
    case "$unit" in
      docker.service)
        jq -e '.modules.docker.status == "SUCCESS"' "$manifest" >/dev/null || continue ;;
      postgresql.service)
        [[ "$postgres_source" == system ]] || continue
        jq -e '.modules.postgresql.status == "SUCCESS"' "$manifest" >/dev/null || continue ;;
      mysql.service|mariadb.service)
        [[ "$mysql_source" == system ]] || continue
        jq -e '.modules.mysql.status == "SUCCESS"' "$manifest" >/dev/null || continue ;;
    esac
    if systemctl list-unit-files "$unit" --no-legend 2>/dev/null | grep -q "^$unit "; then
      if ! systemctl is-active --quiet "$unit"; then
        systemctl start "$unit"
        printf 'STARTED 服务：%s\n' "$unit"
      fi
    fi
  done
}

resolve_conflicts(){
  local conflict answer
  if (( ${#conflicts[@]} > 0 )); then
    printf '检测到 %d 项目标数据冲突：\n' "${#conflicts[@]}"
    for conflict in "${conflicts[@]}"; do printf '  %s\n' "$conflict"; done
  fi
  if (( ${#conflicts[@]} > 0 || port_conflict > 0 )); then
    if [[ "$conflict_policy" == ask ]]; then
      [[ -t 0 ]] || { echo '非交互执行遇到冲突，需要 --conflict。' >&2; return 1; }
      printf '处理冲突：[s] 跳过 / [r] 备份现有数据并替换 / [a] 中止：'
      IFS= read -r answer || return 1
      case "$answer" in
        s|S) conflict_policy=skip ;;
        r|R) conflict_policy=backup-replace ;;
        a|A) conflict_policy=abort ;;
        *) echo '选择无效，已中止。' >&2; return 1 ;;
      esac
    fi
    [[ "$conflict_policy" != abort ]] || { echo '已中止，未修改目标。'; return 1; }
    if (( port_conflict > 0 )) && [[ "$conflict_policy" != skip ]]; then
      echo '已有端口被占用；端口冲突仅支持跳过，不能替换现有服务。' >&2
      return 1
    fi
  else
    conflict_policy=abort
  fi
}
confirm_apply(){
  local answer
  [[ -t 0 ]] || { echo '实际恢复需要交互式确认。' >&2; return 1; }
  printf '即将修改目标服务器。请输入 RESTORE 继续：'
  IFS= read -r answer || return 1
  [[ "$answer" == RESTORE ]] || { echo '已取消，未修改目标。'; return 1; }
}
verify_restored_files(){
  local relative source_file destination name failures=0
  for relative in "${restored_config_paths[@]}"; do
    source_file="$(bundle_file "$relative")"
    destination="$target_home/${relative#home/}"
    cmp -s -- "$source_file" "$destination" || {
      printf 'VERIFY FAILED 配置：%s\n' "$destination" >&2; failures=1;
    }
  done
  for name in "${restored_compose_paths[@]}"; do
    [[ -f "$name" ]] || { printf 'VERIFY FAILED Compose：%s\n' "$name" >&2; failures=1; }
  done
  for name in "${restored_volume_names[@]}"; do
    docker volume inspect "$name" >/dev/null 2>&1 || {
      printf 'VERIFY FAILED Volume：%s\n' "$name" >&2; failures=1;
    }
  done
  for name in "${restored_custom_paths[@]}"; do
    [[ -e "$name" ]] || { printf 'VERIFY FAILED 文件：%s\n' "$name" >&2; failures=1; }
  done
  (( failures == 0 ))
}
verify_restored(){
  verify_restored_files
  verify_databases
}

job_init(){
  local root_home now manifest_sha
  root_home="$(getent passwd 0 | cut -d: -f6)"
  [[ "$root_home" == /* ]] || { echo '无法确定 root HOME。' >&2; return 1; }
  job_root="$root_home/.local/state/server-shell-kit/jobs"
  install -d -m 0700 -- "$job_root"
  job_dir="$(mktemp -d "$job_root/$(date -u +%Y%m%d-%H%M%S)-XXXXXXXX")"
  job_file="$job_dir/job.json"
  exec {job_lock_fd}> "$job_dir/lock"
  flock -n "$job_lock_fd" || return 1
  now="$(date -u +%FT%TZ)"
  manifest_sha="$(sha256sum "$manifest" | cut -d' ' -f1)"
  jq -nc --arg id "${job_dir##*/}" --arg bundle "$bundle" \
    --arg manifest_sha "$manifest_sha" --arg now "$now" \
    --arg conflict "$conflict_policy" --arg postgres_source "$postgres_source" \
    --arg mysql_source "$mysql_source" --arg postgres_user "$postgres_user" \
    --arg mysql_user "$mysql_user" --argjson restore_globals "$restore_globals" '
    {schema_version:1,id:$id,bundle:$bundle,manifest_sha256:$manifest_sha,
     status:"RUNNING",current_stage:"preflight",started_at:$now,completed_at:null,
     backup_dirs:[],confirmed_ports:[],
     options:{conflict_policy:$conflict,postgres_source:$postgres_source,
       mysql_source:$mysql_source,postgres_user:$postgres_user,mysql_user:$mysql_user,
       restore_globals:$restore_globals},
     steps:(["preflight","system","user","dependencies","docker","config",
       "compose","volumes","database","files","services","verify"] |
       map({key:.,value:{status:"PENDING",started_at:null,completed_at:null,reason:""}}) |
       from_entries)}' > "$job_file"
  chmod 0600 -- "$job_file"
  job_update_step preflight SUCCESS ''
  printf '迁移任务 ID：%s\n' "${job_dir##*/}"
}
job_record_paths(){
  local step="$1" paths_json
  case "$step" in
    config) paths_json="$(jq -nc '$ARGS.positional' --args "${restored_config_paths[@]}")" ;;
    compose) paths_json="$(jq -nc '$ARGS.positional' --args "${restored_compose_paths[@]}")" ;;
    volumes) paths_json="$(jq -nc '$ARGS.positional' --args "${restored_volume_names[@]}")" ;;
    files) paths_json="$(jq -nc '$ARGS.positional' --args "${restored_custom_paths[@]}")" ;;
    *) return 0 ;;
  esac
  job_write --arg step "$step" --argjson paths "$paths_json" '.steps[$step].restored = $paths'
}
job_current_ports(){
  bash "$script_dir/discover.sh" | jq -c '
    [.network.listening_ports | if type == "array" then .[] else empty end |
      select(.protocol == "tcp" or .protocol == "udp") |
      (try (.local_address | capture(":(?<number>[0-9]+)$").number)
       catch empty) as $number | "\($number)/\(.protocol)"] | unique'
}
job_record_ports(){
  local before="$1" after added
  after="$(job_current_ports)"
  added="$(jq -nc --argjson before "$before" --argjson after "$after" '$after - $before')"
  job_write --argjson ports "$added" '
    .confirmed_ports = ((.confirmed_ports // []) + $ports | unique)'
}
run_step(){
  local step="$1" ports_before='[]'
  shift
  if job_step_success "$step"; then
    printf 'SKIPPED 已完成步骤：%s\n' "$step"
    return 0
  fi
  current_step="$step"
  job_update_step "$step" RUNNING ''
  if [[ "$step" == docker || "$step" == services ]]; then
    ports_before="$(job_current_ports)"
  fi
  "$@"
  job_record_paths "$step"
  if [[ "$step" == docker || "$step" == services ]]; then job_record_ports "$ports_before"; fi
  job_update_step "$step" SUCCESS ''
  current_step=''
}
skip_step(){
  local step="$1" reason="$2"
  if job_step_success "$step"; then return 0; fi
  current_step="$step"
  job_update_step "$step" SKIPPED "$reason"
  current_step=''
}
job_complete(){
  local now
  now="$(date -u +%FT%TZ)"
  job_write --arg now "$now" '.status="SUCCESS" | .current_stage="complete" |
    .completed_at=$now'
}
load_restored_paths(){
  if [[ -n "$resume_id" ]]; then
    mapfile -t restored_config_paths < <(jq -r '.steps.config.restored[]?' "$job_file")
    mapfile -t restored_compose_paths < <(jq -r '.steps.compose.restored[]?' "$job_file")
    mapfile -t restored_volume_names < <(jq -r '.steps.volumes.restored[]?' "$job_file")
    mapfile -t restored_custom_paths < <(jq -r '.steps.files.restored[]?' "$job_file")
  fi
}

resolve_conflicts
confirm_apply
if [[ -n "$resume_id" ]]; then
  job_write --arg policy "$conflict_policy" '.options.conflict_policy=$policy'
  job_update_step preflight SUCCESS ''
  load_restored_paths
else
  job_init
fi
run_step system restore_system_base
if [[ "$source_user" == root ]]; then skip_step user '来源用户为 root'
else run_step user restore_user; fi
run_step dependencies restore_dependencies
if jq -e '.modules.docker.status == "SUCCESS"' "$manifest" >/dev/null; then
  run_step docker restore_docker_service
else skip_step docker '备份不含 Docker 模块'; fi
if jq -e 'any(.files[]; .path | startswith("home/"))' "$manifest" >/dev/null; then
  run_step config restore_home_config
else skip_step config '备份不含用户配置'; fi
if jq -e 'any(.modules.docker.details.compose_files[]?; .status == "SUCCESS")' "$manifest" >/dev/null; then
  run_step compose restore_compose
else skip_step compose '备份不含 Compose 文件'; fi
if jq -e '.modules.docker.status == "SUCCESS"' "$manifest" >/dev/null; then
  if jq -e 'any(.modules.docker.details.volumes[]?; .status == "SUCCESS")' "$manifest" >/dev/null; then
    run_step volumes restore_volumes
  else skip_step volumes '备份不含 Docker Volume'; fi
else
  skip_step volumes '备份不含 Docker 模块'
fi
if jq -e '.modules.postgresql.status == "SUCCESS" or .modules.mysql.status == "SUCCESS"' "$manifest" >/dev/null; then
  run_step database restore_databases
else skip_step database '备份不含数据库模块'; fi
if jq -e '(.modules.files.details // [] | length) > 0' "$manifest" >/dev/null; then
  run_step files restore_custom_files
else skip_step files '备份不含自定义目录'; fi
run_step services start_supported_services
run_step verify verify_restored
job_complete
printf '恢复完成。原有数据备份目录：%s\n' "${backup_dir:-无}"
