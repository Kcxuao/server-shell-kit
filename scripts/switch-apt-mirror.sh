#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

APT_ROOT="${SERVER_SHELL_KIT_APT_ROOT:-/etc/apt}"
BACKUP_ROOT="${SERVER_SHELL_KIT_APT_BACKUP_ROOT:-/var/backups/server-shell-kit/apt}"
[[ "$APT_ROOT" == /* && "$BACKUP_ROOT" == /* ]] || { echo 'APT 路径必须是绝对路径。' >&2; exit 1; }
. /etc/os-release
case "${ID:-}" in ubuntu|debian) ;; *) echo '仅支持 Debian/Ubuntu。' >&2; exit 1 ;; esac
command -v apt-get >/dev/null 2>&1 || { echo '未找到 apt-get。' >&2; exit 1; }

source_files(){
  local file
  shopt -s nullglob
  for file in "$APT_ROOT/sources.list" "$APT_ROOT"/sources.list.d/*.list "$APT_ROOT"/sources.list.d/*.sources; do
    [[ -f "$file" && ! -L "$file" ]] && printf '%s\n' "$file"
  done
  shopt -u nullglob
}
mirror_name(){
  case "$1" in tuna) echo '清华 TUNA' ;; ustc) echo '中科大 USTC' ;; *) return 1 ;; esac
}
transform(){
  local mirror="$1" source="$2" host
  case "$mirror" in
    tuna) host='https://mirrors.tuna.tsinghua.edu.cn' ;;
    ustc) host='https://mirrors.ustc.edu.cn' ;;
    *) return 2 ;;
  esac
  if [[ "$ID" == ubuntu ]]; then
    sed -E \
      -e "s#https?://([a-z]{2}\\.)?archive\\.ubuntu\\.com/ubuntu#${host}/ubuntu#g" \
      -e "s#https?://security\\.ubuntu\\.com/ubuntu#${host}/ubuntu#g" \
      -e "s#https?://ports\\.ubuntu\\.com/ubuntu-ports#${host}/ubuntu-ports#g" \
      -e "s#https?://mirrors\\.(tuna\\.tsinghua|ustc)\\.edu\\.cn/ubuntu-ports#${host}/ubuntu-ports#g" \
      -e "s#https?://mirrors\\.(tuna\\.tsinghua|ustc)\\.edu\\.cn/ubuntu#${host}/ubuntu#g" \
      "$source"
  else
    sed -E \
      -e "s#https?://(deb|ftp)\\.debian\\.org/debian(/|[[:space:]]|$)#${host}/debian\\2#g" \
      -e "s#https?://mirrors\\.(tuna\\.tsinghua|ustc)\\.edu\\.cn/debian(/|[[:space:]]|$)#${host}/debian\\2#g" \
      "$source"
  fi
}
apt_update(){
  run_root timeout 180 apt-get update -o Acquire::Retries=1 \
    -o Acquire::http::Timeout=15 -o Acquire::https::Timeout=15
}
workdir="$(mktemp -d)"
trap 'rm -rf -- "$workdir"' EXIT
original=()
staged=()
restore_transaction(){
  local i
  for i in "${!original[@]}"; do
    run_root cp -p -- "$workdir/before.$i" "${original[$i]}"
  done
}
apply_changes(){
  local i
  for i in "${!original[@]}"; do
    if ! run_root install -m 0644 -o root -g root "${staged[$i]}" "${original[$i]}"; then
      echo "写入软件源失败：${original[$i]}，正在回滚。" >&2
      restore_transaction
      return 1
    fi
  done
  if apt_update; then
    echo 'APT 软件源已更新。'
  else
    echo 'apt-get update 失败，正在恢复切换前的配置。' >&2
    restore_transaction
    return 1
  fi
}

if [[ "${1:-}" == --restore ]]; then
  run_root test -d "$BACKUP_ROOT/original" || { echo '没有可恢复的原始软件源备份。' >&2; exit 1; }
  while IFS= read -r file; do
    saved="$BACKUP_ROOT/original${file#"$APT_ROOT"}"
    run_root test -f "$saved" || continue
    i="${#original[@]}"
    original+=("$file")
    run_root cp -p -- "$file" "$workdir/before.$i"
    staged+=("$saved")
    printf '恢复：%s\n' "$file"
  done < <(source_files)
  ((${#original[@]} > 0)) || { echo '没有找到可恢复的软件源文件。' >&2; exit 1; }
  printf '输入 yes 恢复首次切换前的软件源：'
  IFS= read -r answer || exit 1
  [[ "$answer" == [Yy][Ee][Ss] ]] || { echo '已取消。'; exit 0; }
  apply_changes
  exit
fi

mirror="${1:-}"
mirror_name "$mirror" >/dev/null || { echo '用法：switch-apt-mirror.sh tuna|ustc|--restore' >&2; exit 2; }
while IFS= read -r file; do
  i="${#original[@]}"
  transform "$mirror" "$file" > "$workdir/after.$i"
  if ! cmp -s -- "$file" "$workdir/after.$i"; then
    original+=("$file")
    staged+=("$workdir/after.$i")
    run_root cp -p -- "$file" "$workdir/before.$i"
    printf '\n文件：%s\n' "$file"
    diff -u -- "$file" "$workdir/after.$i" || true
  fi
done < <(source_files)
((${#original[@]} > 0)) || { echo '没有找到可切换的官方软件源，或当前已是所选镜像。'; exit 0; }
printf '\n目标镜像：%s；仅修改以上官方源地址，保留其他源与签名配置。\n' "$(mirror_name "$mirror")"
printf '输入 yes 备份、切换并测试 apt-get update：'
IFS= read -r answer || exit 1
[[ "$answer" == [Yy][Ee][Ss] ]] || { echo '已取消。'; exit 0; }
run_root install -d -m 0700 "$BACKUP_ROOT/original"
for file in "${original[@]}"; do
  relative="${file#"$APT_ROOT"}"
  saved="$BACKUP_ROOT/original$relative"
  if ! run_root test -e "$saved"; then
    run_root install -d -m 0700 "$(dirname "$saved")"
    run_root cp -p -- "$file" "$saved"
  fi
done
apply_changes
