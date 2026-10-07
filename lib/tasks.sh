# shellcheck shell=bash
# tasks.sh - bottom panel: recent cluster tasks and cluster log, task
# descriptions (same wording as the web interface) and the task log viewer.

TASK_TAB=tasks            # tasks | log
TASK_CUR=0 TASK_SCROLL=0
declare -ga TASK_LINES=() TASK_UPID=() TASK_NODE=()

# Task type -> description format (%s = object id), as in the web UI.
declare -gA TASK_DESC=(
    [qmstart]="VM %s - Start" [qmstop]="VM %s - Stop" [qmshutdown]="VM %s - Shutdown"
    [qmreboot]="VM %s - Reboot" [qmreset]="VM %s - Reset" [qmsuspend]="VM %s - Hibernate"
    [qmpause]="VM %s - Pause" [qmresume]="VM %s - Resume" [qmcreate]="VM %s - Create"
    [qmdestroy]="VM %s - Destroy" [qmclone]="VM %s - Clone" [qmigrate]="VM %s - Migrate"
    [qmrestore]="VM %s - Restore" [qmsnapshot]="VM %s - Snapshot" [qmrollback]="VM %s - Rollback"
    [qmdelsnapshot]="VM %s - Delete Snapshot" [qmtemplate]="VM %s - Convert to template"
    [qmconfig]="VM %s - Configure" [qmmove]="VM %s - Move disk" [qmresize]="VM %s - Resize disk"
    [qmimport]="VM %s - Import" [qmremote_migrate]="VM %s - Remote Migrate"
    [vzstart]="CT %s - Start" [vzstop]="CT %s - Stop" [vzshutdown]="CT %s - Shutdown"
    [vzreboot]="CT %s - Reboot" [vzsuspend]="CT %s - Suspend" [vzresume]="CT %s - Resume"
    [vzcreate]="CT %s - Create" [vzdestroy]="CT %s - Destroy" [vzclone]="CT %s - Clone"
    [vzmigrate]="CT %s - Migrate" [vzsnapshot]="CT %s - Snapshot" [vzrollback]="CT %s - Rollback"
    [vzdelsnapshot]="CT %s - Delete Snapshot" [vztemplate]="CT %s - Convert to template"
    [vzmount]="CT %s - Mount" [vzumount]="CT %s - Unmount" [vzresize]="CT %s - Resize disk"
    [vncproxy]="VM/CT %s - Console" [spiceproxy]="VM/CT %s - Console (Spice)"
    [termproxy]="VM/CT %s - Console (xterm.js)" [vncshell]="Shell" [spiceshell]="Shell (Spice)"
    [vzdump]="VM/CT %s - Backup" [startall]="Bulk start VMs and Containers"
    [stopall]="Bulk shutdown VMs and Containers" [suspendall]="Suspend all VMs"
    [migrateall]="Bulk migrate VMs and Containers" [aptupdate]="Update package database"
    [imgdel]="Erase data" [imgcopy]="Copy data" [download]="%s - Download"
    [srvstart]="SRV %s - Start" [srvstop]="SRV %s - Stop" [srvrestart]="SRV %s - Restart"
    [srvreload]="SRV %s - Reload" [diskinit]="Disk %s - Initialize GPT" [wipedisk]="Device %s - Wipe Disk"
    [zfscreate]="ZFS Storage %s - Create" [dircreate]="Directory Storage %s - Create"
    [lvmcreate]="LVM Storage %s - Create" [lvmthincreate]="LVM-Thin Storage %s - Create"
    [hamigrate]="HA %s - Migrate" [harelocate]="HA %s - Relocate" [hastart]="HA %s - Start"
    [hastop]="HA %s - Stop" [hashutdown]="HA %s - Shutdown"
    [acmenewcert]="SRV %s - Order Certificate" [acmerenew]="SRV %s - Renew Certificate"
    [acmeregister]="ACME Account %s - Register" [reboot]="Reboot" [shutdown]="Shutdown"
    [pull_file]="%s - Download"
)

