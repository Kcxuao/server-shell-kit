#!/usr/bin/env bash
set -Eeuo pipefail

BASE_URL="${SERVER_SHELL_KIT_BASE_URL:-https://build.kcxuao.art}"
BASE_URL="${BASE_URL%/}"
WORK_DIR=''
REPO_DIR=''

RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; CYAN='\033[36m'; BOLD='\033[1m'; RESET='\033[0m'
[[ -t 1 && "${TERM:-}" != dumb ]] || RED='' GREEN='' YELLOW='' CYAN='' BOLD='' RESET=''

line(){ printf '%b%s%b\n' "$CYAN" '  ────────────────────────────────────────────────' "$RESET"; }
pause_menu(){ printf '\n  按 Enter 返回菜单...'; IFS= read -r _ || true; }
header(){
  [[ -t 1 && -n "${TERM:-}" && "$TERM" != dumb ]] && clear 2>/dev/null || true
  printf '\n  %b%bSERVER SHELL KIT%b  %b/ 服务器配置%b\n' "$CYAN" "$BOLD" "$RESET" "$CYAN" "$RESET"
  line
}
status_chip(){
  if [[ "$2" == 1 ]]; then
    printf '%b●%b %s' "$GREEN" "$RESET" "$1"
  else
    printf '%b○%b %s' "$YELLOW" "$RESET" "$1"
  fi
}
menu_item(){ printf '  %b%2s%b  %s\n' "$CYAN$BOLD" "$1" "$RESET" "$2"; }
target_info(){
  if [[ $EUID -eq 0 ]]; then TARGET_USER="${SUDO_USER:-root}"; else TARGET_USER="$(id -un)"; fi
  TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
  [[ -n "$TARGET_HOME" && "$TARGET_HOME" != / ]] || { echo '无法确定目标用户的 HOME。' >&2; return 1; }
}
show_status(){
  target_info
  local zsh=0 starship=0 plugins=0 aliases=0 guard=0
  command -v zsh >/dev/null 2>&1 && zsh=1
  command -v starship >/dev/null 2>&1 && starship=1
  [[ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh && -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && plugins=1
  [[ -f "$TARGET_HOME/.config/zsh/server-shell-kit/aliases.zsh" ]] && aliases=1
  if [[ -f "$TARGET_HOME/.config/zsh/plugins/dangerous-command-guard/dangerous-command-guard.plugin.zsh" ]] &&
     [[ -f "$TARGET_HOME/.zshrc" ]] &&
     grep -Fq 'dangerous-command-guard.plugin.zsh' "$TARGET_HOME/.zshrc" &&
     { [[ ! -f "$TARGET_HOME/.config/zsh/server-shell-kit/danger-guard.conf" ]] ||
       ! grep -Fxq 'enabled=0' "$TARGET_HOME/.config/zsh/server-shell-kit/danger-guard.conf"; }; then
    guard=1
  fi
  printf '  %b目标%b  %s  ·  %s\n' "$BOLD" "$RESET" "$TARGET_USER" "$(. /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-未知系统}")"
  printf '  '
  status_chip Zsh "$zsh"; printf '   '; status_chip Starship "$starship"; printf '   '; status_chip 插件 "$plugins"
  printf '\n  '
  status_chip Alias "$aliases"; printf '   '; status_chip 命令保护 "$guard"
  printf '\n'

}
preflight(){
  local name="$1"
  target_info
  printf '\n%b即将执行：%s%b\n' "$CYAN$BOLD" "$name" "$RESET"
  printf '目标用户：%s\n配置位置：%s/.zshrc、%s/.config\n' "$TARGET_USER" "$TARGET_HOME" "$TARGET_HOME"
  if [[ "$name" == 卸载* ]]; then
    printf '仅移除工具文件和写入的启动配置行；已有备份保留。\n'
  else
    printf '已有配置首次覆盖前会保存为 *.server-shell-kit.bak。\n'
  fi
  printf '输入 yes 继续，其他内容取消：'
  local answer
  IFS= read -r answer || return 1
  [[ "$answer" == [Yy][Ee][Ss] ]]
}

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
  ensure_curl
  WORK_DIR="$(mktemp -d)" || { echo '创建临时目录失败。' >&2; return 1; }
  trap cleanup EXIT
  REPO_DIR="$WORK_DIR/server-shell-kit"
  local file
  local files=(
    scripts/common.sh scripts/install-full.sh scripts/install-zsh.sh
    scripts/install-plugins.sh scripts/install-starship.sh
    scripts/install-aliases.sh scripts/install-danger-guard.sh
    scripts/uninstall.sh scripts/update-config.sh scripts/bootstrap.sh
    scripts/bootstrap-base.sh scripts/bootstrap-dev.sh scripts/bootstrap-container.sh
    scripts/install-docker.sh
    scripts/setup-admin-user.sh scripts/setup-ssh-key.sh scripts/setup-firewall.sh
    scripts/switch-apt-mirror.sh scripts/migrate-config.sh
    scripts/backup.sh scripts/backup-config.sh scripts/backup-files.sh scripts/backup-secrets.sh
    scripts/plan.sh scripts/restore.sh scripts/restore-databases.sh
    scripts/backup-docker.sh scripts/backup-postgresql.sh scripts/backup-mysql.sh
    scripts/install-language-manager.sh
    scripts/configure-programming-mirror.py
    scripts/configure-rm-backup.sh
    scripts/configure-danger-guard.sh
    scripts/doctor.sh
    scripts/configure-docker-mirrors.sh
    scripts/discover.sh scripts/snapshot.sh
    menus/terminal.sh menus/programming.sh menus/docker.sh
    menus/doctor.sh menus/system-tools.sh
    configs/starship.toml configs/aliases.zsh
    plugins/dangerous-command-guard.plugin.zsh
  )
  printf '正在从 %s 下载安装文件...\n' "$BASE_URL"
  for file in "${files[@]}"; do
    mkdir -p -- "$REPO_DIR/${file%/*}"
    if ! curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 120 \
      -o "$REPO_DIR/$file" "$BASE_URL/$file"; then
      printf '下载失败：%s\n' "$BASE_URL/$file" >&2
      return 1
    fi
  done
}

