#!/usr/bin/env bash
set -Eeuo pipefail

usage(){
  echo '用法：plan.sh --manifest manifest.json --source source-snapshot.json --target target-snapshot.json [--dry-run]' >&2
}
manifest='' source_snapshot='' target_snapshot=''
while (( $# > 0 )); do
  case "$1" in
    --manifest|--source|--target)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      case "$1" in
        --manifest) manifest="$2" ;;
        --source) source_snapshot="$2" ;;
        --target) target_snapshot="$2" ;;
      esac
      shift 2 ;;
    --dry-run) shift ;;
    *) usage; exit 2 ;;
  esac
done
[[ -f "$manifest" && -f "$source_snapshot" && -f "$target_snapshot" ]] || {
  usage; exit 2;
}
command -v jq >/dev/null 2>&1 || { echo 'Migration Plan 需要 jq。' >&2; exit 1; }
jq -e '.schema_version == 1 and (.hostname | type == "string") and
  (.modules | type == "object") and
  (.files | type == "array")' "$manifest" >/dev/null || {
  echo '备份 Manifest 格式无效。' >&2; exit 2;
}
for snapshot in "$source_snapshot" "$target_snapshot"; do
  jq -e '.schema_version == 1 and (.system | type == "object") and
    (.development | type == "object") and (.docker | type == "object") and
    (.network | type == "object") and (.databases | type == "object")' \
    "$snapshot" >/dev/null || { echo '环境快照格式无效。' >&2; exit 2; }
done
if ! jq -e --slurpfile source "$source_snapshot" \
  '.hostname == $source[0].system.hostname' "$manifest" >/dev/null; then
  echo 'Manifest 与来源快照的主机名不一致。' >&2
  exit 2
fi

