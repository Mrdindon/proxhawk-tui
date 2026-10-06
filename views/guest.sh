# shellcheck shell=bash
# views/guest.sh - panels shared by virtual machines (qemu) and containers
# (lxc): summary, task history, backup, replication, snapshots, firewall,
# permissions and the configuration helpers.

title_qemu() {
    Tf "Virtual Machine %s on node '%s'" "$CTX_VMID${CTX_NAME:+ ($CTX_NAME)}" "$CTX_NODE"
    _title_tags
}
title_lxc() {
    Tf "Container %s on node '%s'" "$CTX_VMID${CTX_NAME:+ ($CTX_NAME)}" "$CTX_NODE"
    _title_tags
}
_title_tags() {
    local t=${R_TAGS[$CTX_ID]-} tg out=""
    if [[ -n $t ]]; then
        for tg in ${t//;/ }; do out+=" ${C[tag]}${tg}${C[norm]}${C[title]}"; done
        REPLY+="$out"
    else
        local title=$REPLY
        T "No Tags"; REPLY="$title  ${C[dim]}${REPLY}${C[norm]}"
    fi
    [[ -n ${R_LOCK[$CTX_ID]-} ]] && REPLY+=" ${C[warn]}${G[lock]} ${R_LOCK[$CTX_ID]}${C[norm]}"
    [[ -n ${PENDING[$CTX_ID]-} ]] && REPLY+=" ${C[warn]}${SPIN_MARK} ${PENDING[$CTX_ID]}${C[norm]}"
}

# prop_get <property string> <key>: value of key=value in "a=1,b=2" strings.
prop_get() {
    local s=",$1," k=$2
    REPLY=""
    [[ $s == *",$k="* ]] || return 1
    s=${s#*,"$k"=}
    REPLY=${s%%,*}
}

# Load /pending of the current guest into CFGV (current) and CFGP (pending).
declare -gA CFGV=() CFGP=() CFGD=()
guest_config() {
    local row k
    local -a f
    CFGV=() CFGP=() CFGD=()
    api_get rows "/nodes/$CTX_NODE/$CTX_TYPE/$CTX_VMID/pending" "" "key,value,pending,delete" || return 1
    for row in "${API_ROWS[@]}"; do
        tsv_split f "$row"
        k=${f[0]}
        CFGV[$k]=${f[1]-}
        [[ -n ${f[2]-} ]] && CFGP[$k]=${f[2]}
        [[ -n ${f[3]-} && ${f[3]} != 0 ]] && CFGD[$k]=1
    done
    return 0
}

# Config line: value, with the pending change shown like the web UI.
# cfg_line <label> <key> <display value> [default display]
cfg_line() {
    local label=$1 key=$2 val=$3 def=${4:-}
    if [[ -z $val && -n $def ]]; then T "$def"; val="${C[dim]}${REPLY}${C[norm]}"; fi
    if [[ -n ${CFGP[$key]-} ]]; then val+="  ${C[err]}(${CFGP[$key]})${C[norm]}"
    elif [[ -n ${CFGD[$key]-} ]]; then strip "$val"; val="${C[err]}${REPLY} (delete)${C[norm]}"
    fi
    c_kv_sel "$label" "$val" "$key" 26
}

# Edit a configuration row with the API schema form (Enter on a row).
# Related keys are edited together, like the dialogs of the web UI.
guest_cfg_edit() {
    local key=$1 only=$1
    [[ -n $key && $key != _* ]] || return
    case $CTX_TYPE:$key in
        qemu:memory) only="memory balloon shares allow-ksm" ;;
        qemu:cores) only="sockets cores cpu cpulimit cpuunits numa vcpus affinity" ;;
        lxc:memory) only="memory swap" ;;
        lxc:cores) only="cores cpulimit cpuunits" ;;
        *:startup) only="onboot startup" ;;
    esac
    form_reset
    FORM_GET="/nodes/$CTX_NODE/$CTX_TYPE/$CTX_VMID/config" FORM_ONLY=$only
    form_run "Edit: $key" PUT "$FORM_GET" && content_load 1
}

