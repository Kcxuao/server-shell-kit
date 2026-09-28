#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
run(){ bash "$SCRIPT_DIR/$1"; }
run install-zsh.sh
run install-plugins.sh
run install-starship.sh
run install-aliases.sh
run install-danger-guard.sh
echo '完整环境安装完成。建议退出 SSH 后重新登录。'
