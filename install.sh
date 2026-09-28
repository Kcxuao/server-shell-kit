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
  [[ -f "$TARGET_HOME/.config/zsh/plugins/dangerous-command-guard/dangerous-command-guard.plugin.zsh" ]] && guard=1
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
    scripts/setup-admin-user.sh scripts/setup-ssh-key.sh scripts/setup-firewall.sh
    scripts/switch-apt-mirror.sh scripts/migrate-config.sh
    scripts/install-language-manager.sh
    scripts/configure-programming-mirror.py
    scripts/configure-rm-backup.sh
    scripts/doctor.sh
    scripts/configure-docker-mirrors.sh
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
  menu_item 2 '安装终端环境'
  menu_item 3 '自选终端组件  ›'
  menu_item 4 '编程环境安装  ›'
  menu_item 5 '环境体检  ›'
  menu_item 6 'Docker 安装与镜像加速  ›'
  printf '\n  %b管理配置%b\n' "$BOLD" "$RESET"
  menu_item 7 '更新已安装的工具配置'
  menu_item 8 '卸载工具配置'
  menu_item 9 'rm -rf 自动备份设置'
  printf '\n'
  menu_item 0 '退出'
  line
}

show_components(){
  local -n boxes=$1
  local -a labels=('Zsh' 'Starship 提示符' '自动建议与语法高亮' '高危命令保护' '常用 Alias')
  local i mark left right
  header
  printf '\n  %b自选终端组件%b  /  方向键移动 · Enter 选择\n' "$BOLD" "$RESET"
  printf '  目标用户  %s\n\n' "$TARGET_USER"
  for i in "${!labels[@]}"; do
    mark=' '
    [[ "${boxes[i]}" == 1 ]] && mark='✓'
    if (( i == component_cursor )); then
      printf '  %b› [%s] %s%b\n' "$CYAN$BOLD" "$mark" "${labels[i]}" "$RESET"
    else
      printf '    [%s] %s\n' "$mark" "${labels[i]}"
    fi
  done
  printf '\n'
  left='  返回主菜单'; right='  下一步'
  (( component_cursor == 5 )) && left='› 返回主菜单'
  (( component_cursor == 6 )) && right='› 下一步'
  if (( component_cursor == 5 )); then
    printf '  %b%s%b                  %s\n' "$CYAN$BOLD" "$left" "$RESET" "$right"
  elif (( component_cursor == 6 )); then
    printf '  %s                  %b%s%b\n' "$left" "$CYAN$BOLD" "$right" "$RESET"
  else
    printf '  %s                  %s\n' "$left" "$right"
  fi
  printf '\n'
  line
}

