#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
command -v apt-get >/dev/null 2>&1 || { echo '防火墙配置目前仅支持 Debian/Ubuntu。' >&2; exit 1; }
ssh_port=22
if [[ -n "${SSH_CONNECTION:-}" ]]; then
  read -r _ _ _ detected_port <<< "$SSH_CONNECTION"
  [[ "$detected_port" =~ ^[0-9]+$ ]] && ssh_port="$detected_port"
fi
printf '当前 SSH 端口 [%s]：' "$ssh_port"
IFS= read -r answer || exit 1
ssh_port="${answer:-$ssh_port}"
valid_port(){ [[ "$1" =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 )); }
valid_port "$ssh_port" || { echo 'SSH 端口无效。' >&2; exit 1; }
printf '其他需要放行的 TCP 端口，逗号分隔（可留空）：'
IFS= read -r additional || exit 1
ports=("$ssh_port")
if [[ -n "$additional" ]]; then
  IFS=',' read -r -a extra_ports <<< "$additional"
  for port in "${extra_ports[@]}"; do
    port="${port//[[:space:]]/}"
    valid_port "$port" || { printf '端口无效：%s\n' "$port" >&2; exit 1; }
    ports+=("$port")
  done
fi
printf '将放行 TCP 端口：%s\n' "${ports[*]}"
printf '请输入 yes 安装并启用 UFW：'
IFS= read -r answer || exit 1
[[ "$answer" == [Yy][Ee][Ss] ]] || { echo '已取消。'; exit 0; }
run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y ufw
for port in "${ports[@]}"; do run_root ufw allow "$port/tcp"; done
run_root ufw --force enable
run_root ufw status
printf '防火墙已启用。请保持当前 SSH 会话，并从另一会话验证登录。\n'
