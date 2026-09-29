# Dangerous Command Guard for interactive Zsh
[[ -n "${DCG_LOADED:-}" ]] && return
typeset -g DCG_LOADED=1
typeset -g DCG_ENABLED=1
typeset -g DCG_CONFIG="$HOME/.config/zsh/server-shell-kit/danger-guard.conf"
if [[ -f "$DCG_CONFIG" ]] && grep -Fxq 'enabled=0' "$DCG_CONFIG"; then
    DCG_ENABLED=0
fi
typeset -g DCG_RM_BACKUP=1
typeset -g DCG_RM_BACKUP_CONFIG="$HOME/.config/zsh/server-shell-kit/rm-backup.conf"
if [[ -f "$DCG_RM_BACKUP_CONFIG" ]] && grep -Fxq 'enabled=0' "$DCG_RM_BACKUP_CONFIG"; then
    DCG_RM_BACKUP=0
fi

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
    if [[ "${IMPACT_GUARD_CONFIRM_BRIEF:-0}" == 1 ]]; then
        printf '\n%b输入 yes 执行，其他输入取消 › %b' "$DCG_YELLOW" "$DCG_RESET"
        IFS= read -r answer </dev/tty
        [[ "$answer" == [Yy][Ee][Ss] ]] && return 0
        printf '\n%b已取消执行。%b\n' "$DCG_RED" "$DCG_RESET"
        return 1
    fi
    printf '\n%b%b============================================================%b\n' "$DCG_YELLOW" "$DCG_BOLD" "$DCG_RESET"
    printf '%b%b⚠️  检测到高危命令%b\n' "$DCG_YELLOW" "$DCG_BOLD" "$DCG_RESET"
    printf '%b%b============================================================%b\n' "$DCG_YELLOW" "$DCG_BOLD" "$DCG_RESET"
    printf '\n命令：%s\n风险：%s\n\n' "$cmd" "$reason"
    printf '%b请输入 yes 确认执行：%b' "$DCG_YELLOW" "$DCG_RESET"
    IFS= read -r answer </dev/tty
    [[ "$answer" == [Yy][Ee][Ss] ]] && { printf '\n%b✓ 已确认，继续执行%b\n\n' "$DCG_GREEN" "$DCG_RESET"; return 0; }
    printf '\n%b✗ 已取消执行%b\n\n' "$DCG_RED" "$DCG_RESET"; return 1
}

_dcg_confirm_level2() {
    local cmd="$1" reason="$2" answer
    zle -I 2>/dev/null
    if [[ "${IMPACT_GUARD_CONFIRM_BRIEF:-0}" == 1 ]]; then
        printf '\n%b重新输入完整命令确认 › %b' "$DCG_RED" "$DCG_RESET"
        IFS= read -r answer </dev/tty
        [[ "$answer" == "$cmd" ]] && return 0
        printf '\n%b命令不匹配，已取消执行。%b\n' "$DCG_RED" "$DCG_RESET"
        return 1
    fi
    printf '\n%b%b============================================================%b\n' "$DCG_RED" "$DCG_BOLD" "$DCG_RESET"
    printf '%b%b🚨 检测到极高危命令%b\n' "$DCG_RED" "$DCG_BOLD" "$DCG_RESET"
    printf '%b%b============================================================%b\n' "$DCG_RED" "$DCG_BOLD" "$DCG_RESET"
    printf '\n命令：%s\n风险：%s\n%b此操作可能造成不可恢复的数据丢失。%b\n\n' "$cmd" "$reason" "$DCG_RED" "$DCG_RESET"
    printf '请重新输入完整命令确认：\n> '
    IFS= read -r answer </dev/tty
    [[ "$answer" == "$cmd" ]] && { printf '\n%b✓ 命令匹配，继续执行%b\n\n' "$DCG_GREEN" "$DCG_RESET"; return 0; }
    printf '\n%b✗ 命令不匹配，已取消执行%b\n\n' "$DCG_RED" "$DCG_RESET"; return 1
}

_dcg_is_force_recursive_rm() {
    [[ "$1" =~ '(^|[;&|[:space:]])(sudo[[:space:]]+)?(command[[:space:]]+)?rm[[:space:]].*(-rf|-fr|-[rR][[:space:]]+-f|-f[[:space:]]+-[rR])' ]]
}

