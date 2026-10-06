# shellcheck shell=bash
# api.sh - access to the Proxmox VE API.
#
# Reads go through the persistent broker (lib/broker.pl) when possible and
# fall back to `pvesh` otherwise. Writes always use `pvesh` in the background
# so that the interface never blocks; they are tracked as "jobs".
#
#   api_get MODE PATH [QUERY] [FIELDS]   -> API_ROWS[] / API_ERR, rc 0|1
#   api_exec DESC METHOD PATH [--opt val ...]   (asynchronous write)
#   api_jobs_poll                        (called by the main loop)

API_BACKEND=""
API_ERR=""
API_TTL=0               # cache lifetime (seconds) for the next api_get calls
declare -ga API_ROWS=()
declare -gA _API_CACHE=() _API_CACHE_T=()
declare -gA JOBS=()     # pid -> description
declare -gA JOBS_OUT=() # pid -> output file
declare -gA TASK_WATCH=()   # UPID -> description (tasks started by pvetty)
API_WAIT_TASKS=0            # 1 = api_exec_sync waits for the worker task to finish

api_start() {
    local line=""
    # Replay of recorded API answers (tests without a Proxmox VE node).
    if [[ ${CFG[backend]} == replay ]]; then
        [[ -d ${PVETTY_REPLAY-} ]] || die "backend replay: set PVETTY_REPLAY to a recorded directory"
        API_BACKEND=replay
        LOCAL_NODE=$(< "$PVETTY_REPLAY/node")
        CLEANUP_HOOKS+=(api_stop)
        return 0
    fi
    if [[ ${CFG[backend]} != pvesh ]]; then
        coproc BROKER { exec perl "$PVETTY_HOME/lib/broker.pl" 2>>"$RUN_DIR/broker.err"; }
        if IFS= read -r -t 60 line <&"${BROKER[0]}" && [[ $line == $'\x04READY\t'* ]]; then
            API_BACKEND=broker
            LOCAL_NODE=${line#*$'\t'}
            log "broker ready on $LOCAL_NODE"
        else
            log "broker failed to start: $line"
            api_stop
        fi
    fi
    if [[ -z $API_BACKEND ]]; then
        command -v pvesh >/dev/null || die "pvesh not found - is this a Proxmox VE node?"
        API_BACKEND=pvesh
    fi
    CLEANUP_HOOKS+=(api_stop)
}

api_stop() {
    if [[ -n ${BROKER_PID:-} ]]; then
        kill "$BROKER_PID" 2>/dev/null
        wait "$BROKER_PID" 2>/dev/null
    fi
    unset BROKER_PID
}

# Percent-encode a string (for query values).
urlenc() {
    local s=$1 out="" c i
    for (( i = 0; i < ${#s}; i++ )); do
        c=${s:i:1}
        case $c in
            [a-zA-Z0-9.~_-]) out+=$c ;;
            *) printf -v c '%%%02X' "'$c"; out+=$c ;;
        esac
    done
    REPLY=$out
}

api_cache_clear() { _API_CACHE=(); _API_CACHE_T=(); }

api_get() {
    local mode=$1 path=$2 query=${3:-} fields=${4:-}
    local key="$mode|$path|$query|$fields" line
    API_ROWS=() API_ERR=""
    now
    if (( API_TTL > 0 )) && [[ -v _API_CACHE[$key] ]] && (( NOW - _API_CACHE_T[$key] < API_TTL )); then
        [[ -n ${_API_CACHE[$key]} ]] && mapfile -t API_ROWS <<< "${_API_CACHE[$key]}"
        return 0
    fi

    if [[ $API_BACKEND == replay ]]; then
        _api_replay_get "$key"
        return
    fi
    if [[ $API_BACKEND == broker ]]; then
        if ! _api_broker_get "$mode" "$path" "$query" "$fields"; then
            [[ -n $API_ERR ]] && { [[ -n ${PVETTY_RECORD-} ]] && _api_record "$key" 1; return 1; }
            # The broker died: fall back to pvesh for the rest of the session.
            log "broker lost, switching to pvesh"
            api_stop
            API_BACKEND=pvesh
            _api_pvesh_get "$mode" "$path" "$query" "$fields" || return 1
        fi
    else
        _api_pvesh_get "$mode" "$path" "$query" "$fields" || return 1
    fi
    if (( API_TTL > 0 )); then
        local IFS=$'\n'
        _API_CACHE[$key]="${API_ROWS[*]}"
        _API_CACHE_T[$key]=$NOW
    fi
    [[ -n ${PVETTY_RECORD-} ]] && _api_record "$key" 0
    return 0
}

# ---------------------------------------------------------------------------
# Record / replay. PVETTY_RECORD=<dir> saves every answer (and errors);
# backend=replay with PVETTY_REPLAY=<dir> serves them back. Writes are not
# executed in replay mode (they succeed without effect). Used by
# tools/screen-test.sh; also handy to reproduce a display problem elsewhere.
# ---------------------------------------------------------------------------
_api_key_file() {
    local h
    h=$(printf '%s' "$1" | md5sum); REPLY=${h%% *}
}
_api_record() {
    local key=$1 failed=$2 dir=$PVETTY_RECORD
    mkdir -p "$dir"
    [[ -s $dir/node ]] || printf '%s' "$LOCAL_NODE" > "$dir/node"
    _api_key_file "$key"
    if (( failed )); then printf '\x04ERR\t%s\n' "$API_ERR" > "$dir/$REPLY"
    else printf '%s\n' "${API_ROWS[@]}" > "$dir/$REPLY"
    fi
    printf '%s\t%s\n' "$REPLY" "$key" >> "$dir/index"
}
_api_replay_get() {
    local f
    _api_key_file "$1"; f="$PVETTY_REPLAY/$REPLY"
    if [[ ! -e $f ]]; then API_ERR="not recorded: $1"; return 1; fi
    mapfile -t API_ROWS < "$f"
    if [[ ${API_ROWS[0]-} == $'\x04ERR\t'* ]]; then API_ERR=${API_ROWS[0]#*$'\t'}; API_ROWS=(); return 1; fi
    [[ ${#API_ROWS[@]} == 1 && -z ${API_ROWS[0]} ]] && API_ROWS=()
    return 0
}

_api_broker_get() {
    local line
    [[ -n ${BROKER_PID:-} ]] && kill -0 "$BROKER_PID" 2>/dev/null || return 1
    printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >&"${BROKER[1]}" || return 1
    while IFS= read -r -t 120 line <&"${BROKER[0]}"; do
        if [[ $line == $'\x04'* ]]; then
            [[ $line == $'\x04OK' ]] && return 0
            API_ERR=${line#*$'\t'}
            return 1
        fi
        API_ROWS+=("$line")
    done
    return 1
}

_api_pvesh_get() {
    local mode=$1 path=$2 query=$3 fields=$4 pair k v
    case $mode in
        schema|propparse|propprint|pluginopts|perm)
            # Schema requests need the API stack: one-shot broker call.
            mapfile -t API_ROWS < <(perl "$PVETTY_HOME/lib/broker.pl" --once "$mode" "$path" "$query" "$fields" 2>"$RUN_DIR/pvesh.err")
            if [[ -s $RUN_DIR/pvesh.err ]]; then API_ERR=$(tail -n 1 "$RUN_DIR/pvesh.err"); return 1; fi
            return 0 ;;
    esac
    local -a args=()
    local -a pairs=()
    [[ -n $query ]] && IFS="&" read -r -a pairs <<< "$query"
    for pair in "${pairs[@]}"; do
        k=${pair%%=*} v=${pair#*=}
        printf -v v "%b" "${v//%/\\x}"
        args+=("--$k" "$v")
    done
    mapfile -t API_ROWS < <(pvesh get "$path" "${args[@]}" --output-format json 2>"$RUN_DIR/pvesh.err" \
        | perl "$PVETTY_HOME/lib/broker.pl" --filter "$mode" "$fields")
    if [[ -s $RUN_DIR/pvesh.err ]] && (( ${#API_ROWS[@]} == 0 )); then
        API_ERR=$(tail -n 1 "$RUN_DIR/pvesh.err")
        return 1
    fi
    return 0
}

# Convenience: first row of a "rows" request split into fields -> API_F[]
api_row() {
    api_get rows "$1" "${2:-}" "${3:-}" || return 1
    tsv_split API_F "${API_ROWS[0]-}"
    return 0
}

# Convenience: "kv" request into associative array API_KV.
# Array values are joined with "," in API_KV, with "\x1e" in API_KV_RAW.
declare -gA API_KV=() API_KV_RAW=()
api_kv() {
    local r v
    API_KV=() API_KV_RAW=()
    api_get kv "$1" "${2:-}" || return 1
    for r in "${API_ROWS[@]}"; do
        v=${r#*$'\t'}
        API_KV_RAW[${r%%$'\t'*}]=$v
        API_KV[${r%%$'\t'*}]=${v//$'\x1e'/,}
    done
    return 0
}

# ---------------------------------------------------------------------------
# Writes. api_exec DESCRIPTION METHOD PATH [args...]
# METHOD: create (POST) | set (PUT) | delete (DELETE)
# ---------------------------------------------------------------------------
JOB_SEQ=0
# Like the web UI, starting a task opens the task viewer, which follows it
# live. pvesh runs worker tasks synchronously (it returns when the task is
# finished), so it is started in the background and the new task is detected
# in the list of active tasks of the node as soon as it is registered.
# Calls without a task report their result in the footer.
api_exec() {
    local desc=$1; shift
    if [[ $API_BACKEND == replay ]]; then Tf "%s: done (replay, not executed)" "$desc"; status_msg ok "$REPLY"; return 0; fi
    local out="$RUN_DIR/job.$(( ++JOB_SEQ )).log"
    local node=$LOCAL_NODE path=${2-} t0 upid="" i row
    [[ $path =~ ^/nodes/([^/]+) ]] && node=${BASH_REMATCH[1]}
    log "exec: pvesh $*"
    # The guest already runs a task (Proxmox would refuse: config locked):
    # offer to queue the action (lib/queue.sh).
    if declare -F queue_add >/dev/null && queue_guest_of_path "$path"; then
        local gid=$REPLY
        if [[ -n ${GBUSY[$gid]-} || ( -n ${PENDING[$gid]-} ) ]]; then
            Tf "%s is busy (%s). Queue this action to run when it is finished?" "$gid" "${PENDING[$gid]:-running}"
            if dlg_yesno "Queue" "$REPLY"; then queue_add "$gid" "$desc" "$@"; queue_run; return 0; fi
        fi
    fi
    # Repaint first (dialogs may have cleared the screen).
    draw
    # Tasks already running on the node.
    local -A before=()
    if api_get rows "/nodes/$node/tasks" "source=active" "upid"; then
        for row in "${API_ROWS[@]}"; do before[$row]=1; done
    fi
    printf -v t0 '%(%s)T' -1
    # Detached: the shell does not wait for it (no zombie), the exit code is
    # written to a file.
    ( setsid bash -c 'pvesh "$@" > "$0" 2>&1 < /dev/null; echo $? > "$0.rc"' "$out" "$@" & )
    T "Starting"; spinner_start "$REPLY: $desc"
    for (( i = 0; i < 240; i++ )); do
        if api_get rows "/nodes/$node/tasks" "source=active" "upid,starttime"; then
            for row in "${API_ROWS[@]}"; do
                [[ -n ${before[${row%%$'\t'*}]-} ]] && continue
                (( ${row#*$'\t'} >= t0 - 2 )) || continue
                upid=${row%%$'\t'*}; break
            done
        fi
        [[ -n $upid ]] && break
        [[ -s $out.rc ]] && break                 # finished (no task, or a very short one)
        sleep 0.5
    done
    spinner_stop
    if [[ -z $upid && -s $out.rc ]]; then
        # Very short task: find it among the last tasks of the node.
        upid=$(grep -m1 -o 'UPID:[^ ]*' "$out")
        if [[ -z $upid ]] && api_get rows "/nodes/$node/tasks" "limit=10" "upid,starttime"; then
            for row in "${API_ROWS[@]}"; do
                [[ -n ${before[${row%%$'\t'*}]-} ]] && continue
                (( ${row#*$'\t'} >= t0 - 2 )) && { upid=${row%%$'\t'*}; break; }
            done
        fi
    fi
    if [[ -n $upid ]]; then
        task_viewer "$upid" "$desc"
        return 0
    fi
    if [[ ! -s $out.rc ]]; then
        # Still running without a visible task: follow it in the footer.
        Tf "%s: started" "$desc"; status_msg info "$REPLY"
        BG_CMDS[$out]=$desc
        return 0
    fi
    _api_exec_report "$desc" "$out"
}

# Result of a finished background command (no task).
_api_exec_report() {
    local desc=$1 out=$2 rc
    rc=$(< "$out.rc")
    if [[ $rc == 0 ]]; then
        Tf "%s: done" "$desc"; status_msg ok "$REPLY"
    else
        Tf "%s: failed - %s" "$desc" "$(api_error_line "$out")"; status_msg err "$REPLY"
    fi
    api_cache_clear; NEED_REFRESH=1
    rm -f "$out" "$out.rc"
    [[ $rc == 0 ]]
}
declare -gA BG_CMDS=()   # output file -> description (commands without task)

# Synchronous write with a spinner (for quick configuration changes).
api_exec_sync() {
    local desc=$1; shift
    if [[ $API_BACKEND == replay ]]; then
        : > "$RUN_DIR/job.sync.log"
        Tf "%s: done (replay, not executed)" "$desc"; status_msg ok "$REPLY"; return 0
    fi
    local out="$RUN_DIR/job.sync.log" rc
    spinner_start "$desc"
    pvesh "$@" > "$out" 2>&1 < /dev/null
    rc=$?
    # pvesh passes numbers as strings, which some Rust backed endpoints (SDN
    # prefix lists, route maps...) refuse: retry through the broker.
    if (( rc != 0 )) && grep -q 'invalid type: string' "$out" && [[ $API_BACKEND == broker ]]; then
        _api_broker_write "$@" > "$out" 2>&1 && rc=0
    fi
    spinner_stop
    if (( rc == 0 )); then
        local upid
        upid=$(grep -m1 -o 'UPID:[^ ]*' "$out")
        if [[ -n $upid ]]; then
            if (( API_WAIT_TASKS )); then
                task_wait "$upid" "$desc"; rc=$?
            else
                task_viewer "$upid" "$desc"
            fi
        else
            Tf "%s: done" "$desc"; status_msg ok "$REPLY"
        fi
    else
        Tf "%s: failed - %s" "$desc" "$(api_error_line "$out")"; status_msg err "$REPLY"
    fi
    api_cache_clear
    return $rc
}

# Most useful error line of a pvesh output (skips usage lines and UPIDs).
api_error_line() {
    local l
    l=$(grep -v -e '^[[:space:]]*$' -e '^UPID:' -e '^pvesh ' -e '^400 Parameter verification failed' -e '^Usage' "$1" 2>/dev/null | tail -n 1)
    [[ -z $l ]] && l=$(grep -v '^[[:space:]]*$' "$1" 2>/dev/null | tail -n 1)
    printf '%s' "$l"
}

# _api_broker_write <create|set|delete> <path> [--key value ...]
_api_broker_write() {
    local cmd=$1 path=$2 q m
    shift 2
    case $cmd in create) m=POST ;; set) m=PUT ;; delete) m=DELETE ;; *) return 1 ;; esac
    q="method=$m"
    while (( $# >= 2 )); do
        urlenc "$2"; q+="&${1#--}=$REPLY"
        shift 2
    done
    api_get write "$path" "$q" "" || { echo "$API_ERR"; return 1; }
    printf '%s\n' "${API_ROWS[@]}"
}

# Called periodically: reports finished background jobs.
api_jobs_poll() {
    local pid rc last
    for pid in "${!JOBS[@]}"; do
        kill -0 "$pid" 2>/dev/null && continue
        wait "$pid" 2>/dev/null; rc=$?
        last=$(api_error_line "${JOBS_OUT[$pid]}")
        local upid
        upid=$(grep -m1 -o 'UPID:[^ ]*' "${JOBS_OUT[$pid]}" 2>/dev/null)
        if (( rc == 0 )) && [[ -n $upid ]]; then
            # The worker task keeps running: follow it until it stops.
            TASK_WATCH[$upid]=${JOBS[$pid]}
        elif (( rc == 0 )); then
            Tf "%s: finished" "${JOBS[$pid]}"; status_msg ok "$REPLY"
        else
            Tf "%s: failed - %s" "${JOBS[$pid]}" "$last"; status_msg err "$REPLY"
        fi
        rm -f "${JOBS_OUT[$pid]}"
        unset "JOBS[$pid]" "JOBS_OUT[$pid]"
        api_cache_clear
        NEED_REFRESH=1
    done
    local u
    declare -F queue_run >/dev/null && queue_run
    for u in "${!BG_CMDS[@]}"; do
        [[ -s $u.rc ]] || continue
        _api_exec_report "${BG_CMDS[$u]}" "$u"
        unset "BG_CMDS[$u]"
    done
    for u in "${!TASK_WATCH[@]}"; do
        _task_status "$u" || continue
        [[ $TASK_ST == stopped ]] || continue
        _task_report "$u" "${TASK_WATCH[$u]}"
        unset "TASK_WATCH[$u]"
        NEED_REFRESH=1
    done
}

# Status of a task: TASK_ST (running|stopped), TASK_EXIT (OK or error).
_task_status() {
    local node=${1#UPID:}; node=${node%%:*}
    TASK_ST="" TASK_EXIT=""
    api_get rows "/nodes/$node/tasks/$1/status" "" "status,exitstatus" || return 1
    TASK_ST=${API_ROWS[0]%%$'\t'*} TASK_EXIT=${API_ROWS[0]#*$'\t'}
}
_task_report() {
    if [[ $TASK_EXIT == OK || $TASK_EXIT == WARNINGS* ]]; then
        Tf "%s: finished (%s)" "$2" "$TASK_EXIT"; status_msg ok "$REPLY"; return 0
    fi
    Tf "%s: failed - %s" "$2" "$TASK_EXIT"; status_msg err "$REPLY"; return 1
}

# Wait for a worker task (used by synchronous calls): task_wait <upid> <desc> [timeout]
task_wait() {
    local i t=${3:-3600}
    for (( i = 0; i < t; i++ )); do
        _task_status "$1" && [[ $TASK_ST == stopped ]] && { _task_report "$1" "$2"; return; }
        sleep 1
    done
    Tf "%s: still running" "$2"; status_msg warn "$REPLY"
    return 1
}

# tsv_split <array name> <row>: split a TAB separated row, keeping empty
# fields (a plain IFS=$'\t' read would merge consecutive tabs).
tsv_split() {
    local -n _tsv=$1
    IFS=$'\x1e' read -r -a _tsv <<< "${2//$'\t'/$'\x1e'}"
}
