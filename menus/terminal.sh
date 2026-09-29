#!/usr/bin/env bash
guard_menu(){
  local choice
  while true; do
    header
    printf '\n  %b高危命令保护设置%b\n' "$BOLD" "$RESET"
    printf '  1  查看当前 Impact Guard 状态\n'
    printf '  2  启用 Impact Guard\n'
    printf '  3  禁用 Impact Guard\n'
    printf '  4  查看 rm 递归删除备份状态\n'
    printf '  5  启用 rm 递归删除备份\n'
    printf '  6  禁用 rm 递归删除备份\n'
    printf '  0  返回终端环境\n'
    line
    printf '  选择操作  › '
    IFS= read -r choice || return 0
    case "$choice" in
      1) bash "$REPO_DIR/scripts/configure-danger-guard.sh" status || true ;;
      2) bash "$REPO_DIR/scripts/configure-danger-guard.sh" enable || true ;;
      3) bash "$REPO_DIR/scripts/configure-danger-guard.sh" disable || true ;;
      4) bash "$REPO_DIR/scripts/configure-rm-backup.sh" status || true ;;
      5) bash "$REPO_DIR/scripts/configure-rm-backup.sh" enable || true ;;
      6) bash "$REPO_DIR/scripts/configure-rm-backup.sh" disable || true ;;
      0) return 0 ;;
      *) printf '请输入 0-6。\n' ;;
    esac
    pause_menu
  done
}

terminal_menu(){
  local choice
  while true; do
    header
    printf '\n  %b终端环境%b\n' "$BOLD" "$RESET"
    printf '  1  安装完整终端环境\n'
    printf '  2  自选终端组件\n'
    printf '  3  高危命令保护设置\n'
    printf '  0  返回主菜单\n'
    line
    printf '  选择操作  › '
    IFS= read -r choice || return 0
    case "$choice" in
      1) run_local install-full.sh '安装终端环境'; pause_menu ;;
      2) component_menu ;;
      3) guard_menu ;;
      0) return 0 ;;
      *) printf '请输入 0-3。\n'; pause_menu ;;
    esac
  done
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