run_local(){
  local script="$1" name="$2"
  if ! preflight "$name"; then printf '已取消。\n'; return 0; fi
  printf '\n%b▶ 正在执行：%s%b\n' "$CYAN" "$name" "$RESET"
  if bash "$REPO_DIR/scripts/$script"; then
    printf '%b✓ %s 完成%b\n' "$GREEN" "$name" "$RESET"
    printf '重新打开 Zsh 后查看效果；可用 dcg-status 检查命令保护。\n'
  else
    printf '%b✗ %s 失败，请检查上方错误信息。%b\n' "$RED" "$name" "$RESET"
  fi
}

show_menu(){
  header
  show_status
  printf '\n  %b开始使用%b\n' "$BOLD" "$RESET"
  menu_item 1 '新服务器初始化  ›'
  menu_item 2 '终端环境  ›'
  menu_item 3 '编程环境  ›'
  menu_item 4 'Docker  ›'
  menu_item 5 '环境体检  ›'
  menu_item 6 '系统工具  ›'
  menu_item 7 '更新配置'
  menu_item 8 '卸载'
  printf '\n'
  menu_item 0 '退出'
  line
}

main(){
  download_repo
  source "$REPO_DIR/menus/terminal.sh"
  source "$REPO_DIR/menus/programming.sh"
  source "$REPO_DIR/menus/docker.sh"
  source "$REPO_DIR/menus/doctor.sh"
  source "$REPO_DIR/menus/system-tools.sh"
  local choice
  while true; do
    show_menu
    printf '  %b选择操作%b  › ' "$BOLD" "$RESET"
    IFS= read -r choice || { printf '\n'; return 0; }
    case "$choice" in
      1) bash "$REPO_DIR/scripts/bootstrap.sh" ;;
      2) terminal_menu ;;
      3) language_menu || true ;;
      4) docker_menu ;;
      5) doctor_menu || true ;;
      6) system_tools_menu ;;
      7) run_local update-config.sh '更新已安装的工具配置'; pause_menu ;;
      8) run_local uninstall.sh '卸载工具配置'; pause_menu ;;
      0) return 0 ;;
      *) printf '%b无效选项，请输入 0-8。%b\n' "$RED" "$RESET"; pause_menu ;;
    esac
  done
}
main "$@"
