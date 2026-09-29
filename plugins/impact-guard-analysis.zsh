# Read-only, best-effort impact lookup for Impact Guard.
_impact_guard_ui_init() {
    local width=${COLUMNS:-70}
    [[ "$width" == <-> ]] || width=70
    (( width == 0 )) && width=70
    (( width > 70 )) && width=70
    (( width < 40 )) && width=40
    _IG_WIDTH=$width
    _IG_INNER=$(( width - 4 ))
    _IG_COLOR=1
    [[ -t 1 && "$TERM" != dumb && -z ${NO_COLOR+x} ]] || _IG_COLOR=0
    if (( _IG_COLOR )); then
        _IG_RED=$'\e[31m'; _IG_BRED=$'\e[1;31m'; _IG_YELLOW=$'\e[33m'
        _IG_CYAN=$'\e[36m'; _IG_WHITE=$'\e[97m'; _IG_GREEN=$'\e[32m'
        _IG_DIM=$'\e[90m'; _IG_RESET=$'\e[0m'
    else
        _IG_RED=''; _IG_BRED=''; _IG_YELLOW=''; _IG_CYAN=''; _IG_WHITE=''
        _IG_GREEN=''; _IG_DIM=''; _IG_RESET=''
    fi
}

_impact_guard_rule_color() {
    case "$1" in
      极高风险|CRITICAL) REPLY=$_IG_BRED ;;
      高风险|HIGH) REPLY=$_IG_RED ;;
      中风险|警告|WARNING) REPLY=$_IG_YELLOW ;;
      低风险|INFO) REPLY=$_IG_CYAN ;;
      *) REPLY=$_IG_YELLOW ;;
    esac
}