# d = remove (or detach) a configuration key, v = revert a pending change.
guest_cfg_key() {
    local key=${2-} p="/nodes/$CTX_NODE/$CTX_TYPE/$CTX_VMID/config"
    case $1 in
        d|DEL)
            [[ -n $key && $key != _* ]] || return 0
            if [[ $key == unused* ]]; then Tf "Delete the disk '%s'? Its data will be destroyed." "$key"
            elif [[ $key =~ ^(ide|sata|scsi|virtio|mp)[0-9]+$ ]]; then Tf "Detach '%s'? The disk becomes an unused disk." "$key"
            else Tf "Remove '%s' from the configuration?" "$key"
            fi
            confirm "$REPLY" || return 0
            api_exec_sync "Remove $key" set "$p" --delete "$key"
            content_load 1 ;;
        v)
            [[ -n $key && $key != _* ]] || return 0
            api_exec_sync "Revert $key" set "$p" --revert "$key"
            content_load 1 ;;
        *) return 1 ;;
    esac
    return 0
}

# Next free index of a configuration key prefix: cfg_next <prefix> [max]
cfg_next() {
    local i=0
    guest_config
    while [[ -n ${CFGV[$1$i]-}${CFGP[$1$i]-} ]] && (( i < ${2:-30} )); do (( i++ )); done
    REPLY="$1$i"
}

# Disk actions: resize (+size) and move to another storage.
guest_disk_resize() {
    local disk=$1
    [[ $disk =~ ^(ide|sata|scsi|virtio|efidisk|tpmstate|rootfs|mp)[0-9]*$ ]] || { status_msg warn "Select a disk"; return; }
    dlg_input "Resize disk $disk" "Size increment (e.g. +4G):" "+1G" || return
    local opt=disk
    api_exec_sync "Resize $disk" set "/nodes/$CTX_NODE/$CTX_TYPE/$CTX_VMID/resize" --"$opt" "$disk" --size "$REPLY"
    content_load 1
}
guest_disk_move() {
    local disk=$1 st
    [[ $disk =~ ^(ide|sata|scsi|virtio|efidisk|tpmstate|rootfs|mp|unused)[0-9]*$ ]] || { status_msg warn "Select a disk"; return; }
    local ct=images; [[ $CTX_TYPE == lxc ]] && ct=rootdir
    if [[ -n ${CRUD_ANSWER[storage]-} ]]; then st=${CRUD_ANSWER[storage]}
    else
        choice_storages "$ct" || return
        local c; local -a cl it=()
        IFS=, read -r -a cl <<< "$REPLY"
        for c in "${cl[@]}"; do it+=("${c%%=*}" "${c#*=}"); done
        dlg_menu "Move $disk" "Target storage:" "${it[@]}" || return
        st=$REPLY
    fi
    if [[ $CTX_TYPE == qemu ]]; then
        api_exec "Move disk $disk" create "/nodes/$CTX_NODE/qemu/$CTX_VMID/move_disk" --disk "$disk" --storage "$st" --delete 1
    else
        api_exec "Move volume $disk" create "/nodes/$CTX_NODE/lxc/$CTX_VMID/move_volume" --volume "$disk" --storage "$st" --delete 1
    fi
}

# Add a device: guest_add_device <key> <initial value> <title>
guest_add_device() {
    form_reset
    FORM_ONLY=$1
    FORM_VAL[$1]=$2
    form_run "Add: $3" PUT "/nodes/$CTX_NODE/$CTX_TYPE/$CTX_VMID/config" && content_load 1
}

