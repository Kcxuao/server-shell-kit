#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

usage(){
  echo '用法：backup.sh config|data|full [--output-dir 绝对目录] [--secrets skip|include|encrypt] [--path 绝对路径] [--postgres-db 名称] [--postgres-source system|docker:容器] [--postgres-user 用户] [--mysql-db 名称] [--mysql-source system|docker:容器] [--mysql-user 用户]' >&2
}
[[ $# -ge 1 ]] || { usage; exit 2; }
mode="$1"
shift
case "$mode" in config|data|full) ;; *) usage; exit 2 ;; esac
output_dir="${HOME:-}"
secret_policy=ask
postgres_source=system postgres_user=postgres
mysql_source=system mysql_user=root
paths=() postgres_databases=() mysql_databases=()
while (( $# > 0 )); do
  [[ $# -ge 2 ]] || { usage; exit 2; }
  case "$1" in
    --output-dir) output_dir="$2" ;;
    --secrets) secret_policy="$2" ;;
    --path) paths+=("$2") ;;
    --postgres-db) postgres_databases+=("$2") ;;
    --postgres-source) postgres_source="$2" ;;
    --postgres-user) postgres_user="$2" ;;
    --mysql-db) mysql_databases+=("$2") ;;
    --mysql-source) mysql_source="$2" ;;
    --mysql-user) mysql_user="$2" ;;
    *) usage; exit 2 ;;
  esac
  shift 2
