#!/usr/bin/env bash
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
          if bash "$REPO_DIR/scripts/install-docker.sh"; then
            if [[ -t 0 ]]; then
              printf '\n可继续配置 Docker Hub 镜像加速源。\n'
              bash "$REPO_DIR/scripts/configure-docker-mirrors.sh" || true
            fi
          fi
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
