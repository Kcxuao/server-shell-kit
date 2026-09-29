#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

# Machine-readable rows: key, state, label, reason, destination, initial selection.
row(){ printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$@"; }
has_line(){ [[ -f "$TARGET_HOME/.zshrc" ]] && grep -Fxq -- "$1" "$TARGET_HOME/.zshrc"; }
zsh_check(){
  command -v zsh >/dev/null 2>&1 || return 1
  if command -v timeout >/dev/null 2>&1; then
    run_user timeout 8s zsh -ic "$1" </dev/null >/dev/null 2>&1
  else
    run_user zsh -ic "$1" </dev/null >/dev/null 2>&1
  fi
}
zsh_command(){ zsh_check "command -v $1 >/dev/null"; }
version_of(){ "$1" --version 2>&1 | head -n 1 | tr '\t' ' '; }

zsh_path="$(command -v zsh 2>/dev/null || true)"
login_shell="$(getent passwd "$TARGET_USER" | cut -d: -f7)"
if [[ -z "$zsh_path" ]]; then
  row zsh missing Zsh '尚未安装' component 0
elif [[ "$login_shell" != "$zsh_path" ]]; then
  row zsh issue Zsh '已安装，但目标用户的默认 Shell 不是 Zsh' component 0
else
  row zsh ok Zsh '已设为默认 Shell' - -
fi

if ! command -v starship >/dev/null 2>&1; then
  row starship missing Starship '尚未安装' component 1
elif [[ ! -f "$TARGET_HOME/.config/starship.toml" ]] || ! has_line 'command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"' 'starship init zsh'; then
  row starship issue Starship '已安装，但配置或 Zsh 启动行缺失' component 1
elif ! zsh_command starship; then
  row starship issue Starship '已安装，但新 Zsh 会话无法使用' component 1
else
  row starship ok Starship '已安装且可在新 Zsh 会话使用' - -
fi

auto_file=/usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
syntax_file=/usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
if [[ ! -f "$auto_file" && ! -f "$syntax_file" ]]; then
  row plugins missing 自动建议与语法高亮 '尚未安装' component 2
elif [[ ! -f "$auto_file" || ! -f "$syntax_file" ]] ||
  ! has_line '[[ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh' 'zsh-autosuggestions.zsh' ||
  ! has_line '[[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh' 'zsh-syntax-highlighting.zsh'; then
  row plugins issue 自动建议与语法高亮 '安装或 Zsh 启动配置不完整' component 2
elif ! zsh_check 'typeset -f _zsh_autosuggest_start >/dev/null && typeset -f _zsh_highlight >/dev/null'; then
  row plugins issue 自动建议与语法高亮 '配置齐全，但新 Zsh 会话未加载插件' component 2
else
  row plugins ok 自动建议与语法高亮 '插件文件和启动配置齐全' - -
fi

alias_file="$TARGET_HOME/.config/zsh/server-shell-kit/aliases.zsh"
if [[ ! -f "$alias_file" ]]; then
  row aliases missing 常用Alias '尚未配置' component 4
elif ! has_line '[[ -f "$HOME/.config/zsh/server-shell-kit/aliases.zsh" ]] && source "$HOME/.config/zsh/server-shell-kit/aliases.zsh"' 'server-shell-kit/aliases.zsh'; then
  row aliases issue 常用Alias '配置文件存在，但 Zsh 启动行缺失' component 4
elif ! zsh_check 'alias ll >/dev/null'; then
  row aliases issue 常用Alias '配置齐全，但新 Zsh 会话未加载 Alias' component 4
else
  row aliases ok 常用Alias '配置文件和启动行齐全' - -
fi

guard_dir="$TARGET_HOME/.config/zsh/plugins/dangerous-command-guard"
guard_library="$guard_dir/dangerous-command-guard.plugin.zsh"
guard_entry="$guard_dir/impact-guard.plugin.zsh"
guard_analysis="$guard_dir/impact-guard-analysis.zsh"
old_guard_start='[[ -f "$HOME/.config/zsh/plugins/dangerous-command-guard/dangerous-command-guard.plugin.zsh" ]] && source "$HOME/.config/zsh/plugins/dangerous-command-guard/dangerous-command-guard.plugin.zsh"'
new_guard_start='[[ -f "$HOME/.config/zsh/plugins/dangerous-command-guard/impact-guard.plugin.zsh" ]] && source "$HOME/.config/zsh/plugins/dangerous-command-guard/impact-guard.plugin.zsh"'
if [[ ! -f "$guard_library" && ! -f "$guard_entry" ]]; then
  row guard missing 高危命令保护 '尚未配置' component 3
elif has_line "$old_guard_start" && has_line "$new_guard_start"; then
  row guard issue 高危命令保护 '标准新旧启动行同时存在' component 3
elif [[ ! -f "$guard_entry" || ! -f "$guard_analysis" ]]; then
  row guard issue 高危命令保护 'Impact Guard 入口或分析模块缺失' component 3
elif ! has_line "$new_guard_start"; then
  row guard issue 高危命令保护 'Impact Guard 已安装，但 Zsh 启动行缺失或仍指向旧入口' component 3
elif ! zsh_check 'command -v dcg >/dev/null && command -v jq >/dev/null'; then
  row guard issue 高危命令保护 '目标用户缺少外部 dcg 或 jq' component 3
elif ! zsh_check 'typeset -f _impact_guard_accept_line >/dev/null && typeset -f dcg-status >/dev/null'; then
  row guard issue 高危命令保护 '配置齐全，但新 Zsh 会话未加载 Impact Guard' component 3
else
  row guard ok 高危命令保护 'Impact Guard 文件、依赖和启动行齐全' - -
fi

check_language(){
  local key="$1" label="$2" index="$3" manager="$4" runtime="$5" startup="$6" shell_command="$7" version
  if [[ ! -e "$manager" ]]; then
    row "$key" missing "$label" '尚未安装管理器' language "$index"
  elif [[ ! -e "$runtime" ]]; then
    row "$key" issue "$label" '管理器已安装，但默认版本缺失' language "$index"
  elif ! has_line "$startup"; then
    row "$key" issue "$label" '默认版本已安装，但 Zsh 启动配置缺失' language "$index"
  elif ! zsh_command "$shell_command"; then
    row "$key" issue "$label" '默认版本已安装，但新 Zsh 会话无法使用' language "$index"
  elif [[ "$key" == java ]] && [[ ! -x "$TARGET_HOME/.sdkman/candidates/maven/current/bin/mvn" ]]; then
    row "$key" issue "$label" 'JDK 已安装，但 Maven 尚未安装' language "$index"
  elif [[ "$key" == java ]] && ! grep -q 'https://maven.aliyun.com/repository/public' "$TARGET_HOME/.m2/settings.xml" 2>/dev/null; then
    row "$key" issue "$label" 'Maven 国内镜像尚未配置' language "$index"
  elif [[ "$key" == python ]] && ! has_line 'export UV_DEFAULT_INDEX="https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple/"'; then
    row "$key" issue "$label" 'uv 国内包源尚未配置' language "$index"
  elif [[ "$key" == rust ]] && { ! zsh_command cargo || ! grep -q 'sparse+https://mirrors.ustc.edu.cn/crates.io-index/' "$TARGET_HOME/.cargo/config.toml" 2>/dev/null; }; then
    row "$key" issue "$label" 'Cargo 不可用或国内包源尚未配置' language "$index"
  else
    version="$(version_of "$runtime" || true)"
    row "$key" ok "$label" "${version:-默认版本已生效}" - -
  fi
}

java_runtime="$TARGET_HOME/.sdkman/candidates/java/current/bin/java"
python_runtime="$TARGET_HOME/.local/bin/python"
node_runtime="$TARGET_HOME/.nvm/versions/node"
rust_runtime="$TARGET_HOME/.cargo/bin/rustc"
check_language java Java 0 "$TARGET_HOME/.sdkman/bin/sdkman-init.sh" "$java_runtime" \
  '[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"' java
check_language python Python 1 "$TARGET_HOME/.local/bin/uv" "$python_runtime" \
  '[[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || export PATH="$HOME/.local/bin:$PATH"' python

if [[ ! -f "$TARGET_HOME/.nvm/alias/default" ]]; then
  node_default=''
else
  node_default="$(cat "$TARGET_HOME/.nvm/alias/default")"
fi
if [[ ! -f "$TARGET_HOME/.nvm/nvm.sh" ]]; then
  row node missing Node.js '尚未安装 nvm' language 2
elif [[ -z "$node_default" ]] || ! compgen -G "$node_runtime/*/bin/node" >/dev/null; then
  row node issue Node.js 'nvm 已安装，但默认 Node.js 版本缺失' language 2
elif ! has_line 'export NVM_DIR="$HOME/.nvm"; [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"' || ! zsh_command node; then
  row node issue Node.js '默认版本已安装，但新 Zsh 会话无法使用' language 2
elif ! zsh_command npm || ! grep -Eq '^registry=https://registry\.npmmirror\.com/?$' "$TARGET_HOME/.npmrc" 2>/dev/null; then
  row node issue Node.js 'npm 不可用或国内包源尚未配置' language 2
else
  row node ok Node.js '默认版本已在新 Zsh 会话生效' - -
fi

check_language rust Rust 3 "$TARGET_HOME/.cargo/bin/rustup" "$rust_runtime" \
  '[[ ":$PATH:" == *":$HOME/.cargo/bin:"* ]] || export PATH="$HOME/.cargo/bin:$PATH"' rustc

service_row(){
  local key="$1" label="$2" binary="$3" unit="$4" focus="$5"
  local destination=bootstrap
  [[ "$key" == docker ]] && destination=docker
  if ! command -v "$binary" >/dev/null 2>&1 && [[ ! -x "/usr/sbin/$binary" ]]; then
    row "$key" missing "$label" '尚未安装' "$destination" "$focus"
  elif [[ ! -d /run/systemd/system ]] || ! command -v systemctl >/dev/null 2>&1 ||
    ! systemctl list-unit-files "$unit" --no-legend 2>/dev/null | grep -q .; then
    row "$key" unknown "$label" '无法确认 systemd 服务状态' "$destination" "$focus"
  elif systemctl is-active --quiet "$unit" 2>/dev/null; then
    row "$key" ok "$label" '服务正在运行' - -
  else
    row "$key" issue "$label" '已安装，但服务未运行' "$destination" "$focus"
  fi
}
service_row docker Docker docker docker.service 1
service_row ssh SSH sshd ssh.service 1

if ! command -v ufw >/dev/null 2>&1 && [[ ! -x /usr/sbin/ufw ]]; then
  row ufw missing UFW '尚未安装' bootstrap 6
else
  if [[ $EUID -eq 0 ]]; then
    ufw_state="$(/usr/sbin/ufw status 2>/dev/null || true)"
  else
    ufw_state="$(sudo -n /usr/sbin/ufw status 2>/dev/null || true)"
  fi
  if [[ "$ufw_state" == *'Status: active'* ]]; then
    row ufw ok UFW '防火墙已启用' - -
  elif [[ "$ufw_state" == *'Status: inactive'* ]]; then
    row ufw issue UFW '已安装，但防火墙未启用' bootstrap 6
  else
    row ufw unknown UFW '无法读取防火墙状态' bootstrap 6
  fi
fi

if [[ -s "$TARGET_HOME/.ssh/authorized_keys" ]]; then
  row sshkey ok SSH公钥 '已配置 authorized_keys' - -
else
  row sshkey missing SSH公钥 '尚未配置' bootstrap 5
fi
