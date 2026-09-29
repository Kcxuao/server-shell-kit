#!/usr/bin/env bash
apt_mirror_menu(){
  local choice
  while true; do
    header
    printf '\n  %bAPT 镜像源切换%b\n' "$BOLD" "$RESET"
    printf '  1  切换清华 TUNA 镜像\n'
    printf '  2  切换中科大 USTC 镜像\n'
    printf '  3  恢复首次切换前的源\n'
    printf '  0  返回系统工具\n'
    line
    printf '  选择操作  › '
    IFS= read -r choice || return 0
    case "$choice" in
      1) bash "$REPO_DIR/scripts/switch-apt-mirror.sh" tuna || true ;;
      2) bash "$REPO_DIR/scripts/switch-apt-mirror.sh" ustc || true ;;
      3) bash "$REPO_DIR/scripts/switch-apt-mirror.sh" --restore || true ;;
      0) return 0 ;;
      *) printf '请输入 0-3。\n' ;;
    esac
    pause_menu
  done
}

migration_menu(){
  local choice backup_path
  while true; do
    header
    printf '\n  %b配置迁移/备份恢复%b\n' "$BOLD" "$RESET"
    printf '  1  导出当前机器配置\n'
    printf '  2  从备份目录导入个人配置\n'
    printf '  0  返回系统工具\n'
    line
    printf '  选择操作  › '
    IFS= read -r choice || return 0
    case "$choice" in
      1) bash "$REPO_DIR/scripts/migrate-config.sh" backup || true ;;
      2)
        printf '备份目录路径：'
        IFS= read -r backup_path || return 0
        bash "$REPO_DIR/scripts/migrate-config.sh" restore "$backup_path" || true
        ;;
      0) return 0 ;;
      *) printf '请输入 0-2。\n' ;;
    esac
    pause_menu
  done
}

system_tools_menu(){
  local choice
  while true; do
    header
    printf '\n  %b系统工具%b\n' "$BOLD" "$RESET"
    printf '  1  APT 镜像源切换\n'
    printf '  2  管理员用户配置\n'
    printf '  3  SSH Key 配置\n'
    printf '  4  UFW 防火墙配置\n'
    printf '  5  配置迁移/备份恢复\n'
    printf '  0  返回主菜单\n'
    line
    printf '  选择操作  › '
    IFS= read -r choice || return 0
    case "$choice" in
      1) apt_mirror_menu ;;
      2) bash "$REPO_DIR/scripts/setup-admin-user.sh" || true; pause_menu ;;
      3) bash "$REPO_DIR/scripts/setup-ssh-key.sh" || true; pause_menu ;;
      4) bash "$REPO_DIR/scripts/setup-firewall.sh" || true; pause_menu ;;
      5) migration_menu ;;
      0) return 0 ;;
      *) printf '请输入 0-5。\n'; pause_menu ;;
    esac
  done
}
