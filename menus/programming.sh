#!/usr/bin/env bash
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
