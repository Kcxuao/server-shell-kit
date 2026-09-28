#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
shopt -s extglob

config_file="${SERVER_SHELL_KIT_DOCKER_DAEMON_CONFIG:-/etc/docker/daemon.json}"
[[ "$config_file" == /* ]] || { echo 'Docker 配置路径必须是绝对路径。' >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo '配置镜像加速源需要 jq。' >&2; exit 1; }
command -v dockerd >/dev/null 2>&1 || { echo '请先安装 Docker。' >&2; exit 1; }
command -v systemctl >/dev/null 2>&1 || { echo '需要 systemd 管理 Docker 服务。' >&2; exit 1; }

if (( $# == 0 )); then
  [[ -t 0 ]] || { echo '用法：configure-docker-mirrors.sh https://镜像地址 [...]' >&2; exit 2; }
  printf 'Docker Hub 镜像加速地址（多个用逗号分隔，留空取消）：'
  IFS= read -r input || exit 1
  [[ -n "$input" ]] || { echo '未修改镜像配置。'; exit 0; }
  IFS=',' read -r -a requested <<< "$input"
else
  requested=("$@")
fi

declare -a mirrors=()
declare -A seen=()
for url in "${requested[@]}"; do
  url="${url##+([[:space:]])}"
  url="${url%%+([[:space:]])}"
  [[ "$url" =~ ^https://[A-Za-z0-9][A-Za-z0-9.-]*(:[0-9]{1,5})?/?$ ]] || {
    printf '镜像地址无效：%s（需要 HTTPS 地址）\n' "$url" >&2; exit 2;
  }
  url="${url%/}"
  [[ -n "${seen[$url]:-}" ]] || mirrors+=("$url")
  seen[$url]=1
done
(( ${#mirrors[@]} > 0 )) || { echo '没有可用的镜像地址。' >&2; exit 2; }

printf '将设置 Docker Hub 镜像加速源：\n'
printf '  %s\n' "${mirrors[@]}"
printf '会保留 daemon.json 的其他设置，并重启 Docker 服务。\n'
if (( $# == 0 )); then
  printf '输入 yes 继续，其他内容取消：'
  IFS= read -r answer || exit 1
  [[ "$answer" == [Yy][Ee][Ss] ]] || { echo '已取消。'; exit 0; }
fi

workdir="$(mktemp -d)"
trap 'rm -rf -- "$workdir"' EXIT
config_exists=0
config_mode=0644
if run_root test -e "$config_file"; then
  config_exists=1
  config_mode="$(run_root stat -c '%a' "$config_file")"
  run_root cp -p "$config_file" "$workdir/original"
  run_root cat "$config_file" > "$workdir/before"
  jq -e 'type == "object"' "$workdir/before" >/dev/null || { echo '现有 daemon.json 不是有效 JSON 对象，未修改。' >&2; exit 1; }
else
  printf '{}\n' > "$workdir/before"
fi
mirrors_json="$(jq -n '$ARGS.positional' --args "${mirrors[@]}")"
if jq -e --argjson mirrors "$mirrors_json" '."registry-mirrors" == $mirrors' "$workdir/before" >/dev/null; then
  echo '镜像配置已是目标状态，无需重启 Docker。'
  exit 0
fi
jq --argjson mirrors "$mirrors_json" '."registry-mirrors" = $mirrors' "$workdir/before" > "$workdir/after"
run_root dockerd --validate --config-file "$workdir/after" >/dev/null || { echo 'Docker 配置校验失败，未修改。' >&2; exit 1; }
if ! run_root test -d "$(dirname "$config_file")"; then
  run_root install -d -m 0755 "$(dirname "$config_file")"
fi
if (( config_exists )) && ! run_root test -e "$config_file.server-shell-kit.bak"; then
  run_root cp -p "$config_file" "$config_file.server-shell-kit.bak"
  printf '已备份：%s\n' "$config_file.server-shell-kit.bak"
fi
run_root install -m "$config_mode" -o root -g root "$workdir/after" "$config_file"
if run_root systemctl restart docker && run_root systemctl is-active --quiet docker; then
  echo '镜像加速源已配置，Docker 服务运行正常。'
else
  echo 'Docker 重启失败，正在恢复修改前的配置。' >&2
  if (( config_exists )); then
    run_root cp -p "$workdir/original" "$config_file"
  else
    run_root rm -f "$config_file"
  fi
  run_root systemctl restart docker || true
  exit 1
fi