# Pick a storage for a new volume: REPLY = storage id.
_pick_store() {
    if [[ -n ${CRUD_ANSWER[storage]-} ]]; then REPLY=${CRUD_ANSWER[storage]}; return 0; fi
    choice_storages "$1" || { dlg_msg "Storage" "No storage with '$1' content."; return 1; }
    local c; local -a cl it=()
    IFS=, read -r -a cl <<< "$REPLY"
    for c in "${cl[@]}"; do it+=("${c%%=*}" "${c#*=}"); done
    dlg_menu "Storage" "Storage:" "${it[@]}"
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
guest_summary() {
    local p="/nodes/$CTX_NODE/$CTX_TYPE/$CTX_VMID" w=$CONTENT_W
    if ! api_row "$p/status/current" "" "status,qmpstatus,ha.managed,ha.state,cpu*10000,cpus,mem:i,maxmem:i,swap:i,maxswap:i,disk:i,maxdisk:i,uptime:i,agent,lock,template"; then
        c_api_error; return
    fi
    local -a s=("${API_F[@]}")
    local st=${s[1]:-${s[0]}}
    fmt_uptime "${s[12]}"
    Tf "%s (Uptime: %s)" "$CTX_VMID${CTX_NAME:+ ($CTX_NAME)}" "$REPLY"
    c_add "${C[title]}${REPLY}${C[norm]}"
    repeat "${G[h]}" "$w"; c_add "${C[border]}${REPLY}${C[norm]}"
    status_glyph "$st"; T "$st"
    c_kv "Status" "${STATUS_G}${C[norm]} $REPLY" 18
    local ha="none"; [[ ${s[2]} == 1 ]] && ha=${s[3]:-managed}
    T "$ha"; c_kv "HA State" "$REPLY" 18
    c_kv "Node" "$CTX_NODE" 18
    if [[ ${s[15]} == 1 ]]; then
        T "Template"; c_kv "Type" "$REPLY" 18
    else
        usage_line "CPU usage" "${s[4]:-0}" "${s[5]:-1}" "$w" cpu; c_add "$REPLY"
        usage_line "Memory usage" "${s[6]:-0}" "${s[7]:-0}" "$w"; c_add "$REPLY"
        [[ $CTX_TYPE == lxc ]] && { usage_line "SWAP usage" "${s[8]:-0}" "${s[9]:-0}" "$w"; c_add "$REPLY"; }
    fi
    if [[ $CTX_TYPE == lxc ]]; then
        usage_line "Bootdisk size" "${s[10]:-0}" "${s[11]:-0}" "$w"; c_add "$REPLY"
    else
        fmt_bytes "${s[11]:-0}"; c_kv "Bootdisk size" "$REPLY" 18
    fi
    guest_ips "${s[0]}" "${s[13]}"
    c_kv "IPs" "$REPLY" 18
    # Notes panel.
    api_kv "$p/config"
    if [[ -n ${API_KV[description]-} ]]; then
        c_blank
        c_section "Notes"
        c_text "${API_KV[description]}"
    fi
    c_blank
    rrd_graphs "$p/rrddata" \
        "CPU usage|pct|cpu*10000" \
        "Memory usage|b|mem:i|maxmem:i" \
        "Network traffic|rate|netin:i|netout:i" \
        "Disk IO|rate|diskread:i|diskwrite:i"
}

# guest_ips <status> <agent flag> -> REPLY
guest_ips() {
    local st=$1 agent=$2 row ips=""
    if [[ $st != running ]]; then T "Guest not running"; REPLY="${C[dim]}${REPLY}${C[norm]}"; return; fi
    if [[ $CTX_TYPE == lxc ]]; then
        api_get rows "/nodes/$CTX_NODE/lxc/$CTX_VMID/interfaces" "" "name,inet,inet6" || { REPLY="-"; return; }
        for row in "${API_ROWS[@]}"; do
            local -a f; tsv_split f "$row"
            [[ ${f[0]} == lo ]] && continue
            [[ -n ${f[1]} ]] && ips+="${f[1]%/*} "
            [[ -n ${f[2]} && ${f[2]} != fe80* ]] && ips+="${f[2]%/*} "
        done
    else
        if [[ $agent != 1 ]]; then T "Guest Agent not running"; REPLY="${C[dim]}${REPLY}${C[norm]}"; return; fi
        if ! api_get rows "/nodes/$CTX_NODE/qemu/$CTX_VMID/agent/network-get-interfaces" "" "@result.*.ip-addresses;ip-address"; then
            T "Guest Agent not running"; REPLY="${C[dim]}${REPLY}${C[norm]}"; return
        fi
        for row in "${API_ROWS[@]}"; do
            [[ $row == 127.* || $row == ::1 || $row == fe80* ]] && continue
            ips+="$row "
        done
    fi
    REPLY=${ips:-"-"}
}

# ---------------------------------------------------------------------------
# Task history, backup, replication, snapshots, firewall, permissions
# ---------------------------------------------------------------------------
guest_tasks() { _task_history "vmid=$CTX_VMID"; }

guest_backup() {
    local id row n=0
    local -a f
    table_spec "volid:Name:**|notes:Notes:*|protected:Protected:9:bool|ctime:Date:19:t|format:Format:8|size:Size:10:b:r|enc:Encrypted:9|verify:Verify State:12"
    table_header
    for id in "${RES_IDS[@]}"; do
        [[ ${R_TYPE[$id]} == storage && ${R_NODE[$id]} == "$CTX_NODE" && ${R_STATUS[$id]} == available && ,${R_CONTENT[$id]}, == *,backup,* ]] || continue
        api_get rows "/nodes/$CTX_NODE/storage/${R_STORAGE[$id]}/content" "content=backup&vmid=$CTX_VMID" \
            "volid,notes,protected,ctime,format,size,encrypted,verification.state" || continue
        for row in "${API_ROWS[@]}"; do
            tsv_split f "$row"
            local enc="No"; [[ -n ${f[6]} ]] && enc="Yes"
            T "$enc"; enc=$REPLY
            local vs=${f[7]:-none}; status_color "$vs"; [[ $vs == ok ]] && vs="${STATUS_C}${G[st_ok]} OK${C[norm]}"
            table_row "${f[0]#*:}"$'\t'"${f[1]%%$'\x1f'*}"$'\t'"${f[2]}"$'\t'"${f[3]}"$'\t'"${f[4]}"$'\t'"${f[5]}"$'\t'"$enc"$'\t'"$vs"
            c_sel "$REPLY" "${f[0]}"
            (( n++ ))
        done
    done
    (( n )) || c_msg dim "No items"
}
guest_backup_enter() {
    local vol=$1
    [[ -n $vol ]] || return
    local -a items=()
    T "Restore"; items+=(restore "$REPLY")
    T "Show Configuration"; items+=(config "$REPLY")
    T "Change Protection"; items+=(protect "$REPLY")
    T "Edit Notes"; items+=(notes "$REPLY")
    T "Remove"; items+=(remove "$REPLY")
    dlg_menu "Backup" "$vol" "${items[@]}" || return
    case $REPLY in
        restore) guest_backup_restore "$vol" ;;
        config)
            api_get rows "/nodes/$CTX_NODE/vzdump/extractconfig" "volume=$(urlenc "$vol"; printf '%s' "$REPLY")" "" || { status_msg err "$API_ERR"; return; }
            printf '%s\n' "${API_ROWS[@]}" | tr '\037' '\n' > "$RUN_DIR/backup.conf"
            pager_show "$RUN_DIR/backup.conf" "$vol" ;;
        protect)
            api_get rows "/nodes/$CTX_NODE/storage/${vol%%:*}/content/$vol" "" "protected"
            local np=1; [[ ${API_ROWS[0]-} == 1 ]] && np=0
            api_exec_sync "Change Protection" set "/nodes/$CTX_NODE/storage/${vol%%:*}/content/$vol" --protected "$np"
            content_load 1 ;;
        notes)
            api_get rows "/nodes/$CTX_NODE/storage/${vol%%:*}/content/$vol" "" "notes"
            dlg_input "Edit Notes" "Notes of $vol:" "${API_ROWS[0]//$'\x1f'/ }" || return
            api_exec_sync "Edit Notes" set "/nodes/$CTX_NODE/storage/${vol%%:*}/content/$vol" --notes "$REPLY"
            content_load 1 ;;
        remove)
            Tf "Remove backup '%s'?" "$vol"; confirm "$REPLY" || return
            api_exec "Remove $vol" delete "/nodes/$CTX_NODE/storage/${vol%%:*}/content/$vol" ;;
    esac
}
guest_backup_restore() {
    local vol=$1
    _guest_label
    Tf "Restore %s from '%s'? ALL current data of the guest will be overwritten." "$REPLY" "$vol"
    dlg_yesno "Restore" "$REPLY" || return
    if [[ $CTX_TYPE == qemu ]]; then
        api_exec "VM $CTX_VMID - Restore" create "/nodes/$CTX_NODE/qemu" --vmid "$CTX_VMID" --archive "$vol" --force 1
    else
        api_exec "CT $CTX_VMID - Restore" create "/nodes/$CTX_NODE/lxc" --vmid "$CTX_VMID" --ostemplate "$vol" --restore 1 --force 1
    fi
}
guest_backup_key() {
    case $1 in
        n) act_backup_now ;;
        r) [[ -n ${2-} ]] && guest_backup_restore "$2" ;;
        *) return 1 ;;
    esac
    return 0
}

