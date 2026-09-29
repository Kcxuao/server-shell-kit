# Impact Guard: external dcg is the only risk decision source.
[[ -n "${IMPACT_GUARD_LOADED:-}" ]] && return
typeset -g IMPACT_GUARD_LOADED=1
typeset -g IMPACT_GUARD_DIR="${${(%):-%N}:A:h}"
typeset -g DCG_LIBRARY_MODE=1
source "$IMPACT_GUARD_DIR/dangerous-command-guard.plugin.zsh" || return 1
unset DCG_LIBRARY_MODE
source "$IMPACT_GUARD_DIR/impact-guard-analysis.zsh" || return 1

_impact_guard_accept_line() {
    local command_text="$BUFFER" output dcg_status_code decision pack_id rule_id severity reason confirmed=0
    local IMPACT_GUARD_CONFIRM_BRIEF=1
    [[ -z "${command_text//[[:space:]]/}" || "$command_text" =~ '^[[:space:]]*#' || "$DCG_ENABLED" != 1 ]] && { zle .accept-line; return; }
    if ! command -v dcg >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        print -u2 'Impact Guard：缺少外部 dcg 或 jq，命令已取消。'
        zle reset-prompt; return
    fi
    if command -v timeout >/dev/null 2>&1; then
        output="$(printf '%s' "$command_text" | command timeout 8s dcg test --stdin --dialect posix --format json --with-packs core.filesystem,core.git,containers.docker,containers.compose,system.disk,system.permissions,system.services 2>/dev/null)"
        dcg_status_code=$?
    else
        output="$(printf '%s' "$command_text" | command dcg test --stdin --dialect posix --format json --with-packs core.filesystem,core.git,containers.docker,containers.compose,system.disk,system.permissions,system.services 2>/dev/null)"
        dcg_status_code=$?
    fi
    if ! jq -e 'type == "object" and (.decision == "allow" or .decision == "deny")' >/dev/null 2>&1 <<< "$output"; then
        print -u2 'Impact Guard：dcg 输出无效或缺少判定，命令已取消。'
        zle reset-prompt; return
    fi
    decision="$(jq -r '.decision' <<< "$output")"
    if [[ "$decision" == allow ]]; then
        (( dcg_status_code == 0 )) || { print -u2 'Impact Guard：dcg 判定与退出状态不一致，命令已取消。'; zle reset-prompt; return; }
        zle .accept-line; return
    fi
    # dcg uses exit status 1 for a valid deny result.
    if (( dcg_status_code != 1 )); then print -u2 'Impact Guard：dcg 调用异常，命令已取消。'; zle reset-prompt; return; fi
    pack_id="$(jq -r '.pack_id // .matches[0].pack_id // "UNKNOWN"' <<< "$output")"
    rule_id="$(jq -r '.rule_id // .matches[0].rule_id // "UNKNOWN"' <<< "$output")"
    severity="$(jq -r '.severity // .matches[0].severity // "UNKNOWN"' <<< "$output")"
    reason="$(jq -r '.reason // .message // .matches[0].description // "外部 dcg 已拦截"' <<< "$output")"
    local rule_key="${rule_id##*:}" rule_name severity_label localized_reason
    case "$pack_id:$rule_key" in
      containers.docker:volume-rm)
        rule_name='删除 Docker Volume'
        localized_reason='此操作会永久删除 Docker Volume 及其中的数据。'
        ;;
      system.services:systemctl-stop)
        rule_name='修改 systemd 服务状态'
        localized_reason='此操作会影响服务的运行或开机启动状态，请确认服务名称和依赖。'
        ;;
      core.filesystem:rm-rf|core.filesystem:rm-recursive-force)
        rule_name='递归强制删除文件或目录'
        localized_reason='此操作会递归删除目标，可能造成数据丢失。'
        ;;
      core.filesystem:rm-rf-general)
        rule_name='递归强制删除文件或目录'
        localized_reason='rm -rf 会递归强制删除目标；请先确认路径和内容。'
        ;;
      core.git:reset-hard)
        rule_name='丢弃 Git 未提交修改'
        localized_reason='此操作会强制丢弃 Git 工作区修改。'
        ;;
      *)
        rule_name="外部规则 $rule_key"
        localized_reason="未配置此规则的中文原因；dcg 原文：$reason"
        ;;
    esac
    case "$severity" in
      critical) severity_label='极高风险' ;;
      high) severity_label='高风险' ;;
      medium) severity_label='中风险' ;;
      low) severity_label='低风险' ;;
      info) severity_label='提示' ;;
      *) severity_label='未知' ;;
    esac
    zle -I
    printf "\n"
    _impact_guard_analyze "$command_text" "$pack_id" "$rule_id" "$PWD" "$localized_reason" "$severity_label" "$rule_name"
    case "$severity" in
      critical) _dcg_confirm_level2 "$command_text" "$localized_reason" && confirmed=1 ;;
      high|medium|low|info) _dcg_confirm_level1 "$command_text" "$localized_reason" && confirmed=1 ;;
      *) _dcg_confirm_level2 "$command_text" "$localized_reason（严重级别未知）" && confirmed=1 ;;
    esac
    (( confirmed )) || { zle reset-prompt; return; }
    if [[ "$DCG_RM_BACKUP" == 1 ]] && _dcg_is_force_recursive_rm "$command_text"; then
        if ! _dcg_backup_rm "$command_text"; then
            printf '%b✗ 无法安全备份删除目标，命令已取消。%b\n' "$DCG_RED" "$DCG_RESET"
            zle reset-prompt; return
        fi
    fi
    zle .accept-line
}

if [[ -o interactive ]]; then
    zle -N _impact_guard_accept_line
    bindkey '^M' _impact_guard_accept_line
    bindkey '^J' _impact_guard_accept_line
fi
