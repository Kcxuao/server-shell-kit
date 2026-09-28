# Dangerous Command Guard for interactive Zsh
[[ -n "${DCG_LOADED:-}" ]] && return
typeset -g DCG_LOADED=1
typeset -g DCG_ENABLED=1

typeset -g DCG_RED=$'\033[31m'
typeset -g DCG_YELLOW=$'\033[33m'
typeset -g DCG_GREEN=$'\033[32m'
typeset -g DCG_BOLD=$'\033[1m'
typeset -g DCG_RESET=$'\033[0m'

_dcg_detect() {
    local cmd="$1"
    typeset -g DCG_LEVEL=0
    typeset -g DCG_REASON=""

    if [[ "$cmd" =~ '(^|[;&|[:space:]])(sudo[[:space:]]+)?(command[[:space:]]+)?rm[[:space:]].*(-rf|-fr|-[rR][[:space:]]+-f|-f[[:space:]]+-[rR]).*[[:space:]]/(\*|[[:space:]]|$)' ]]; then DCG_LEVEL=2; DCG_REASON="递归强制删除根目录"; return; fi
    if [[ "$cmd" =~ '(^|[;&|[:space:]])(sudo[[:space:]]+)?(command[[:space:]]+)?rm[[:space:]].*(-rf|-fr|-[rR][[:space:]]+-f|-f[[:space:]]+-[rR]).*[[:space:]]/(etc|usr|var|opt|root|home|boot|srv)(/|[[:space:]]|$)' ]]; then DCG_LEVEL=2; DCG_REASON="递归强制删除系统关键目录"; return; fi
    if [[ "$cmd" =~ '(^|[;&|[:space:]])(sudo[[:space:]]+)?(command[[:space:]]+)?rm[[:space:]].*(-rf|-fr|-[rR][[:space:]]+-f|-f[[:space:]]+-[rR]).*(^|[[:space:]])(\*|\./\*|\.\./\*)($|[[:space:]])' ]]; then DCG_LEVEL=2; DCG_REASON="使用通配符进行递归强制删除"; return; fi

    if [[ "$cmd" =~ '(^|[;&|[:space:]])(sudo[[:space:]]+)?mkfs(\.[a-zA-Z0-9_-]+)?[[:space:]]' ]]; then DCG_LEVEL=2; DCG_REASON="格式化文件系统"; return; fi
    if [[ "$cmd" =~ '(^|[;&|[:space:]])(sudo[[:space:]]+)?wipefs[[:space:]]' ]]; then DCG_LEVEL=2; DCG_REASON="擦除文件系统或磁盘签名"; return; fi
    if [[ "$cmd" =~ '(^|[;&|[:space:]])(sudo[[:space:]]+)?dd[[:space:]].*of=/dev/' ]]; then DCG_LEVEL=2; DCG_REASON="直接向块设备写入数据"; return; fi
    if [[ "$cmd" =~ '(^|[;&|[:space:]])(sudo[[:space:]]+)?shred[[:space:]].*/dev/' ]]; then DCG_LEVEL=2; DCG_REASON="擦除块设备数据"; return; fi
    if [[ "$cmd" =~ '(^|[;&|[:space:]])(sudo[[:space:]]+)?(fdisk|cfdisk|sfdisk|parted|gdisk)[[:space:]]+/dev/' ]]; then DCG_LEVEL=2; DCG_REASON="修改磁盘分区"; return; fi
    if [[ "$cmd" =~ '(^|[;&|[:space:]])(sudo[[:space:]]+)?(lvremove|vgremove|pvremove)[[:space:]]' ]]; then DCG_LEVEL=2; DCG_REASON="删除 LVM 存储结构"; return; fi

    if [[ "$cmd" =~ '(^|[;&|[:space:]])(sudo[[:space:]]+)?chmod[[:space:]].*-R.*777' ]]; then DCG_LEVEL=2; DCG_REASON="递归设置 777 权限"; return; fi
    if [[ "$cmd" =~ '(^|[;&|[:space:]])(sudo[[:space:]]+)?chmod[[:space:]].*-R.*[[:space:]]/([[:space:]]|$)' ]]; then DCG_LEVEL=2; DCG_REASON="递归修改根目录权限"; return; fi
    if [[ "$cmd" =~ '(^|[;&|[:space:]])(sudo[[:space:]]+)?chown[[:space:]].*-R.*[[:space:]]/([[:space:]]|$)' ]]; then DCG_LEVEL=2; DCG_REASON="递归修改根目录所有权"; return; fi

    if [[ "$cmd" =~ '(^|[;&|[:space:]])(sudo[[:space:]]+)?docker[[:space:]]+volume[[:space:]]+prune' ]]; then DCG_LEVEL=2; DCG_REASON="清理 Docker Volume，可能永久删除持久化数据"; return; fi
    if [[ "$cmd" =~ '(^|[;&|[:space:]])(sudo[[:space:]]+)?docker[[:space:]]+volume[[:space:]]+(rm|remove)[[:space:]]' ]]; then DCG_LEVEL=2; DCG_REASON="删除 Docker Volume"; return; fi
    if [[ "$cmd" =~ 'docker[[:space:]]+compose[[:space:]]+down.*(-v|--volumes)' || "$cmd" =~ 'docker-compose[[:space:]]+down.*(-v|--volumes)' ]]; then DCG_LEVEL=2; DCG_REASON="Docker Compose 删除容器及 Volume"; return; fi

    if [[ "$cmd" =~ '(^|[;&|[:space:]])(sudo[[:space:]]+)?iptables[[:space:]]+(-F|--flush)' ]]; then DCG_LEVEL=2; DCG_REASON="清空 iptables 防火墙规则"; return; fi
    if [[ "$cmd" =~ '(^|[;&|[:space:]])(sudo[[:space:]]+)?nft[[:space:]]+flush[[:space:]]+ruleset' ]]; then DCG_LEVEL=2; DCG_REASON="清空 nftables 防火墙规则"; return; fi
    if [[ "$cmd" =~ '(^|[;&|[:space:]])(sudo[[:space:]]+)?userdel[[:space:]].*-r' ]]; then DCG_LEVEL=2; DCG_REASON="删除用户及其 HOME 数据"; return; fi

    if [[ "$cmd" =~ '(^|[;&|[:space:]])(sudo[[:space:]]+)?find[[:space:]].*[[:space:]]-delete([[:space:]]|$)' ]]; then DCG_LEVEL=1; DCG_REASON="find 批量删除文件"; return; fi
    if [[ "$cmd" =~ '(^|[;&|[:space:]])(sudo[[:space:]]+)?find[[:space:]].*(-exec|-execdir).*rm[[:space:]]' ]]; then DCG_LEVEL=1; DCG_REASON="find 批量调用 rm 删除文件"; return; fi
    if [[ "$cmd" =~ '(^|[;&|[:space:]])(sudo[[:space:]]+)?(command[[:space:]]+)?rm[[:space:]].*(-rf|-fr|-[rR][[:space:]]+-f|-f[[:space:]]+-[rR])' ]]; then DCG_LEVEL=1; DCG_REASON="递归强制删除文件或目录"; return; fi
    if [[ "$cmd" =~ '(^|[;&|[:space:]])(sudo[[:space:]]+)?docker[[:space:]]+system[[:space:]]+prune' ]]; then DCG_LEVEL=1; DCG_REASON="清理 Docker 未使用资源"; return; fi
    if [[ "$cmd" =~ '(^|[;&|[:space:]])git[[:space:]]+reset[[:space:]]+--hard' ]]; then DCG_LEVEL=1; DCG_REASON="Git 强制丢弃工作区修改"; return; fi
    if [[ "$cmd" =~ '(^|[;&|[:space:]])git[[:space:]]+push[[:space:]].*(--force|-f)([[:space:]]|$)' ]]; then DCG_LEVEL=1; DCG_REASON="Git 强制推送"; return; fi
    if [[ "$cmd" =~ '(^|[;&|[:space:]])(sudo[[:space:]]+)?(reboot|poweroff|halt)([[:space:]]|$)' ]]; then DCG_LEVEL=1; DCG_REASON="重启或关闭服务器"; return; fi
    if [[ "$cmd" =~ '(^|[;&|[:space:]])(sudo[[:space:]]+)?shutdown[[:space:]]' ]]; then DCG_LEVEL=1; DCG_REASON="关闭或重启服务器"; return; fi
}

