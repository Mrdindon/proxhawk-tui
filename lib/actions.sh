# shellcheck shell=bash
# actions.sh - toolbar buttons and the actions behind them (power actions,
# console/shell, clone, migrate, remove, bulk actions, create wizards...).
# Every write goes through api_exec / api_exec_sync (pvesh).

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
_guest_path() { REPLY="/nodes/$CTX_NODE/$CTX_TYPE/$CTX_VMID"; }

# confirm <text>: honour the "confirm" setting.
confirm() {
    [[ ${CFG[confirm]} == 1 ]] || return 0
    dlg_yesno "Confirm" "$1"
}

_guest_label() {
    if [[ $CTX_TYPE == qemu ]]; then Tf "VM %s" "$CTX_VMID"; else Tf "CT %s" "$CTX_VMID"; fi
    [[ -n $CTX_NAME ]] && REPLY+=" ($CTX_NAME)"
}

# Node IP (for SSH to other cluster nodes).
node_ip() {
    local row
    REPLY=""
    api_get rows /cluster/status "" "type,name,ip" || return 1
    for row in "${API_ROWS[@]}"; do
        [[ $row == node$'\t'"$1"$'\t'* ]] && { REPLY=${row##*$'\t'}; return 0; }
    done
    return 1
}

# Run a command on a node: locally, or through SSH for remote nodes.
node_cmd() {
    local node=$1; shift
    if [[ $node == "$LOCAL_NODE" ]]; then
        term_run "$@"
    else
        node_ip "$node" || { status_msg err "Cannot resolve node $node"; return 1; }
        term_run ssh -t -o BatchMode=yes "root@$REPLY" "$@"
    fi
}

# ---------------------------------------------------------------------------
# Guest power actions (qemu and lxc)
# ---------------------------------------------------------------------------
_guest_status() {
    _guest_path
    api_exec "$2" create "$REPLY/status/$1" "${@:3}"
}

act_start() { _guest_label; Tf "%s - Start" "$REPLY"; _guest_status start "$REPLY"; }
act_shutdown() {
    _guest_label; local l=$REPLY
    Tf "Do you really want to shutdown %s?" "$l"; confirm "$REPLY" || return
    Tf "%s - Shutdown" "$l"; _guest_status shutdown "$REPLY"
}
act_stop() {
    _guest_label; local l=$REPLY
    Tf "Do you really want to stop %s? (hard stop, data may be lost)" "$l"; confirm "$REPLY" || return
    Tf "%s - Stop" "$l"; _guest_status stop "$REPLY"
}
act_reboot() {
    _guest_label; local l=$REPLY
    Tf "Do you really want to reboot %s?" "$l"; confirm "$REPLY" || return
    Tf "%s - Reboot" "$l"; _guest_status reboot "$REPLY"
}
act_reset() {
    _guest_label; local l=$REPLY
    Tf "Do you really want to reset %s?" "$l"; confirm "$REPLY" || return
    Tf "%s - Reset" "$l"; _guest_status reset "$REPLY"
}
act_pause() {
    _guest_label; local l=$REPLY st=${R_STATUS[$CTX_ID]-}
    # The cluster resources only say "running": ask QEMU for the real state.
    if [[ $CTX_TYPE == qemu ]] && api_row "/nodes/$CTX_NODE/qemu/$CTX_VMID/status/current" "" "qmpstatus"; then
        st=${API_F[0]:-$st}
    fi
    if [[ $st == paused || $st == suspended ]]; then
        Tf "%s - Resume" "$l"; _guest_status resume "$REPLY"
    else
        Tf "%s - Pause" "$l"; _guest_status suspend "$REPLY"
    fi
}
act_hibernate() {
    _guest_label; local l=$REPLY
    Tf "Do you really want to hibernate %s?" "$l"; confirm "$REPLY" || return
    Tf "%s - Hibernate" "$l"; _guest_status suspend "$REPLY" --todisk 1
}

# Shutdown button with its drop-down (like the web UI split button).
act_shutdown_menu() {
    local -a items=()
    T "Shutdown"; items+=(shutdown "$REPLY")
    T "Stop"; items+=(stop "$REPLY")
    T "Reboot"; items+=(reboot "$REPLY")
    if [[ $CTX_TYPE == qemu ]]; then
        T "Pause / Resume"; items+=(pause "$REPLY")
        T "Hibernate"; items+=(hibernate "$REPLY")
        T "Reset"; items+=(reset "$REPLY")
    else
        T "Suspend / Resume"; items+=(pause "$REPLY")
    fi
    _guest_label
    dlg_menu "Shutdown" "$REPLY" "${items[@]}" || return
    "act_$REPLY"
}

# Console: serial terminal for VMs, `pct enter` for containers. Linux VMs
# without a serial port are offered an SSH connection instead.
act_console() {
    if [[ $CTX_TYPE == lxc ]]; then
        node_cmd "$CTX_NODE" pct enter "$CTX_VMID"
        return
    fi
    api_kv "/nodes/$CTX_NODE/qemu/$CTX_VMID/config"
    if [[ -n ${API_KV[serial0]-} ]]; then
        T "Connecting to the serial console - press Ctrl+O to exit."
        status_msg info "$REPLY"
        node_cmd "$CTX_NODE" qm terminal "$CTX_VMID"
    elif [[ ${API_KV[ostype]-} == l26 || ${API_KV[ostype]-} == l24 ]]; then
        act_ssh
    else
        dlg_msg "Console" "The graphical console (noVNC/SPICE) cannot be displayed in a text terminal.

Add a serial port to the VM (Hardware > Add > Serial Port, or 'qm set $CTX_VMID -serial0 socket') and configure the guest to use it to get a text console here. The QEMU monitor is available in the Monitor panel."
    fi
}

# IP addresses of the current VM: guest agent first, then the neighbour
# (ARP/NDP) table of the node matched against the MAC addresses of the VM.
guest_ip_candidates() {
    local row mac k ip i
    local -a macs=()
    GUEST_IPS=()
    api_kv "/nodes/$CTX_NODE/qemu/$CTX_VMID/config"
    for k in "${!API_KV[@]}"; do
        [[ $k =~ ^net[0-9]+$ ]] || continue
        if [[ ${API_KV[$k]} =~ ([0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}) ]]; then macs+=("${BASH_REMATCH[1],,}"); fi
    done
    if [[ ${R_STATUS[$CTX_ID]-} == running ]] && \
        api_get rows "/nodes/$CTX_NODE/qemu/$CTX_VMID/agent/network-get-interfaces" "" "@result.*.ip-addresses;ip-address,ip-address-type"; then
        for row in "${API_ROWS[@]}"; do
            ip=${row%%$'\t'*}
            [[ $ip == 127.* || $ip == ::1 || $ip == fe80* ]] && continue
            GUEST_IPS+=("$ip")
        done
    fi
    local neigh="" scan=""
    # Optional ping sweep of the bridge networks of the VM (fills the
    # neighbour table), local node and networks up to /24 only.
    if [[ ${1-} == scan && $CTX_NODE == "$LOCAL_NODE" ]]; then
        local br cidr net
        for k in "${!API_KV[@]}"; do
            [[ $k =~ ^net[0-9]+$ && ${API_KV[$k]} =~ bridge=([^,]+) ]] || continue
            br=${BASH_REMATCH[1]}
            cidr=$(ip -4 -o addr show dev "$br" 2>/dev/null | awk '{print $4; exit}')
            [[ $cidr =~ ^([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+/(2[4-9]|3[0-2])$ ]] || continue
            net=${BASH_REMATCH[1]}
            T "Scanning"; spinner_start "$REPLY $net.0/24"
            # Wait for the pings only (a bare "wait" would wait for the broker).
            local -a pids=()
            for i in {1..254}; do ping -c1 -W1 "$net.$i" >/dev/null 2>&1 & pids+=($!); done
            wait "${pids[@]}"
            spinner_stop
        done
    fi
    if [[ $CTX_NODE == "$LOCAL_NODE" ]]; then neigh=$(ip neigh show 2>/dev/null)
    elif node_ip "$CTX_NODE"; then neigh=$(ssh -o BatchMode=yes "root@$REPLY" ip neigh show 2>/dev/null)
    fi
    for mac in "${macs[@]}"; do
        while read -r ip _ _ _ lladdr _; do
            [[ ${lladdr,,} == "$mac" && $ip != fe80* ]] || continue
            [[ " ${GUEST_IPS[*]} " == *" $ip "* ]] || GUEST_IPS+=("$ip")
        done <<< "$neigh"
    done
}

# Open an SSH session to the guest.
act_ssh() {
    local host user ip
    local -a items=()
    guest_ip_candidates
    for ip in "${GUEST_IPS[@]}"; do items+=("$ip" ""); done
    if (( ${#GUEST_IPS[@]} == 0 )) && [[ $CTX_NODE == "$LOCAL_NODE" ]]; then
        T "Scan the bridge network for the VM's MAC address"; items+=(_scan "$REPLY")
    fi
    T "Other address..."; items+=(_other "$REPLY")
    _guest_label
    Tf "%s has no serial port. Open an SSH connection instead?" "$REPLY"
    local text=$REPLY
    (( ${#GUEST_IPS[@]} )) || { T "No IP address found (guest agent / neighbour table)."; text+=$'\n'"$REPLY"; }
    dlg_menu "SSH" "$text" "${items[@]}" || return
    host=$REPLY
    if [[ $host == _scan ]]; then
        guest_ip_candidates scan
        items=()
        for ip in "${GUEST_IPS[@]}"; do items+=("$ip" ""); done
        T "Other address..."; items+=(_other "$REPLY")
        (( ${#GUEST_IPS[@]} )) || { T "No address found for the MAC addresses of the VM."; text=$REPLY; }
        dlg_menu "SSH" "$text" "${items[@]}" || return
        host=$REPLY
    fi
    if [[ $host == _other ]]; then dlg_input "SSH" "Host name or IP address:" "${CTX_NAME:-}" || return; host=$REPLY; fi
    [[ -n $host ]] || return
    dlg_input "SSH" "User name:" "${SSH_LAST_USER:-${CFG[ssh_user]:-root}}" || return
    user=${REPLY:-root}; SSH_LAST_USER=$user
    # Options of the configuration: key file, jump host, extra options.
    local -a sshopt=(-t -o StrictHostKeyChecking=accept-new)
    [[ -n ${CFG[ssh_key]} ]] && sshopt+=(-i "${CFG[ssh_key]}")
    [[ -n ${CFG[ssh_jump]} ]] && sshopt+=(-J "${CFG[ssh_jump]}")
    # shellcheck disable=SC2206
    [[ -n ${CFG[ssh_options]} ]] && sshopt+=(${CFG[ssh_options]})
    term_run bash -c 'clear; printf "\e[1m%s\e[0m\n" "$1"; shift; ssh "$@"; echo; read -rp "[Enter] to return to pvetty" _' \
        sh "pvetty - ssh $user@$host" "${sshopt[@]}" "$user@$host"
}

# Browser console: the URL of the console of the web UI (noVNC / xterm.js),
# shown, copied to the clipboard of the terminal (OSC 52) and clickable in
# terminals supporting hyperlinks (OSC 8).
act_web_console() {
    local host=${CFG[console_host]} node=${CTX_NODE:-$LOCAL_NODE} url
    if [[ -z $host ]]; then node_ip "$node" && host=$REPLY; fi
    [[ -z $host ]] && host=$(hostname -f 2>/dev/null)
    case $CTX_TYPE in
        qemu) url="https://$host:8006/?console=kvm&novnc=1&vmid=$CTX_VMID&vmname=$CTX_NAME&node=$node&resize=off&cmd=" ;;
        lxc) url="https://$host:8006/?console=lxc&xtermjs=1&vmid=$CTX_VMID&vmname=$CTX_NAME&node=$node&resize=off&cmd=" ;;
        *) url="https://$host:8006/?console=shell&xtermjs=1&vmid=0&vmname=&node=$node&resize=off&cmd=" ;;
    esac
    WEB_CONSOLE_URL=$url
    printf '\e]52;c;%s\a' "$(printf '%s' "$url" | base64 -w 0)"
    term_run _web_console_screen "$url"
}

_web_console_screen() {
    clear
    T "Graphical console in the web browser (log in to the web UI if asked):"; printf '%s\n\n' "$REPLY"
    # OSC 8 hyperlink: clickable in most recent terminals.
    printf '  \e]8;;%s\e\\%s\e]8;;\e\\\n\n' "$1" "$1"
    T "The URL was copied to the clipboard (if the terminal allows it). Press a key to return."; printf '%s\n' "$REPLY"
    read -rsn1 _
}

# Run a command in the guest: QEMU guest agent for VMs, pct exec for
# containers. The output is shown in a window.
act_run_command() {
    local cmd out rc=""
    dlg_input "Run command" "Command to run in $CTX_TYPE $CTX_VMID (/bin/sh -c):" "${LAST_GUEST_CMD-}" || return
    cmd=$REPLY; [[ -n $cmd ]] || return
    LAST_GUEST_CMD=$cmd
    local -a lines=()
    T "Running"; spinner_start "$REPLY: $cmd"
    if [[ $CTX_TYPE == qemu ]]; then
        local p="/nodes/$CTX_NODE/qemu/$CTX_VMID/agent" pid row i
        pid=$(pvesh create "$p/exec" --command /bin/sh --command -c --command "$cmd" --output-format json 2>"$RUN_DIR/exec.err" | perl -MJSON -ne 'print decode_json($_)->{pid}')
        if [[ -z $pid ]]; then
            spinner_stop; dlg_msg "Run command" "$(api_error_line "$RUN_DIR/exec.err")"; return
        fi
        for (( i = 0; i < 600; i++ )); do
            api_kv "$p/exec-status" "pid=$pid" && [[ ${API_KV[exited]-} == 1 ]] && break
            sleep 0.5
        done
        rc=${API_KV[exitcode]-}
        mapfile -t lines < <(printf '%s' "${API_KV[out-data]-}" | tr '\037' '\n')
        if [[ -n ${API_KV[err-data]-} ]]; then
            lines+=("" "${C[err]}stderr:${C[norm]}")
            mapfile -t -O "${#lines[@]}" lines < <(printf '%s' "${API_KV[err-data]}" | tr '\037' '\n')
        fi
    else
        if [[ $CTX_NODE == "$LOCAL_NODE" ]]; then
            out=$(timeout 300 pct exec "$CTX_VMID" -- /bin/sh -c "$cmd" 2>&1); rc=$?
        else
            node_ip "$CTX_NODE"
            out=$(timeout 300 ssh -o BatchMode=yes "root@$REPLY" pct exec "$CTX_VMID" -- /bin/sh -c "$(printf '%q' "$cmd")" 2>&1); rc=$?
        fi
        mapfile -t lines <<< "$out"
    fi
    spinner_stop
    Tf "Exit code: %s" "${rc:-?}"; lines+=("" "${C[dim]}$REPLY${C[norm]}")
    overlay_show "$CTX_TYPE $CTX_VMID: $cmd" "${lines[@]}"
}

# "More" menu (clone, template, migrate, HA, remove...).
act_more() {
    local -a items=()
    T "Clone"; items+=(clone "$REPLY")
    T "Convert to template"; items+=(template "$REPLY")
    T "Migrate"; items+=(migrate "$REPLY")
    T "Manage HA"; items+=(ha "$REPLY")
    T "Edit Notes"; items+=(notes "$REPLY")
    T "Backup now"; items+=(backup "$REPLY")
    T "Take Snapshot"; items+=(snapshot "$REPLY")
    T "Run command"; items+=(runcmd "$REPLY")
    T "Browser console (URL)"; items+=(webconsole "$REPLY")
    T "Remove"; items+=(remove "$REPLY")
    _guest_label
    dlg_menu "More" "$REPLY" "${items[@]}" || return
    case $REPLY in
        clone) act_clone ;;
        template) act_template ;;
        migrate) act_migrate ;;
        ha) act_ha ;;
        notes) act_edit_notes ;;
        backup) act_backup_now ;;
        snapshot) act_snapshot_new ;;
        runcmd) act_run_command ;;
        webconsole) act_web_console ;;
        remove) act_remove ;;
    esac
}

