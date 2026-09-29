#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

usage(){
  echo '用法：restore.sh --bundle 绝对备份目录 [--target-snapshot 快照.json --dry-run | --apply] [--conflict skip|backup-replace|abort] [--restore-globals] [--postgres-source system|docker:容器] [--mysql-source system|docker:容器] [--postgres-user 用户] [--mysql-user 用户]' >&2
}
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
    rm -f -- "$target_snapshot"
    if [[ -n "$active_stage" && -d "$active_stage" ]]; then
      rm -rf -- "$active_stage"
    fi
  }
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
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

for command_name in tar realpath stat install getent useradd; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf '缺少恢复所需命令：%s\n' "$command_name" >&2; exit 1;
  }
done
port_conflict=0
[[ "$plan_text" != *'[CONFLICT] target port already in use:'* ]] || port_conflict=1

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
  [[ -n "${seen_conflict[$key]:-}" ]] && return 0
  seen_conflict[$key]=1
  conflicts+=("$key")
}
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

resolve_conflicts
confirm_apply
restore_system_base
restore_user
restore_dependencies
restore_docker_service
restore_home_config
restore_compose
if jq -e '.modules.docker.status == "SUCCESS"' "$manifest" >/dev/null; then
  restore_volumes
fi
restore_databases
restore_custom_files
start_supported_services
verify_restored_files
verify_databases
printf '恢复完成。原有数据备份目录：%s\n' "${backup_dir:-无}"