_dcg_confirm_level1() {
    local cmd="$1" reason="$2" answer
    zle -I 2>/dev/null
    printf '\n%b%b============================================================%b\n' "$DCG_YELLOW" "$DCG_BOLD" "$DCG_RESET"
    printf '%b%b⚠️  检测到高危命令%b\n' "$DCG_YELLOW" "$DCG_BOLD" "$DCG_RESET"
    printf '%b%b============================================================%b\n' "$DCG_YELLOW" "$DCG_BOLD" "$DCG_RESET"
    printf '\n命令：%s\n风险：%s\n\n' "$cmd" "$reason"
    printf '%b请输入 YES 确认执行：%b' "$DCG_YELLOW" "$DCG_RESET"
    IFS= read -r answer </dev/tty
    [[ "$answer" == YES ]] && { printf '\n%b✓ 已确认，继续执行%b\n\n' "$DCG_GREEN" "$DCG_RESET"; return 0; }
    printf '\n%b✗ 已取消执行%b\n\n' "$DCG_RED" "$DCG_RESET"; return 1
}

_dcg_confirm_level2() {
    local cmd="$1" reason="$2" answer
    zle -I 2>/dev/null
    printf '\n%b%b============================================================%b\n' "$DCG_RED" "$DCG_BOLD" "$DCG_RESET"
    printf '%b%b🚨 检测到极高危命令%b\n' "$DCG_RED" "$DCG_BOLD" "$DCG_RESET"
    printf '%b%b============================================================%b\n' "$DCG_RED" "$DCG_BOLD" "$DCG_RESET"
    printf '\n命令：%s\n风险：%s\n%b此操作可能造成不可恢复的数据丢失。%b\n\n' "$cmd" "$reason" "$DCG_RED" "$DCG_RESET"
    printf '请重新输入完整命令确认：\n> '
    IFS= read -r answer </dev/tty
    [[ "$answer" == "$cmd" ]] && { printf '\n%b✓ 命令匹配，继续执行%b\n\n' "$DCG_GREEN" "$DCG_RESET"; return 0; }
    printf '\n%b✗ 命令不匹配，已取消执行%b\n\n' "$DCG_RED" "$DCG_RESET"; return 1
}

