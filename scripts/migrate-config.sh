#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

user_files=(
  .zshrc .bashrc .gitconfig .vimrc .tmux.conf
  .config/starship.toml
  .config/zsh/server-shell-kit/aliases.zsh
  .config/zsh/plugins/dangerous-command-guard/dangerous-command-guard.plugin.zsh
  .ssh/authorized_keys
)
system_files=(/etc/os-release /etc/timezone /etc/default/locale /etc/apt/sources.list)
shopt -s nullglob
for file in /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/debian.sources; do
  [[ -f "$file" ]] && system_files+=("$file")
done
shopt -u nullglob

backup(){
  local bundle rel source destination file
  bundle="$(run_user mktemp -d "$TARGET_HOME/server-shell-kit-backup-XXXXXXXX")"
  run_user chmod 0700 "$bundle"
  run_user mkdir -p "$bundle/home" "$bundle/system"
  for rel in "${user_files[@]}"; do
    source="$TARGET_HOME/$rel"
    [[ -f "$source" && ! -L "$source" ]] || continue
    destination="$bundle/home/$rel"
    run_user mkdir -p "$(dirname "$destination")"
    run_user cp -p -- "$source" "$destination"
  done
  for file in "${system_files[@]}"; do
    [[ -f "$file" && ! -L "$file" ]] || continue
    destination="$bundle/system${file#/etc}"
    run_user mkdir -p "$(dirname "$destination")"
    run_root cat -- "$file" | run_user tee "$destination" >/dev/null
    run_user chmod 0600 "$destination"
  done
  {
    printf 'created_utc=%s\n' "$(date -u +%FT%TZ)"
    printf 'source_user=%s\n' "$TARGET_USER"
    printf 'source_os=%s\n' "$(. /etc/os-release; printf '%s' "${PRETTY_NAME:-unknown}")"
    printf 'note=system files are reference only; restore imports selected home config only\n'
  } | run_user tee "$bundle/manifest.txt" >/dev/null
  dpkg-query -W -f='${Status} ${binary:Package}\n' | awk '$1 == "install" && $2 == "ok" && $3 == "installed" { print $4 }' | run_user tee "$bundle/packages.txt" >/dev/null
  if command -v systemctl >/dev/null 2>&1; then
    systemctl list-unit-files --state=enabled --no-legend 2>/dev/null | run_user tee "$bundle/enabled-services.txt" >/dev/null || true
  fi
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
