#!/usr/bin/env bash
set -Eeuo pipefail

usage(){ echo '用法：diff.sh --source 来源快照.json [--target 目标快照.json]' >&2; }
source_snapshot='' target_snapshot=''
while (( $# > 0 )); do
  case "$1" in
    --source|--target)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      if [[ "$1" == --source ]]; then source_snapshot="$2"; else target_snapshot="$2"; fi
      shift 2 ;;
    *) usage; exit 2 ;;
  esac
done
[[ -f "$source_snapshot" ]] || { usage; exit 2; }
command -v jq >/dev/null 2>&1 || { echo '状态差异比较需要 jq。' >&2; exit 1; }
for snapshot in "$source_snapshot" ${target_snapshot:+"$target_snapshot"}; do
  jq -e '.schema_version == 1 and (.system | type == "object") and
    ((.users | type) == "array" or (.users.status == "unavailable")) and
    (.network | type == "object") and (.services | type == "object") and
    (.development | type == "object") and (.docker | type == "object") and
    (.databases | type == "object")' "$snapshot" >/dev/null || {
    echo "环境快照格式无效：$snapshot" >&2; exit 2;
  }
done
if [[ -z "$target_snapshot" ]]; then
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  target_snapshot="$(mktemp /tmp/server-shell-kit-diff-XXXXXXXX.json)"
  trap 'rm -f -- "$target_snapshot"' EXIT
  bash "$script_dir/discover.sh" > "$target_snapshot"
fi

jq -rn --slurpfile sources "$source_snapshot" --slurpfile targets "$target_snapshot" '
  def arr: if type == "array" then . else [] end;
  def item($group; $name; $value): {group:$group,name:$name,value:$value};
  def port:
    try (.local_address | capture(":(?<number>[0-9]+)$").number) catch null;
  def availability: if type == "array" then "available" else "unavailable" end;
  def inventory($snapshot; $other):
    [item("System";"OS";
       {distribution:$snapshot.system.distribution,version:$snapshot.system.distribution_version,
        architecture:$snapshot.system.architecture}),
     item("System";"timezone";$snapshot.system.timezone),
     item("Inventory";"Users";($snapshot.users | availability)),
     (if ($snapshot.users | type) == "array" and ($other.users | type) == "array" then
        $snapshot.users[] | item("Users";.name;{uid,home,shell,sudo}) else empty end),
     item("Inventory";"Services enabled";($snapshot.services.enabled | availability)),
     item("Inventory";"Services running";($snapshot.services.running | availability)),
     (if ($snapshot.services.enabled | type) == "array" and
         ($other.services.enabled | type) == "array" then
        $snapshot.services.enabled[] | item("Services enabled";.;true) else empty end),
     (if ($snapshot.services.running | type) == "array" and
         ($other.services.running | type) == "array" then
        $snapshot.services.running[] | item("Services running";.;true) else empty end),
     item("Inventory";"Ports";($snapshot.network.listening_ports | availability)),
     (if ($snapshot.network.listening_ports | type) == "array" and
         ($other.network.listening_ports | type) == "array" then
       $snapshot.network.listening_ports[] |
       select(.protocol == "tcp" or .protocol == "udp") |
       "\(port)/\(.protocol)" | select(startswith("null/") | not) |
       item("Ports";.;true) else empty end),
     ($snapshot.development | to_entries[] |
       item("Development";.key;{status:.value.status,version:.value.version})),
     item("Docker";"daemon";$snapshot.docker.status),
     (if $snapshot.docker.status == "available" and $other.docker.status == "available" then
        item("Docker";"version";$snapshot.docker.version.version),
        item("Docker";"compose";$snapshot.docker.compose_version.version)
      else empty end),
     item("Inventory";"Docker containers";($snapshot.docker.containers | availability)),
     item("Inventory";"Docker images";($snapshot.docker.images | availability)),
     item("Inventory";"Docker volumes";($snapshot.docker.volumes | availability)),
     item("Inventory";"Docker networks";($snapshot.docker.networks | availability)),
     (if ($snapshot.docker.containers | type) == "array" and
         ($other.docker.containers | type) == "array" then
       $snapshot.docker.containers[] |
       item("Docker containers";.name;{image,state}) else empty end),
     (if ($snapshot.docker.images | type) == "array" and
         ($other.docker.images | type) == "array" then
       $snapshot.docker.images[] |
       select(.repository != "<none>" and .repository != null) |
       item("Docker images";"\(.repository):\(.tag)";.digest) else empty end),
     (if ($snapshot.docker.volumes | type) == "array" and
         ($other.docker.volumes | type) == "array" then
       $snapshot.docker.volumes[] | item("Docker volumes";.name;.driver) else empty end),
     (if ($snapshot.docker.networks | type) == "array" and
         ($other.docker.networks | type) == "array" then
       $snapshot.docker.networks[] | item("Docker networks";.name;{driver,scope}) else empty end),
     ($snapshot.databases | to_entries[] as $database |
       item("Databases";"\($database.key)/systemd";
         {status:$database.value.systemd.status,units:$database.value.systemd.units}),
       item("Databases";"\($database.key)/docker";
         {status:$database.value.docker.status,
          containers:[$database.value.docker.containers | arr[] | {name,image}]}))] |
    unique_by(.group,.name);
  def index_items: map({key:(.group + "/" + .name),value:.}) | from_entries;
  $sources[0] as $source | $targets[0] as $target |
  (inventory($source; $target) | index_items) as $left |
  (inventory($target; $source) | index_items) as $right |
  ([($left + $right | keys[]) as $key |
    $left[$key] as $before | $right[$key] as $after |
    {group:($before.group // $after.group),name:($before.name // $after.name),
     before:$before.value,after:$after.value,
     state:(if $before == null then "EXTRA"
            elif $after == null then "MISSING"
            elif $before.value == $after.value then "SAME" else "CHANGED" end)}] |
    sort_by(.group,.name)) as $rows |
  "Snapshot Diff",
  "Source: \($source.system.hostname // "未知")",
  "Target: \($target.system.hostname // "未知")",
  ($rows[] |
    "[\(.state)] \(.group) \(.name)" +
    (if .state == "CHANGED" then " | \(.before | tojson) -> \(.after | tojson)"
     else "" end)),
  "SAME: \([$rows[] | select(.state == "SAME")] | length)",
  "CHANGED: \([$rows[] | select(.state == "CHANGED")] | length)",
  "MISSING: \([$rows[] | select(.state == "MISSING")] | length)",
  "EXTRA: \([$rows[] | select(.state == "EXTRA")] | length)"
'