_dcg_guard() {
    local cmd="$1"
    [[ "$DCG_ENABLED" == 1 ]] || return 0
    [[ -z "${cmd//[[:space:]]/}" ]] && return 0
    [[ "$cmd" =~ '^[[:space:]]*#' ]] && return 0
    _dcg_detect "$cmd"
    case "$DCG_LEVEL" in
        0) return 0 ;;
        1) _dcg_confirm_level1 "$cmd" "$DCG_REASON" ;;
        2) _dcg_confirm_level2 "$cmd" "$DCG_REASON" ;;
    esac
}

_dcg_accept_line() {
    local cmd="$BUFFER"
    if _dcg_guard "$cmd"; then zle .accept-line; else zle reset-prompt; fi
}

if [[ -o interactive ]]; then
    zle -N _dcg_accept_line
    bindkey '^M' _dcg_accept_line
    bindkey '^J' _dcg_accept_line
fi

dcg-enable(){ DCG_ENABLED=1; echo 'Dangerous Command Guard: enabled'; }
dcg-disable(){ DCG_ENABLED=0; echo 'Dangerous Command Guard: disabled'; }
dcg-status(){ [[ "$DCG_ENABLED" == 1 ]] && echo 'Dangerous Command Guard: enabled' || echo 'Dangerous Command Guard: disabled'; }
dcg-test(){
    local cmd="$*"
    [[ -z "$cmd" ]] && { echo "用法: dcg-test 'command'"; return 1; }
    _dcg_detect "$cmd"
    case "$DCG_LEVEL" in 0) echo '级别: 安全' ;; 1) echo '级别: 高危' ;; 2) echo '级别: 极高危' ;; esac
    echo "命令: $cmd"
    [[ "$DCG_LEVEL" != 0 ]] && echo "原因: $DCG_REASON"
}