_dcg_backup_rm() {
    local cmd="$1" word target resolved backup_root backup_dir index=0 recursive=0 force=0 options=1
    local -a words paths
    words=( ${(z)cmd} )
    (( ${#words} >= 3 )) || return 1
    if [[ "${words[1]}" == sudo ]]; then shift words; fi
    if [[ "${words[1]}" == command ]]; then shift words; fi
    [[ "${words[1]}" == rm ]] || return 1
    shift words
    for word in "${words[@]}"; do
        # Dynamic expansion and shell operators cannot be mapped reliably to deleted files.
        [[ "$word" == *'$'* || "$word" == *'`'* || "$word" == *'*'* || "$word" == *'?'* ||
           "$word" == *'['* || "$word" == *']'* || "$word" == *'{'* || "$word" == *'}'* ||
           "$word" == *';'* || "$word" == *'|'* || "$word" == *'&'* || "$word" == *'>'* ||
           "$word" == *'<'* || "$word" == *$'\n'* ]] && return 1
        word="${(Q)word}"
        if (( options )) && [[ "$word" == -- ]]; then
            options=0
        elif (( options )) && [[ "$word" == -* ]]; then
            case "$word" in
                --recursive) recursive=1 ;;
                --force) force=1 ;;
                -*)
                    [[ "$word" =~ '^-[rfR]+$' ]] || return 1
                    [[ "$word" == *r* || "$word" == *R* ]] && recursive=1
                    [[ "$word" == *f* ]] && force=1 ;;
                *) return 1 ;;
            esac
        else
            [[ -n "$word" && "$word" != '~'* ]] || return 1
            paths+=( "$word" )
        fi
    done
    (( recursive && force && ${#paths} )) || return 1
    backup_root="$HOME/.local/share/server-shell-kit/rm-backups"
    mkdir -p -m 700 -- "$backup_root" || return 1
    backup_root="$(realpath -m -- "$backup_root")" || return 1
    for target in "${paths[@]}"; do
        resolved="$(realpath -m -- "$target")" || return 1
        [[ "$resolved" != / && "$backup_root" != "$resolved" && "$backup_root" != "$resolved"/* ]] || return 1
    done
    backup_dir="$(mktemp -d "$backup_root/$(date +%Y%m%d-%H%M%S)-XXXXXXXX")" || return 1
    chmod 700 -- "$backup_dir" || return 1
    for target in "${paths[@]}"; do
        if [[ -e "$target" || -L "$target" ]]; then
            (( index += 1 ))
            if ! cp -a -- "$target" "$backup_dir/$index"; then
                rm -rf -- "$backup_dir"
                return 1
            fi
            if ! printf '%s\t%s\n' "$index" "$(realpath -m -s -- "$target")" >> "$backup_dir/paths.txt"; then
                rm -rf -- "$backup_dir"
                return 1
            fi
        fi
    done
    printf '已备份到：%s\n' "$backup_dir"
    printf '恢复时查看 paths.txt，将编号文件复制回原路径。\n'
}

_dcg_guard() {
    local cmd="$1"
    [[ "$DCG_ENABLED" == 1 ]] || return 0
    [[ -z "${cmd//[[:space:]]/}" ]] && return 0
    [[ "$cmd" =~ '^[[:space:]]*#' ]] && return 0
    _dcg_detect "$cmd"
    case "$DCG_LEVEL" in
        0) return 0 ;;
        1) _dcg_confirm_level1 "$cmd" "$DCG_REASON" || return 1 ;;
        2) _dcg_confirm_level2 "$cmd" "$DCG_REASON" || return 1 ;;
    esac
    if [[ "$DCG_RM_BACKUP" == 1 ]] && _dcg_is_force_recursive_rm "$cmd"; then
        if ! _dcg_backup_rm "$cmd"; then
            printf '%b✗ 无法安全备份删除目标，命令已取消。请使用明确的路径。%b\n' "$DCG_RED" "$DCG_RESET"
            return 1
        fi
    fi
    return 0
}

_dcg_accept_line() {
    local cmd="$BUFFER"
    if _dcg_guard "$cmd"; then zle .accept-line; else zle reset-prompt; fi
}

if [[ -o interactive && "${DCG_LIBRARY_MODE:-0}" != 1 ]]; then
    zle -N _dcg_accept_line
    bindkey '^M' _dcg_accept_line
    bindkey '^J' _dcg_accept_line
fi

dcg-enable(){ DCG_ENABLED=1; echo 'Dangerous Command Guard: enabled'; }
dcg-disable(){ DCG_ENABLED=0; echo 'Dangerous Command Guard: disabled'; }
dcg-status(){ [[ "$DCG_ENABLED" == 1 ]] && echo 'Dangerous Command Guard: enabled' || echo 'Dangerous Command Guard: disabled'; }
_dcg_set_rm_backup() {
    local value="$1" config_dir="${DCG_RM_BACKUP_CONFIG:h}"
    mkdir -p -- "$config_dir" || return 1
    printf 'enabled=%s\n' "$value" > "$DCG_RM_BACKUP_CONFIG" || return 1
    chmod 600 -- "$DCG_RM_BACKUP_CONFIG" || return 1
    DCG_RM_BACKUP="$value"
}
dcg-backup-enable(){ _dcg_set_rm_backup 1 && echo 'rm -rf 自动备份：已开启'; }
dcg-backup-disable(){ _dcg_set_rm_backup 0 && echo 'rm -rf 自动备份：已关闭'; }
dcg-backup-status(){ [[ "$DCG_RM_BACKUP" == 1 ]] && echo 'rm -rf 自动备份：已开启' || echo 'rm -rf 自动备份：已关闭'; }
dcg-test(){
    local cmd="$*"
    [[ -z "$cmd" ]] && { echo "用法: dcg-test 'command'"; return 1; }
    _dcg_detect "$cmd"
    case "$DCG_LEVEL" in 0) echo '级别: 安全' ;; 1) echo '级别: 高危' ;; 2) echo '级别: 极高危' ;; esac
    echo "命令: $cmd"
    [[ "$DCG_LEVEL" != 0 ]] && echo "原因: $DCG_REASON"
}