component_menu(){
  if [[ ! -t 0 || ! -t 1 || -z "${TERM:-}" || "$TERM" == dumb ]]; then
    printf '自选终端组件需要交互式终端。\n'
    pause_menu
    return 0
  fi
  local -a checked=(0 0 0 0 0)
  if [[ "${1:-}" =~ ^[0-4]$ ]]; then checked[$1]=1; fi
  local -a names=('Zsh' 'Starship 提示符' '自动建议与语法高亮' '高危命令保护' '常用 Alias')
  local -a scripts=(install-zsh.sh install-starship.sh install-plugins.sh install-danger-guard.sh install-aliases.sh)
  local -a selected=() failed=()
  local key rest i name
  local component_cursor=0
  while true; do
    show_components checked
    IFS= read -rsn1 key || return 0
    case "$key" in
      $'\e')
        IFS= read -rsn1 -t 0.2 rest || continue
        [[ "$rest" == '[' ]] || continue
        IFS= read -rsn1 -t 0.2 rest || continue
        case "$rest" in
          A) if (( component_cursor >= 5 )); then component_cursor=4
             elif (( component_cursor > 0 )); then component_cursor=$((component_cursor - 1)); fi ;;
          B) (( component_cursor < 5 )) && ((component_cursor+=1)) || true ;;
          C) (( component_cursor == 5 )) && component_cursor=6 || true ;;
          D) (( component_cursor == 6 )) && component_cursor=5 || true ;;
        esac
        ;;
      '')
        if (( component_cursor < 5 )); then
          if [[ "${checked[component_cursor]}" == 0 ]]; then checked[component_cursor]=1; else checked[component_cursor]=0; fi
        elif (( component_cursor == 5 )); then
          return 0
        else
          selected=()
          for i in 0 1 2 3 4; do [[ "${checked[i]}" == 1 ]] && selected+=("${names[i]}"); done
          if (( ${#selected[@]} == 0 )); then
            printf '\n  请先勾选至少一个组件。按 Enter 继续...'
            IFS= read -r _ || return 0
            continue
          fi
          printf '\n  已选择：%s\n' "${selected[*]}"
          if ! preflight '安装所选终端组件'; then
            printf '已取消。按 Enter 继续...'
            IFS= read -r _ || return 0
            continue
          fi
          failed=()
          for i in 0 1 2 3 4; do
            [[ "${checked[i]}" == 1 ]] || continue
            name="${names[i]}"
            printf '\n%b▶ 正在安装：%s%b\n' "$CYAN" "$name" "$RESET"
            if bash "$REPO_DIR/scripts/${scripts[i]}"; then
              printf '%b✓ %s 完成%b\n' "$GREEN" "$name" "$RESET"
            else
              failed+=("$name")
              printf '%b✗ %s 失败，请检查上方错误信息。%b\n' "$RED" "$name" "$RESET"
            fi
          done
          printf '\n安装结果：\n'
          for name in "${selected[@]}"; do
            if [[ " ${failed[*]} " == *" $name "* ]]; then
              printf '  ✗ %s\n' "$name"
            else
              printf '  ✓ %s\n' "$name"
            fi
          done
          printf '重新打开 Zsh 后查看效果。\n'
          printf '\n按 Enter 返回主菜单...'
          IFS= read -r _ || true
          return 0
        fi
        ;;
    esac
  done
}

show_languages(){
  local -n boxes=$1
  local -a labels=('Java + Maven · SDKMAN' 'Python · uv' 'Node.js + npm · nvm' 'Rust + Cargo · rustup')
  local i mark left right
  header
  printf '\n  %b编程环境安装%b  /  方向键移动 · Enter 选择\n' "$BOLD" "$RESET"
  printf '  目标用户  %s\n\n' "$TARGET_USER"
  for i in "${!labels[@]}"; do
    mark=' '
    [[ "${boxes[i]}" == 1 ]] && mark='✓'
    if (( i == language_cursor )); then
      printf '  %b› [%s] %s%b\n' "$CYAN$BOLD" "$mark" "${labels[i]}" "$RESET"
    else
      printf '    [%s] %s\n' "$mark" "${labels[i]}"
    fi
  done
  printf '\n'
  left='  返回主菜单'; right='  下一步'
  (( language_cursor == 4 )) && left='› 返回主菜单'
  (( language_cursor == 5 )) && right='› 下一步'
  if (( language_cursor == 4 )); then
    printf '  %b%s%b                  %s\n' "$CYAN$BOLD" "$left" "$RESET" "$right"
  elif (( language_cursor == 5 )); then
    printf '  %s                  %b%s%b\n' "$left" "$CYAN$BOLD" "$right" "$RESET"
  else
    printf '  %s                  %s\n' "$left" "$right"
  fi
  printf '\n'
  line
}

language_menu(){
  if [[ ! -t 0 || ! -t 1 || -z "${TERM:-}" || "$TERM" == dumb ]]; then
    printf '编程环境安装需要交互式终端。\n'
    pause_menu
    return 0
  fi
  local -a checked=(0 0 0 0) names=(java python node rust) selected=()
  if [[ "${1:-}" =~ ^[0-3]$ ]]; then checked[$1]=1; fi
  local key rest i answer result
  local language_cursor=0
  while true; do
    show_languages checked
    IFS= read -rsn1 key || return 0
    case "$key" in
      $'\e')
        IFS= read -rsn1 -t 0.2 rest || continue
        [[ "$rest" == '[' ]] || continue
        IFS= read -rsn1 -t 0.2 rest || continue
        case "$rest" in
          A) if (( language_cursor >= 4 )); then language_cursor=3
             elif (( language_cursor > 0 )); then language_cursor=$((language_cursor - 1)); fi ;;
          B) (( language_cursor < 4 )) && ((language_cursor+=1)) || true ;;
          C) (( language_cursor == 4 )) && language_cursor=5 || true ;;
          D) (( language_cursor == 5 )) && language_cursor=4 || true ;;
        esac
        ;;
      '')
        if (( language_cursor < 4 )); then
          if [[ "${checked[language_cursor]}" == 0 ]]; then checked[language_cursor]=1; else checked[language_cursor]=0; fi
        elif (( language_cursor == 4 )); then
          return 0
        else
          selected=()
          for i in 0 1 2 3; do [[ "${checked[i]}" == 1 ]] && selected+=("${names[i]}"); done
          if (( ${#selected[@]} == 0 )); then
            printf '\n  请先勾选至少一种语言。按 Enter 继续...'
            IFS= read -r _ || return 0
            continue
          fi
          printf '\n  将为 %s 安装：%s\n' "$TARGET_USER" "${selected[*]}"
          printf '  输入 yes 开始，其他内容取消：'
          IFS= read -r answer || return 0
          if [[ "$answer" == [Yy][Ee][Ss] ]]; then
            if bash "$REPO_DIR/scripts/install-language-manager.sh" "${selected[@]}"; then result=0; else result=1; fi
            printf '\n  按 Enter 返回主菜单...'
            IFS= read -r _ || true
            return "$result"
          fi
        fi
        ;;
    esac
  done
}

docker_menu(){
  local choice answer
  while true; do
    header
    printf '\n  %bDocker 安装与镜像加速%b\n' "$BOLD" "$RESET"
    printf '  1  安装 Docker 与 Compose，并设置镜像加速源\n'
    printf '  2  仅配置或更新镜像加速源\n'
    printf '  0  返回主菜单\n'
    line
    printf '  选择操作  › '
    IFS= read -r choice || return 0
    case "$choice" in
      1)
        printf '\n将安装发行版提供的 Docker 包及可用的 Compose 插件。输入 yes 继续：'
        IFS= read -r answer || return 0
        if [[ "$answer" == [Yy][Ee][Ss] ]]; then
          bash "$REPO_DIR/scripts/bootstrap-container.sh" || true
        else
          printf '已取消。\n'
        fi
        pause_menu
        ;;
      2)
        bash "$REPO_DIR/scripts/configure-docker-mirrors.sh" || true
        pause_menu
        ;;
      0) return 0 ;;
      *) printf '请输入 0-2。\n'; pause_menu ;;
    esac
  done
}

