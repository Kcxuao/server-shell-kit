#!/usr/bin/env bash
set -Eeuo pipefail

REPO_OWNER="${SERVER_SHELL_KIT_OWNER:-Kcxuao}"
REPO_NAME="${SERVER_SHELL_KIT_REPO:-server-shell-kit}"
REPO_REF="${SERVER_SHELL_KIT_REF:-main}"
BASE_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_REF}"

if [[ $EUID -eq 0 ]]; then TARGET_USER="${SUDO_USER:-root}"; else TARGET_USER="$USER"; fi
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TARGET_GROUP="$(id -gn "$TARGET_USER")"

run_root(){ if [[ $EUID -eq 0 ]]; then "$@"; else sudo "$@"; fi; }
run_user(){ if [[ $EUID -eq 0 && "$TARGET_USER" != root ]]; then sudo -u "$TARGET_USER" -H "$@"; else "$@"; fi; }
fetch(){ curl -fsSL "$1" -o "$2"; }
ensure_dir(){ run_user mkdir -p "$1"; }
ensure_line(){ local file="$1" line="$2" marker="$3"; run_user touch "$file"; grep -Fq "$marker" "$file" 2>/dev/null || printf '\n%s\n' "$line" | run_user tee -a "$file" >/dev/null; }