# task_desc <type> <id> -> REPLY
task_desc() {
    local t=$1 id=$2
    if [[ -v TASK_DESC[$t] ]]; then
        if [[ $t == vzdump && -z $id ]]; then T "Backup Job"; return; fi
        Tf "${TASK_DESC[$t]}" "$id"
        REPLY=${REPLY% - }
    else
        REPLY="$t${id:+ $id}"
    fi
}

# Narrow terminals hide the "End Time" and "Node" columns.
_task_cols() {
    TASK_NARROW=0
    (( COLS < 110 )) && TASK_NARROW=1
    if (( TASK_NARROW )); then TASK_DW=$(( COLS - 51 )); else TASK_DW=$(( COLS - 82 )); fi
    (( TASK_DW < 10 )) && TASK_DW=10
}

tasks_header() {
    local h=""
    _task_cols
    if [[ $TASK_TAB == tasks ]]; then
        local f
        T "Start Time"; fit "$REPLY" 15; h+="$REPLY  "
        if (( ! TASK_NARROW )); then
            T "End Time"; fit "$REPLY" 15; h+="$REPLY  "
            T "Node"; fit "$REPLY" 10; h+="$REPLY  "
        fi
        T "User name"; fit "$REPLY" 14; h+="$REPLY  "
        T "Status"; fit "$REPLY" 12; f=$REPLY
        T "Description"; fit "$REPLY" "$TASK_DW"; h+="$REPLY  $f"
    else
        T "Time"; fit "$REPLY" 15; h+="$REPLY  "
        T "Node"; fit "$REPLY" 10; h+="$REPLY  "
        T "Service"; fit "$REPLY" 14; h+="$REPLY  "
        T "PID"; fit "$REPLY" 8; h+="$REPLY  "
        T "User name"; fit "$REPLY" 14; h+="$REPLY  "
        T "Severity"; fit "$REPLY" 8; h+="$REPLY  "
        T "Message"; h+=$REPLY
    fi
    REPLY=$h
}

# Guests with a running task (any origin): PENDING[qemu/100]="task description".
# Shown as an animated marker in the tree, the grids and the title.
declare -gA PENDING=()
pending_load() {
    local row id
    local -a f
    PENDING=()
    api_get rows /cluster/tasks "" "type,id,endtime" || return 0
    for row in "${API_ROWS[@]}"; do
        tsv_split f "$row"
        [[ -z ${f[2]-} && ${f[1]-} =~ ^[0-9]+$ ]] || continue
        # Console sessions are long lived tasks that do not lock the guest.
        [[ ${f[0]} == @(vncproxy|spiceproxy|termproxy|vncshell|spiceshell) ]] && continue
        for id in "qemu/${f[1]}" "lxc/${f[1]}"; do
            [[ -n ${R_TYPE[$id]-} ]] || continue
            task_desc "${f[0]}" "${f[1]}"; PENDING[$id]=$REPLY
        done
    done
    # Actions started or waiting in the proxhawk-tui queue.
    if declare -p GQUEUE >/dev/null 2>&1; then
        for id in "${!GBUSY[@]}"; do [[ -z ${PENDING[$id]-} && ! -s ${GBUSY[$id]}.rc ]] && PENDING[$id]="${BG_CMDS[${GBUSY[$id]}]:-running}"; done
        for id in "${!GQUEUE[@]}"; do [[ -n ${GQUEUE[$id]} && -z ${PENDING[$id]-} ]] && PENDING[$id]="queued"; done
    fi
}