act_clone() {
    local newid name
    api_get rows /cluster/nextid "" "" ; newid=${API_ROWS[0]-}
    dlg_input "Clone" "VM ID of the clone:" "$newid" || return
    newid=$REPLY
    dlg_input "Clone" "Name of the clone:" "${CTX_NAME:+$CTX_NAME-clone}" || return
    name=$REPLY
    _guest_path; local p=$REPLY
    local -a args=(--newid "$newid")
    if [[ $CTX_TYPE == qemu ]]; then [[ -n $name ]] && args+=(--name "$name")
    else [[ -n $name ]] && args+=(--hostname "$name")
    fi
    if [[ ${R_TMPL[$CTX_ID]} != 1 ]] && dlg_yesno "Clone" "Full clone (independent copy of all disks)?"; then
        args+=(--full 1)
    fi
    _guest_label; Tf "%s - Clone" "$REPLY"
    api_exec "$REPLY" create "$p/clone" "${args[@]}"
}

act_template() {
    _guest_label; local l=$REPLY
    Tf "Convert %s to a template? This cannot be undone." "$l"; confirm "$REPLY" || return
    _guest_path; Tf "%s - Convert to template" "$l"
    api_exec "$REPLY" create "/nodes/$CTX_NODE/$CTX_TYPE/$CTX_VMID/template"
}