doctor_menu(){
  local -a report=() issue_dest=() issue_focus=()
  local -a pending=('Zsh' 'Starship' '自动建议与语法高亮' '常用 Alias' '高危命令保护' 'Java' 'Python' 'Node.js' 'Rust' 'Docker' 'SSH' 'UFW' 'SSH 公钥')
  local -a frames=('·' '··' '···')
  local entry key state label reason dest focus choice item number doctor_fd doctor_pid read_status ticks
  if ! command -v setsid >/dev/null 2>&1; then
    printf '环境体检需要 setsid，当前系统未找到该命令。\n'
    pause_menu
    return 1
  fi
  while true; do
    header
    printf '\n  %b环境体检%b  /  目标用户 %s\n' "$BOLD" "$RESET" "$TARGET_USER"
    printf '  正在逐项检查，结果会随完成实时显示。\n'
    report=()
    issue_dest=(); issue_focus=()
    coproc DOCTOR { setsid -w bash "$REPO_DIR/scripts/doctor.sh" </dev/null; }
    doctor_fd="${DOCTOR[0]}"
    doctor_pid="$DOCTOR_PID"
    ticks=0
    while true; do
      if IFS= read -r -t 0.25 -u "$doctor_fd" entry; then
        item="${#report[@]}"
        report+=("$entry")
        if [[ -t 1 && "${TERM:-}" != dumb ]]; then printf '\r\033[K'; fi
      else
        read_status=$?
        if (( read_status > 128 )); then
          if [[ -t 1 && "${TERM:-}" != dumb ]]; then
            printf '\r\033[K  正在检测：%s %s' "${pending[${#report[@]}]:-收尾}" "${frames[ticks % 3]}"
          fi
          ((ticks+=1))
          continue
        fi
        break
      fi
      IFS=$'\t' read -r key state label reason dest focus <<< "$entry"
      case "$item" in
        0) printf '\n  %b终端组件%b\n' "$BOLD" "$RESET" ;;
        5) printf '\n  %b编程环境%b\n' "$BOLD" "$RESET" ;;
        9) printf '\n  %b服务器服务%b\n' "$BOLD" "$RESET" ;;
      esac
      case "$state" in
        ok) printf '  %b✓ 正常%b  %s：%s\n' "$GREEN" "$RESET" "$label" "$reason" ;;
        missing) printf '  %b○ 未安装%b  %s：%s\n' "$YELLOW" "$RESET" "$label" "$reason" ;;
        issue)
          number=$(( ${#issue_dest[@]} + 1 ))
          printf '  %b! 异常%b  %s：%s  [处理 %s]\n' "$RED" "$RESET" "$label" "$reason" "$number"
          issue_dest+=("$dest"); issue_focus+=("$focus")
          ;;
        unknown) printf '  %b? 无法判断%b  %s：%s\n' "$YELLOW" "$RESET" "$label" "$reason" ;;
      esac
      if (( ${#report[@]} < ${#pending[@]} )); then
        if [[ -t 1 && "${TERM:-}" != dumb ]]; then
          printf '  正在检测：%s' "${pending[${#report[@]}]}"
        fi
      fi
    done
    if [[ -t 1 && "${TERM:-}" != dumb ]]; then printf '\r\033[K'; fi
    if ! wait "$doctor_pid" || (( ${#report[@]} != ${#pending[@]} )); then
      printf '\n  环境体检未能完成，请检查上方错误信息。\n'
      pause_menu
      return 1
    fi
    printf '\n'
    line
    if (( ${#issue_dest[@]} == 0 )); then
      printf '  没有需要处理的异常项。按 Enter 返回主菜单...'
      IFS= read -r _ || true
      return 0
    fi
    printf '  输入处理编号进入对应菜单；输入 0 返回主菜单：'
    IFS= read -r choice || return 0
    [[ "$choice" == 0 ]] && return 0
    if [[ ! "$choice" =~ ^[1-9][0-9]*$ ]] || (( choice > ${#issue_dest[@]} )); then
      printf '  编号无效。按 Enter 继续...'
      IFS= read -r _ || return 0
      continue
    fi
    case "${issue_dest[choice-1]}" in
      component) component_menu "${issue_focus[choice-1]}" ;;
      language) language_menu "${issue_focus[choice-1]}" || true ;;
      bootstrap) bash "$REPO_DIR/scripts/bootstrap.sh" --focus "${issue_focus[choice-1]}" ;;
      docker) docker_menu ;;
    esac
  done
}

main(){
  download_repo
  local choice
  while true; do
    show_menu
    printf '  %b选择操作%b  › ' "$BOLD" "$RESET"
    IFS= read -r choice || { printf '\n'; return 0; }
    case "$choice" in
      1) bash "$REPO_DIR/scripts/bootstrap.sh" ;;
      2) run_local install-full.sh '安装终端环境'; pause_menu ;;
      3) component_menu ;;
      4) language_menu || true ;;
      5) doctor_menu || true ;;
      6) docker_menu ;;
      7) run_local update-config.sh '更新已安装的工具配置'; pause_menu ;;
      8) run_local uninstall.sh '卸载工具配置'; pause_menu ;;
      9) bash "$REPO_DIR/scripts/configure-rm-backup.sh"; pause_menu ;;
      0) return 0 ;;
      *) printf '%b无效选项，请输入 0-9。%b\n' "$RED" "$RESET"; pause_menu ;;
    esac
  done
}
main "$@"
