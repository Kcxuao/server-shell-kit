#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
command -v adduser >/dev/null 2>&1 || { echo '缺少 adduser，请先运行基础服务器初始化。' >&2; exit 1; }
command -v ssh-keygen >/dev/null 2>&1 || { echo '缺少 ssh-keygen，请先安装 openssh-client。' >&2; exit 1; }
getent group sudo >/dev/null 2>&1 || { echo '缺少 sudo 用户组，请先运行基础服务器初始化。' >&2; exit 1; }
printf '管理员用户名：'
IFS= read -r admin_user || exit 1
[[ "$admin_user" =~ ^[a-z_][a-z0-9_-]*$ && "$admin_user" != root ]] || {
  echo '用户名只能包含小写字母、数字、下划线和连字符，且不能为 root。' >&2; exit 1;
}
printf '粘贴该用户的单行 SSH 公钥：'
IFS= read -r public_key || exit 1
[[ "$public_key" =~ ^(ssh-(ed25519|rsa)|ecdsa-sha2-nistp(256|384|521))[[:space:]]+[A-Za-z0-9+/=]+([[:space:]].*)?$ ]] || {
  echo '公钥格式无效。' >&2; exit 1;
}
printf '%s\n' "$public_key" | ssh-keygen -lf - >/dev/null || { echo '公钥校验失败。' >&2; exit 1; }
printf '将创建或配置用户 %s，加入 sudo 组并添加公钥。\n' "$admin_user"
printf '输入 yes 继续：'
IFS= read -r answer || exit 1
[[ "$answer" == [Yy][Ee][Ss] ]] || { echo '已取消。'; exit 0; }
if ! id "$admin_user" >/dev/null 2>&1; then
  echo '请在接下来的系统提示中为新用户设置密码。'
  run_root adduser --gecos '' "$admin_user"
fi
admin_home="$(getent passwd "$admin_user" | cut -d: -f6)"
[[ -n "$admin_home" && "$admin_home" != / ]] || { echo '无法确定新用户的 HOME。' >&2; exit 1; }
admin_group="$(id -gn "$admin_user")"
run_root usermod -aG sudo "$admin_user"
ssh_dir="$admin_home/.ssh"
keys="$ssh_dir/authorized_keys"
run_root install -d -m 0700 -o "$admin_user" -g "$admin_group" "$ssh_dir"
if [[ -f "$keys" ]] && grep -Fxq -- "$public_key" "$keys"; then
  echo '该公钥已经存在。请从另一个会话验证登录和 sudo 权限。'
  exit 0
fi
if [[ -f "$keys" && ! -e "$keys.server-shell-kit.bak" ]]; then
  run_root cp -p -- "$keys" "$keys.server-shell-kit.bak"
fi
if [[ ! -e "$keys" ]]; then
  run_root install -m 0600 -o "$admin_user" -g "$admin_group" /dev/null "$keys"
fi
run_root chown "$admin_user:$admin_group" "$keys"
run_root chmod 0600 "$keys"
printf '%s\n' "$public_key" | run_root tee -a "$keys" >/dev/null
printf '管理员 %s 已配置。请保持当前会话，另开会话测试 SSH 和 sudo。\n' "$admin_user"