act_migrate() {
    local id n
    local -a items=()
    for id in "${RES_IDS[@]}"; do
        [[ ${R_TYPE[$id]} == node && ${R_NODE[$id]} != "$CTX_NODE" && ${R_STATUS[$id]} == online ]] || continue
        items+=("${R_NODE[$id]}" "")
    done
    if (( ${#items[@]} == 0 )); then dlg_msg "Migrate" "No other online node available (standalone node)."; return; fi
    _guest_label
    dlg_menu "Migrate" "Target node for $REPLY:" "${items[@]}" || return
    n=$REPLY
    local -a args=(--target "$n")
    [[ ${R_STATUS[$CTX_ID]} == running ]] && { [[ $CTX_TYPE == qemu ]] && args+=(--online 1) || args+=(--restart 1); }
    _guest_label; Tf "%s - Migrate" "$REPLY"
    api_exec "$REPLY" create "/nodes/$CTX_NODE/$CTX_TYPE/$CTX_VMID/migrate" "${args[@]}"
}

act_ha() {
    local sid="vm:$CTX_VMID"
    [[ $CTX_TYPE == lxc ]] && sid="ct:$CTX_VMID"
    if [[ -n ${R_HA[$CTX_ID]-} ]]; then
        local -a items=()
        T "started"; items+=(started "$REPLY")
        T "stopped"; items+=(stopped "$REPLY")
        T "ignored"; items+=(ignored "$REPLY")
        T "Remove from HA"; items+=(remove "$REPLY")
        dlg_menu "Manage HA" "Requested state for $sid:" "${items[@]}" || return
        if [[ $REPLY == remove ]]; then
            api_exec_sync "HA $sid - Remove" delete "/cluster/ha/resources/$sid"
        else
            api_exec_sync "HA $sid - $REPLY" set "/cluster/ha/resources/$sid" --state "$REPLY"
        fi
    else
        dlg_yesno "Manage HA" "Add $sid to High Availability (requested state: started)?" || return
        api_exec_sync "HA $sid - Add" create /cluster/ha/resources --sid "$sid" --state started
    fi
    NEED_REFRESH=1
}

act_remove() {
    _guest_label; local l=$REPLY
    if [[ ${R_STATUS[$CTX_ID]} == running ]]; then dlg_msg "Remove" "$l is running - stop it first."; return; fi
    Tf "Remove %s and all its disks? Type the ID (%s) to confirm:" "$l" "$CTX_VMID"
    dlg_input "Remove" "$REPLY" "" || return
    [[ $REPLY == "$CTX_VMID" ]] || { status_msg warn "Removal cancelled"; return; }
    local -a args=(--purge 1)
    dlg_yesno "Remove" "Also destroy unreferenced disks owned by the guest?" && args+=(--destroy-unreferenced-disks 1)
    Tf "%s - Destroy" "$l"
    api_exec "$REPLY" delete "/nodes/$CTX_NODE/$CTX_TYPE/$CTX_VMID" "${args[@]}"
}

act_backup_now() {
    local id s
    local -a items=()
    for id in "${RES_IDS[@]}"; do
        [[ ${R_TYPE[$id]} == storage && ${R_NODE[$id]} == "$CTX_NODE" && ,${R_CONTENT[$id]}, == *,backup,* ]] || continue
        items+=("${R_STORAGE[$id]}" "${R_PLUGIN[$id]}")
    done
    (( ${#items[@]} )) || { dlg_msg "Backup" "No storage with 'backup' content on this node."; return; }
    dlg_menu "Backup now" "Storage:" "${items[@]}" || return
    s=$REPLY
    dlg_menu "Backup now" "Mode:" snapshot "Snapshot" suspend "Suspend" stop "Stop" || return
    local mode=$REPLY
    _guest_label; Tf "%s - Backup" "$REPLY"
    api_exec "$REPLY" create "/nodes/$CTX_NODE/vzdump" --vmid "$CTX_VMID" --storage "$s" --mode "$mode" --compress zstd
}

# Notes are edited with $EDITOR (multi-line text, like the web UI).
act_edit_notes() {
    local path=$1 f="$RUN_DIR/notes.md" ed=${CFG[editor]:-${VISUAL:-${EDITOR:-}}} ok=0
    if [[ -z $path ]]; then
        case $CTX_TYPE in
            qemu|lxc) path="/nodes/$CTX_NODE/$CTX_TYPE/$CTX_VMID/config" ;;
            node) path="/nodes/$CTX_NODE/config" ;;
            dc) path="/cluster/options" ;;
            pool) path="/pools/$CTX_POOL"; ;;
            *) return ;;
        esac
    fi
    if [[ -z $ed ]]; then
        command -v nano >/dev/null && ed=nano || ed=vi
    fi
    if [[ $CTX_TYPE == pool ]]; then
        api_get rows /pools "poolid=$CTX_POOL" comment; printf '%s' "${API_ROWS[0]-}" | tr '\037' '\n' > "$f"
    else
        api_kv "$path"; printf '%s' "${API_KV[description]-}" | tr '\037' '\n' > "$f"
    fi
    local before; before=$(cksum < "$f")
    # shellcheck disable=SC2086
    term_run $ed "$f"
    [[ $(cksum < "$f") == "$before" ]] && return
    local text; text=$(< "$f")
    if [[ $CTX_TYPE == pool ]]; then
        api_exec_sync "Edit Notes" set /pools --poolid "$CTX_POOL" --comment "$text"
    else
        api_exec_sync "Edit Notes" set "$path" --description "$text"
    fi
    content_load 1
}

# ---------------------------------------------------------------------------
# Snapshots (used by the Snapshots panels)
# ---------------------------------------------------------------------------
act_snapshot_new() {
    local name desc
    dlg_input "Take Snapshot" "Name:" "snap$(printf '%(%Y%m%d%H%M)T' -1)" || return
    name=$REPLY
    dlg_input "Take Snapshot" "Description:" "" || return
    desc=$REPLY
    local -a args=(--snapname "$name")
    [[ -n $desc ]] && args+=(--description "$desc")
    if [[ $CTX_TYPE == qemu && ${R_STATUS[$CTX_ID]} == running ]] && dlg_yesno "Take Snapshot" "Include RAM (VM state)?"; then
        args+=(--vmstate 1)
    fi
    _guest_label; Tf "%s - Snapshot" "$REPLY"
    api_exec "$REPLY" create "/nodes/$CTX_NODE/$CTX_TYPE/$CTX_VMID/snapshot" "${args[@]}"
}

act_snapshot_rollback() {
    local s=$1
    [[ -n $s && $s != current ]] || return
    Tf "Rollback to snapshot '%s'? Current state will be lost." "$s"; confirm "$REPLY" || return
    _guest_label; Tf "%s - Rollback" "$REPLY"
    api_exec "$REPLY" create "/nodes/$CTX_NODE/$CTX_TYPE/$CTX_VMID/snapshot/$s/rollback"
}

act_snapshot_delete() {
    local s=$1
    [[ -n $s && $s != current ]] || return
    Tf "Remove snapshot '%s'?" "$s"; confirm "$REPLY" || return
    _guest_label; Tf "%s - Delete Snapshot" "$REPLY"
    api_exec "$REPLY" delete "/nodes/$CTX_NODE/$CTX_TYPE/$CTX_VMID/snapshot/$s"
}

# ---------------------------------------------------------------------------
# Node actions
# ---------------------------------------------------------------------------
act_node_shell() {
    local sh=${SHELL:-/bin/bash}
    T "Starting shell - type 'exit' to return to pvetty."; status_msg info "$REPLY"
    if [[ $CTX_NODE == "$LOCAL_NODE" ]]; then
        term_run bash -c 'clear; printf "\e[1m%s\e[0m\n" "$1"; exec "$2" -l' sh "pvetty - shell on $CTX_NODE (exit to return)" "$sh"
    else
        node_cmd "$CTX_NODE" bash -l
    fi
}

act_node_reboot() {
    Tf "Reboot node '%s'?" "$CTX_NODE"; confirm "$REPLY" || return
    api_exec_sync "Node $CTX_NODE - Reboot" create "/nodes/$CTX_NODE/status" --command reboot
}

act_node_shutdown() {
    Tf "Shutdown node '%s'?" "$CTX_NODE"; confirm "$REPLY" || return
    api_exec_sync "Node $CTX_NODE - Shutdown" create "/nodes/$CTX_NODE/status" --command shutdown
}

act_node_bulk() {
    local -a items=()
    T "Bulk Start"; items+=(startall "$REPLY")
    T "Bulk Shutdown"; items+=(stopall "$REPLY")
    T "Bulk Suspend"; items+=(suspendall "$REPLY")
    T "Bulk Migrate"; items+=(migrateall "$REPLY")
    dlg_menu "Bulk Actions" "Node $CTX_NODE" "${items[@]}" || return
    local a=$REPLY
    task_desc "$a" ""; local d=$REPLY
    confirm "$d ($CTX_NODE)?" || return
    if [[ $a == migrateall ]]; then
        local id; local -a nodes=()
        for id in "${RES_IDS[@]}"; do
            [[ ${R_TYPE[$id]} == node && ${R_NODE[$id]} != "$CTX_NODE" ]] && nodes+=("${R_NODE[$id]}" "")
        done
        (( ${#nodes[@]} )) || { dlg_msg "Bulk Migrate" "No other node available."; return; }
        dlg_menu "Bulk Migrate" "Target node:" "${nodes[@]}" || return
        api_exec "$d" create "/nodes/$CTX_NODE/migrateall" --target "$REPLY"
    else
        api_exec "$d" create "/nodes/$CTX_NODE/$a"
    fi
}

# ---------------------------------------------------------------------------
# Toolbars per type (hot key, label, icon, enabled, action)
# ---------------------------------------------------------------------------
toolbar_node() {
    tb_add b "Reboot" "${G[btn_reboot]}" 1 act_node_reboot
    tb_add h "Shutdown" "${G[btn_shutdown]}" 1 act_node_shutdown
    tb_add S "Shell" "${G[btn_shell]}" 1 act_node_shell
    tb_add w "Web console" "${G[btn_console]}" 1 act_web_console
    tb_add B "Bulk Actions" "${G[btn_bulk]}" 1 act_node_bulk
}

_toolbar_guest() {
    local st=${R_STATUS[$CTX_ID]-} run=0 tmpl=${R_TMPL[$CTX_ID]-0}
    [[ $st == running || $st == paused || $st == suspended ]] && run=1
    if [[ $tmpl == 1 ]]; then
        tb_add m "More" "${G[btn_more]}" 1 act_more
        return
    fi
    tb_add s "Start" "${G[btn_start]}" $(( ! run )) act_start
    tb_add h "Shutdown" "${G[btn_shutdown]}" "$run" act_shutdown_menu
    tb_add c "Console" "${G[btn_console]}" "$run" act_console
    [[ $CTX_TYPE == qemu ]] && tb_add H "SSH" "${G[btn_shell]}" "$run" act_ssh
    tb_add w "Web console" "${G[btn_console]}" "$run" act_web_console
    tb_add m "More" "${G[btn_more]}" 1 act_more
}
toolbar_qemu() { _toolbar_guest; }
toolbar_lxc() { _toolbar_guest; }

# ---------------------------------------------------------------------------
# Header buttons
# ---------------------------------------------------------------------------
act_help() {
    local f="$PVETTY_HOME/docs/USAGE.md"
    [[ -r $f ]] || f="$PVETTY_HOME/README.md"
    pager_show "$f" "Documentation"
}

act_user_menu() {
    local k v
    while :; do
        local -a items=()
        _onoff() { if [[ $1 == 1 ]]; then T "on"; else T "off"; fi; }
        T "Language"; items+=(language "$REPLY: $LANG_NAME")
        T "Icon set"; items+=(glyphs "$REPLY: $GLYPH_SET")
        _onoff "${CFG[icons]}"; v=$REPLY; T "Icons"; items+=(icons "$REPLY: $v")
        T "Theme"; items+=(theme "$REPLY: $THEME_NAME")
        _onoff "${CFG[mouse]}"; v=$REPLY; T "Mouse"; items+=(mouse "$REPLY: $v")
        _onoff "${CFG[confirm]}"; v=$REPLY; T "Confirm actions"; items+=(confirm "$REPLY: $v")
        _onoff "${CFG[confirm_quit]}"; v=$REPLY; T "Confirm quit"; items+=(confirm_quit "$REPLY: $v")
        T "Automatic refresh (s, 0 = off)"; items+=(refresh "$REPLY: ${CFG[refresh]}")
        T "Startup selection"; items+=(startup "$REPLY: ${CFG[startup]}")
        T "Task panel rows"; items+=(task_rows "$REPLY: ${CFG[task_rows]}")
        T "Tree width (0 = auto)"; items+=(tree_width "$REPLY: ${CFG[tree_width]}")
        _onoff "${CFG[show_tags]}"; v=$REPLY; T "Tags in the tree"; items+=(show_tags "$REPLY: $v")
        _onoff "${CFG[ip_column]}"; v=$REPLY; T "IP column in the grids"; items+=(ip_column "$REPLY: $v")
        T "Parallel queued actions"; items+=(queue_parallel "$REPLY: ${CFG[queue_parallel]}")
        T "SSH user (VM console)"; items+=(ssh_user "$REPLY: ${CFG[ssh_user]}")
        T "SSH key file"; items+=(ssh_key "$REPLY: ${CFG[ssh_key]:--}")
        T "SSH jump host"; items+=(ssh_jump "$REPLY: ${CFG[ssh_jump]:--}")
        T "Browser console host"; items+=(console_host "$REPLY: ${CFG[console_host]:-(node IP)}")
        T "Plugins"; items+=(plugins "$REPLY: ${CFG[plugins]:--}")
        T "Key bindings"; items+=(keys "$REPLY: key.<action> = <keys> (F1)")
        T "About"; items+=(about "$REPLY: pvetty $PVETTY_VERSION")
        T "Logout (quit)"; items+=(quit "$REPLY")
        T "Application Settings"
        DLG_NOTAGS=1
        dlg_menu "$REPLY" "${PVE_USER:-root@pam} - $(T "saved in ~/.config/pvetty/pvetty.conf"; printf '%s' "$REPLY")" "${items[@]}" || { DLG_NOTAGS=0; break; }
        DLG_NOTAGS=0
        k=$REPLY
        case $k in
            language)
                local -a langs=() c n
                while read -r c n; do langs+=("$c" "$n"); done < <(i18n_list)
                dlg_menu "Language" "Select the interface language:" "${langs[@]}" || continue
                core_save_config language "$REPLY"; i18n_load ;;
            glyphs)
                # Preview of each set: the icons are drawn by the font of the
                # terminal of the client (squares = font without those glyphs).
                local pn pu
                printf -v pn '       '
                pu="▦ ▣ ▭ ◈ ◫ ◇ ◉ ›"
                dlg_menu "Icons" "Icon set. The Nerd Font icons are drawn by the font of YOUR terminal: if they appear as squares below, install a Nerd Font on the computer running the terminal and select it in the terminal settings (see docs/CONFIGURATION.md)." \
                    nerd "Nerd Font   $pn" unicode "Unicode     $pu" ascii "ASCII       D N V C S P o \$" || continue
                core_save_config glyphs "$REPLY"; glyphs_load; chart_init ;;
            icons|confirm|confirm_quit|show_tags|ip_column)
                [[ ${CFG[$k]} == 1 ]] && v=0 || v=1
                core_save_config "$k" "$v"
                [[ $k == icons ]] && glyphs_load ;;
            mouse)
                [[ ${CFG[mouse]} == 1 ]] && v=0 || v=1
                term_leave; core_save_config mouse "$v"; term_enter ;;
            theme)
                local -a th=() f
                for f in "$PVETTY_HOME"/themes/*.sh; do f=${f##*/}; th+=("${f%.sh}" ""); done
                dlg_menu "Theme" "Colour theme:" "${th[@]}" || continue
                core_save_config theme "$REPLY"; theme_load ;;
            refresh|task_rows|tree_width|queue_parallel)
                dlg_input "Settings" "$k:" "${CFG[$k]}" || continue
                [[ $REPLY =~ ^[0-9]+$ ]] || { dlg_msg "Settings" "A number is expected."; continue; }
                core_save_config "$k" "$REPLY"
                layout_compute ;;
            startup)
                dlg_menu "Startup selection" "Entry selected when pvetty starts:" \
                    root "Datacenter" last "$(T "Last selection"; printf '%s' "$REPLY")" "$SEL_ID" "$(T "Current selection"; printf '%s' "$REPLY")" || continue
                core_save_config startup "$REPLY" ;;
            ssh_user|ssh_key|ssh_jump|console_host)
                dlg_input "Settings" "$k (empty = default):" "${CFG[$k]}" || continue
                core_save_config "$k" "$REPLY" ;;
            plugins) plugins_dialog ;;
            keys) help_overlay ;;
            about)
                dlg_msg "About" "pvetty $PVETTY_VERSION - text console for Proxmox VE
