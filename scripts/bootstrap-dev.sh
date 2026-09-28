#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
command -v apt-get >/dev/null 2>&1 || { echo '开发环境目前仅支持 Debian/Ubuntu。' >&2; exit 1; }
run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y \
  build-essential pkg-config
printf '开发工具安装完成。\n'
