#!/usr/bin/env bash
set -Eeuo pipefail

command -v jq >/dev/null 2>&1 || { echo '环境发现需要 jq。' >&2; exit 1; }
export LC_ALL=C

unavailable(){ jq -nc --arg reason "$1" '{status:"unavailable",reason:$reason}'; }
lines_json(){ jq -Rsc 'split("\n") | map(select(length > 0))'; }
version_json(){
  local name="$1" flag="$2" output
  if ! command -v "$name" >/dev/null 2>&1; then
    printf '{"status":"absent"}\n'
  elif output="$("$name" "$flag" 2>&1)"; then
    jq -nc --arg version "${output%%$'\n'*}" '{status:"available",version:$version}'
  else
    unavailable "$name 版本不可读取"
  fi
}

created_at="$(date -u +%FT%TZ)"
. /etc/os-release
timezone="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
[[ -n "$timezone" ]] || timezone="$(cat /etc/timezone 2>/dev/null || true)"
cpu_count="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
[[ "$cpu_count" =~ ^[0-9]+$ ]] || cpu_count=null
cpu_model="$(awk -F: '/^model name[[:space:]]*:/ {sub(/^[[:space:]]+/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null || true)"
memory_kb="$(awk '$1 == "MemTotal:" {print $2}' /proc/meminfo 2>/dev/null || true)"
swap_kb="$(awk '$1 == "SwapTotal:" {print $2}' /proc/meminfo 2>/dev/null || true)"
uptime_seconds="$(awk '{printf "%.0f", $1}' /proc/uptime 2>/dev/null || true)"
for value in memory_kb swap_kb uptime_seconds; do
  [[ "${!value}" =~ ^[0-9]+$ ]] || printf -v "$value" 'null'
done
if command -v df >/dev/null 2>&1 && disk_output="$(df -P -k -l 2>/dev/null)"; then
  disks="$(printf '%s\n' "$disk_output" | awk 'NR > 1 {print $2 "\t" $3 "\t" $4 "\t" $6}' |
    jq -Rsc 'split("\n") | map(select(length > 0) | split("\t") |
      {size_kb:(.[0]|tonumber),used_kb:(.[1]|tonumber),available_kb:(.[2]|tonumber),mountpoint:.[3]})')"
else
  disks="$(unavailable '磁盘信息不可读取')"
fi
system="$(jq -nc \
  --arg distribution "${ID:-}" --arg distribution_version "${VERSION_ID:-}" \
  --arg kernel "$(uname -r)" --arg architecture "$(uname -m)" \
  --arg hostname "$(hostname)" --arg timezone "$timezone" --arg locale "${LANG:-}" \
  --arg cpu_model "$cpu_model" --argjson cpu_count "$cpu_count" \
  --argjson memory_kb "$memory_kb" --argjson swap_kb "$swap_kb" \
  --argjson uptime_seconds "$uptime_seconds" --argjson disks "$disks" \
  '{distribution:$distribution,distribution_version:$distribution_version,kernel:$kernel,
    architecture:$architecture,hostname:$hostname,timezone:$timezone,locale:$locale,
    uptime_seconds:$uptime_seconds,cpu:{model:$cpu_model,count:$cpu_count},
    memory_kb:$memory_kb,swap_kb:$swap_kb,disks:$disks}')"

users='[]'
if passwd_output="$(getent passwd 2>/dev/null)"; then
  while IFS=: read -r username _ uid gid _ home shell; do
    [[ "$uid" =~ ^[0-9]+$ ]] && (( uid >= 1000 && uid < 65534 )) || continue
    sudo_member=null
    if groups="$(id -nG "$username" 2>/dev/null)"; then
      sudo_member=false
      [[ " $groups " == *' sudo '* ]] && sudo_member=true
    fi
    user="$(jq -nc --arg name "$username" --argjson uid "$uid" --arg home "$home" \
      --arg shell "$shell" --argjson sudo "$sudo_member" \
      '{name:$name,uid:$uid,home:$home,shell:$shell,sudo:$sudo}')"
    users="$(jq -nc --argjson users "$users" --argjson user "$user" '$users + [$user]')"
  done <<< "$passwd_output"
