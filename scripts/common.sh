#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $EUID -eq 0 ]]; then TARGET_USER="${SUDO_USER:-root}"; else TARGET_USER="$USER"; fi
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TARGET_GROUP="$(id -gn "$TARGET_USER")"

run_root(){ if [[ $EUID -eq 0 ]]; then "$@"; else sudo "$@"; fi; }
run_user(){ if [[ $EUID -eq 0 && "$TARGET_USER" != root ]]; then sudo -u "$TARGET_USER" -H "$@"; else "$@"; fi; }
ensure_dir(){ run_user mkdir -p "$1"; }
ensure_line(){ local file="$1" line="$2" marker="$3"; run_user touch "$file"; grep -Fq "$marker" "$file" 2>/dev/null || printf '\n%s\n' "$line" | run_user tee -a "$file" >/dev/null; }
