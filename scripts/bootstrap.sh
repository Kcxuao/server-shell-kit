#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

clear_menu(){
  [[ -t 1 && -n "${TERM:-}" && "$TERM" != dumb ]] && clear 2>/dev/null || true
}

check_system(){
  command -v apt-get >/dev/null 2>&1 || { echo '新服务器初始化目前仅支持 Debian/Ubuntu。' >&2; return 1; }
  [[ -f /etc/os-release ]] || { echo '无法识别系统版本。' >&2; return 1; }
  . /etc/os-release
  case "${ID:-}" in debian|ubuntu) ;; *) echo '新服务器初始化目前仅支持 Debian/Ubuntu。' >&2; return 1 ;; esac
  if [[ $EUID -ne 0 ]]; then
    command -v sudo >/dev/null 2>&1 || { echo '需要 root 或 sudo 权限。' >&2; return 1; }
    sudo -n true 2>/dev/null || echo '执行过程中可能需要输入 sudo 密码。'
  fi
}
profile_name(){
  case "$1" in
    base) printf '基础服务器' ;;
    dev) printf '开发服务器' ;;
    container) printf '容器服务器' ;;
    *) return 1 ;;
  esac
}
show_plan(){
  local profile="$1"
  printf '\n  初始化方案：%s\n' "$(profile_name "$profile")"
  printf '  目标用户：%s (%s)\n' "$TARGET_USER" "$TARGET_HOME"
  printf '  1. 更新系统软件包，安装基础工具与 OpenSSH，启用自动安全更新\n'
  printf '  2. 安装 Zsh、Starship、插件、Alias 和高危命令保护\n'
  case "$profile" in
    dev) printf '  3. 安装通用编译工具\n' ;;
    container) printf '  3. 安装发行版 Docker 包和可用的 Compose 插件；可选配置镜像加速源\n' ;;
  esac
  printf '  时区：%s\n' "${SERVER_SHELL_KIT_TIMEZONE:-保持系统现状}"
  printf '  语言环境：%s\n' "${SERVER_SHELL_KIT_LOCALE:-保持系统现状}"
  printf '  管理员、SSH 公钥与防火墙在独立菜单中配置，不随方案自动启用。\n'
  printf '  运行中失败会停止；可修复后重新运行，已完成的配置会复用。\n'
}
record_step(){
  local state_dir="$TARGET_HOME/.local/state/server-shell-kit"
  ensure_dir "$state_dir"
  printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$1" "$2" | run_user tee -a "$state_dir/bootstrap.log" >/dev/null
}
run_step(){
  local label="$1" script="$2"
  printf '\n▶ %s\n' "$label"
  if bash "$REPO_DIR/scripts/$script"; then
    record_step OK "$label" || return 1
    printf '✓ %s 完成\n' "$label"
  else
    record_step FAILED "$label" || true
    printf '✗ %s 失败，初始化已停止。\n' "$label" >&2
    return 1
  fi
}
run_profile(){
  local profile="$1" answer
  check_system || return 1
  if [[ -t 0 ]]; then
    printf '时区（例：Asia/Shanghai；留空保持现状）：'
    IFS= read -r answer || return 1
    [[ -z "$answer" ]] || export SERVER_SHELL_KIT_TIMEZONE="$answer"
    printf '语言环境（例：zh_CN.UTF-8；留空保持现状）：'
    IFS= read -r answer || return 1
    [[ -z "$answer" ]] || export SERVER_SHELL_KIT_LOCALE="$answer"
  fi
  if [[ -n "${SERVER_SHELL_KIT_TIMEZONE:-}" ]]; then
    [[ "$SERVER_SHELL_KIT_TIMEZONE" =~ ^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)+$ && -f "/usr/share/zoneinfo/$SERVER_SHELL_KIT_TIMEZONE" ]] || { echo '时区无效。' >&2; return 1; }
  fi
  if [[ -n "${SERVER_SHELL_KIT_LOCALE:-}" ]]; then
    [[ "$SERVER_SHELL_KIT_LOCALE" =~ ^[A-Za-z]{2,3}_[A-Za-z]{2}\.UTF-8$ ]] || { echo '语言环境格式无效。' >&2; return 1; }
  fi
  show_plan "$profile"
  printf '\n输入 yes 开始初始化：'
  IFS= read -r answer || return 1
  [[ "$answer" == [Yy][Ee][Ss] ]] || { echo '已取消。'; return 0; }
  run_step '基础系统' bootstrap-base.sh || return 1
  export SERVER_SHELL_KIT_SKIP_APT_UPDATE=1
  run_step '终端环境' install-full.sh || return 1
  case "$profile" in
    dev) run_step '开发工具' bootstrap-dev.sh || return 1 ;;
    container) run_step '容器工具' bootstrap-container.sh || return 1 ;;
  esac
  printf '\n初始化完成。执行记录：%s/.local/state/server-shell-kit/bootstrap.log\n' "$TARGET_HOME"
  printf '请重新登录后检查默认 Shell、工具版本和 SSH 访问。\n'
}
show_menu(){
  clear_menu
  printf '\n  SERVER SHELL KIT  /  新服务器初始化\n'
  printf '  ────────────────────────────────────────────────\n'
  printf '  适用系统  Debian · Ubuntu    目标用户  %s\n' "$TARGET_USER"
  if [[ -n "${FOCUS_HINT:-}" ]]; then printf '  体检提示  %s\n' "$FOCUS_HINT"; fi
  printf '  ────────────────────────────────────────────────\n'
  printf '   1  基础服务器      系统更新、基础工具、终端环境\n'
  printf '   2  开发服务器      基础方案 + 通用编译工具\n'
  printf '   3  容器服务器      基础方案 + Docker、可选镜像加速\n'
  printf '\n   4  创建或配置管理员用户\n'
  printf '   5  添加当前用户的 SSH 公钥\n'
  printf '   6  配置 UFW 防火墙\n'
  printf '\n   7  切换 APT 软件源\n'
  printf '   8  迁移备份与导入\n'
  printf '   0  返回主菜单\n'
  printf '  ────────────────────────────────────────────────\n'
}
mirror_menu(){
  local choice
  while true; do
    clear_menu
    printf '\n  APT 软件源\n'
    printf '   1  切换清华 TUNA 镜像\n'
    printf '   2  切换中科大 USTC 镜像\n'
    printf '   3  恢复首次切换前的源\n'
    printf '   0  返回\n'
    printf '  选择操作  › '
    IFS= read -r choice || return 0
    case "$choice" in
      1) bash "$REPO_DIR/scripts/switch-apt-mirror.sh" tuna || true ;;
      2) bash "$REPO_DIR/scripts/switch-apt-mirror.sh" ustc || true ;;
      3) bash "$REPO_DIR/scripts/switch-apt-mirror.sh" --restore || true ;;
      0) return 0 ;;
      *) echo '请输入 0-3。' ;;
    esac
  done
}
migration_menu(){
  local choice backup_path
  while true; do
    clear_menu
    printf '\n  迁移备份\n'
    printf '   1  导出当前机器配置\n'
    printf '   2  从备份目录导入个人配置\n'
    printf '   0  返回\n'
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
      *) echo '请输入 0-2。' ;;
    esac
  done
}
main(){
  local choice
  if [[ "${1:-}" == --plan ]]; then
    profile_name "${2:-}" >/dev/null || { echo '用法：bootstrap.sh --plan base|dev|container' >&2; return 2; }
    check_system || return 1
    show_plan "$2"
    return 0
  fi
  if [[ "${1:-}" == --focus ]]; then
    case "${2:-}" in
      1) FOCUS_HINT='SSH 服务异常：查看基础服务器方案（1）' ;;
      3) FOCUS_HINT='Docker 服务异常：查看容器服务器方案（3）' ;;
      5) FOCUS_HINT='SSH 公钥未配置：选择添加当前用户的 SSH 公钥（5）' ;;
      6) FOCUS_HINT='UFW 未运行：选择配置 UFW 防火墙（6）' ;;
      *) printf '无效的体检跳转编号。\n' >&2; return 2 ;;
    esac
  fi
  while true; do
    show_menu
    printf '  选择操作  › '
    IFS= read -r choice || { printf '\n'; return 0; }
    case "$choice" in
      1) run_profile base || true ;;
      2) run_profile dev || true ;;
      3) run_profile container || true ;;
      4) bash "$REPO_DIR/scripts/setup-admin-user.sh" || true ;;
      5) bash "$REPO_DIR/scripts/setup-ssh-key.sh" || true ;;
      6) bash "$REPO_DIR/scripts/setup-firewall.sh" || true ;;
      7) mirror_menu; continue ;;
      8) migration_menu; continue ;;
      0) return 0 ;;
      *) echo '请输入 0-8。' ;;
    esac
    printf '\n按 Enter 继续...'
    IFS= read -r _ || return 0
  done
}
main "$@"