else
  users="$(unavailable '用户信息不可读取')"
fi

if command -v ip >/dev/null 2>&1 && ip_output="$(ip -j address show 2>/dev/null)"; then
  addresses="$(jq -c '[.[] | {interface:.ifname,addresses:[.addr_info[]? |
    {family,local,prefixlen}]}]' <<< "$ip_output")"
else
  addresses="$(unavailable 'IP 地址不可读取')"
fi
if command -v ip >/dev/null 2>&1 && route_output="$(ip -j route show default 2>/dev/null)"; then
  gateways="$(jq -c '[.[] | {gateway:(.gateway // null),interface:(.dev // null)}]' <<< "$route_output")"
else
  gateways="$(unavailable '默认网关不可读取')"
fi
if [[ -r /etc/resolv.conf ]]; then
  dns="$(awk '$1 == "nameserver" {print $2}' /etc/resolv.conf | lines_json)"
else
  dns="$(unavailable 'DNS 配置不可读取')"
fi
if command -v ss >/dev/null 2>&1 && ports_output="$(ss -H -lntu 2>/dev/null)"; then
  ports="$(printf '%s\n' "$ports_output" | awk 'NF >= 5 {print $1 "\t" $5}' |
    jq -Rsc 'split("\n") | map(select(length > 0) | split("\t") |
      {protocol:.[0],local_address:.[1]})')"
else
  ports="$(unavailable '监听端口不可读取')"
fi
network="$(jq -nc --argjson addresses "$addresses" --argjson dns "$dns" \
  --argjson gateways "$gateways" --argjson listening_ports "$ports" \
  '{addresses:$addresses,dns:$dns,default_gateways:$gateways,listening_ports:$listening_ports}')"

if command -v systemctl >/dev/null 2>&1 &&
   unit_output="$(systemctl list-unit-files --type=service --all --no-legend --no-pager --plain 2>/dev/null)"; then
  all_units="$(printf '%s\n' "$unit_output" | awk '$1 ~ /\.service$/ {print $1}' | lines_json)"
  if enabled_output="$(systemctl list-unit-files --type=service --state=enabled --no-legend --no-pager --plain 2>/dev/null)" &&
     running_output="$(systemctl list-units --type=service --state=running --no-legend --no-pager --plain 2>/dev/null)"; then
    enabled="$(printf '%s\n' "$enabled_output" | awk '$1 ~ /\.service$/ {print $1}' | lines_json)"
    running="$(printf '%s\n' "$running_output" | awk '$1 ~ /\.service$/ {print $1}' | lines_json)"
    services="$(jq -nc --argjson enabled "$enabled" --argjson running "$running" \
      '{status:"available",enabled:$enabled,running:$running}')"
  else
    running="$(unavailable '运行中的服务不可读取')"
    services="$(unavailable 'systemd 服务状态不可读取')"
  fi
else
  all_units="$(unavailable 'systemd 服务清单不可读取')"
  running="$(unavailable '运行中的服务不可读取')"
  services="$(unavailable 'systemd 服务状态不可读取')"
fi

development='{}'
for spec in 'git --version' 'java -version' 'mvn -version' 'python --version' \
  'uv --version' 'node --version' 'npm --version' 'rustc --version' 'cargo --version'; do
  read -r name flag <<< "$spec"
  item="$(version_json "$name" "$flag")"
  development="$(jq -nc --argjson current "$development" --arg key "$name" \
    --argjson item "$item" '$current + {($key):$item}')"
done

if ! command -v docker >/dev/null 2>&1; then
  docker='{"status":"absent","containers":[],"images":[],"volumes":[],"networks":[]}'
  containers='[]'
