#!/usr/bin/env bash
set -Eeuo pipefail

REPO_OWNER="${SERVER_SHELL_KIT_OWNER:-Kcxuao}"
REPO_NAME="${SERVER_SHELL_KIT_REPO:-server-shell-kit}"
REPO_REF="${SERVER_SHELL_KIT_REF:-main}"
ARCHIVE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/archive/refs/heads/${REPO_REF}.tar.gz"
WORK_DIR=''
REPO_DIR=''

RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; CYAN='\033[36m'; BOLD='\033[1m'; RESET='\033[0m'

line(){ printf '%s\n' '============================================================'; }
pause_menu(){ printf '\n按 Enter 返回主菜单...'; read -r _; }
header(){ clear 2>/dev/null || true; printf "%b" "$CYAN$BOLD"; line; printf '                  Server Shell Kit\n'; line; printf "%b\n" "$RESET"; printf 'Linux 服务器 Zsh 美化与高危命令防误操作工具\n\n'; }

ensure_curl(){
  command -v curl >/dev/null 2>&1 && return 0
  echo '未检测到 curl，尝试安装...'
  if command -v apt-get >/dev/null 2>&1; then
    if [[ $EUID -eq 0 ]]; then apt-get update && apt-get install -y curl; else sudo apt-get update && sudo apt-get install -y curl; fi
  else
    echo '请先安装 curl。'; exit 1
  fi
}

cleanup(){ [[ -z "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"; }

download_repo(){
  if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "$REPO_DIR/scripts/common.sh" && -f "$REPO_DIR/scripts/install-full.sh" ]]; then
      return 0
    fi
  fi
  WORK_DIR="$(mktemp -d)" || { echo '创建临时目录失败。' >&2; return 1; }
  trap cleanup EXIT
  printf '正在下载仓库：%s\n' "$ARCHIVE_URL"
  if ! curl -fL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 120 -o "$WORK_DIR/main.tar.gz" "$ARCHIVE_URL"; then
    echo '仓库下载失败。' >&2; return 1
  fi
  if ! tar -xzf "$WORK_DIR/main.tar.gz" -C "$WORK_DIR"; then
    echo '仓库解压失败。' >&2; return 1
  fi
  REPO_DIR="$WORK_DIR/$REPO_NAME-$REPO_REF"
  if [[ ! -f "$REPO_DIR/scripts/common.sh" || ! -f "$REPO_DIR/scripts/install-full.sh" ]]; then
    echo '归档缺少必要脚本。' >&2; return 1
  fi
}

run_local(){
  local script="$1" name="$2"
  printf '\n%b正在执行：%s%b\n' "$CYAN" "$name" "$RESET"
  bash "$REPO_DIR/scripts/$script"
}

show_menu(){
  header
  printf '%b请选择操作：%b\n\n' "$BOLD" "$RESET"
  printf '  %b1)%b 安装完整环境\n' "$GREEN" "$RESET"
  printf '  %b2)%b 仅安装 Zsh\n' "$GREEN" "$RESET"
  printf '  %b3)%b 安装 Starship 美化\n' "$GREEN" "$RESET"
  printf '  %b4)%b 安装自动建议 / 语法高亮\n' "$GREEN" "$RESET"
  printf '  %b5)%b 安装高危命令保护\n' "$GREEN" "$RESET"
  printf '  %b6)%b 安装常用 Alias\n' "$GREEN" "$RESET"
  printf '  %b7)%b 更新全部配置\n' "$YELLOW" "$RESET"
  printf '  %b8)%b 更新高危命令保护\n' "$YELLOW" "$RESET"
  printf '  %b9)%b 卸载本工具配置\n' "$RED" "$RESET"
  printf '  %b0)%b 退出\n\n' "$RED" "$RESET"
  line
}

main(){
  ensure_curl
  download_repo
  while true; do
    show_menu
    printf '请输入编号 [0-9]：'; read -r choice
    case "$choice" in
      1) run_local install-full.sh '完整环境'; pause_menu ;;
      2) run_local install-zsh.sh 'Zsh'; pause_menu ;;
      3) run_local install-starship.sh 'Starship'; pause_menu ;;
      4) run_local install-plugins.sh 'Zsh 插件'; pause_menu ;;
      5) run_local install-danger-guard.sh '高危命令保护'; pause_menu ;;
      6) run_local install-aliases.sh '常用 Alias'; pause_menu ;;
      7) run_local install-full.sh '全部配置更新'; pause_menu ;;
      8) run_local install-danger-guard.sh '高危命令保护更新'; pause_menu ;;
      9)
        printf '\n%b请输入 YES 确认卸载：%b' "$RED" "$RESET"; read -r confirm
        [[ "$confirm" == 'YES' ]] && run_local uninstall.sh '卸载' || echo '已取消。'
        pause_menu
        ;;
      0) exit 0 ;;
      *) printf '\n%b无效选项。%b\n' "$RED" "$RESET"; sleep 1 ;;
    esac
  done
}
main "$@"