done
case "$secret_policy" in ask|skip|include|encrypt) ;; *) usage; exit 2 ;; esac
[[ "$output_dir" == /* ]] || { echo '备份输出目录必须是绝对路径。' >&2; exit 2; }
if [[ "$mode" == config ]] && (( ${#paths[@]} + ${#postgres_databases[@]} + ${#mysql_databases[@]} > 0 )); then
  echo 'config 类型不接受数据备份选项。' >&2; exit 2
fi
command -v jq >/dev/null 2>&1 || { echo '备份需要 jq。' >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo '备份需要 sha256sum。' >&2; exit 1; }
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
mkdir -p -- "$output_dir"
bundle="$(mktemp -d "$output_dir/server-shell-kit-backup-$(date -u +%Y%m%d-%H%M%S)-XXXXXXXX")"
bundle_complete=0
cleanup(){
  if (( bundle_complete == 0 )) && [[ -n "${bundle:-}" && -d "$bundle" ]]; then
    rm -rf -- "$bundle"
  fi
  if [[ -n "${encrypted_partial:-}" && -f "$encrypted_partial" ]]; then
    rm -f -- "$encrypted_partial"
  fi
  if [[ -n "${gpg_home:-}" && -d "$gpg_home" ]]; then
    GNUPGHOME="$gpg_home" gpgconf --kill gpg-agent >/dev/null 2>&1 || true
    rm -rf -- "$gpg_home"
  fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
created_at="$(date -u +%FT%TZ)"
version="$(git -C "$repo_dir" rev-parse --short HEAD 2>/dev/null || true)"
[[ -n "$version" ]] || version=unversioned
. /etc/os-release
modules='{}'
failed=0
successful=0
set_module(){
  local name="$1" state="$2" reason="$3"
  modules="$(jq -nc --argjson current "$modules" --arg name "$name" --arg status "$state" \
    --arg reason "$reason" '$current + {($name):{status:$status,reason:$reason}}')"
  printf '%-12s %s%s\n' "$name" "$state" "${reason:+  $reason}"
  [[ "$state" != FAILED ]] || failed=1
  [[ "$state" != SUCCESS || "$name" == snapshot ]] || successful=1
}

if bash "$script_dir/discover.sh" > "$bundle/snapshot.json" &&
   jq -e '.schema_version == 1' "$bundle/snapshot.json" >/dev/null; then
  set_module snapshot SUCCESS ''
else
  rm -f -- "$bundle/snapshot.json"
  set_module snapshot FAILED '环境快照生成失败'
fi

findings="$(bash "$script_dir/backup-secrets.sh" "$mode" "$bundle/snapshot.json" "${paths[@]}")"
if [[ -n "$findings" ]]; then
  printf '发现可能的敏感文件：\n%s\n' "$findings" >&2
fi
if [[ "$secret_policy" == ask ]]; then
  secret_policy=skip
  if [[ -n "$findings" && -t 0 && -t 2 ]]; then
    printf '处理方式：[s] 跳过（默认） / [i] 包含 / [e] 加密备份：' >&2
    IFS= read -r answer
    case "$answer" in
      i|I) secret_policy=include ;;
      e|E) secret_policy=encrypt ;;
    esac
  fi
fi
if [[ "$secret_policy" == include ]]; then
  echo '已明确选择包含可能的敏感文件；输出目录仅供授权用户访问。' >&2
elif [[ "$secret_policy" == encrypt ]]; then
  command -v gpg >/dev/null 2>&1 || { echo '加密备份需要 GPG。' >&2; exit 1; }
  [[ -t 0 && -r /dev/tty && -w /dev/tty ]] || {
    echo '加密备份需要交互式终端输入口令。' >&2; exit 1;
  }
  printf '加密备份口令：' > /dev/tty
  IFS= read -r -s passphrase < /dev/tty
  printf '\n确认口令：' > /dev/tty
  IFS= read -r -s confirmation < /dev/tty
  printf '\n' > /dev/tty
  [[ -n "$passphrase" && "$passphrase" == "$confirmation" ]] || {
    unset passphrase confirmation
    echo '口令为空或两次输入不一致。' >&2; exit 1;
  }
  unset confirmation
fi
export SERVER_SHELL_KIT_BACKUP_SECRETS="$secret_policy"

if [[ "$mode" == config || "$mode" == full ]]; then
  if SERVER_SHELL_KIT_BACKUP_STRICT=1 bash "$script_dir/backup-config.sh" "$bundle"; then
    set_module config SUCCESS ''
  else set_module config FAILED '配置采集不完整；详见 config-status.json'; fi
  if [[ -f "$bundle/config-status.json" ]]; then
    modules="$(jq -nc --argjson current "$modules" \
      --slurpfile details "$bundle/config-status.json" \
      '$current | .config.details = $details[0]')"
  fi
else set_module config SKIPPED '当前备份类型未选择'; fi

if [[ "$mode" == data || "$mode" == full ]]; then
  if bash "$script_dir/backup-docker.sh" "$bundle"; then
    set_module docker SUCCESS '详见 docker/status.json'
  else
    status=$?
    if (( status == 3 )); then set_module docker SKIPPED 'Docker 未安装'
    else set_module docker FAILED 'Docker 元数据或 Volume 备份失败'; fi
  fi
  if [[ -f "$bundle/docker/status.json" ]]; then
    modules="$(jq -nc --argjson current "$modules" \
      --slurpfile details "$bundle/docker/status.json" \
      '$current | .docker.details = $details[0]')"
  fi
  if (( ${#paths[@]} > 0 )); then
    if bash "$script_dir/backup-files.sh" "$bundle" "${paths[@]}"; then
      set_module files SUCCESS '按读取时状态归档；运行中的文件未冻结'
    else set_module files FAILED '至少一个自定义目录备份失败'; fi
  else set_module files SKIPPED '未指定自定义目录'; fi
  if (( ${#postgres_databases[@]} > 0 )); then
    if bash "$script_dir/backup-postgresql.sh" "$bundle" "$postgres_source" \
      "$postgres_user" "${postgres_databases[@]}"; then
      set_module postgresql SUCCESS ''
    else set_module postgresql FAILED 'PostgreSQL 导出失败'; fi
  elif [[ -f "$bundle/snapshot.json" ]] &&
       jq -e '[.databases.postgresql.systemd.status,.databases.postgresql.docker.status] |
         any(. == "running" or . == "installed")' "$bundle/snapshot.json" >/dev/null; then
    set_module postgresql FAILED '检测到 PostgreSQL，但未指定数据库名'
  else set_module postgresql SKIPPED '未指定数据库名'; fi
  if (( ${#mysql_databases[@]} > 0 )); then
    if bash "$script_dir/backup-mysql.sh" "$bundle" "$mysql_source" \
      "$mysql_user" "${mysql_databases[@]}"; then
      set_module mysql SUCCESS ''
    else set_module mysql FAILED 'MySQL/MariaDB 导出失败'; fi
  elif [[ -f "$bundle/snapshot.json" ]] &&
       jq -e '[.databases.mysql.systemd.status,.databases.mysql.docker.status,
         .databases.mariadb.systemd.status,.databases.mariadb.docker.status] |
         any(. == "running" or . == "installed")' "$bundle/snapshot.json" >/dev/null; then
    set_module mysql FAILED '检测到 MySQL/MariaDB，但未指定数据库名'
  else set_module mysql SKIPPED '未指定数据库名'; fi
else
  set_module docker SKIPPED '当前备份类型未选择'
  set_module files SKIPPED '当前备份类型未选择'
  set_module postgresql SKIPPED '当前备份类型未选择'
  set_module mysql SKIPPED '当前备份类型未选择'
fi

files='[]'
while IFS= read -r -d '' file; do
  relative="${file#"$bundle"/}"
  checksum="$(sha256sum -- "$file")"
  checksum="${checksum%% *}"
  size="$(stat -c '%s' -- "$file")"
  entry="$(jq -nc --arg path "$relative" --arg sha256 "$checksum" --argjson size_bytes "$size" \
    '{path:$path,size_bytes:$size_bytes,sha256:$sha256}')"
  files="$(jq -nc --argjson files "$files" --argjson entry "$entry" '$files + [$entry]')"
done < <(find "$bundle" -type f ! -name manifest.json -print0)
jq -n --argjson schema_version 1 --arg created_at "$created_at" \
  --arg hostname "$(hostname)" --arg os "${PRETTY_NAME:-unknown}" \
  --arg server_shell_kit_version "$version" --arg type "$mode" \
  --arg secret_policy "$secret_policy" \
  --argjson modules "$modules" --argjson files "$files" \
  '{schema_version:$schema_version,created_at:$created_at,hostname:$hostname,os:$os,
    server_shell_kit_version:$server_shell_kit_version,type:$type,
    secret_policy:$secret_policy,modules:$modules,files:$files}' \
  > "$bundle/manifest.json"
if [[ "$secret_policy" == encrypt ]]; then
  encrypted="$bundle.tar.gz.gpg"
  encrypted_partial="$encrypted.partial"
  gpg_home="$(mktemp -d "$output_dir/.server-shell-kit-gpg-XXXXXXXX")"
  if tar -C "$output_dir" -czf - "$(basename -- "$bundle")" |
     GNUPGHOME="$gpg_home" gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 \
       --cipher-algo AES256 --symmetric --output "$encrypted_partial" 3<<< "$passphrase"; then
    unset passphrase
    mv -- "$encrypted_partial" "$encrypted"
    encrypted_partial=''
    rm -rf -- "$bundle"
    printf '加密备份文件：%s\n' "$encrypted"
  else
    unset passphrase
    echo '备份加密失败，临时明文目录将清理。' >&2
    exit 1
  fi
else
  bundle_complete=1
  printf '备份目录：%s\n' "$bundle"
fi
if (( failed )); then exit 1; fi
if (( successful == 0 )); then
  echo '没有完成任何备份模块。' >&2
  exit 1
fi
