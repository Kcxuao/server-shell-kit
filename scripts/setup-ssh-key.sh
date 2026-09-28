#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
command -v ssh-keygen >/dev/null 2>&1 || { echo '缺少 ssh-keygen，请先安装 openssh-client。' >&2; exit 1; }
printf '将公钥添加到 %s 的 authorized_keys。\n' "$TARGET_USER"
printf '粘贴单行 SSH 公钥：'
IFS= read -r public_key || exit 1
[[ "$public_key" =~ ^(ssh-(ed25519|rsa)|ecdsa-sha2-nistp(256|384|521))[[:space:]]+[A-Za-z0-9+/=]+([[:space:]].*)?$ ]] || {
  echo '公钥格式无效。' >&2; exit 1;
}
printf '%s\n' "$public_key" | ssh-keygen -lf - >/dev/null || { echo '公钥校验失败。' >&2; exit 1; }
ssh_dir="$TARGET_HOME/.ssh"
keys="$ssh_dir/authorized_keys"
ensure_dir "$ssh_dir"
run_user chmod 0700 "$ssh_dir"
if [[ -f "$keys" ]] && grep -Fxq -- "$public_key" "$keys"; then
  echo '该公钥已经存在。'; exit 0
fi
backup_file "$keys"
run_user touch -- "$keys"
run_user chmod 0600 "$keys"
printf '%s\n' "$public_key" | run_user tee -a "$keys" >/dev/null
echo '公钥已添加。请从另一个会话验证登录后，再考虑收紧 SSH 登录设置。'
