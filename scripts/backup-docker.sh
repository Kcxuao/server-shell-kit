#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
source "$(dirname -- "${BASH_SOURCE[0]}")/backup-secrets.sh"

[[ $# == 1 && "$1" == /* ]] || { echo '用法：backup-docker.sh 绝对备份目录' >&2; exit 2; }
bundle="$1"
snapshot="$bundle/snapshot.json"
[[ -f "$snapshot" ]] || { echo '缺少状态快照，无法安全备份 Docker。' >&2; exit 1; }
status="$(jq -r '.docker.status // "unavailable"' "$snapshot")"
[[ "$status" != absent ]] || { echo 'Docker 未安装，跳过 Docker 模块。'; exit 3; }
[[ "$status" == available ]] || { echo 'Docker 不可读取，跳过 Volume 数据。' >&2; exit 1; }

mkdir -p -- "$bundle/docker/volumes"
jq '.docker' "$snapshot" > "$bundle/docker/inventory.json"
containers="$(docker ps -q 2>/dev/null)" || { echo '无法检查运行中容器与 Volume 的关联。' >&2; exit 1; }
attached='[]'
while IFS= read -r id; do
  [[ -n "$id" ]] || continue
  mounts="$(docker inspect --format '{{json .Mounts}}' "$id" 2>/dev/null)" || {
    echo '无法确认 Volume 是否被容器使用。' >&2; exit 1;
  }
  attached="$(jq -nc --argjson before "$attached" --argjson mounts "$mounts" \
    '$before + [$mounts[]? | select(.Type == "volume") | .Name] | unique')"
done <<< "$containers"
database_containers="$(jq -r '.docker.containers[]? |
  select(.image | test("(^|/)(postgres|mysql|mariadb|redis)(:|@|$)"; "i")) | .id' "$snapshot")"
while IFS= read -r id; do
  [[ -n "$id" ]] || continue
  mounts="$(docker inspect --format '{{json .Mounts}}' "$id" 2>/dev/null)" || {
    echo '无法确认数据库容器的 Volume。' >&2; exit 1;
  }
  attached="$(jq -nc --argjson before "$attached" --argjson mounts "$mounts" \
    '$before + [$mounts[]? | select(.Type == "volume") | .Name] | unique')"
done <<< "$database_containers"

results='[]'
failed=0
index=0
while IFS= read -r volume; do
  [[ -n "$volume" ]] || continue
  index=$((index + 1))
  reason=''
  archive_json=null
  if jq -e --arg name "$volume" 'index($name) != null' <<< "$attached" >/dev/null; then
    state=SKIPPED; reason='运行中使用或关联数据库容器，避免不一致与数据库目录复制'
  else
    driver="$(jq -r --arg name "$volume" '.docker.volumes[] | select(.name == $name) | .driver' "$snapshot")"
    if [[ "$driver" != local ]]; then
      state=SKIPPED; reason='仅支持 local Volume'
    elif ! options="$(docker volume inspect --format '{{json .Options}}' "$volume" 2>/dev/null)"; then
      state=FAILED; reason='Volume 选项不可读取'; failed=1
    elif ! jq -e 'type == "null" or type == "object"' <<< "$options" >/dev/null; then
      state=FAILED; reason='Volume 选项格式无效'; failed=1
    elif jq -e 'type == "object" and length > 0' <<< "$options" >/dev/null; then
      state=SKIPPED; reason='Volume 使用了自定义挂载选项'
    elif ! mountpoint="$(docker volume inspect --format '{{.Mountpoint}}' "$volume" 2>/dev/null)" ||
         [[ "$mountpoint" != /* || ! -d "$mountpoint" || -L "$mountpoint" ]]; then
      state=FAILED; reason='Volume 路径不可读取'; failed=1
    elif ! sensitive="$(find "$mountpoint" -xdev -type f \( -name 'PG_VERSION' \
        -o -name 'ibdata1' -o -name 'aria_log_control' -o -name 'dump.rdb' \
        -o -name 'appendonly.aof' -o -path '*/.ssh/id_*' -o -path '*/etc/shadow' \
        -o -path '*/etc/gshadow' \) -print -quit 2>/dev/null)"; then
      state=FAILED; reason='无法完成敏感文件检查'; failed=1
    elif [[ -n "$sensitive" ]]; then
      state=SKIPPED; reason='发现数据库数据或禁止自动包含的凭据'
    elif [[ "${SERVER_SHELL_KIT_BACKUP_SECRETS:-skip}" == skip &&
            -n "$(backup_secret_tree "$mountpoint")" ]]; then
      state=SKIPPED; reason='发现可能包含敏感数据的文件'
    else
      archive="$bundle/docker/volumes/$(printf '%03d' "$index").tar.gz"
      if tar --one-file-system -czf "$archive" -C "$mountpoint" .; then
        state=SUCCESS
        archive_json="$(jq -nc --arg path "docker/volumes/$(basename -- "$archive")" '$path')"
      else
        state=FAILED; reason='Volume 归档失败'; failed=1
        rm -f -- "$archive"
      fi
    fi
  fi
  result="$(jq -nc --arg name "$volume" --arg status "$state" --arg reason "$reason" \
    --argjson archive "$archive_json" \
    '{name:$name,status:$status,reason:$reason,archive:$archive}')"
  results="$(jq -nc --argjson results "$results" --argjson result "$result" '$results + [$result]')"
done < <(jq -r '.docker.volumes[]?.name' "$snapshot")
mkdir -p -- "$bundle/docker/compose"
compose_results='[]'
declare -A seen_compose=()
compose_index=0
while IFS= read -r id; do
  [[ -n "$id" ]] || continue
  if ! config_files="$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.project.config_files" }}' "$id" 2>/dev/null)"; then
    failed=1
    compose_result="$(jq -nc --arg container "$id" \
      '{container:$container,status:"FAILED",reason:"Compose 标签不可读取",file:null}')"
    compose_results="$(jq -nc --argjson results "$compose_results" \
      --argjson result "$compose_result" '$results + [$result]')"
    continue
  fi
  [[ -n "$config_files" && "$config_files" != '<no value>' ]] || continue
  IFS=',' read -r -a compose_paths <<< "$config_files"
  for path in "${compose_paths[@]}"; do
    [[ -n "$path" && -z "${seen_compose[$path]:-}" ]] || continue
    seen_compose[$path]=1
    compose_index=$((compose_index + 1))
    compose_file_json=null
    if [[ "$path" != /* || ! -f "$path" || -L "$path" || ! -r "$path" ]]; then
      compose_state=SKIPPED; compose_reason='文件不可读取或路径不是普通绝对文件'
    elif [[ "${SERVER_SHELL_KIT_BACKUP_SECRETS:-skip}" == skip ]] &&
         grep -Eiq '(^|[^[:alnum:]_])(environment|env_file|secrets|password|token|api[_-]?key|private[_-]?key)[[:space:]:=]' "$path"; then
      compose_state=SKIPPED; compose_reason='文件可能包含敏感配置'
    else
      if (( $? != 1 )); then
        compose_state=FAILED; compose_reason='敏感内容检查失败'; failed=1
      else
        destination="docker/compose/$(printf '%03d' "$compose_index").yml"
        if cp -- "$path" "$bundle/$destination"; then
          chmod 0600 -- "$bundle/$destination"
          compose_state=SUCCESS; compose_reason=''
          compose_file_json="$(jq -nc --arg file "$destination" '$file')"
        else
          compose_state=FAILED; compose_reason='文件复制失败'; failed=1
        fi
      fi
    fi
    compose_result="$(jq -nc --arg source "$path" --arg status "$compose_state" \
      --arg reason "$compose_reason" --argjson file "$compose_file_json" \
      '{source:$source,status:$status,reason:$reason,file:$file}')"
    compose_results="$(jq -nc --argjson results "$compose_results" \
      --argjson result "$compose_result" '$results + [$result]')"
  done
done < <(jq -r '.docker.containers[]?.id' "$snapshot")
jq -nc --argjson volumes "$results" --argjson compose_files "$compose_results" \
  '{volumes:$volumes,compose_files:$compose_files}' \
  > "$bundle/docker/status.json"
(( failed == 0 ))