jq -rn --slurpfile manifests "$manifest" \
  --slurpfile sources "$source_snapshot" --slurpfile targets "$target_snapshot" '
  def array($value): if ($value | type) == "array" then $value else [] end;
  def port($item):
    try ($item.local_address | capture(":(?<number>[0-9]+)$").number) catch null;
  def ports($snapshot; $public):
    [array($snapshot.network.listening_ports)[] |
      select(.protocol == "tcp" or .protocol == "udp") |
      select(($public | not) or (.local_address | test("^(0\\.0\\.0\\.0|\\[::\\]|\\*):[0-9]+$"))) |
      {protocol,number:port(.)} | select(.number != null and .number != "22") |
      "\(.number)/\(.protocol)"] | unique;
  def database_names($module):
    array($module.details.databases) | map(select(.status == "SUCCESS") | .name);
  def image_ref:
    if (.repository == null or .repository == "<none>" or .repository == "") then empty
    elif (.digest != null and .digest != "<none>" and .digest != "") then
      "\(.repository)@\(.digest)"
    elif (.tag != null and .tag != "<none>" and .tag != "") then
      "\(.repository):\(.tag)"
    else empty end;
  def plan($m; $s; $t):
    (array($m.modules.docker.details.volumes) | map(select(.status == "SUCCESS"))) as $volumes |
    (array($m.modules.docker.inventory.images) | map(image_ref) | unique) as $images |
    (array($t.docker.images) | map(image_ref) | unique) as $target_images |
    (array($m.modules.docker.inventory.networks) |
      map(.name | select(. != "bridge" and . != "host" and . != "none")) | unique) as $networks |
    (array($t.docker.networks) | map(.name) | unique) as $target_networks |
    database_names($m.modules.postgresql) as $postgres |
    (if $m.modules.mysql.details.status == "SUCCESS" then
       array($m.modules.mysql.details.databases) else [] end) as $mysql |
    ports($s; true) as $source_ports |
    ports($t; false) as $target_ports |
    (["Migration Plan (dry run)",
      "Source: \($s.system.hostname)", "Target: \($t.system.hostname)"] +
    (if (($m.modules.docker.status == "SUCCESS") or ($volumes | length > 0)) and
        $t.docker.status == "absent" then ["[INSTALL] docker"] else [] end) +
    (if (($postgres | length > 0) or
         $m.modules.postgresql.details.globals.status == "SUCCESS") and
        $m.modules.postgresql.details.source == "system" and
        $t.databases.postgresql.systemd.status == "absent" then
       ["[INSTALL] PostgreSQL"] else [] end) +
    (if ($mysql | length > 0) and $m.modules.mysql.details.source == "system" and
        $t.databases.mysql.systemd.status == "absent" and
        $t.databases.mariadb.systemd.status == "absent" then
       ["[INSTALL] MySQL/MariaDB"] else [] end) +
    [($s.development | to_entries[] | select(.value.status == "available") | .key) as $tool |
      select($t.development[$tool].status == "absent") | "[INSTALL] \($tool)"] +
    (if any($m.files[]; .path | startswith("home/")) and
        ($m.source_user | type) == "string" and $m.source_user != "root" and
        ($t.users | type) == "array" and
        (array($t.users) | map(.name) | index($m.source_user)) == null then
       ["[CREATE] \($m.source_user)"] else [] end) +
    (if any($m.files[]; .path | startswith("home/")) then
       ["[RESTORE] shell config"] else [] end) +
    [array($m.modules.files.details)[] | "[RESTORE] file:\(.source)"] +
    (if $t.docker.status == "absent" or ($t.docker.images | type) == "array" then
       [($images - $target_images)[] | "[PULL] \(.)"] else [] end) +
    (if $t.docker.status == "absent" or ($t.docker.networks | type) == "array" then
       [($networks - $target_networks)[] | "[CREATE] docker-network:\(.)"] else [] end) +
    (if $m.modules.postgresql.details.globals.status == "SUCCESS" then
       ["[RESTORE] PostgreSQL globals"] else [] end) +
    [$postgres[] | "[RESTORE] PostgreSQL:\(.)"] +
    [$mysql[] | "[RESTORE] MySQL:\(.)"] +
    [$volumes[] | "[RESTORE] docker-volume:\(.name)"] +
    [array($m.modules.docker.details.compose_files)[] |
      select(.status == "SUCCESS") | "[RESTORE] Compose:\(.source)"] +
    [array($m.modules.docker.details.volumes)[] |
      select(.status == "SKIPPED") | "[WARNING] Docker Volume \(.name) 未纳入备份：\(.reason)"] +
    (if ($t.network.listening_ports | type) == "array" then
       [($source_ports - $target_ports)[] | "[OPEN] \(.)"] else [] end) +
    [$volumes[] | .name as $name |
      select(any(array($t.docker.volumes)[]; .name == $name)) |
      "[CONFLICT] target Docker volume already exists: \($name)"] +
    [$postgres[] | . as $name |
      select(any(array($t.databases.postgresql.existing_databases)[]; . == $name)) |
      "[CONFLICT] target PostgreSQL already contains database \($name)"] +
    [$mysql[] | . as $name |
      select(any(array($t.databases.mysql.existing_databases)[]; . == $name) or
        any(array($t.databases.mariadb.existing_databases)[]; . == $name)) |
      "[CONFLICT] target MySQL/MariaDB already contains database \($name)"] +
    [$source_ports[] as $number | select($target_ports | index($number) != null) |
      "[CONFLICT] target port already in use: \($number)"] +
    (if $s.system.distribution != $t.system.distribution or
        $s.system.distribution_version != $t.system.distribution_version then
       ["[WARNING] OS \($s.system.distribution) \($s.system.distribution_version) -> \($t.system.distribution) \($t.system.distribution_version)"]
       else [] end) +
    (if ((($postgres | length) > 0 and
          ($t.databases.postgresql.existing_databases? | type) != "array") or
        (($mysql | length) > 0 and
         ($t.databases.mysql.existing_databases? | type) != "array" and
         ($t.databases.mariadb.existing_databases? | type) != "array")) then
       ["[WARNING] 目标快照未提供完整数据库名清单；无法确认数据库冲突"]
       else [] end) +
    (if $m.modules.postgresql.details.globals.status == "SUCCESS" then
       ["[WARNING] 目标快照不包含 PostgreSQL 角色清单，无法确认全局角色冲突"]
       else [] end) +
    (if $m.modules.postgresql.status == "SUCCESS" and
        ($m.modules.postgresql.details.databases? | type) != "array" then
       ["[WARNING] Manifest 缺少 PostgreSQL 数据库清单，请使用新版备份"]
       else [] end) +
    (if $m.modules.mysql.status == "SUCCESS" and
        ($m.modules.mysql.details.databases? | type) != "array" then
       ["[WARNING] Manifest 缺少 MySQL 数据库清单，请使用新版备份"]
       else [] end) +
    (if $m.modules.docker.status == "SUCCESS" and
        ($m.modules.docker.inventory? | type) != "object" then
       ["[WARNING] Manifest 缺少 Docker 镜像和网络清单，请使用新版备份"]
       else [] end) +
    (if $m.modules.docker.status == "SUCCESS" and
        (($m.modules.docker.inventory.images? | type) != "array" or
         ($m.modules.docker.inventory.networks? | type) != "array") then
       ["[WARNING] 备份的 Docker 镜像或网络清单不可读取"]
       else [] end) +
    (if (array($t.system.disks) | map(select(.mountpoint == "/")) | first) as $root |
        ($root != null and
          (([$m.files[].size_bytes] | add // 0) * 2 > ($root.available_kb * 1024)))
       then ["[WARNING] target disk space may be insufficient (按备份文件大小的两倍估算)"]
       else [] end) +
    (if ($t.system.disks | type) != "array" then
       ["[WARNING] 目标磁盘空间不可读取"]
       elif (array($t.system.disks) | map(select(.mountpoint == "/")) | length) == 0 then
       ["[WARNING] 目标根分区空间不可读取"] else [] end) +
    (if (($m.modules.docker.status == "SUCCESS") or ($volumes | length > 0)) and
        $t.docker.status == "unavailable" then
       ["[WARNING] 目标 Docker 状态不可读取，无法确认冲突"] else [] end) +
    (if ($volumes | length > 0) and ($t.docker.volumes | type) != "array" then
       ["[WARNING] 目标 Docker Volume 清单不可读取，无法确认冲突"] else [] end) +
    (if $t.docker.status != "absent" and ($images | length > 0) and
        ($t.docker.images | type) != "array" then
       ["[WARNING] 目标 Docker 镜像清单不可读取，无法确认需拉取的镜像"] else [] end) +
    (if $t.docker.status != "absent" and ($networks | length > 0) and
        ($t.docker.networks | type) != "array" then
       ["[WARNING] 目标 Docker 网络清单不可读取，无法确认需创建的网络"] else [] end) +
    (if ($source_ports | length > 0) and
        ($t.network.listening_ports | type) != "array" then
       ["[WARNING] 目标监听端口不可读取，无法确认端口冲突"] else [] end) +
    (if any($m.files[]; .path | startswith("home/")) and
        ($t.users | type) != "array" then
       ["[WARNING] 目标用户清单不可读取，无法确认用户冲突"] else [] end) +
    (if any($m.files[]; .path | startswith("home/")) or
        (array($m.modules.files.details) | length > 0) then
       ["[WARNING] 目标快照不包含文件路径清单，无法确认配置和自定义目录冲突"]
       else [] end) +
    (if any($m.files[]; .path | startswith("home/")) and
        ($m.source_user | type) != "string" then
       ["[WARNING] Manifest 缺少来源用户名，无法确定是否需要创建用户"]
       else [] end))[];
  plan($manifests[0]; $sources[0]; $targets[0])
'