_impact_guard_titled_line() {
    local title=$1 n=$(( _IG_WIDTH - ${#1} - 5 ))
    [[ "$title" == '🛡'* || "$title" == '⚠'* ]] && (( n-- ))
    (( n < 1 )) && n=1
    printf '%s╭─ %s %s╮%s\n' "$_IG_DIM" "$title" "${(l:$n::─:)}" "$_IG_RESET"
}

_impact_guard_display_width() {
    local value=$1 ch
    REPLY=0
    for ch in ${(s::)value}; do
        if [[ "$ch" == [[:ascii:]] || "$ch" == ● || "$ch" == ○ || "$ch" == • ]]; then
            (( REPLY++ ))
        else
            (( REPLY += 2 ))
        fi
    done
}

_impact_guard_frame_row() {
    local value=$1 color=${2:-} visible padding
    _impact_guard_display_width "$value"; visible=$REPLY
    padding=$(( _IG_WIDTH - visible - 4 ))
    (( padding < 0 )) && padding=0
    printf '%s│%s  %b%s%b%*s%s│%s\n' "$_IG_DIM" "$_IG_RESET" "$color" "$value" "$_IG_RESET" "$padding" '' "$_IG_DIM" "$_IG_RESET"
}

_impact_guard_wrap_row() {
    local value=$1 color=${2:-} line='' ch char_width line_width=0
    local max_width=$(( _IG_WIDTH - 6 ))
    for ch in ${(s::)value}; do
        if [[ "$ch" == [[:ascii:]] ]]; then char_width=1; else char_width=2; fi
        if (( line_width + char_width > max_width )); then
            _impact_guard_frame_row "$line" "$color"
            line='' line_width=0
        fi
        line+=$ch
        (( line_width += char_width ))
    done
    _impact_guard_frame_row "$line" "$color"
}

_impact_guard_banner() {
    local level=$1 color label right='DESTRUCTIVE ACTION' padding
    _impact_guard_rule_color "$level"; color=$REPLY
    _impact_guard_titled_line '🛡  IMPACT GUARD'
    label="● ${level:-风险未知}"
    _impact_guard_display_width "$label"; padding=$(( _IG_WIDTH - REPLY - ${#right} - 6 ))
    (( padding < 1 )) && padding=1
    printf '%s│%s  %b%s%b%*s%s  %s│%s\n' "$_IG_DIM" "$_IG_RESET" "$color" "$label" "$_IG_RESET" "$padding" '' "$right" "$_IG_DIM" "$_IG_RESET"
    printf '%s╰%s╯%s\n' "$_IG_DIM" "${(l:$(( _IG_WIDTH - 2 ))::─:)}" "$_IG_RESET"
}

_impact_guard_result() {
    local color=$1 reason=$2
    _impact_guard_titled_line RESULT
    _impact_guard_frame_row '● 待确认 / CONFIRM' "$_IG_YELLOW"
    _impact_guard_wrap_row "$reason"
    printf '%s╰%s╯%s\n' "$_IG_DIM" "${(l:$(( _IG_WIDTH - 2 ))::─:)}" "$_IG_RESET"
}

_impact_guard_check_row() {
    local check_state=$1 label=$2 value=$3 marker color label_width padding
    case "$check_state" in
      ok) marker='●'; color=$_IG_GREEN ;;
      warn) marker='●'; color=$_IG_YELLOW ;;
      none) marker='○'; color=$_IG_DIM ;;
      *) marker='●'; color=$_IG_YELLOW ;;
    esac
    _impact_guard_display_width "$label"; label_width=$REPLY
    padding=$(( 16 - label_width ))
    (( padding < 1 )) && padding=1
    local value_width
    _impact_guard_display_width "$value"; value_width=$REPLY
    if (( 2 + 2 + 2 + label_width + padding + 2 + value_width > _IG_WIDTH )); then
        printf '  %b%s%b  %s\n      %s\n' "$color" "$marker" "$_IG_RESET" "$label" "$value"
    else
        printf '  %b%s%b  %s%*s  %s\n' "$color" "$marker" "$_IG_RESET" "$label" "$padding" '' "$value"
    fi
}

_impact_guard_analyze() {
    local command_text="$1" pack_id="$2" rule_id="$3" reason="$5" severity="$6" rule_name="$7"
    local details line tag id kind value extra1 extra2 level_color target_count=0 check_count=0 i current_check_id=0
    local -a paths sizes types checks typed_checks
    _impact_guard_ui_init
    details="$(_impact_guard_analyze_details "$@")"
    while IFS= read -r line; do
        if [[ "$line" == __IGR__\|* ]]; then
            IFS='|' read -r tag id kind value extra1 extra2 <<< "$line"
            case "$kind" in
              T) paths[$id]=$value; (( target_count++ )) ;;
              S) sizes[$id]=$value ;;
              Y) types[$id]=$value ;;
              C) typed_checks+=("$id|$value|$extra1|$extra2") ;;
            esac
        elif [[ -n "$line" && "$line" != __IG_FULL_REPORT__ ]]; then
            checks+=("${line#  }")
            (( check_count++ ))
        fi
    done <<< "$details"
    _impact_guard_rule_color "$severity"; level_color=$REPLY
    _impact_guard_banner "${severity:-风险未知}"
    printf '\n  %b$ %s%b\n' "$_IG_WHITE" "$command_text" "$_IG_RESET"
    printf '\n  %bTARGET%b\n' "$_IG_WHITE" "$_IG_RESET"
    if (( target_count )); then
        for (( i = 1; i <= ${#paths}; i++ )); do
            [[ -n "${paths[$i]:-}" ]] || continue
            (( i > 1 )) && printf '\n'
            if [[ "${types[$i]:-}" == "Docker Volume"* ]]; then
                printf '  Volume     %b%s%b\n' "$_IG_CYAN" "${paths[$i]}" "$_IG_RESET"
            else
                printf '  Path       %b%s%b\n' "$_IG_CYAN" "${paths[$i]}" "$_IG_RESET"
            fi
            printf '  Size       %s\n' "${sizes[$i]:-UNKNOWN}"
            printf '  Type       %s\n' "${types[$i]:-UNKNOWN}"
        done
    else
        printf '  Path       UNKNOWN\n  Size       UNKNOWN\n  Type       UNKNOWN\n'
    fi
    printf '\n  %bCHECKS%b\n' "$_IG_WHITE" "$_IG_RESET"
    if (( ${#typed_checks} )); then
        for line in "${typed_checks[@]}"; do
            IFS='|' read -r id value extra1 extra2 <<< "$line"
            if (( target_count > 1 && current_check_id != id )); then
                printf '  %b目标 %s%b\n' "$_IG_CYAN" "$id" "$_IG_RESET"
                current_check_id=$id
            fi
            _impact_guard_check_row "$value" "$extra1" "$extra2"
        done
    elif (( check_count )); then
        for line in "${checks[@]}"; do printf '  %b•%b  %s\n' "$_IG_CYAN" "$_IG_RESET" "$line"; done
    else
        printf '  %b●%b  UNKNOWN（没有取得可展示的检查结果）\n' "$_IG_YELLOW" "$_IG_RESET"
    fi
    printf '\n  Impact                  %s\n' "${rule_name:-影响待评估}"
    printf '  Recoverability          %bUNKNOWN%b\n\n' "$_IG_YELLOW" "$_IG_RESET"
    _impact_guard_result "$level_color" "${reason:-请核对目标与影响}"
    if [[ "$rule_id" == "$pack_id":* ]]; then
        printf '  %bdcg %s%b\n' "$_IG_DIM" "$rule_id" "$_IG_RESET"
    else
        printf '  %bdcg %s / %s%b\n' "$_IG_DIM" "${pack_id:-UNKNOWN}" "${rule_id:-UNKNOWN}" "$_IG_RESET"
    fi
}

_impact_guard_analyze_details() {
    local command_text="$1" pack_id="$2" rule_id="$3" cwd="$4" reason="$5" severity="$6" rule_name="$7"
    local -a words
    local token target target_abs output state container_ids mount_data mount_match name service_state source destination inspect_output
    words=( ${(z)command_text} )
    if (( ${#words} < 2 )) || [[ "$command_text" == *('$('*|'${'*|'`'*|'*'*|'?'*|'|'*|'>'*|'<'*|';'*|'&&'*|'||'*) ]]; then
        printf '__IGR__|1|T|UNKNOWN（包含未展开表达式或复合命令）\n影响：无法确认目标与关联资源。\n'
        return
    fi
    while [[ "${words[1]}" == sudo || "${words[1]}" == command ]]; do words=( ${words[2,-1]} ); done
    case "${words[1]} ${words[2]:-} ${words[3]:-}" in
      'docker volume rm'|'docker volume remove')
        local target_count=0 driver mountpoint size
        for token in $words[4,-1]; do
            if [[ "$token" == -f || "$token" == --force ]]; then continue; fi
            if [[ "$token" == -* ]]; then
                printf '__IGR__|1|T|UNKNOWN（包含未支持的 Docker 选项）\n'; return
            fi
            (( target_count += 1 ))
            target="${(Q)token}"
            printf '__IGR__|%s|T|%s\n' "$target_count" "$target"
            printf '__IGR__|%s|Y|Docker Volume 名称（未验证）\n' "$target_count"
            if ! command -v docker >/dev/null 2>&1; then
                printf '__IGR__|%s|C|unknown|Volume|UNKNOWN（Docker 不可用）\n' "$target_count"
                printf '  Volume、关联容器和数据量：UNKNOWN（Docker 不可用）\n'
                continue
            fi
            output="$(command timeout 8s docker volume inspect "$target" 2>/dev/null)" || {
                printf '__IGR__|%s|C|unknown|Volume|UNKNOWN（查询失败或目标不存在）\n' "$target_count"
                printf '  Volume、关联容器和数据量：UNKNOWN（查询失败或目标不存在）\n'; continue; }
            driver="$(jq -r '.[0].Driver // "UNKNOWN"' <<< "$output")"
            mountpoint="$(jq -r '.[0].Mountpoint // "UNKNOWN"' <<< "$output")"
            printf '__IGR__|%s|Y|Docker Volume\n' "$target_count"
            printf '__IGR__|%s|C|ok|Volume|已确认，驱动 %s\n' "$target_count" "$driver"
            printf '__IGR__|%s|E|Docker volume inspect：Volume 已确认（驱动 %s）\n' "$target_count" "$driver"
            printf '__IGR__|%s|A|数据类型：UNKNOWN\n' "$target_count"
            printf '__IGR__|%s|A|备份状态：UNKNOWN\n' "$target_count"
            printf '  Volume：已确认（驱动 %s）\n' "$driver"
            printf '__IG_FULL_REPORT__\n'
            local containers
            if containers="$(command timeout 8s docker ps -a --filter "volume=$target" --format '{{.Names}} ({{.Status}})' 2>/dev/null)"; then
                if [[ -n "$containers" ]]; then
                    printf '__IGR__|%s|D|%s\n' "$target_count" "Volume → 容器：${containers//$'\n'/、}"
                    printf '__IGR__|%s|I|删除该 Volume 会移除容器使用的持久化存储。\n' "$target_count"
                    printf '__IGR__|%s|A|使用者：%s\n' "$target_count" "${containers//$'\n'/、}"
                    printf '__IGR__|%s|C|warn|关联容器|%s\n' "$target_count" "${containers//$'\n'/、}"
                    printf '  使用者：%s\n' "${containers//$'\n'/、}"
                else
                    printf '__IGR__|%s|D|未发现关联容器（已查询全部容器）\n' "$target_count"
                    printf '__IGR__|%s|A|使用者：未发现（已查询全部容器）\n' "$target_count"
                    printf '__IGR__|%s|C|none|关联容器|未发现（已查询全部容器）\n' "$target_count"
                    printf '  使用者：未发现关联容器（已查询全部容器）\n'
                fi
            else
                printf '__IGR__|%s|A|使用者：UNKNOWN\n' "$target_count"
                printf '__IGR__|%s|C|unknown|关联容器|UNKNOWN（查询失败）\n' "$target_count"
                printf '  使用者：UNKNOWN（Docker 容器信息不可读取）\n'
            fi
            if [[ "$driver" == local && -d "$mountpoint" ]]; then
                size="$(command timeout 8s du -sh -- "$mountpoint" 2>/dev/null)" || size=''
                if [[ -n "$size" ]]; then
                    printf '__IGR__|%s|A|数据量：%s\n' "$target_count" "${size%%$'\t'*}"
                    printf '__IGR__|%s|S|%s\n' "$target_count" "${size%%$'\t'*}"
                    printf '  数据量：%s\n' "${size%%$'\t'*}"
                else
                    printf '__IGR__|%s|A|数据量：UNKNOWN\n' "$target_count"
                    printf '  数据量：UNKNOWN（大小探测失败）\n'
                fi
            else
                printf '__IGR__|%s|A|数据量：UNKNOWN\n' "$target_count"
                printf '  数据量：UNKNOWN（远程驱动或挂载点不可读）\n'
            fi
        done
        (( target_count > 0 )) || printf '__IGR__|1|T|UNKNOWN（未解析到字面 Volume 名）\n'
        ;;
      'systemctl disable '*|'systemctl stop '*|'systemctl mask '*)
        local now=0 unit_count=0
        for token in $words[3,-1]; do
            case "$token" in
              --now) now=1 ;;
              --force|--runtime|--no-warn) ;;
              -*) printf '__IGR__|1|T|UNKNOWN（包含未支持的 systemctl 选项）\n'; return ;;
              *) (( unit_count += 1 )); target="${(Q)token}" ;;
            esac
        done
        if (( unit_count != 1 )); then printf '__IGR__|1|T|UNKNOWN（未能唯一确定 systemd unit）\n'; return; fi
        [[ "$target" == *.service ]] || target+=".service"
        printf '__IGR__|1|T|%s\n' "$target"
        if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
            local active enabled deps
            active="$(command timeout 5s systemctl is-active "$target" 2>/dev/null || true)"
            enabled="$(command timeout 5s systemctl is-enabled "$target" 2>/dev/null || true)"
            deps="$(command timeout 5s systemctl list-dependencies --reverse --plain --no-pager "$target" 2>/dev/null | sed -n '2,5p' | tr '\n' ' ')"
            printf '  当前：%s、%s\n' "${active:-UNKNOWN}" "${enabled:-UNKNOWN}"
            printf '  反向依赖：%s\n' "${deps:-UNKNOWN}"
            if [[ "${words[2]}" == disable ]]; then
                if (( now )); then printf '  影响：取消开机自启并立即停止当前服务。\n'
                else printf '  影响：取消开机自启；不立即停止当前服务。\n'; fi
            elif [[ "${words[2]}" == stop ]]; then printf '  影响：停止当前服务。\n'
            elif (( now )); then printf '  影响：屏蔽服务并立即停止当前服务。\n'
            else printf '  影响：屏蔽服务，阻止手动和自动启动。\n'; fi
        else printf '  当前状态和依赖：UNKNOWN（systemd 不可用）\n'; fi
        ;;
      mkfs*|wipefs*|dd\ *|shred\ *|fdisk\ *|cfdisk\ *|sfdisk\ *|parted\ *|gdisk\ *)
        local device=''
        for token in $words[2,-1]; do
            if [[ "$token" == /dev/* ]]; then device="$token"
            elif [[ "$token" == of=/dev/* ]]; then device="${token#of=}"
            fi
        done
        if [[ -z "$device" ]]; then printf '__IGR__|1|T|UNKNOWN（未能确定块设备参数）\n'; return; fi
        printf '__IGR__|1|T|%s\n' "$device"
        if command -v lsblk >/dev/null 2>&1; then
            output="$(command timeout 5s lsblk -f "$device" 2>/dev/null)" || output=''
            printf '  块设备与文件系统：%s\n' "${output:-UNKNOWN}"
        else printf '  块设备与文件系统：UNKNOWN（lsblk 不可用）\n'; fi
        if command -v findmnt >/dev/null 2>&1; then
            output="$(command timeout 5s findmnt -S "$device" -n -o SOURCE,TARGET,FSTYPE 2>/dev/null)" || output=''
            printf '  挂载状态：%s\n' "${output:-未发现挂载点}"
        else printf '  挂载状态：UNKNOWN（findmnt 不可用）\n'; fi
        ;;
      'git reset '*|'git push '*)
        printf '__IGR__|1|T|%s\n' "$PWD"
        output="$(command timeout 5s git status --short 2>&1)" || output=''
        if [[ -n "$output" ]]; then printf '  工作区状态：%s\n' "${output//$'\n'/; }"
        else printf '  工作区状态：干净或 UNKNOWN（当前目录可能不是 Git 仓库）\n'; fi
        output="$(command timeout 5s git diff --stat 2>/dev/null)" || output=''
        printf '  未暂存差异：%s\n' "${output:-无差异或 UNKNOWN}"
        output="$(command timeout 5s git diff --cached --stat 2>/dev/null)" || output=''
        printf '  已暂存差异：%s\n' "${output:-无差异或 UNKNOWN}"
        printf '  远端和提交影响：UNKNOWN（未访问网络）\n'
        ;;
      'rm '*|'sudo rm '*|'command rm '*)
        local options=1 recursive=0 force=0
        local -a targets
        local target_index=0
        for token in $words[2,-1]; do
            [[ "$token" == *'$'* || "$token" == *'`'* || "$token" == *'*'* || "$token" == *'?'* ||
               "$token" == *'['* || "$token" == *';'* || "$token" == *'|'* || "$token" == *'&'* ||
               "$token" == *'>'* || "$token" == *'<'* ]] && {
                printf '__IGR__|1|T|UNKNOWN（包含未展开表达式）\n影响：文件、挂载关系和数据量 UNKNOWN。\n'; return; }
            token="${(Q)token}"
            if (( options )) && [[ "$token" == -- ]]; then options=0
            elif (( options )) && [[ "$token" == -* ]]; then
                [[ "$token" =~ '^-[rfR]+$' || "$token" == --recursive || "$token" == --force ]] || {
                    printf '__IGR__|1|T|UNKNOWN（包含未支持的 rm 选项）\n'; return; }
                [[ "$token" == *r* || "$token" == *R* || "$token" == --recursive ]] && recursive=1
                [[ "$token" == *f* || "$token" == --force ]] && force=1
            else targets+=( "$token" )
            fi
        done
        if (( ! recursive || ! force || ! ${#targets} )); then
            printf '__IGR__|1|T|UNKNOWN（无法可靠解析删除目标）\n'; return
        fi
        for target in "${targets[@]}"; do
            (( target_index += 1 ))
            printf '__IGR__|%s|T|%s\n' "$target_index" "${target:A}"
            printf '__IGR__|%s|A|数据类型：UNKNOWN\n' "$target_index"
            printf '__IGR__|%s|A|数据量：UNKNOWN\n' "$target_index"
            printf '__IGR__|%s|A|使用者：UNKNOWN\n' "$target_index"
            printf '__IGR__|%s|A|备份状态：UNKNOWN\n' "$target_index"
            if [[ -L "$target" ]]; then
                printf '__IGR__|%s|Y|符号链接\n' "$target_index"
                printf '__IGR__|%s|C|ok|目标状态|符号链接已确认\n' "$target_index"
                printf '__IGR__|%s|E|符号链接存在；所指目录未展开。\n' "$target_index"
                printf '  类型：符号链接；不展开所指目录。\n'
            elif [[ -e "$target" ]]; then
                target_abs="${target:A}"
                if [[ -d "$target" ]]; then state=目录; else state=文件; fi
                printf '__IGR__|%s|Y|%s\n' "$target_index" "$state"
                printf '__IGR__|%s|C|ok|目标状态|已确认\n' "$target_index"
                printf '__IGR__|%s|E|目标存在；类型：%s\n' "$target_index" "$state"
                printf '  类型：%s；存在：已确认\n' "$state"
                if command -v findmnt >/dev/null 2>&1; then
                    output="$(command timeout 5s findmnt -T "$target" -J -o SOURCE,TARGET,FSTYPE 2>/dev/null | jq -r '.filesystems[0] | select(. != null) | "\(.source // "UNKNOWN") → \(.target // "UNKNOWN")（\(.fstype // "UNKNOWN")）"' 2>/dev/null)" || output=''
                    printf '  文件系统挂载：%s\n' "${output:-UNKNOWN}"
                    if [[ -n "$output" ]]; then
                        printf '__IGR__|%s|C|ok|文件系统|%s\n' "$target_index" "$output"
                    else
                        printf '__IGR__|%s|C|unknown|文件系统|UNKNOWN（查询失败）\n' "$target_index"
                    fi
                else
                    printf '  文件系统挂载：UNKNOWN\n'
                    printf '__IGR__|%s|C|unknown|文件系统|UNKNOWN（findmnt 不可用）\n' "$target_index"
                fi
                if [[ -d "$target" ]]; then
                    output="$(command timeout 8s du -sh -- "$target" 2>/dev/null)" || output=''
                    if [[ -n "$output" ]]; then
                        printf '__IGR__|%s|A|数据量：%s\n' "$target_index" "${output%%$'\t'*}"
                        printf '__IGR__|%s|S|%s\n' "$target_index" "${output%%$'\t'*}"
                        printf '  目录大小：%s\n' "${output%%$'\t'*}"
                    else
                        printf '__IGR__|%s|A|数据量：UNKNOWN\n' "$target_index"
                        printf '  目录大小：UNKNOWN（探测失败）\n'
                    fi
                    if [[ -f "$target/manifest.json" || -f "$target/manifest.txt" ]] && [[ -f "$target/SHA256SUMS" ]]; then
                        printf '__IGR__|%s|E|检测到备份清单与 SHA256SUMS（未验证备份可恢复性）\n' "$target_index"
                        printf '__IGR__|%s|A|备份状态：检测到清单文件；可恢复性 UNKNOWN\n' "$target_index"
                        printf '  目录类型：检测到项目备份清单和 SHA256SUMS\n'
                        printf '__IGR__|%s|C|warn|备份清单|发现清单与 SHA256SUMS；可恢复性 UNKNOWN\n' "$target_index"
                    else
                        printf '__IGR__|%s|C|none|备份清单|未发现清单与 SHA256SUMS 组合\n' "$target_index"
                    fi
                    if command -v docker >/dev/null 2>&1; then
                        container_ids="$(command timeout 5s docker ps -aq 2>/dev/null)" || container_ids='!unknown'
                        if [[ "$container_ids" == '!unknown' ]]; then
                            printf '  Docker bind mount：UNKNOWN（容器清单不可读取）\n'
                            printf '__IGR__|%s|C|unknown|Docker 挂载|UNKNOWN（容器清单不可读取）\n' "$target_index"
                        elif [[ -n "$container_ids" ]]; then
                            inspect_output="$(command timeout 8s docker inspect ${(z)container_ids} 2>/dev/null)" || inspect_output='!unknown'
                            if [[ "$inspect_output" == '!unknown' ]]; then mount_data='!unknown'
                            else mount_data="$(jq -r '.[] | .Name as $name | .State.Status as $status | .Mounts[]? | select(.Type == "bind") | [$name,$status,.Source,.Destination] | @tsv' <<< "$inspect_output")" || mount_data='!unknown'; fi
                            if [[ "$mount_data" == '!unknown' ]]; then
                                printf '  Docker bind mount：UNKNOWN（挂载信息不可读取）\n'
                                printf '__IGR__|%s|C|unknown|Docker 挂载|UNKNOWN（挂载信息不可读取）\n' "$target_index"
                            else
                                mount_match=''
                                while IFS=$'\t' read -r name service_state source destination; do
                                    [[ -n "$source" ]] || continue
                                    if [[ "$target_abs" == "$source" || "$target_abs" == "$source"/* || "$source" == "$target_abs"/* ]]; then
                                        mount_match+="${name#/} ($service_state: $source → $destination) "
                                        printf '__IGR__|%s|D|%s\n' "$target_index" "${target_abs} → 容器 ${name#/}：${destination}（bind mount，状态 ${service_state}）"
                                        printf '__IGR__|%s|I|删除该路径会影响上述容器的直接 bind mount。\n' "$target_index"
                                        printf '__IG_FULL_REPORT__\n'
                                        printf '__IGR__|%s|C|warn|Docker 挂载|容器 %s：%s\n' "$target_index" "${name#/}" "$destination"
                                    fi
                                done <<< "$mount_data"
                                if [[ -z "$mount_match" ]]; then
                                    printf '__IGR__|%s|D|未发现相交的 bind mount（已查询全部容器挂载）\n' "$target_index"
                                    printf '__IGR__|%s|C|none|Docker 挂载|未发现相交挂载\n' "$target_index"
                                fi
                                printf '  Docker bind mount：%s\n' "${mount_match:-未发现相交的 bind mount}"
                            fi
                        else
                            printf '__IGR__|%s|D|未发现运行或停止的容器\n' "$target_index"
                            printf '  Docker bind mount：未发现运行或停止的容器\n'
                            printf '__IGR__|%s|C|none|Docker 挂载|未发现容器\n' "$target_index"
                        fi
                    else
                        printf '  Docker bind mount：UNKNOWN（Docker 不可用）\n'
                        printf '__IGR__|%s|C|unknown|Docker 挂载|UNKNOWN（Docker 不可用）\n' "$target_index"
                    fi
                fi
                local db_marker=0
                if [[ -f "$target/PG_VERSION" ]]; then
                    db_marker=1
                    printf '__IGR__|%s|E|PG_VERSION：PostgreSQL 集群标记文件\n' "$target_index"
                fi
                if [[ -f "$target/ibdata1" ]]; then
                    db_marker=1
                    printf '__IGR__|%s|E|ibdata1：MySQL/InnoDB 数据文件标记\n' "$target_index"
                fi
                if [[ -f "$target/aria_log_control" ]]; then
                    db_marker=1
                    printf '__IGR__|%s|E|aria_log_control：MariaDB/Aria 标记文件\n' "$target_index"
                fi
                if (( db_marker )); then
                    printf '__IGR__|%s|A|数据类型：疑似数据库数据（文件标记；实例未确认）\n' "$target_index"
                    printf '__IGR__|%s|A|备份状态：UNKNOWN\n' "$target_index"
                    printf '__IGR__|%s|I|删除目标可能删除疑似数据库文件；运行实例关联 UNKNOWN。\n' "$target_index"
                    printf '  内容提示：疑似数据库数据（文件标记，未确认实例）\n'
                    printf '__IGR__|%s|C|warn|数据库标记|疑似数据库数据（实例未确认）\n' "$target_index"
                    printf '__IG_FULL_REPORT__\n'
                elif [[ -d "$target" ]]; then
                    printf '__IGR__|%s|C|none|数据库标记|未发现已检查的标记文件\n' "$target_index"
                fi
            elif [[ -d "${target:h}" && -x "${target:h}" && -r "${target:h}" ]]; then
                printf '__IGR__|%s|E|目标不存在；父目录可读取\n' "$target_index"
                printf '__IGR__|%s|A|数据量：UNKNOWN（目标不存在）\n' "$target_index"
                printf '  存在：否（可读取父目录，目标不存在）\n'
                printf '__IGR__|%s|C|none|目标状态|未发现（父目录可读取）\n' "$target_index"
            else
                printf '__IGR__|%s|E|目标或父目录不可读取\n' "$target_index"
                printf '__IGR__|%s|A|数据量：UNKNOWN\n' "$target_index"
                printf '  存在：UNKNOWN（目标或父目录不可读取）\n'
                printf '__IGR__|%s|C|unknown|目标状态|UNKNOWN（不可读取）\n' "$target_index"
            fi
        done
        ;;
      *)
        printf '__IGR__|1|T|%s\n' "${(Q)words[2]:-UNKNOWN}"
        printf '更深层影响：UNKNOWN（无专用只读分析器）\n'
        ;;
    esac
}
