#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
command -v jq >/dev/null 2>&1 || { echo '保存快照需要 jq。' >&2; exit 1; }
[[ -n "${HOME:-}" && "$HOME" == /* ]] || { echo '无法确定快照目录。' >&2; exit 1; }
umask 077
snapshot_dir="${SERVER_SHELL_KIT_SNAPSHOT_DIR:-$HOME/.local/share/server-shell-kit/snapshots}"
[[ "$snapshot_dir" == /* ]] || { echo '快照目录必须是绝对路径。' >&2; exit 2; }
mkdir -p -- "$snapshot_dir"
chmod 0700 -- "$snapshot_dir"
temporary="$(mktemp "$snapshot_dir/.snapshot.XXXXXXXX")"
trap 'rm -f -- "$temporary"' EXIT
bash "$script_dir/discover.sh" > "$temporary"
jq -e '.schema_version == 1 and (.created_at | type == "string") and
  (.system | type == "object") and (.network | type == "object") and
  (.development | type == "object") and (.docker | type == "object") and
  (.databases | type == "object")' "$temporary" >/dev/null
snapshot="$snapshot_dir/$(date -u +%Y%m%d-%H%M%S)-${temporary##*.}.json"
mv -- "$temporary" "$snapshot"
trap - EXIT
printf '快照已保存：%s\n' "$snapshot"