guest_replication() {
    view_table "/nodes/$CTX_NODE/replication" "guest=$CTX_VMID" "id:Job:10|target:Target:12|state:Status:10|last_sync:Last Sync:19:t|duration:Duration:9:s:r|next_sync:Next Sync:19:t|fail_count:Fail count:10:s:r|error:Error:*"
}
for _t in qemu lxc; do
    crud "v_${_t}_replication" label="Replication Job" add=/cluster/replication fix="id={vmid}-0" \
        edit="/cluster/replication/{1}" del="/cluster/replication/{1}" first="target schedule rate comment disable" \
        choices="target:choice_nodes"
done

guest_snapshots() {
    local row name
    local -a f
    local -A parent=() stime=() desc=() vm=()
    local -a names=()
    api_get rows "/nodes/$CTX_NODE/$CTX_TYPE/$CTX_VMID/snapshot" "" "name,parent,snaptime,description,vmstate" || { c_api_error; return; }
    for row in "${API_ROWS[@]}"; do
        tsv_split f "$row"
        name=${f[0]}; names+=("$name")
        parent[$name]=${f[1]-} stime[$name]=${f[2]-} desc[$name]=${f[3]-} vm[$name]=${f[4]-}
    done
    table_spec "name:Name:*|ram:RAM:5|date:Date/Status:19|desc:Description:*"
    table_header
    # Depth = number of ancestors; order by time with "current" last.
    local -a keyed=()
    for name in "${names[@]}"; do
        local d=0 p=${parent[$name]-}
        while [[ -n $p && $d -lt 50 ]]; do (( d++ )); p=${parent[$p]-}; done
        local t=${stime[$name]:-9999999999}
        [[ $name == current ]] && t=9999999999
        keyed+=("$t"$'\t'"$d"$'\t'"$name")
    done
    local -a order
    mapfile -t order < <(printf '%s\n' "${keyed[@]}" | sort -n)
    for row in "${order[@]}"; do
        tsv_split f "$row"
        local d=${f[1]} n=${f[2]} label date ram=""
        printf -v label '%*s' $(( d * 2 )) ""
        if [[ $n == current ]]; then
            T "NOW"; label+="${C[accent]}${G[btn_start]} $REPLY${C[norm]}"
            date=""
        else
            label+="${G[m_snapshot]:-*} $n"
            fmt_time "${stime[$n]}"; date=$REPLY
            [[ ${vm[$n]} == 1 ]] && { T Yes; ram=$REPLY; }
        fi
        table_row "$label"$'\t'"$ram"$'\t'"$date"$'\t'"${desc[$n]%%$'\x1f'*}"
        c_sel "$REPLY" "$n"
    done
}
guest_snapshots_key() {
    local s=${2-}
    case $1 in
        n) act_snapshot_new ;;
        R) act_snapshot_rollback "$s" ;;
        d) act_snapshot_delete "$s" ;;
        *) return 1 ;;
    esac
    return 0
}
guest_snapshots_enter() {
    local s=$1
    [[ -n $s ]] || return
    if [[ $s == current ]]; then act_snapshot_new; return; fi
    local -a items=()
    T "Rollback"; items+=(rollback "$REPLY")
    T "Edit"; items+=(edit "$REPLY")
    T "Remove"; items+=(remove "$REPLY")
    dlg_menu "Snapshot" "$s" "${items[@]}" || return
    case $REPLY in
        rollback) act_snapshot_rollback "$s" ;;
        remove) act_snapshot_delete "$s" ;;
        edit)
            local p="/nodes/$CTX_NODE/$CTX_TYPE/$CTX_VMID/snapshot/$s/config"
            api_kv "$p"
            dlg_input "Snapshot $s" "Description:" "${API_KV[description]-}" || return
            api_exec_sync "Snapshot $s - Edit" set "$p" --description "$REPLY"
            content_load 1 ;;
    esac
}


