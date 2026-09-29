#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/backup-config.sh"

backup(){
  local bundle
  bundle="$(run_user mktemp -d "$TARGET_HOME/server-shell-kit-backup-XXXXXXXX")"
  run_user chmod 0700 "$bundle"
  backup_config "$bundle"
  {
    printf 'created_utc=%s\n' "$(date -u +%FT%TZ)"
    printf 'source_user=%s\n' "$TARGET_USER"
    printf 'source_os=%s\n' "$(. /etc/os-release; printf '%s' "${PRETTY_NAME:-unknown}")"
    printf 'note=system files are reference only; restore imports selected home config only\n'
  } | run_user tee "$bundle/manifest.txt" >/dev/null
  (cd "$bundle" && find home system -type f -print0 | sort -z | xargs -0 sha256sum) | run_user tee "$bundle/SHA256SUMS" >/dev/null
  printf '备份目录：%s\n' "$bundle"
  printf '请将整个目录复制到新服务器；备份不含 SSH 私钥、数据库和 Docker 数据。\n'
}
restore(){
  local bundle="$1" rel source destination line answer
  bundle="$(cd -- "$bundle" && pwd -P)" || { echo '备份目录不存在。' >&2; return 1; }
  [[ -f "$bundle/manifest.txt" && -f "$bundle/SHA256SUMS" ]] || { echo '这不是有效的迁移备份目录。' >&2; return 1; }
  (cd "$bundle" && sha256sum -c SHA256SUMS) || { echo '备份校验失败，未导入。' >&2; return 1; }
  printf '将从 %s 导入个人配置到 %s。\n' "$bundle" "$TARGET_HOME"
  printf '系统软件源、软件清单和服务清单只供参考，不自动应用。\n'
  printf '输入 yes 继续：'
  IFS= read -r answer || return 1
  [[ "$answer" == [Yy][Ee][Ss] ]] || { echo '已取消。'; return 0; }
  for rel in "${user_files[@]}"; do
    [[ "$rel" == .ssh/authorized_keys ]] && continue
    source="$bundle/home/$rel"
    [[ -f "$source" && ! -L "$source" ]] || continue
    awk -v wanted="home/$rel" '$2 == wanted { found=1 } END { exit !found }' "$bundle/SHA256SUMS" || { echo "文件未列入校验清单：$rel" >&2; return 1; }
    destination="$TARGET_HOME/$rel"
    ensure_dir "$(dirname "$destination")"
    backup_file "$destination"
    run_user install -m 0600 -- "$source" "$destination"
    printf '已导入：%s\n' "$rel"
  done
  source="$bundle/home/.ssh/authorized_keys"
  if [[ -f "$source" && ! -L "$source" ]]; then
    awk -v wanted="home/.ssh/authorized_keys" '$2 == wanted { found=1 } END { exit !found }' "$bundle/SHA256SUMS" || { echo "公钥文件未列入校验清单。" >&2; return 1; }
    destination="$TARGET_HOME/.ssh/authorized_keys"
    ensure_dir "$TARGET_HOME/.ssh"
    run_user chmod 0700 "$TARGET_HOME/.ssh"
    backup_file "$destination"
    run_user touch "$destination"
    run_user chmod 0600 "$destination"
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -n "$line" ]] || continue
      grep -Fxq -- "$line" "$destination" 2>/dev/null || printf '%s\n' "$line" | run_user tee -a "$destination" >/dev/null
    done < "$source"
    echo '已合并 SSH authorized_keys。'
  fi
  echo '个人配置导入完成。请重新登录后检查 Shell 配置。'
}
case "${1:-}" in
  backup) backup ;;
  restore) [[ -n "${2:-}" ]] || { echo '用法：migrate-config.sh restore 备份目录' >&2; exit 2; }; restore "$2" ;;
  *) echo '用法：migrate-config.sh backup|restore 备份目录' >&2; exit 2 ;;
esac
