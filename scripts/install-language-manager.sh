#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

usage(){ printf '用法：%s java|python|node|rust [...]\n' "$0" >&2; }
(( $# > 0 )) || { usage; exit 2; }
declare -a selected=() failed=()
declare -A seen=()
for language in "$@"; do
  case "$language" in java|python|node|rust) ;; *) usage; exit 2 ;; esac
  [[ -n "${seen[$language]:-}" ]] || selected+=("$language")
  seen[$language]=1
done

command -v curl >/dev/null 2>&1 || { printf '需要 curl 才能安装语言管理器。\n' >&2; exit 1; }
ensure_python3(){
  command -v python3 >/dev/null 2>&1 && return 0
  command -v apt-get >/dev/null 2>&1 || { echo '配置 Maven 和 Cargo 镜像需要 Python 3。' >&2; return 1; }
  run_root apt-get update || return 1
  run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y python3
}

download_installer(){
  local url="$1" file
  file="$(mktemp)" || return 1
  if ! curl -fsSL --retry 3 --connect-timeout 10 --max-time 120 -o "$file" "$url"; then
    rm -f -- "$file"
    return 1
  fi
  chmod 0644 "$file" || { rm -f -- "$file"; return 1; }
  printf '%s\n' "$file"
}

install_java(){
  local installer
  if [[ ! -s "$TARGET_HOME/.sdkman/bin/sdkman-init.sh" ]]; then
    installer="$(download_installer 'https://get.sdkman.io?ci=true&rcupdate=false')" || return 1
    if ! run_user env SDKMAN_DIR="$TARGET_HOME/.sdkman" bash "$installer"; then rm -f -- "$installer"; return 1; fi
    rm -f -- "$installer"
  fi
  ensure_line "$TARGET_HOME/.zshrc" '[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"' || return 1
  run_user env SDKMAN_DIR="$TARGET_HOME/.sdkman" bash -c \
    'set -e; source "$SDKMAN_DIR/bin/sdkman-init.sh"; yes | sdk install java; yes | sdk install maven' || return 1
  ensure_python3 || return 1
  backup_file "$TARGET_HOME/.m2/settings.xml" || return 1
  run_user python3 "$REPO_DIR/scripts/configure-programming-mirror.py" maven "$TARGET_HOME"
}

install_python(){
  local installer
  if [[ ! -x "$TARGET_HOME/.local/bin/uv" ]]; then
    installer="$(download_installer 'https://astral.sh/uv/install.sh')" || return 1
    if ! run_user env UV_NO_MODIFY_PATH=1 sh "$installer"; then rm -f -- "$installer"; return 1; fi
    rm -f -- "$installer"
  fi
  ensure_line "$TARGET_HOME/.zshrc" '[[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || export PATH="$HOME/.local/bin:$PATH"' || return 1
  run_user env UV_NO_CONFIG=1 "$TARGET_HOME/.local/bin/uv" python install 3 --default --managed-python || return 1
  ensure_line "$TARGET_HOME/.zshrc" 'export UV_DEFAULT_INDEX="https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple/"'
}

install_node(){
  local installer
  if [[ ! -s "$TARGET_HOME/.nvm/nvm.sh" ]]; then
    command -v git >/dev/null 2>&1 || { printf '安装 nvm 需要 git。\n' >&2; return 1; }
    installer="$(download_installer 'https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.8/install.sh')" || return 1
    if ! run_user env NVM_DIR="$TARGET_HOME/.nvm" PROFILE=/dev/null bash "$installer"; then rm -f -- "$installer"; return 1; fi
    rm -f -- "$installer"
  fi
  ensure_line "$TARGET_HOME/.zshrc" 'export NVM_DIR="$HOME/.nvm"; [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"' || return 1
  run_user env NVM_DIR="$TARGET_HOME/.nvm" bash -c \
    'set -e; source "$NVM_DIR/nvm.sh"; nvm install node; nvm alias default node' || return 1
  backup_file "$TARGET_HOME/.npmrc" || return 1
  run_user env NVM_DIR="$TARGET_HOME/.nvm" bash -c \
    'set -e; source "$NVM_DIR/nvm.sh"; npm config set registry https://registry.npmmirror.com --location=user'
}

install_rust(){
  local installer
  if [[ ! -x "$TARGET_HOME/.cargo/bin/rustup" ]]; then
    installer="$(download_installer 'https://sh.rustup.rs')" || return 1
    if ! run_user sh "$installer" -y --no-modify-path --default-toolchain stable; then rm -f -- "$installer"; return 1; fi
    rm -f -- "$installer"
  fi
  ensure_line "$TARGET_HOME/.zshrc" '[[ ":$PATH:" == *":$HOME/.cargo/bin:"* ]] || export PATH="$HOME/.cargo/bin:$PATH"' || return 1
  run_user "$TARGET_HOME/.cargo/bin/rustup" default stable || return 1
  ensure_python3 || return 1
  backup_file "$TARGET_HOME/.cargo/config.toml" || return 1
  run_user python3 "$REPO_DIR/scripts/configure-programming-mirror.py" cargo "$TARGET_HOME"
}

for language in "${selected[@]}"; do
  printf '\n▶ %s：安装管理器、默认稳定版本并配置国内包源\n' "$language"
  if "install_$language"; then
    printf '✓ %s 完成\n' "$language"
  else
    failed+=("$language")
    printf '✗ %s 失败，请检查上方错误信息。\n' "$language" >&2
  fi
done

printf '\n安装结果：\n'
for language in "${selected[@]}"; do
  if [[ " ${failed[*]} " == *" $language "* ]]; then
    printf '  ✗ %s\n' "$language"
  else
    printf '  ✓ %s\n' "$language"
  fi
done
printf '重新登录后检查对应语言的版本。\n'
(( ${#failed[@]} == 0 ))
