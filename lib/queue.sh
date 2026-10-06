# shellcheck shell=bash
# queue.sh - per-guest action queue and batch actions.
#
# A guest runs one action at a time (Proxmox locks the guest config): an
# action on a guest that already has a running task is queued and started
# when the guest is free. Batch actions (several marked guests) use the same
# queue, with at most CFG[queue_parallel] actions running at once.
#
#   queue_add <guest id> <description> <pvesh args...>
#   queue_run                        start what can be started (main loop)
#   queue_cancel <guest id> <index>  remove a queued action

declare -gA GQUEUE=()     # guest id -> queued actions, one per line: desc \x1f arg \x1f arg...
declare -gA GBUSY=()      # guest id -> output file of the action started by the queue
declare -gA SELECTED=()   # guests marked with Space in the search grids

queue_add() {
    local id=$1 desc=$2 item; shift 2
    printf -v item '%s\x1f' "$desc" "$@"
    GQUEUE[$id]+="${item%$'\x1f'}"$'\n'
    PENDING[$id]=${PENDING[$id]:-queued}
    Tf "%s: queued" "$desc"; status_msg info "$REPLY"
    NEED_REDRAW=1
}

queue_count() {
    local id n=0 line
    for id in "${!GQUEUE[@]}"; do
        while IFS= read -r line; do [[ -n $line ]] && (( n++ )); done <<< "${GQUEUE[$id]}"
    done
    REPLY=$n
}