tasks_load() {
    local row line
    local -a f
    TASK_LINES=() TASK_UPID=() TASK_NODE=()
    pending_load
    (( TASK_H > 0 )) || return 0
    _task_cols
    if [[ $TASK_TAB == tasks ]]; then
        api_get rows /cluster/tasks "" "upid,starttime,endtime,node,user,type,id,status" || return 1
        # Running tasks first, then most recent first (as in the web UI).
        local -a running=() done_=()
        for row in "${API_ROWS[@]}"; do
            tsv_split f "$row"
            if [[ -z ${f[2]} ]]; then running+=("$row"); else done_+=("$row"); fi
        done
        # Actions queued by proxhawk-tui first (cancel with x).
        if declare -F queue_lines >/dev/null; then
            queue_lines
            local qi
            for qi in "${!QUEUE_LINES[@]}"; do
                line=""; fit "" 15; line+="$REPLY  "
                if (( ! TASK_NARROW )); then fit "" 15; line+="$REPLY  "; fit "" 10; line+="$REPLY  "; fi
                fit "${PVE_USER:-root@pam}" 14; line+="$REPLY  "
                fit "${QUEUE_LINES[qi]#*$'\t'}" 12; local qst=$REPLY
                fit "${QUEUE_LINES[qi]%%$'\t'*}" "$TASK_DW"; line+="$REPLY  $qst"
                TASK_LINES+=("$line"); TASK_UPID+=("${QUEUE_KEYS[qi]}"); TASK_NODE+=("")
            done
        fi
        for row in "${running[@]}" "${done_[@]}"; do
            tsv_split f "$row"
            line=""
            fmt_time "${f[1]}" "$DATE_SHORT"; fit "$REPLY" 15; line+="$REPLY  "
            if (( ! TASK_NARROW )); then
                fmt_time "${f[2]}" "$DATE_SHORT"; fit "$REPLY" 15; line+="$REPLY  "
                fit "${f[3]}" 10; line+="$REPLY  "
            fi
            fit "${f[4]}" 14; line+="$REPLY  "
            fmtv task "${f[7]}"; fit "$REPLY" 12; local st=$REPLY
            task_desc "${f[5]}" "${f[6]}"; fit "$REPLY" "$TASK_DW"; line+="$REPLY  $st"
            TASK_LINES+=("$line"); TASK_UPID+=("${f[0]}"); TASK_NODE+=("${f[3]}")
        done
    else
        api_get rows /cluster/log "max=100" "time,node,tag,pid,user,pri,msg" || return 1
        local -a sev=(emerg alert crit err warning notice info debug)
        for row in "${API_ROWS[@]}"; do
            tsv_split f "$row"
            line=""
            fmt_time "${f[0]}" "$DATE_SHORT"; fit "$REPLY" 15; line+="$REPLY  "
            fit "${f[1]}" 10; line+="$REPLY  "
            fit "${f[2]}" 14; line+="$REPLY  "
            fit "${f[3]}" 8; line+="$REPLY  "
            fit "${f[4]}" 14; line+="$REPLY  "
            local s=${sev[${f[5]:-6}]:-info} c=${C[norm]}
            (( ${f[5]:-6} <= 3 )) && c=${C[err]}
            (( ${f[5]:-6} == 4 )) && c=${C[warn]}
            fit "$s" 8; line+="${c}${REPLY}${C[norm]}  ${f[6]}"
            TASK_LINES+=("$line"); TASK_UPID+=(""); TASK_NODE+=("${f[1]}")
        done
    fi
    (( TASK_CUR >= ${#TASK_LINES[@]} )) && TASK_CUR=$(( ${#TASK_LINES[@]} ? ${#TASK_LINES[@]} - 1 : 0 ))
    return 0
}

# Open a task in the task viewer (Enter on a task of the task lists).
show_task_log() {
    [[ -n ${1-} && ${1-} != queue\|* ]] || return 0
    task_viewer "$1"
}

# x on a task of the Tasks panel: cancel a queued action or stop a running task.
task_stop_or_cancel() {
    local key=$1 rest
    [[ -n $key ]] || return 0
    if [[ $key == queue\|* ]]; then
        rest=${key#queue|}
        queue_cancel "${rest%|*}" "${rest##*|}"
        tasks_load
        return 0
    fi
    _task_status "$key" || return 0
    [[ $TASK_ST == running ]] || { T "This task is not running"; status_msg warn "$REPLY"; return 0; }
    T "Stop this task?"; confirm "$REPLY" || return 0
    local node=${key#UPID:}; node=${node%%:*}
    api_exec_sync "Stop task" delete "/nodes/$node/tasks/$key"
    tasks_load
}

# Display a text file in a pager (less, $PAGER, or a dialog text box).
pager_show() {
    local file=$1 title=${2:-proxhawk-tui} p=${CFG[pager]:-${PAGER:-}}
    if [[ -z $p ]] && command -v less >/dev/null; then p="less -R"; fi
    if [[ -n $p ]]; then
        # shellcheck disable=SC2086
        term_run $p "$file"
    else
        dlg_textbox "$title" "$file"
    fi
}
