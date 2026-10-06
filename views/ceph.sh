# shellcheck shell=bash
# views/ceph.sh - Ceph panels: Datacenter > Ceph and Node > Ceph (Status,
# Configuration, Monitor, OSD, CephFS, Pools, Log), including the
# installation / initialisation wizard.

# Shared status summary: ceph_status_view <status path>
ceph_status_view() {
    local p=$1 k
    if ! api_kv "$p"; then
        ceph_not_installed
        return
    fi
    local st=${API_KV[health.status]-}
    status_color "$st"; [[ $st == HEALTH_OK ]] && STATUS_C=${C[ok]}; [[ $st == HEALTH_WARN ]] && STATUS_C=${C[warn]}
    c_section "Health"
    c_kv "Status" "${STATUS_C}${st}${C[norm]}"
    for k in $(printf '%s\n' "${!API_KV[@]}" | grep '^health\.checks\.[A-Z_]*\.summary\.message$' | sort); do
        local name=${k#health.checks.}; name=${name%%.*}
        local sev=${API_KV[health.checks.$name.severity]-}
        local col=${C[warn]}; [[ $sev == HEALTH_ERR ]] && col=${C[err]}
        c_add "  ${col}${G[bullet]} ${name}${C[norm]}: ${API_KV[$k]}"
    done
    c_blank
    c_section "Services"
    c_kv "Monitors" "${API_KV[monmap.num_mons]:-?} (quorum: ${API_KV[quorum_names]-})"
    c_kv "Managers" "${API_KV[mgrmap.num_standbys]:-0} standby, active: ${API_KV[mgrmap.available]:-?}"
    c_kv "OSDs" "${API_KV[osdmap.num_osds]:-0} total, ${API_KV[osdmap.num_up_osds]:-0} up, ${API_KV[osdmap.num_in_osds]:-0} in"
    c_kv "MDS" "${API_KV[fsmap.up]:-0} up, ${API_KV[fsmap.in]:-0} in"
    c_blank
    c_section "Performance"
    c_kv "Placement Groups" "${API_KV[pgmap.num_pgs]:-0} (pools: ${API_KV[pgmap.num_pools]:-0})"
    for k in $(printf '%s\n' "${!API_KV[@]}" | grep '^pgmap\.pgs_by_state\.[0-9]*\.state_name$' | sort -V); do
        local i=${k#pgmap.pgs_by_state.}; i=${i%%.*}
        c_add "  ${G[bullet]} ${API_KV[$k]}: ${API_KV[pgmap.pgs_by_state.$i.count]-}"
    done
    usage_line "Usage" "${API_KV[pgmap.bytes_used]:-0}" "${API_KV[pgmap.bytes_total]:-0}" "$CONTENT_W"; c_add "$REPLY"
    c_kv "Reads" "$(fmt_rate "${API_KV[pgmap.read_bytes_sec]:-0}"; printf '%s' "$REPLY")"
    c_kv "Writes" "$(fmt_rate "${API_KV[pgmap.write_bytes_sec]:-0}"; printf '%s' "$REPLY")"
}

ceph_not_installed() {
    c_msg warn "Ceph is not installed or not initialized on this node."
    c_add ""
    c_add "  ${C[dim]}${API_ERR}${C[norm]}"
    c_blank
    T "Press 'I' to install Ceph, then 'N' to initialize the configuration (first node only)."
    c_add "  $REPLY"
}

# Install Ceph in a terminal (same as the web UI wizard, which runs pveceph).
ceph_install() {
    local -a items=() rel=()
    local row
    if api_get rows "/nodes/$CTX_NODE/ceph/releases" "" "name,version"; then
        for row in "${API_ROWS[@]}"; do items+=("${row%%$'\t'*}" "${row#*$'\t'}"); done
    fi
    (( ${#items[@]} )) || items=(squid "Ceph 19.2 Squid")
    local version repo
    version=${CRUD_ANSWER[version]-}
    [[ -z $version ]] && { dlg_menu "Install Ceph" "Ceph version:" "${items[@]}" || return 0; version=$REPLY; }
    repo=${CRUD_ANSWER[repository]-}
    [[ -z $repo ]] && { dlg_menu "Install Ceph" "Repository:" no-subscription "No-Subscription" enterprise "Enterprise (subscription required)" test "Test" || return 0; repo=$REPLY; }
    node_cmd "$CTX_NODE" bash -c "pveceph install --version '$version' --repository '$repo'; echo; read -rp '[Enter] to return to pvetty' _"
    content_load 1
}

ceph_init() {
    form_reset
    FORM_FIRST="network cluster-network size min_size pg_bits disable_cephx"
    form_run "Ceph: Initialize Configuration" POST "/nodes/$CTX_NODE/ceph/init" || return 0
    if dlg_yesno "Ceph" "Create the first monitor and manager on '$CTX_NODE' now?"; then
        api_exec_sync "Create Ceph monitor" create "/nodes/$CTX_NODE/ceph/mon/$CTX_NODE"
    fi
    content_load 1
}

# Start / stop / restart a Ceph service: ceph_service <action> <service> <node>
ceph_service() {
    api_exec "Ceph $2 - ${1^}" create "/nodes/${3:-$CTX_NODE}/ceph/$1" --service "$2"
}

ceph_global_keys() {
    case $1 in
        I) ceph_install ;;
        N) ceph_init ;;
        F)
            form_reset
            FORM_GET=/cluster/ceph/flags
            local row; api_get rows /cluster/ceph/flags "" "name,value"
            for row in "${API_ROWS[@]}"; do FORM_VAL[${row%%$'\t'*}]=${row#*$'\t'}; done
            form_run "Manage Global Flags" PUT /cluster/ceph/flags && content_load 1 ;;
        *) return 1 ;;
    esac
    return 0
}

# ---------------------------------------------------------------------------
v_dc_ceph() { ceph_status_view /cluster/ceph/status; }
v_dc_ceph__key() { ceph_global_keys "$@"; }
VIEW_LIVE[v_dc_ceph]=1
VIEW_HINT[v_dc_ceph]="F:Global_Flags I:Install N:Initialize"

v_node_ceph() { ceph_status_view "/nodes/$CTX_NODE/ceph/status"; }
v_node_ceph__key() { ceph_global_keys "$@"; }
VIEW_LIVE[v_node_ceph]=1
VIEW_HINT[v_node_ceph]="I:Install N:Initialize F:Global_Flags"

v_node_cephconfig() {
    c_section "Configuration (/etc/pve/ceph.conf)"
    if api_get rows "/nodes/$CTX_NODE/ceph/cfg/raw" "" ""; then c_text "${API_ROWS[*]}"; else c_api_error; fi
    c_blank
    c_section "Configuration Database"
    view_table "/nodes/$CTX_NODE/ceph/cfg/db" "" "section:WHO:16|name:Option:*|value:Value:*|level:Level:10|can_update_at_runtime:Runtime Updatable:18:bool" -1
    c_blank
    c_section "Crush Map"
    if api_get rows "/nodes/$CTX_NODE/ceph/crush" "" ""; then c_text "${API_ROWS[*]}"; else c_api_error; fi
}

# Monitors and managers: "mon|name|host", "mgr|name|host".
v_node_cephmon() {
    local row
    local -a f
    c_section "Monitor"
    table_spec "name:Name:14|host:Host:12|addr:Address:*|state:Status:10|quorum:Quorum:8:bool|ceph_version:Version:*"
    if api_get rows "/nodes/$CTX_NODE/ceph/mon" "" "$TS_FIELDS"; then
        table_header
        for row in "${API_ROWS[@]}"; do tsv_split f "$row"; table_row "$row"; c_sel "$REPLY" "mon|${f[0]}|${f[1]}"; done
        (( ${#API_ROWS[@]} )) || c_msg dim "No items"
    else ceph_not_installed; return
    fi
    c_blank
    c_section "Manager"
    table_spec "name:Name:14|host:Host:12|addr:Address:*|state:Status:10|ceph_version:Version:*"
    if api_get rows "/nodes/$CTX_NODE/ceph/mgr" "" "$TS_FIELDS"; then
        table_header
        for row in "${API_ROWS[@]}"; do tsv_split f "$row"; table_row "$row"; c_sel "$REPLY" "mgr|${f[0]}|${f[1]}"; done
        (( ${#API_ROWS[@]} )) || c_msg dim "No items"
    fi
}
crud v_node_cephmon:mon label="Monitor" add="/nodes/{?host:Host:choice_nodes}/ceph/mon/{?monid:Monitor ID (usually the node name)}" \
    del="/nodes/{2}/ceph/mon/{1}" noedit=1 async=1
crud v_node_cephmon:mgr label="Manager" add="/nodes/{?host:Host:choice_nodes}/ceph/mgr/{?id:Manager ID (usually the node name)}" \
    del="/nodes/{2}/ceph/mgr/{1}" noedit=1 async=1
CRUD[v_node_cephmon|extra]="S:Start x:Stop R:Restart"
v_node_cephmon__key() {
    local kind=${2%%|*} rest=${2#*|} name host
    name=${rest%%|*} host=${rest#*|}
    case $1 in
        S) [[ -n $2 ]] && ceph_service start "$kind.$name" "$host" ;;
        x) [[ -n $2 ]] && ceph_service stop "$kind.$name" "$host" ;;
        R) [[ -n $2 ]] && ceph_service restart "$kind.$name" "$host" ;;
        *) ceph_global_keys "$1" ;;
    esac
}
VIEW_LIVE[v_node_cephmon]=1

# OSDs: "osd|id|host".
v_node_cephosd() {
    local row
    local -a f
    table_spec "name:Name:10|host:Host:12|device_class:Class:6|osdtype:OSD Type:9|status:Status:8:status|in:In:4|crush_weight:Weight:8:s:r|percent_used:Used %:8:s:r|total_space:Total:11:b:r|blfsdev:Device:*|id:ID:4"
    # The OSD tree (root > hosts > OSDs): every node, keeping the OSDs.
    if ! api_get rows "/nodes/$CTX_NODE/ceph/osd" "" "@root.**;name,host,device_class,osdtype,status,in,crush_weight,percent_used,total_space,blfsdev,id,type"; then
        ceph_not_installed; return
    fi
    local -a osds=()
    for row in "${API_ROWS[@]}"; do [[ $row == *$'\t'osd ]] && osds+=("$row"); done
    API_ROWS=("${osds[@]}")
    table_header
    for row in "${API_ROWS[@]}"; do
        tsv_split f "$row"
        [[ ${f[7]} =~ ^[0-9.]+$ ]] && f[7]=$(printf '%.2f' "${f[7]}")
        table_row "${f[0]}"$'\t'"${f[1]}"$'\t'"${f[2]}"$'\t'"${f[3]}"$'\t'"${f[4]}"$'\t'"${f[5]}"$'\t'"${f[6]}"$'\t'"${f[7]}"$'\t'"${f[8]}"$'\t'"${f[9]}"$'\t'"${f[10]}"
        c_sel "$REPLY" "osd|${f[10]}|${f[1]}"
    done
    (( ${#API_ROWS[@]} )) || c_msg dim "No OSD. Press 'a' to create one."
}
crud v_node_cephosd:osd label="OSD" add="/nodes/{node}/ceph/osd" del="/nodes/{2}/ceph/osd/{1}" delargs="--cleanup 1" \
    noedit=1 async=1 first="dev db_dev db_dev_size wal_dev wal_dev_size encrypted crush-device-class osds-per-device" \
    choices="dev:choice_unused_disks db_dev:choice_unused_disks wal_dev:choice_unused_disks"
CRUD[v_node_cephosd|extra]="o:Out i:In S:Start x:Stop R:Restart s:Scrub F:Global_Flags"
v_node_cephosd__key() {
    local rest=${2#*|} id host
    id=${rest%%|*} host=${rest#*|}
    case $1 in
        o) [[ -n $2 ]] && api_exec_sync "OSD $id - Out" create "/nodes/$host/ceph/osd/$id/out" ;;
        i) [[ -n $2 ]] && api_exec_sync "OSD $id - In" create "/nodes/$host/ceph/osd/$id/in" ;;
        S) [[ -n $2 ]] && ceph_service start "osd.$id" "$host" ;;
        x) [[ -n $2 ]] && ceph_service stop "osd.$id" "$host" ;;
        R) [[ -n $2 ]] && ceph_service restart "osd.$id" "$host" ;;
        s) [[ -n $2 ]] && api_exec_sync "OSD $id - Scrub" create "/nodes/$host/ceph/osd/$id/scrub" ;;
        *) ceph_global_keys "$1"; return ;;
    esac
    content_load 1
    return 0
}
v_node_cephosd__enter() {
    local rest=${1#*|} id host
    id=${rest%%|*} host=${rest#*|}
    [[ -n $1 ]] || return
    api_get kv "/nodes/$host/ceph/osd/$id/metadata" || { dlg_msg "OSD" "$API_ERR"; return; }
    printf '%s\n' "${API_ROWS[@]}" | tr '\t\036' '=,' > "$RUN_DIR/osd.txt"
    pager_show "$RUN_DIR/osd.txt" "OSD $id"
}
VIEW_LIVE[v_node_cephosd]=1

# CephFS and metadata servers: "fs|name", "mds|name|host".
v_node_cephfs() {
    local row
    local -a f
    c_section "CephFS"
    if ! api_get rows "/nodes/$CTX_NODE/ceph/fs" "" "name,data_pool,metadata_pool"; then ceph_not_installed; return; fi
    TABLE_KEY_PREFIX="fs|"
    view_table "/nodes/$CTX_NODE/ceph/fs" "" "name:Name:20|data_pool:Data Pool:*|metadata_pool:Metadata Pool:*"
    c_blank
    c_section "Metadata Servers"
    table_spec "name:Name:16|host:Host:12|addr:Address:*|state:Status:16|ceph_version:Version:*"
    if api_get rows "/nodes/$CTX_NODE/ceph/mds" "" "$TS_FIELDS"; then
        table_header
        for row in "${API_ROWS[@]}"; do tsv_split f "$row"; table_row "$row"; c_sel "$REPLY" "mds|${f[0]}|${f[1]}"; done
        (( ${#API_ROWS[@]} )) || c_msg dim "No items"
    fi
}
crud v_node_cephfs:fs label="CephFS" add="/nodes/{node}/ceph/fs/{?name:Name}" noedit=1 nodel=1 async=1 first="pg_num add-storage"
crud v_node_cephfs:mds label="Metadata Server" add="/nodes/{?host:Host:choice_nodes}/ceph/mds/{?name:Name (e.g. node name)}" \
    del="/nodes/{2}/ceph/mds/{1}" noedit=1 async=1 first="hotstandby"
CRUD[v_node_cephfs|extra]="S:Start x:Stop R:Restart"
v_node_cephfs__key() {
    if [[ ${2%%|*} == fs && ( $1 == d || $1 == DEL ) ]]; then ceph_fs_destroy "${2#*|}"; return 0; fi
    [[ ${2%%|*} == mds ]] || return 1
    local rest=${2#*|}
    case $1 in
        S) ceph_service start "mds.${rest%%|*}" "${rest#*|}" ;;
        x) ceph_service stop "mds.${rest%%|*}" "${rest#*|}" ;;
        R) ceph_service restart "mds.${rest%%|*}" "${rest#*|}" ;;
        *) return 1 ;;
    esac
}

# Destroy a CephFS like the web UI: its storages are disabled and unmounted
# first, then the file system, its pools and the storages are removed.
ceph_fs_destroy() {
    local fs=$1 row
    local -a f
    [[ -n $fs ]] || return
    Tf "Destroy CephFS '%s' with its pools and storages? Its metadata servers are stopped first. All data will be lost." "$fs"
    confirm "$REPLY" || return
    api_get rows /storage "" "storage,type,fs-name" || return
    for row in "${API_ROWS[@]}"; do
        tsv_split f "$row"
        [[ ${f[1]} == cephfs && ( ${f[2]} == "$fs" || ( -z ${f[2]} && ${f[0]} == "$fs" ) ) ]] || continue
        api_exec_sync "Disable storage ${f[0]}" set "/storage/${f[0]}" --disable 1
        [[ $CTX_NODE == "$LOCAL_NODE" ]] && umount "/mnt/pve/${f[0]}" 2>/dev/null
    done
    # Ceph refuses to remove a file system while MDS daemons are active.
    if api_get rows "/nodes/$CTX_NODE/ceph/mds" "" "name,host,state"; then
        local -a mds=("${API_ROWS[@]}")
        for row in "${mds[@]}"; do
            tsv_split f "$row"
            [[ ${f[2]} == *stopped* || ${f[2]} == unknown ]] && continue
            api_exec_sync "Stop mds.${f[0]}" create "/nodes/${f[1]:-$CTX_NODE}/ceph/stop" --service "mds.${f[0]}"
        done
        sleep 3
    fi
    api_exec "CephFS $fs - Destroy" delete "/nodes/$CTX_NODE/ceph/fs/$fs" --remove-storages 1 --remove-pools 1
    content_load 1
}

# Pools.
v_node_cephpools() {
    local row
    local -a f
    table_spec "pool_name:Name:16|type:Type:10|size:Size/min:9|pg_num:# of PGs:9:s:r|pg_autoscale_mode:Autoscale:10|crush_rule_name:CRUSH Rule:16|bytes_used:Used:11:b:r|percent_used:%:7:s:r|application:Application:*"
    if ! api_get rows "/nodes/$CTX_NODE/ceph/pool" "" "pool_name,type,size,min_size,pg_num,pg_autoscale_mode,crush_rule_name,bytes_used,percent_used,application_metadata"; then
        ceph_not_installed; return
    fi
    table_header
    for row in "${API_ROWS[@]}"; do
        tsv_split f "$row"
        local pct=${f[8]}; [[ $pct =~ ^[0-9.e-]+$ ]] && pct=$(printf '%.2f' "$(perl -e "print $pct*100")")
        local app=${f[9]}; app=${app//[\{\}\":]/ }
        table_row "${f[0]}"$'\t'"${f[1]}"$'\t'"${f[2]}/${f[3]}"$'\t'"${f[4]}"$'\t'"${f[5]}"$'\t'"${f[6]}"$'\t'"${f[7]}"$'\t'"$pct"$'\t'"$app"
        c_sel "$REPLY" "${f[0]}"
    done
    (( ${#API_ROWS[@]} )) || c_msg dim "No items"
}
crud v_node_cephpools label="Pool" add="/nodes/{node}/ceph/pool" edit="/nodes/{node}/ceph/pool/{1}" \
    del="/nodes/{node}/ceph/pool/{1}" delargs="--remove_storages 1" \
    first="name size min_size pg_num pg_autoscale_mode crush_rule application add_storages target_size target_size_ratio pg_num_min erasure-coding" \
    choices="crush_rule:choice_ceph_rules"
VIEW_LIVE[v_node_cephpools]=1

v_node_cephlog() {
    local l
    api_get rows "/nodes/$CTX_NODE/ceph/log" "limit=500" "t" || { ceph_not_installed; return; }
    for l in "${API_ROWS[@]}"; do c_add "$l"; done
    C_SCROLL=999999
}
VIEW_LIVE[v_node_cephlog]=1