# Start queued actions of free guests (no running task, nothing started by
# the queue still running), within the parallel limit.
queue_run() {
    local id out running=0 max=${CFG[queue_parallel]:-2} first rest
    local -a parts
    for id in "${!GBUSY[@]}"; do
        out=${GBUSY[$id]}
        if [[ -s $out.rc ]]; then
            unset "GBUSY[$id]"          # reported by api_jobs_poll (BG_CMDS)
            # Free now (the next pending_load sees any other task of the guest):
            # its next queued action can start without waiting for a refresh.
            [[ ${PENDING[$id]-} == queued ]] || unset "PENDING[$id]"
        else
            (( running++ ))
        fi
    done
    for id in "${!GQUEUE[@]}"; do
        [[ -n ${GQUEUE[$id]} ]] || { unset "GQUEUE[$id]"; continue; }
        (( running < max )) || break
        [[ -n ${GBUSY[$id]-} ]] && continue
        # A task of this guest started elsewhere (GUI, another action) is running.
        [[ -n ${PENDING[$id]-} && ${PENDING[$id]} != queued ]] && continue
        first=${GQUEUE[$id]%%$'\n'*}
        rest=${GQUEUE[$id]#*$'\n'}
        GQUEUE[$id]=$rest
        [[ -n $rest ]] || unset "GQUEUE[$id]"
        IFS=$'\x1f' read -r -a parts <<< "$first"
        out="$RUN_DIR/job.$(( ++JOB_SEQ )).log"
        ( setsid bash -c 'pvesh "$@" > "$0" 2>&1 < /dev/null; echo $? > "$0.rc"' "$out" "${parts[@]:1}" & )
        GBUSY[$id]=$out
        BG_CMDS[$out]=${parts[0]}
        PENDING[$id]=${parts[0]}
        (( running++ ))
        Tf "%s: started" "${parts[0]}"; status_msg info "$REPLY"
        NEED_REFRESH=1
    done
}

queue_cancel() {
    local id=$1 idx=$2 line i=0 kept=""
    while IFS= read -r line; do
        [[ -n $line ]] || continue
        (( i++ != idx )) && kept+="$line"$'\n'
    done <<< "${GQUEUE[$id]-}"
    if [[ -n $kept ]]; then GQUEUE[$id]=$kept; else unset "GQUEUE[$id]"; fi
    T "Queued action cancelled"; status_msg info "$REPLY"
    NEED_REFRESH=1
}

# Lines of the Tasks panel for the queued actions: QUEUE_LINES / QUEUE_KEYS.
queue_lines() {
    local id line i desc st
    QUEUE_LINES=() QUEUE_KEYS=()
    T "queued"; st="${C[warn]}${REPLY}${C[norm]}"
    for id in "${!GQUEUE[@]}"; do
        i=0
        while IFS= read -r line; do
            [[ -n $line ]] || continue
            desc=${line%%$'\x1f'*}
            QUEUE_LINES+=("$desc"$'\t'"$st")
            QUEUE_KEYS+=("queue|$id|$i")
            (( i++ ))
        done <<< "${GQUEUE[$id]}"
    done
}

# Guest targeted by an API path (/nodes/N/qemu/ID/...) -> REPLY "qemu/ID".
queue_guest_of_path() {
    REPLY=""
    [[ $1 =~ ^/nodes/[^/]+/(qemu|lxc)/([0-9]+)(/|$) ]] && REPLY="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    [[ -n $REPLY ]]
}

# ---------------------------------------------------------------------------
# Batch actions on the marked guests (or the guest of the selected row).
# ---------------------------------------------------------------------------
batch_toggle() {
    local id=$1
    [[ $id == qemu/* || $id == lxc/* ]] || return 1
    if [[ -n ${SELECTED[$id]-} ]]; then unset "SELECTED[$id]"; else SELECTED[$id]=1; fi
    return 0
}

batch_menu() {
    local -a ids=("${!SELECTED[@]}") items=()
    (( ${#ids[@]} )) || { [[ -n ${1-} && ( $1 == qemu/* || $1 == lxc/* ) ]] && ids=("$1"); }
    (( ${#ids[@]} )) || { T "Mark guests with Space first"; status_msg warn "$REPLY"; return; }
    T "Start"; items+=(start "$REPLY")
    T "Shutdown"; items+=(shutdown "$REPLY")
    T "Stop"; items+=(stop "$REPLY")
    T "Reboot"; items+=(reboot "$REPLY")
    T "Suspend"; items+=(suspend "$REPLY")
    T "Resume"; items+=(resume "$REPLY")
    T "Backup now"; items+=(backup "$REPLY")
    T "Clear selection"; items+=(clear "$REPLY")
    Tf "Batch actions (%d selected)" "${#ids[@]}"
    dlg_menu "$REPLY" "$(printf '%s ' "${ids[@]}")" "${items[@]}" || return
    local act=$REPLY id node vmid type label store=""
    [[ $act == clear ]] && { SELECTED=(); content_load 1; return; }
    if [[ $act == backup ]]; then
        local sid; local -a st=()
        for sid in "${RES_IDS[@]}"; do
            [[ ${R_TYPE[$sid]} == storage && ,${R_CONTENT[$sid]}, == *,backup,* && ${R_STATUS[$sid]} == available ]] || continue
            [[ " ${st[*]} " == *" ${R_STORAGE[$sid]} "* ]] || st+=("${R_STORAGE[$sid]}" "${R_PLUGIN[$sid]}")
        done
        (( ${#st[@]} )) || { dlg_msg "Backup" "No storage with 'backup' content."; return; }
        dlg_menu "Backup now" "Storage:" "${st[@]}" || return
        store=$REPLY
    fi
    Tf "%s: %d guest(s)?" "$act" "${#ids[@]}"; confirm "$REPLY" || return
    for id in "${ids[@]}"; do
        type=${id%%/*} vmid=${id#*/} node=${R_NODE[$id]-}
        [[ -n $node ]] || continue
        if [[ $type == qemu ]]; then Tf "VM %s" "$vmid"; else Tf "CT %s" "$vmid"; fi
        label=$REPLY
        case $act in
            backup) queue_add "$id" "$label - Backup" create "/nodes/$node/vzdump" --vmid "$vmid" --storage "$store" --mode snapshot --compress zstd ;;
            *) queue_add "$id" "$label - ${act^}" create "/nodes/$node/$type/$vmid/status/$act" ;;
        esac
    done
    SELECTED=()
    queue_run
    content_load 1
}
