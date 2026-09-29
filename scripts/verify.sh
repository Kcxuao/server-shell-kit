#!/usr/bin/env bash
set -Eeuo pipefail

usage(){
  echo '用法：verify.sh --source 来源快照.json [--target 目标快照.json] [--postgres-source system|docker:容器] [--mysql-source system|docker:容器] [--postgres-user 用户] [--mysql-user 用户]' >&2
}
source_snapshot='' target_snapshot=''
postgres_source='' mysql_source='' postgres_user=postgres mysql_user=root
while (( $# > 0 )); do
  case "$1" in
    --source|--target|--postgres-source|--mysql-source|--postgres-user|--mysql-user)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      case "$1" in
        --source) source_snapshot="$2" ;;
        --target) target_snapshot="$2" ;;
        --postgres-source) postgres_source="$2" ;;
        --mysql-source) mysql_source="$2" ;;
        --postgres-user) postgres_user="$2" ;;
        --mysql-user) mysql_user="$2" ;;
      esac
      shift 2 ;;
    *) usage; exit 2 ;;
  esac
done
[[ -f "$source_snapshot" ]] || { usage; exit 2; }
command -v jq >/dev/null 2>&1 || { echo '迁移验证需要 jq。' >&2; exit 1; }
for source in "$postgres_source" "$mysql_source"; do
  [[ -z "$source" || "$source" == system ||
     "$source" =~ ^docker:[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || { usage; exit 2; }
done
[[ "$postgres_user" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ &&
   "$mysql_user" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]] || { usage; exit 2; }

for snapshot in "$source_snapshot" ${target_snapshot:+"$target_snapshot"}; do
  jq -e '.schema_version == 1 and (.system | type == "object") and
    (.network | type == "object") and (.services | type == "object") and
    (.development | type == "object") and (.docker | type == "object") and
    (.databases | type == "object")' "$snapshot" >/dev/null || {
    echo "环境快照格式无效：$snapshot" >&2; exit 2;
  }
done

if [[ -z "$target_snapshot" ]]; then
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  target_snapshot="$(mktemp /tmp/server-shell-kit-verify-XXXXXXXX.json)"
  trap 'rm -f -- "$target_snapshot"' EXIT
  bash "$script_dir/discover.sh" > "$target_snapshot"
fi

database_checks='[]'
while IFS= read -r engine; do
  [[ -n "$engine" ]] || continue
  result_state=FAIL result_detail='未发现运行中的目标数据库'
  system_status="$(jq -r --arg engine "$engine" '.databases[$engine].systemd.status // "unavailable"' "$target_snapshot")"
  container="$(jq -r --arg engine "$engine" '.databases[$engine].docker.containers[0].name // empty' "$target_snapshot")"
  if [[ "$engine" == postgresql ]]; then
    selected_source="$postgres_source" client=psql database_user="$postgres_user"
  else
    selected_source="$mysql_source" client=mysql database_user="$mysql_user"
  fi
  if [[ -z "$selected_source" ]]; then
    if [[ "$system_status" == running ]]; then selected_source=system
    elif [[ -n "$container" ]]; then selected_source="docker:$container"
    else selected_source=system; fi
  fi
  if [[ "$system_status" == unavailable && -z "$container" ]]; then
    result_state=WARNING result_detail='目标数据库运行状态不可读取'
  elif [[ "$system_status" == running || -n "$container" ]]; then
    if [[ "$selected_source" == system ]] && ! command -v "$client" >/dev/null 2>&1; then
      result_state=WARNING result_detail="缺少 $client 客户端，连通性未验证"
    elif [[ "$selected_source" == docker:* ]] && ! command -v docker >/dev/null 2>&1; then
      result_state=WARNING result_detail='缺少 Docker 命令，连通性未验证'
    else
      if [[ "$engine" == postgresql ]]; then
        db_command=(psql -X -w -A -t -U "$database_user" -d postgres -c 'SELECT 1')
      else
        db_command=(mysql --batch --skip-column-names --connect-timeout=5
          --user="$database_user" -e 'SELECT 1')
      fi
      if [[ "$selected_source" == docker:* ]]; then
        db_command=(docker exec -i "${selected_source#docker:}" "${db_command[@]}")
      elif [[ "$engine" == postgresql && "$database_user" == postgres && $EUID -eq 0 ]] &&
           id postgres >/dev/null 2>&1 && command -v runuser >/dev/null 2>&1; then
        db_command=(runuser -u postgres -- "${db_command[@]}")
      fi
      connection_result=''
      if connection_result="$("${db_command[@]}" 2>/dev/null)" && [[ "$connection_result" == 1 ]]; then
        result_state=PASS result_detail="通过 $selected_source 查询 SELECT 1"
      else
        result_state=FAIL result_detail="通过 $selected_source 连接或查询失败"
      fi
    fi
  fi
  database_checks="$(jq -nc --argjson checks "$database_checks" --arg name "$engine" \
    --arg state "$result_state" --arg detail "$result_detail" \
    '$checks + [{group:"Database",name:$name,state:$state,detail:$detail}]')"
done < <(jq -r '.databases | to_entries[] | select(.key == "postgresql" or .key == "mysql" or .key == "mariadb") |
  select(.value.systemd.status == "running" or .value.docker.status == "running") | .key' "$source_snapshot")

report="$(jq -rn --slurpfile sources "$source_snapshot" --slurpfile targets "$target_snapshot" \
  --argjson database_checks "$database_checks" '
  def arr: if type == "array" then . else [] end;
  def check($group; $name; $state; $detail):
    {group:$group,name:$name,state:$state,detail:$detail};
  def port: try (.local_address | capture(":(?<number>[0-9]+)$").number) catch null;
  def ports: [.network.listening_ports | arr[] | select(.protocol == "tcp" or .protocol == "udp") |
    {protocol,number:port} | select(.number != null) | "\(.number)/\(.protocol)"] | unique;
  $sources[0] as $s | $targets[0] as $t |
  ([check("System";"disk";
      (if ($t.system.disks | type) != "array" then "WARNING"
       elif any($t.system.disks[]; .mountpoint == "/" and .available_kb > 0) then "PASS"
       else "FAIL" end); "目标根分区可用空间") ,
    check("System";"memory";
      (if ($t.system.memory_kb | type) != "number" then "WARNING"
       elif $t.system.memory_kb > 0 then "PASS" else "FAIL" end); "目标内存信息"),
    check("System";"DNS";
      (if ($t.network.dns | type) != "array" then "WARNING"
       elif ($t.network.dns | length) > 0 then "PASS" else "FAIL" end); "DNS 服务器配置"),
    check("System";"timezone";
      (if $s.system.timezone == "" or $t.system.timezone == "" then "WARNING"
       elif $s.system.timezone == $t.system.timezone then "PASS" else "FAIL" end);
      "来源：\($s.system.timezone // "未知")；目标：\($t.system.timezone // "未知")")]
   + [($s.services.running | arr[]) as $service |
      check("Services";$service;
        (if ($t.services.running | type) != "array" then "WARNING"
         elif ($t.services.running | index($service)) != null then "PASS"
         else "FAIL" end); "来源运行中的服务")]
   + [(($s | ports)[]) as $port |
      check("Ports";$port;
        (if ($t.network.listening_ports | type) != "array" then "WARNING"
         elif (($t | ports) | index($port)) != null then "PASS"
         else "FAIL" end); "来源监听端口")]
   + [($s.development | to_entries[] | select(.value.status == "available")) as $tool |
      check("Development";$tool.key;
        (if $t.development[$tool.key].status == "available" then "PASS"
         elif $t.development[$tool.key].status == "unavailable" then "WARNING"
         else "FAIL" end); "来源已安装的开发工具")]
   + (if $s.docker.status == "available" then
       [check("Docker";"daemon";
          (if $t.docker.status == "available" then "PASS"
           elif $t.docker.status == "unavailable" then "WARNING" else "FAIL" end);
          "Docker 守护进程状态")]
       + [($s.docker.containers | arr[] | select(.state == "running")) as $container |
          check("Docker";"container:\($container.name)";
            (if ($t.docker.containers | type) != "array" then "WARNING"
             elif any($t.docker.containers[]; .name == $container.name and .state == "running")
             then "PASS" else "FAIL" end); "来源运行中的容器")]
       + [($s.docker.volumes | arr[]) as $volume |
          check("Docker";"volume:\($volume.name)";
            (if ($t.docker.volumes | type) != "array" then "WARNING"
             elif any($t.docker.volumes[]; .name == $volume.name) then "PASS"
             else "FAIL" end); "来源 Docker Volume")]
      else [] end)
   + $database_checks) as $checks |
  "Migration Verification",
  ("Source: \($s.system.hostname // "未知")"),
  ("Target: \($t.system.hostname // "未知")"),
  ($checks[] | "[\(.state)] \(.group) \(.name): \(.detail)"),
  "Passed: \([$checks[] | select(.state == "PASS")] | length)",
  "Warning: \([$checks[] | select(.state == "WARNING")] | length)",
  "Failed: \([$checks[] | select(.state == "FAIL")] | length)"
')"
printf '%s\n' "$report"
failed_count="${report##*$'\n'Failed: }"
[[ "$failed_count" == 0 ]]