# ---------------------------------------------------------------------------
# Register the shared panels for both guest types: v_<type>_<id> wrappers.
# ---------------------------------------------------------------------------
for _t in qemu lxc; do
    eval "
v_${_t}_summary() { guest_summary; }
v_${_t}_summary__key() { summary_key \"\$@\"; }
v_${_t}_tasks() { guest_tasks; }
v_${_t}_tasks__enter() { show_task_log \"\$1\" \"\$CTX_NODE\"; }
v_${_t}_backup() { guest_backup; }
v_${_t}_backup__enter() { guest_backup_enter \"\$1\"; }
v_${_t}_backup__key() { guest_backup_key \"\$@\"; }
v_${_t}_replication() { guest_replication; }
v_${_t}_snapshots() { guest_snapshots; }
v_${_t}_snapshots__key() { guest_snapshots_key \"\$@\"; }
v_${_t}_snapshots__enter() { guest_snapshots_enter \"\$1\"; }
v_${_t}_permissions() { acl_table \"/vms/\$CTX_VMID\"; }
v_${_t}_permissions__key() { acl_keys \"/vms/\$CTX_VMID\" \"\$@\"; }
v_${_t}_console() { guest_console_panel; }
v_${_t}_console__enter() { act_console; }
"
    VIEW_LIVE[v_${_t}_summary]=1
    VIEW_LIVE[v_${_t}_tasks]=1
    VIEW_HINT[v_${_t}_summary]="t:Timeframe"
    VIEW_HINT[v_${_t}_tasks]="Enter:Show_log"
    VIEW_HINT[v_${_t}_backup]="n:Backup_now r:Restore Enter:Actions"
    VIEW_HINT[v_${_t}_snapshots]="n:Take_Snapshot R:Rollback d:Remove Enter:Actions"
    VIEW_HINT[v_${_t}_permissions]="a:Add d:Remove"
done
unset _t

guest_console_panel() {
    c_blank
    if [[ $CTX_TYPE == lxc ]]; then
        Tf "Press Enter to attach to the container console (pct enter %s)." "$CTX_VMID"
    else
        api_kv "/nodes/$CTX_NODE/qemu/$CTX_VMID/config"
        if [[ -n ${API_KV[serial0]-} ]]; then
            Tf "Press Enter to open the serial console (qm terminal %s)." "$CTX_VMID"
        elif [[ ${API_KV[ostype]-} == l2[46] ]]; then
            T "No serial port: press Enter to open an SSH connection to this Linux VM."
        else
            T "No serial port: add one (Hardware > Add > Serial Port) to get a text console."
        fi
    fi
    c_sel "  ${C[accent]}${G[btn_console]}${C[norm]} $REPLY" console
    c_blank
    T "The TUI is suspended while the console runs."
    c_add "  ${C[dim]}$REPLY${C[norm]}"
    [[ $CTX_TYPE == qemu ]] && { T "Exit the serial console with Ctrl+O."; c_add "  ${C[dim]}$REPLY${C[norm]}"; }
}

# ---------------------------------------------------------------------------
# IP addresses of a guest for the grids, cached 60 s: guest_ip_cached <id>
# Containers: /interfaces; VMs: guest agent when enabled, otherwise the
# neighbour (ARP) table of the local node matched against the MAC addresses.
# ---------------------------------------------------------------------------
declare -gA IPCACHE=() IPCACHE_T=()
NEIGH_CACHE="" NEIGH_T=0
guest_ip_cached() {
    local id=$1 t=${R_TYPE[$1]-} node=${R_NODE[$1]-} vmid=${R_VMID[$1]-} row ips="" k mac ip lladdr
    local -a f
    now
    if [[ -v IPCACHE[$id] ]] && (( NOW - IPCACHE_T[$id] < 60 )); then REPLY=${IPCACHE[$id]}; return; fi
    if [[ ${R_STATUS[$id]-} == running && -n $node ]]; then
        if [[ $t == lxc ]]; then
            if api_get rows "/nodes/$node/lxc/$vmid/interfaces" "" "name,inet"; then
                for row in "${API_ROWS[@]}"; do
                    tsv_split f "$row"
                    [[ ${f[0]} == lo || -z ${f[1]-} ]] && continue
                    ips+="${f[1]%/*},"
                done
            fi
        else
            api_kv "/nodes/$node/qemu/$vmid/config"
            local -A cfg=(); for k in "${!API_KV[@]}"; do cfg[$k]=${API_KV[$k]}; done
            if [[ ${cfg[agent]-} == 1* || ${cfg[agent]-} == *enabled=1* ]] && \
                api_get rows "/nodes/$node/qemu/$vmid/agent/network-get-interfaces" "" "@result.*.ip-addresses;ip-address,ip-address-type"; then
                for row in "${API_ROWS[@]}"; do
                    [[ $row == *ipv4 && $row != 127.* ]] && ips+="${row%%$'\t'*},"
                done
            elif [[ $node == "$LOCAL_NODE" ]]; then
                (( NOW - NEIGH_T > 30 )) && { NEIGH_CACHE=$(ip -4 neigh show 2>/dev/null); NEIGH_T=$NOW; }
                for k in "${!cfg[@]}"; do
                    [[ $k =~ ^net[0-9]+$ && ${cfg[$k]} =~ ([0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}) ]] || continue
                    mac=${BASH_REMATCH[1],,}
                    while read -r ip _ _ _ lladdr _; do [[ ${lladdr,,} == "$mac" ]] && ips+="$ip,"; done <<< "$NEIGH_CACHE"
                done
            fi
        fi
    fi
    REPLY=${ips%,}
    IPCACHE[$id]=$REPLY IPCACHE_T[$id]=$NOW
}