else
  docker_version="$(version_json docker --version)"
  if compose_output="$(docker compose version 2>/dev/null)"; then
    compose="$(jq -nc --arg version "${compose_output%%$'\n'*}" '{status:"available",version:$version}')"
  else
    compose='{"status":"absent"}'
  fi
  if container_output="$(docker ps -a --format '{{json .}}' 2>/dev/null)"; then
    containers="$(printf '%s\n' "$container_output" | jq -sc \
      '[.[] | {id:.ID,name:.Names,image:.Image,state:.State,status:.Status}]')"
    if image_output="$(docker image ls --digests --format '{{json .}}' 2>/dev/null)"; then
      images="$(printf '%s\n' "$image_output" | jq -sc \
        '[.[] | {id:.ID,repository:.Repository,tag:.Tag,digest:.Digest}]')"
    else images="$(unavailable '镜像清单不可读取')"; fi
    if volume_output="$(docker volume ls --format '{{json .}}' 2>/dev/null)"; then
      volumes="$(printf '%s\n' "$volume_output" | jq -sc '[.[] | {name:.Name,driver:.Driver}]')"
    else volumes="$(unavailable 'Volume 清单不可读取')"; fi
    if network_output="$(docker network ls --format '{{json .}}' 2>/dev/null)"; then
      networks="$(printf '%s\n' "$network_output" | jq -sc \
        '[.[] | {id:.ID,name:.Name,driver:.Driver,scope:.Scope}]')"
    else networks="$(unavailable '网络清单不可读取')"; fi
    docker="$(jq -nc --argjson version "$docker_version" --argjson compose "$compose" \
      --argjson containers "$containers" --argjson images "$images" --argjson volumes "$volumes" \
      --argjson networks "$networks" \
      '{status:"available",version:$version,compose_version:$compose,containers:$containers,
        images:$images,volumes:$volumes,networks:$networks}')"
  else
    containers="$(unavailable 'Docker 容器不可读取')"
    docker="$(jq -nc --argjson version "$docker_version" --argjson compose "$compose" \
      --argjson unavailable "$containers" \
      '{status:"unavailable",version:$version,compose_version:$compose,
        containers:$unavailable,images:$unavailable,volumes:$unavailable,networks:$unavailable}')"
  fi
fi

# Database presence is inferred only from systemd units and Docker image names.
# No database client, socket, credentials, or data files are accessed.
databases="$(jq -nc --argjson units "$all_units" --argjson running "$running" \
  --argjson containers "$containers" '
  def system($pattern):
    if ($units | type) != "array" or ($running | type) != "array" then
      {status:"unavailable"}
    else
      [$units[] | select(test($pattern))] as $matches |
      if ($matches | length) == 0 then {status:"absent"}
      else {status:(if any($matches[]; . as $unit | $running | index($unit) != null)
                    then "running" else "installed" end),units:$matches} end
    end;
  def container($pattern):
    if ($containers | type) != "array" then {status:"unavailable"}
    else [$containers[] | select(.state == "running" and
      (.image | test($pattern; "i"))) | {id,name,image}] as $matches |
      if ($matches | length) == 0 then {status:"absent"}
      else {status:"running",containers:$matches} end end;
  {postgresql:{systemd:system("^(postgresql|postgres)(@.*)?\\.service$"),
               docker:container("(^|/)postgres(:|@|$)")},
   mysql:{systemd:system("^mysql(d)?(@.*)?\\.service$"),
          docker:container("(^|/)mysql(:|@|$)")},
   mariadb:{systemd:system("^mariadb(@.*)?\\.service$"),
            docker:container("(^|/)mariadb(:|@|$)")},
   redis:{systemd:system("^redis(-server)?(@.*)?\\.service$"),
          docker:container("(^|/)redis(:|@|$)")}}
')"

jq -nc --argjson schema_version 1 --arg created_at "$created_at" \
  --argjson system "$system" --argjson users "$users" --argjson network "$network" \
  --argjson services "$services" --argjson development "$development" \
  --argjson docker "$docker" --argjson databases "$databases" \
  '{schema_version:$schema_version,created_at:$created_at,system:$system,users:$users,
    network:$network,services:$services,development:$development,docker:$docker,databases:$databases}'
