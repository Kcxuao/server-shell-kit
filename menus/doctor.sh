#!/usr/bin/env bash
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
    exec {doctor_fd}<&"${DOCTOR[0]}"
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
    exec {doctor_fd}<&-
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
