#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
command -v apt-get >/dev/null 2>&1 || { echo '新服务器初始化目前仅支持 Debian/Ubuntu。' >&2; exit 1; }
run_root apt-get update
run_root env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates curl git vim less unzip htop tmux jq sudo adduser \
  openssh-server openssh-client tzdata locales unattended-upgrades

if [[ -n "${SERVER_SHELL_KIT_TIMEZONE:-}" ]]; then
  timezone="$SERVER_SHELL_KIT_TIMEZONE"
  [[ "$timezone" =~ ^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)+$ && -f "/usr/share/zoneinfo/$timezone" ]] || {
    printf '无效时区：%s\n' "$timezone" >&2; exit 1;
  }
  command -v timedatectl >/dev/null 2>&1 || { echo '系统没有 timedatectl，无法设置时区。' >&2; exit 1; }
  run_root timedatectl set-timezone "$timezone"
fi

if [[ -n "${SERVER_SHELL_KIT_LOCALE:-}" ]]; then
  locale_name="$SERVER_SHELL_KIT_LOCALE"
  [[ "$locale_name" =~ ^[A-Za-z]{2,3}_[A-Za-z]{2}\.UTF-8$ ]] || {
    printf '无效语言环境：%s\n' "$locale_name" >&2; exit 1;
  }
  run_root localedef -i "${locale_name%%.*}" -f UTF-8 "$locale_name"
  run_root update-locale LANG="$locale_name"
fi

periodic_config='/etc/apt/apt.conf.d/52server-shell-kit-periodic'
periodic_content='APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";'
if [[ ! -f "$periodic_config" ]] || [[ "$(cat "$periodic_config")" != "$periodic_content" ]]; then
  if [[ -f "$periodic_config" && ! -e "$periodic_config.server-shell-kit.bak" ]]; then
    run_root cp -p -- "$periodic_config" "$periodic_config.server-shell-kit.bak"
  fi
  printf '%s\n' "$periodic_content" | run_root tee "$periodic_config" >/dev/null
  run_root chmod 0644 "$periodic_config"
fi
printf '基础系统配置完成。\n'
