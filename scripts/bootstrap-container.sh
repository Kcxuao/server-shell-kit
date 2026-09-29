#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
bash "$REPO_DIR/scripts/install-docker.sh"
if [[ -t 0 ]]; then
  printf '\n可继续配置 Docker Hub 镜像加速源。\n'
  bash "$REPO_DIR/scripts/configure-docker-mirrors.sh"
fi
