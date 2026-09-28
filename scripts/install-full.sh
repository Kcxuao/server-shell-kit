#!/usr/bin/env bash
set -Eeuo pipefail
BASE="https://raw.githubusercontent.com/${SERVER_SHELL_KIT_OWNER:-Kcxuao}/${SERVER_SHELL_KIT_REPO:-server-shell-kit}/${SERVER_SHELL_KIT_REF:-main}/scripts"
run(){ local s="$1" t; t="$(mktemp)"; curl -fsSL "$BASE/$s" -o "$t"; SERVER_SHELL_KIT_OWNER="${SERVER_SHELL_KIT_OWNER:-Kcxuao}" SERVER_SHELL_KIT_REPO="${SERVER_SHELL_KIT_REPO:-server-shell-kit}" SERVER_SHELL_KIT_REF="${SERVER_SHELL_KIT_REF:-main}" bash "$t"; rm -f "$t"; }
run install-zsh.sh
run install-plugins.sh
run install-starship.sh
run install-aliases.sh
run install-danger-guard.sh
echo '完整环境安装完成。建议退出 SSH 后重新登录。'