Backend: $API_BACKEND | Dialogs: $DLG | Icons: $GLYPH_SET | Theme: $THEME_NAME
Language: $LANG_NAME ($LANG_CODE)" ;;
            quit) quit_request; [[ $RUNNING == 0 ]] && break ;;
        esac
    done
    content_load 1
}

# Create VM / CT wizards (essential options only; edit the rest afterwards).
_pick_node() {
    local id; local -a items=()
    for id in "${RES_IDS[@]}"; do
        [[ ${R_TYPE[$id]} == node && ${R_STATUS[$id]} == online ]] && items+=("${R_NODE[$id]}" "")
    done
    if (( ${#items[@]} == 2 )); then REPLY=${items[0]}; return 0; fi
    dlg_menu "$1" "Node:" "${items[@]}"
}

_pick_storage() {   # _pick_storage <title> <node> <content type>
    local id; local -a items=()
    for id in "${RES_IDS[@]}"; do
        [[ ${R_TYPE[$id]} == storage && ${R_NODE[$id]} == "$2" && ${R_STATUS[$id]} == available && ,${R_CONTENT[$id]}, == *,$3,* ]] || continue
        fmt_bytes $(( ${R_MAXDISK[$id]:-0} - ${R_DISK[$id]:-0} ))
        items+=("${R_STORAGE[$id]}" "${R_PLUGIN[$id]} - $REPLY free")
    done
    (( ${#items[@]} )) || { dlg_msg "$1" "No storage with '$3' content on node $2."; return 1; }
    dlg_menu "$1" "Storage for '$3':" "${items[@]}"
}

_pick_volume() {    # _pick_volume <title> <node> <content type>
    local id row; local -a items=()
    T "none"; items+=(none "$REPLY")
    for id in "${RES_IDS[@]}"; do
        [[ ${R_TYPE[$id]} == storage && ${R_NODE[$id]} == "$2" && ,${R_CONTENT[$id]}, == *,$3,* ]] || continue
        api_get rows "/nodes/$2/storage/${R_STORAGE[$id]}/content" "content=$3" "volid" || continue
        for row in "${API_ROWS[@]}"; do items+=("$row" ""); done
    done
    dlg_menu "$1" "Select ($3):" "${items[@]}"
}

_create_common() {
    local title=$1
    _pick_node "$title" || return 1; CR_NODE=$REPLY
    api_get rows /cluster/nextid "" ""
    dlg_input "$title" "VM ID:" "${API_ROWS[0]-100}" || return 1; CR_ID=$REPLY
    dlg_input "$title" "Name:" "" || return 1; CR_NAME=$REPLY
    dlg_input "$title" "Memory (MiB):" "${2:-2048}" || return 1; CR_MEM=$REPLY
    dlg_input "$title" "Cores:" "2" || return 1; CR_CORES=$REPLY
    _pick_storage "$title" "$CR_NODE" "$3" || return 1; CR_STORE=$REPLY
    dlg_input "$title" "Disk size (GiB):" "${4:-32}" || return 1; CR_DISK=$REPLY
    # File based storages: choose the image format (qcow2 allows snapshots).
    CR_FORMAT=""
    local id
    for id in "${RES_IDS[@]}"; do
        if [[ ${R_TYPE[$id]} == storage && ${R_STORAGE[$id]} == "$CR_STORE" && ${R_NODE[$id]} == "$CR_NODE" ]] \
            && [[ $3 == images && ${R_PLUGIN[$id]} =~ ^(dir|nfs|cifs|glusterfs|btrfs|cephfs)$ ]]; then
            dlg_menu "$title" "Disk format:" qcow2 "QEMU image format (qcow2)" raw "Raw disk image (raw)" vmdk "VMware image format (vmdk)" || return 1
            CR_FORMAT=$REPLY
        fi
    done
    dlg_input "$title" "Network bridge:" "vmbr0" || return 1; CR_BRIDGE=$REPLY
}

act_create_vm() {
    local T_="Create: Virtual Machine"
    _create_common "$T_" 2048 images 32 || return
    _pick_volume "$T_" "$CR_NODE" iso || return
    local iso=$REPLY
    dlg_menu "$T_" "Guest OS type:" l26 "Linux 6.x - 2.6 Kernel" win11 "Microsoft Windows 11/2022/2025" win10 "Microsoft Windows 10/2016/2019" other "Other" || return
    local os=$REPLY
    local -a args=(--vmid "$CR_ID" --memory "$CR_MEM" --cores "$CR_CORES" --sockets 1 --ostype "$os"
        --scsihw virtio-scsi-single --scsi0 "$CR_STORE:$CR_DISK,iothread=1${CR_FORMAT:+,format=$CR_FORMAT}" --net0 "virtio,bridge=$CR_BRIDGE"
        --boot "order=scsi0;ide2;net0")
    [[ -n $CR_NAME ]] && args+=(--name "$CR_NAME")
    if [[ $iso != none ]]; then args+=(--ide2 "$iso,media=cdrom"); else args+=(--ide2 "none,media=cdrom"); fi
    dlg_yesno "$T_" "Create VM $CR_ID on node $CR_NODE?" || return
    api_exec "VM $CR_ID - Create" create "/nodes/$CR_NODE/qemu" "${args[@]}"
}

act_create_ct() {
    local T_="Create: LXC Container"
    _create_common "$T_" 512 rootdir 8 || return
    _pick_volume "$T_" "$CR_NODE" vztmpl || return
    [[ $REPLY == none ]] && { dlg_msg "$T_" "A container template is required (download one in the storage 'CT Templates' panel)."; return; }
    local tmpl=$REPLY pw
    dlg_password "$T_" "Root password (min. 5 characters, empty = SSH key only):" || return
    pw=$REPLY
    local -a args=(--vmid "$CR_ID" --ostemplate "$tmpl" --memory "$CR_MEM" --cores "$CR_CORES"
        --rootfs "$CR_STORE:$CR_DISK" --net0 "name=eth0,bridge=$CR_BRIDGE,ip=dhcp" --unprivileged 1)
    [[ -n $CR_NAME ]] && args+=(--hostname "$CR_NAME")
    [[ -n $pw ]] && args+=(--password "$pw")
    [[ -r $HOME/.ssh/authorized_keys ]] && dlg_yesno "$T_" "Add root's authorized SSH keys to the container?" && args+=(--ssh-public-keys "$(< "$HOME/.ssh/authorized_keys")")
    dlg_yesno "$T_" "Create CT $CR_ID on node $CR_NODE?" || return
    api_exec "CT $CR_ID - Create" create "/nodes/$CR_NODE/lxc" "${args[@]}"
}
