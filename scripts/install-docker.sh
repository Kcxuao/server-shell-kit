#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

command -v apt-get >/dev/null 2>&1 || { echo '容器环境目前仅支持 Debian/Ubuntu。' >&2; exit 1; }
[[ "${SERVER_SHELL_KIT_SKIP_APT_UPDATE:-0}" == 1 ]] || run_root apt-get update

if ! command -v docker >/dev/null 2>&1 || ! command -v dockerd >/dev/null 2>&1; then
  run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io jq
elif ! command -v jq >/dev/null 2>&1; then
  run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y jq
fi

compose_package_available=0
if ! docker compose version >/dev/null 2>&1; then
  if apt-cache show docker-compose-plugin >/dev/null 2>&1; then
    compose_package_available=1
    run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y docker-compose-plugin
  elif apt-cache show docker-compose-v2 >/dev/null 2>&1; then
    compose_package_available=1
    run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y docker-compose-v2
  else
    echo '当前软件源没有 Compose 插件；Docker 已安装，Compose 请按发行版软件源另行安装。'
  fi
fi

run_root systemctl enable --now docker
if ! command -v docker >/dev/null 2>&1 ||
   ! command -v dockerd >/dev/null 2>&1 ||
   ! docker --version >/dev/null 2>&1 ||
   ! run_root systemctl is-active --quiet docker ||
   { (( compose_package_available )) && ! docker compose version >/dev/null 2>&1; }; then
  echo 'Docker 安装检查失败。' >&2; exit 1;
fi
printf 'Docker 安装完成。请使用 sudo docker；未自动修改用户组。\n'
