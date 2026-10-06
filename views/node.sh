# shellcheck shell=bash
# views/node.sh - "Node" panels.

view_menu node \
    "search|Search|m_search|0" \
    "summary|Summary|m_summary|0" \
    "notes|Notes|m_notes|0" \
    "shell|Shell|m_shell|0" \
    "system|System|m_system|0" \
    "network|Network|m_network|1" \
    "certificates|Certificates|m_cert|1" \
    "dns|DNS|m_dns|1" \
    "hosts|Hosts|m_hosts|1" \
    "options|Options|m_options|1" \
    "time|Time|m_time|1" \
    "syslog|System Log|m_syslog|1" \
    "updates|Updates|m_updates|0" \
    "repos|Repositories|m_repos|1" \
    "firewall|Firewall|m_firewall|0" \
    "fwoptions|Options|m_options|1" \
    "fwlog|Log|m_syslog|1" \
    "disks|Disks|m_disks|0" \
    "lvm|LVM|m_lvm|1" \
    "lvmthin|LVM-Thin|m_lvmthin|1" \
    "directory|Directory|m_dir|1" \
    "zfs|ZFS|m_zfs|1" \
    "ceph|Ceph|m_ceph|0" \
    "cephconfig|Configuration|m_options|1" \
    "cephmon|Monitor|m_monitor|1" \
    "cephosd|OSD|m_disks|1" \
    "cephfs|CephFS|m_dir|1" \
    "cephpools|Pools|m_storage|1" \
    "cephlog|Log|m_syslog|1" \
    "replication|Replication|m_replication|0" \
    "tasks|Task History|m_tasks|0" \
    "subscription|Subscription|m_subscription|0"

title_node() { Tf "Node '%s'" "$CTX_NODE"; }

_grid_match_node() { [[ ${R_NODE[$1]-} == "$CTX_NODE" && ${R_TYPE[$1]} != node ]] && _grid_match_all "$1"; }
v_node_search() { res_grid _grid_match_node; }
v_node_search__enter() { grid_goto "$1"; }
v_node_search__key() { grid_key "$@"; }
VIEW_HINT[v_node_search]="$GRID_HINT"
VIEW_LIVE[v_node_search]=1

# ---------------------------------------------------------------------------
v_node_summary() {
    local n=$CTX_NODE
    if ! api_row "/nodes/$n/status" "" "cpu*10000,wait*10000,loadavg,memory.used,memory.total,swap.used,swap.total,rootfs.used,rootfs.total,ksm.shared,cpuinfo.cpus,cpuinfo.model,cpuinfo.sockets,kversion,pveversion,boot-info.mode,boot-info.secureboot,uptime"; then
        c_api_error; return
    fi
    local -a s=("${API_F[@]}")
    local w=$CONTENT_W
    fmt_uptime "${s[17]}"
    Tf "%s (Uptime: %s)" "$n" "$REPLY"
    c_add "${C[title]}${REPLY}${C[norm]}"
    repeat "${G[h]}" "$w"; c_add "${C[border]}${REPLY}${C[norm]}"
    # The status call samples /proc/stat itself (0 on the first call): use the
    # value collected by pvestatd (cluster resources) like the web UI does.
    local cpu=${R_CPU[node/$n]:-${s[0]}}
    usage_line "CPU usage" "$cpu" "${s[10]}" "$w" cpu; c_add "$REPLY"
    fmt_pct "${s[1]}"; c_kv "IO delay" "$REPLY" 18
    c_kv "Load average" "${s[2]//,/, }" 18
    usage_line "RAM usage" "${s[3]}" "${s[4]}" "$w"; c_add "$REPLY"
    fmt_bytes "${s[9]:-0}"; c_kv "KSM sharing" "$REPLY" 18
    usage_line "/ HD space" "${s[7]}" "${s[8]}" "$w"; c_add "$REPLY"
    usage_line "SWAP usage" "${s[5]}" "${s[6]}" "$w"; c_add "$REPLY"
    local sock="Socket"; (( ${s[12]:-1} > 1 )) && sock="Sockets"
    T "$sock"
    c_kv "CPU(s)" "${s[10]} x ${s[11]} (${s[12]} $REPLY)" 18
    c_kv "Kernel Version" "${s[13]}" 18
    local bm=${s[15]^^}
    [[ ${s[15]} == efi && ${s[16]} == 1 ]] && bm="EFI (Secure Boot)"
    c_kv "Boot Mode" "$bm" 18
    c_kv "Manager Version" "${s[14]}" 18
    c_blank
    rrd_graphs "/nodes/$n/rrddata" \
        "CPU usage|pct|cpu*10000|iowait*10000" \
        "Server load|load|loadavg*100" \
        "Memory usage|b|memused:i|memtotal:i" \
        "Network traffic|rate|netin:i|netout:i"
}
v_node_summary__key() { summary_key "$@"; }
VIEW_LIVE[v_node_summary]=1
VIEW_HINT[v_node_summary]="t:Timeframe"

v_node_notes() {
    api_kv "/nodes/$CTX_NODE/config"
    if [[ -n ${API_KV[description]-} ]]; then c_text "${API_KV[description]}"
    else c_msg dim "No notes. Press 'e' to edit."
    fi
}
v_node_notes__key() { [[ $1 == e ]] && { act_edit_notes "/nodes/$CTX_NODE/config"; return 0; }; return 1; }
VIEW_HINT[v_node_notes]="e:Edit"

v_node_shell() {
    c_blank
    Tf "Press Enter to open a shell on node '%s'." "$CTX_NODE"
    c_sel "  ${C[accent]}${G[btn_shell]}${C[norm]} $REPLY" shell
    c_blank
    T "The TUI is suspended while the shell runs; type 'exit' to come back."
    c_add "  ${C[dim]}$REPLY${C[norm]}"
}
v_node_shell__enter() { act_node_shell; }

# System = services list.
v_node_system() {
    view_table "/nodes/$CTX_NODE/services" "" "name:Name:22|unit-state:Unit:10|active-state:State:10:status|desc:Description:*"
}
_svc_action() {
    local a=$1 s=$2
    [[ -n $s ]] || return
    Tf "%s service '%s'?" "${a^}" "$s"; confirm "$REPLY" || return
    api_exec "SRV $s - ${a^}" create "/nodes/$CTX_NODE/services/$s/$a"
}
v_node_system__key() {
    case $1 in
        S) _svc_action start "$2" ;;
        x) _svc_action stop "$2" ;;
        R) _svc_action restart "$2" ;;
        *) return 1 ;;
    esac
    return 0
}
v_node_system__enter() {
    node_cmd "$CTX_NODE" bash -c "systemctl status --no-pager -l '$1' 2>&1 | \${PAGER:-less}"
}
VIEW_HINT[v_node_system]="Enter:Status S:Start x:Stop R:Restart"

# Network: interfaces with pending changes, Apply / Revert like the web UI.
# Row keys "iface|type".
v_node_network() {
    local row
    local -a f
    table_spec "iface:Name:12|type:Type:10|active:Active:7:bool|autostart:Autostart:10:bool|bridge_vlan_aware:VLAN aware:11:bool|bridge_ports:Ports/Slaves:14|bond_mode:Bond Mode:10|cidr:CIDR:18|gateway:Gateway:15|comments:Comment:*"
    api_get rows "/nodes/$CTX_NODE/network" "" "iface,type,active,autostart,bridge_vlan_aware,bridge_ports,bond_mode,cidr,gateway,comments" || { c_api_error; return; }
    table_sort 0
    table_header
    for row in "${API_ROWS[@]}"; do tsv_split f "$row"; table_row "$row"; c_sel "$REPLY" "${f[0]}|${f[1]}"; done
    # Pending changes (interfaces.new), local node only.
    if [[ $CTX_NODE == "$LOCAL_NODE" && -e /etc/network/interfaces.new ]]; then
        c_blank
        c_section "Pending changes (Apply Configuration to activate)"
        local l
        while IFS= read -r l; do
            case $l in
                +*) c_add "${C[ok]}$l${C[norm]}" ;;
                -*) c_add "${C[err]}$l${C[norm]}" ;;
                *) c_add "${C[dim]}$l${C[norm]}" ;;
            esac
        done < <(diff -u /etc/network/interfaces /etc/network/interfaces.new | tail -n +3)
    fi
}
crud v_node_network label="Network Device" add="/nodes/{node}/network" edit="/nodes/{node}/network/{1}" \
    editfix="type={2}" del="/nodes/{node}/network/{1}" \
    types="bridge,bond,vlan,eth,alias,OVSBridge,OVSBond,OVSPort,OVSIntPort,vnet,fabric" \
    first="iface cidr gateway cidr6 gateway6 autostart bridge_ports bridge_vlan_aware slaves bond_mode bond-primary bond_xmit_hash_policy vlan-raw-device vlan-id mtu comments" \
    typefields="bridge:iface cidr gateway cidr6 gateway6 autostart bridge_vlan_aware bridge_ports bridge_vids mtu comments;bond:iface cidr gateway cidr6 gateway6 autostart slaves bond_mode bond-primary bond_xmit_hash_policy mtu comments;vlan:iface cidr gateway cidr6 gateway6 autostart vlan-raw-device vlan-id mtu comments;eth:iface cidr gateway cidr6 gateway6 autostart mtu comments;alias:iface cidr gateway cidr6 gateway6 comments;OVSBridge:iface cidr gateway cidr6 gateway6 autostart ovs_ports ovs_options mtu comments;OVSBond:iface ovs_bridge ovs_bonds bond_mode ovs_tag ovs_options autostart comments;OVSPort:iface ovs_bridge ovs_tag ovs_options autostart comments;OVSIntPort:iface ovs_bridge cidr gateway cidr6 gateway6 ovs_tag ovs_options mtu autostart comments" \
    extra="A:Apply_Configuration X:Revert"
v_node_network__key() {
    case $1 in
        A)
            T "Apply the pending network configuration (ifreload)?"; confirm "$REPLY" || return 0
            api_exec "Apply network configuration" set "/nodes/$CTX_NODE/network" ;;
        X)
            T "Revert the pending network changes?"; confirm "$REPLY" || return 0
            api_exec_sync "Revert network changes" delete "/nodes/$CTX_NODE/network"; content_load 1 ;;
        *) return 1 ;;
    esac
    return 0
}

v_node_dns() {
    api_kv "/nodes/$CTX_NODE/dns" || { c_api_error; return; }
    c_kv_sel "Search domain" "${API_KV[search]-}" search
    c_kv_sel "DNS server 1" "${API_KV[dns1]-}" dns1
    c_kv_sel "DNS server 2" "${API_KV[dns2]-}" dns2
    c_kv_sel "DNS server 3" "${API_KV[dns3]-}" dns3
}
v_node_dns__enter() { _option_form "DNS" "/nodes/$CTX_NODE/dns" "search dns1 dns2 dns3"; }
v_node_dns__key() { [[ $1 == e ]] && { v_node_dns__enter; return 0; }; return 1; }
VIEW_HINT[v_node_dns]="Enter:Edit"

v_node_hosts() {
    api_kv "/nodes/$CTX_NODE/hosts" || { c_api_error; return; }
    c_text "${API_KV[data]-}"
}
v_node_hosts__key() {
    [[ $1 == e ]] || return 1
    local f="$RUN_DIR/hosts" ed=${CFG[editor]:-${VISUAL:-${EDITOR:-}}}
    [[ -z $ed ]] && { command -v nano >/dev/null && ed=nano || ed=vi; }
    api_kv "/nodes/$CTX_NODE/hosts" || return 0
    local digest=${API_KV[digest]-}
    printf '%s' "${API_KV[data]-}" | tr '\037' '\n' > "$f"
    local before; before=$(cksum < "$f")
    # shellcheck disable=SC2086
    term_run $ed "$f"
    [[ $(cksum < "$f") == "$before" ]] && return 0
    api_exec_sync "Edit /etc/hosts" create "/nodes/$CTX_NODE/hosts" --data "$(< "$f")"$'\n' --digest "$digest"
    content_load 1
    return 0
}
VIEW_HINT[v_node_hosts]="e:Edit"

v_node_options() {
    api_kv "/nodes/$CTX_NODE/config" || { c_api_error; return; }
    local v
    v=${API_KV[startall-onboot-delay]:-}; [[ -z $v ]] && v="${C[dim]}0${C[norm]}"; c_kv_sel "Start on boot delay" "$v" startall-onboot-delay 32
    v=${API_KV[wakeonlan]:-}; [[ -z $v ]] && { T "none"; v="${C[dim]}$REPLY${C[norm]}"; }; c_kv_sel "MAC address for Wake on LAN" "$v" wakeonlan 32
    v=${API_KV[ballooning-target]:-}; [[ -z $v ]] && v="${C[dim]}Default (80%)${C[norm]}"; c_kv_sel "RAM usage target for ballooning" "$v" ballooning-target 32
}
v_node_options__enter() { _option_form "Node Options" "/nodes/$CTX_NODE/config" "$1"; }
v_node_options__key() { [[ $1 == e ]] && { v_node_options__enter "$2"; return 0; }; return 1; }
VIEW_HINT[v_node_options]="Enter:Edit"

v_node_time() {
    api_kv "/nodes/$CTX_NODE/time" || { c_api_error; return; }
    c_kv_sel "Time zone" "${API_KV[timezone]-}" timezone
    fmt_time "${API_KV[time]-}"; c_kv "Server time" "$REPLY (UTC)"
    fmt_time "${API_KV[localtime]-}"; c_kv "Local time" "$REPLY"
}
v_node_time__enter() {
    form_reset
    FORM_GET="/nodes/$CTX_NODE/time" FORM_ONLY=timezone
    [[ $CTX_NODE == "$LOCAL_NODE" ]] && choice_timezones && FORM_CHOICES[timezone]=$REPLY
    form_run "Time zone" PUT "/nodes/$CTX_NODE/time" && content_load 1
}
v_node_time__key() { [[ $1 == e ]] && { v_node_time__enter; return 0; }; return 1; }
VIEW_LIVE[v_node_time]=1
VIEW_HINT[v_node_time]="Enter:Edit"

v_node_syslog() {
    local l
    api_get rows "/nodes/$CTX_NODE/journal" "lastentries=500" "" || { c_api_error; return; }
    for l in "${API_ROWS[@]}"; do
        [[ $l == s=*\;i=* ]] && continue      # journal cursors
        c_add "$l"
    done
    C_SCROLL=999999                            # start at the end, like "tail"
}
VIEW_LIVE[v_node_syslog]=1

v_node_updates() {
    view_table "/nodes/$CTX_NODE/apt/update" "" "Package:Package:28|OldVersion:Version (current):22|Version:Version (new):22|Title:Description:*" 0 0
}
v_node_updates__key() {
    case $1 in
        R) api_exec "Update package database" create "/nodes/$CTX_NODE/apt/update" ;;
        u)
            Tf "Run 'apt-get dist-upgrade' on node '%s'?" "$CTX_NODE"; confirm "$REPLY" || return 0
            node_cmd "$CTX_NODE" bash -c 'apt-get dist-upgrade; echo; read -rp "[Enter] to return to pvetty" _' ;;
        *) return 1 ;;
    esac
    return 0
}
v_node_updates__enter() {
    api_get rows "/nodes/$CTX_NODE/apt/changelog" "name=$1" "" || { status_msg err "$API_ERR"; return; }
    printf '%s\n' "${API_ROWS[@]}" | tr '\037' '\n' > "$RUN_DIR/changelog.txt"
    pager_show "$RUN_DIR/changelog.txt" "Changelog: $1"
}
VIEW_HINT[v_node_updates]="R:Refresh u:Upgrade Enter:Changelog"

# Repositories: standard repositories and APT sources.
# Row keys "std|handle" and "repo|file|index".
v_node_repos() {
    local row n=0
    local -a f files counts
    c_section "Standard Repositories"
    TABLE_KEY_PREFIX="std|"
    view_table "/nodes/$CTX_NODE/apt/repositories" "" "@standard-repos;handle:Handle:*|name:Name:32|status:Configured:10:bool" 0
    c_blank
    c_section "Repositories"
    api_get rows "/nodes/$CTX_NODE/apt/repositories" "" "@files;path,repositories#" || { c_api_error; return; }
    for row in "${API_ROWS[@]}"; do files+=("${row%%$'\t'*}"); counts+=("${row#*$'\t'}"); done
    table_spec "Enabled:Enabled:8:bool|Types:Types:6|URIs:URIs:*|Suites:Suites:18|Components:Components:24|path:File:*"
    table_header
    api_get rows "/nodes/$CTX_NODE/apt/repositories" "" "@files.*.repositories;Enabled,Types,URIs,Suites,Components" || return
    local fi=0 idx=0
    for row in "${API_ROWS[@]}"; do
        while (( fi < ${#counts[@]} && idx >= counts[fi] )); do (( fi++, idx = 0 )); done
        table_row "$row"$'\t'"${files[fi]##*/}"
        c_sel "$REPLY" "repo|${files[fi]}|$idx"
        (( idx++, n++ ))
    done
    (( n )) || c_msg dim "No items"
}
VIEW_HINT[v_node_repos]="a:Add_standard e:Enable/Disable"
v_node_repos__key() {
    local kind=${2%%|*} rest=${2#*|}
    case $1 in
        a|INS)
            local row; local -a items=()
            api_get rows "/nodes/$CTX_NODE/apt/repositories" "" "@standard-repos;handle,name" || return 0
            for row in "${API_ROWS[@]}"; do items+=("${row%%$'\t'*}" "${row#*$'\t'}"); done
            if [[ -n ${CRUD_ANSWER[handle]-} ]]; then REPLY=${CRUD_ANSWER[handle]}
            else dlg_menu "Add: Repository" "Standard repository:" "${items[@]}" || return 0
            fi
            api_exec_sync "Add repository $REPLY" set "/nodes/$CTX_NODE/apt/repositories" --handle "$REPLY" ;;
        e|ENTER)
            [[ $kind == repo ]] || return 0
            local file=${rest%|*} idx=${rest##*|} row2 i=0 on=1
            api_get rows "/nodes/$CTX_NODE/apt/repositories" "" "@files;path"
            for row2 in "${API_ROWS[@]}"; do [[ $row2 == "$file" ]] && break; (( i++ )); done
            api_get rows "/nodes/$CTX_NODE/apt/repositories" "" "@files.$i.repositories;Enabled"
            [[ ${API_ROWS[idx]-0} == 1 ]] && on=0
            api_exec_sync "Repository $file #$idx - $( ((on)) && echo enable || echo disable)" create "/nodes/$CTX_NODE/apt/repositories" \
                --path "$file" --index "$idx" --enabled "$on" ;;
        *) return 1 ;;
    esac
    content_load 1
    return 0
}
v_node_repos__enter() { v_node_repos__key e "$1"; }

# Disks: S.M.A.R.T., Initialize with GPT, Wipe.
v_node_disks() {
    view_table "/nodes/$CTX_NODE/disks/list" "include-partitions=1" "devpath:Device:12|type:Type:9|used:Usage:16|size:Size:11:b:r|gpt:GPT:5:bool|model:Model:*|serial:Serial:16|health:S.M.A.R.T.:11|wearout:Wearout:8:s:r"
}
VIEW_HINT[v_node_disks]="Enter:S.M.A.R.T. G:Initialize_GPT W:Wipe_Disk"
v_node_disks__key() {
    local dev=$2
    [[ -n $dev ]] || return 1
    case $1 in
        G)
            Tf "Initialize %s with a new GPT partition table? ALL DATA ON THE DISK WILL BE LOST." "$dev"
            _disk_confirm "$dev" "$REPLY" || return 0
            api_exec "Initialize GPT $dev" create "/nodes/$CTX_NODE/disks/initgpt" --disk "$dev" ;;
        W)
            Tf "Wipe %s (partition table, signatures)? ALL DATA WILL BE LOST." "$dev"
            _disk_confirm "$dev" "$REPLY" || return 0
            api_exec "Wipe $dev" set "/nodes/$CTX_NODE/disks/wipedisk" --disk "$dev" ;;
        *) return 1 ;;
    esac
    return 0
}
# Destructive disk operations require typing the device name.
_disk_confirm() {
    [[ ${CRUD_ANSWER[confirm]-} == "$1" ]] && return 0
    dlg_input "Confirm" "$2"$'\n\n'"Type the device name ($1) to confirm:" "" || return 1
    [[ $REPLY == "$1" ]] || { status_msg warn "Cancelled"; return 1; }
}
v_node_disks__enter() {
    api_kv "/nodes/$CTX_NODE/disks/smart" "disk=$1" || { status_msg err "$API_ERR"; return; }
    if [[ -n ${API_KV[text]-} ]]; then
        printf '%s\n' "${API_KV[text]}" | tr '\037' '\n' > "$RUN_DIR/smart.txt"
    else
        api_get rows "/nodes/$CTX_NODE/disks/smart" "disk=$1" "@attributes;id,name,value,worst,threshold,raw,fail"
        { printf 'Health: %s\n\n%-4s %-28s %6s %6s %9s %s\n' "${API_KV[health]-}" ID Attribute Value Worst Threshold Raw
          printf '%s\n' "${API_ROWS[@]}" | awk -F'\t' '{printf "%-4s %-28s %6s %6s %9s %s\n",$1,$2,$3,$4,$5,$6}'; } > "$RUN_DIR/smart.txt"
    fi
    pager_show "$RUN_DIR/smart.txt" "S.M.A.R.T. $1"
}

v_node_lvm() {
    view_table "/nodes/$CTX_NODE/disks/lvm" "" "@children;name:Volume Group:24|lvcount:Number of LVs:15:s:r|size:Size:12:b:r|free:Free:12:b:r|children#:Physical Volumes:*"
}
crud v_node_lvm label="Volume Group" add="/nodes/{node}/disks/lvm" del="/nodes/{node}/disks/lvm/{1}" noedit=1 async=1 \
    delargs="--cleanup-config 1 --cleanup-disks 1" first="device name add_storage" choices="device:choice_unused_disks"

v_node_lvmthin() {
    local row
    local -a f
    table_spec "lv:Name:20|vg:Volume Group:16|lv_size:Size:12:b:r|used:Used:12:b:r|metadata_size:Metadata Size:14:b:r|metadata_used:Metadata Used:14:b:r"
    api_get rows "/nodes/$CTX_NODE/disks/lvmthin" "" "$TS_FIELDS" || { c_api_error; return; }
    table_header
    for row in "${API_ROWS[@]}"; do tsv_split f "$row"; table_row "$row"; c_sel "$REPLY" "${f[0]}|${f[1]}"; done
    (( ${#API_ROWS[@]} )) || c_msg dim "No items"
}
crud v_node_lvmthin label="Thinpool" add="/nodes/{node}/disks/lvmthin" del="/nodes/{node}/disks/lvmthin/{1}" noedit=1 async=1 \
    delargs="--volume-group {2} --cleanup-config 1 --cleanup-disks 1" first="device name add_storage" choices="device:choice_unused_disks"

v_node_directory() {
    local row
    local -a f
    table_spec "path:Path:24|device:Device:*|type:Type:8|options:Options:12|unitfile:Unit File:*"
    api_get rows "/nodes/$CTX_NODE/disks/directory" "" "$TS_FIELDS" || { c_api_error; return; }
    table_header
    for row in "${API_ROWS[@]}"; do tsv_split f "$row"; table_row "$row"; c_sel "$REPLY" "${f[0]##*/}"; done
    (( ${#API_ROWS[@]} )) || c_msg dim "No items"
}
crud v_node_directory label="Directory" add="/nodes/{node}/disks/directory" del="/nodes/{node}/disks/directory/{1}" noedit=1 async=1 \
    delargs="--cleanup-config 1 --cleanup-disks 1" first="device name filesystem add_storage" choices="device:choice_unused_disks"

v_node_zfs() {
    view_table "/nodes/$CTX_NODE/disks/zfs" "" "name:Name:20|size:Size:12:b:r|free:Free:12:b:r|alloc:Allocated:12:b:r|frag:Fragmentation:14:s:r|dedup:Deduplication:14:s:r|health:Health:*:status"
}
crud v_node_zfs label="ZFS Pool" add="/nodes/{node}/disks/zfs" del="/nodes/{node}/disks/zfs/{1}" noedit=1 async=1 \
    delargs="--cleanup-config 1 --cleanup-disks 1" first="name devices raidlevel compression ashift add_storage draid-config" \
    choices="devices:choice_unused_disks"
v_node_zfs__enter() {
    api_get json "/nodes/$CTX_NODE/disks/zfs/$1" "" "" || { dlg_msg "ZFS" "$API_ERR"; return; }
    printf '%s' "${API_ROWS[0]}" | perl -MJSON -e '
        my $d = decode_json(join("", <STDIN>));
        printf "Pool: %s\nState: %s\nStatus: %s\nAction: %s\nScan: %s\nErrors: %s\n\n", map { $d->{$_} // "" } qw(name state status action scan errors);
        sub walk { my ($n, $l) = @_; for my $c (@{ $n->{children} // [] }) {
            printf "%s%-30s %-10s %6s %6s %6s\n", "  " x $l, $c->{name}, $c->{state} // "", $c->{read} // "", $c->{write} // "", $c->{cksum} // "";
            walk($c, $l + 1) } }
        printf "%-30s %-10s %6s %6s %6s\n", "NAME", "STATE", "READ", "WRITE", "CKSUM";
        walk($d, 0);' > "$RUN_DIR/zfs.txt"
    pager_show "$RUN_DIR/zfs.txt" "ZFS $1"
}

v_node_replication() {
    view_table "/nodes/$CTX_NODE/replication" "" "guest:Guest:8|id:Job:10|target:Target:12|state:Status:10|last_sync:Last Sync:19:t|duration:Duration:9:s:r|next_sync:Next Sync:19:t|fail_count:Fail count:10:s:r|error:Error:*" 1
}
VIEW_HINT[v_node_replication]="N:Schedule_now L:Log"
v_node_replication__key() {
    [[ -n $2 ]] || return 1
    case $1 in
        N) api_exec_sync "Replication $2 - Schedule now" create "/nodes/$CTX_NODE/replication/$2/schedule_now"; content_load 1 ;;
        L)
            api_get rows "/nodes/$CTX_NODE/replication/$2/log" "" "t" || { dlg_msg "Log" "$API_ERR"; return 0; }
            printf '%s\n' "${API_ROWS[@]}" > "$RUN_DIR/repl.log"; pager_show "$RUN_DIR/repl.log" "Replication $2" ;;
        *) return 1 ;;
    esac
    return 0
}

# Task history table (node or guest). _task_history <query>
_task_history() {
    local row
    local -a f
    table_spec "starttime:Start Time:15:ts|endtime:End Time:15:ts|user:User name:12|desc:Description:*|status:Status:10:task"
    api_get rows "/nodes/$CTX_NODE/tasks" "limit=100${1:+&$1}" "upid,starttime,endtime,node,user,type,id,status" || { c_api_error; return; }
    table_header
    (( ${#API_ROWS[@]} )) || { c_msg dim "No items"; return; }
    for row in "${API_ROWS[@]}"; do
        tsv_split f "$row"
        task_desc "${f[5]}" "${f[6]}"
        table_row "${f[1]}"$'\t'"${f[2]}"$'\t'"${f[4]}"$'\t'"$REPLY"$'\t'"${f[7]}"
        c_sel "$REPLY" "${f[0]}"
    done
}
v_node_tasks() { _task_history ""; }
v_node_tasks__enter() { show_task_log "$1" "$CTX_NODE"; }
VIEW_LIVE[v_node_tasks]=1
VIEW_HINT[v_node_tasks]="Enter:Show_log x:Stop"
v_node_tasks__key() {
    [[ $1 == x && -n $2 ]] || return 1
    T "Stop this task?"; confirm "$REPLY" || return 0
    api_exec_sync "Stop task" delete "/nodes/$CTX_NODE/tasks/$2"
    content_load 1
    return 0
}

v_node_subscription() {
    api_kv "/nodes/$CTX_NODE/subscription" || { c_api_error; return; }
    local st=${API_KV[status]-}
    status_color "$st"
    c_kv "Product Name" "${API_KV[productname]:--}"
    c_kv "Status" "${STATUS_C}${st}${C[norm]} ${API_KV[message]-}"
    c_kv "Subscription Key" "${API_KV[key]:--}"
    c_kv "Server ID" "${API_KV[serverid]-}"
    c_kv "Sockets" "${API_KV[sockets]-}"
    c_kv "Last checked" "$( fmt_time "${API_KV[checktime]-}"; printf '%s' "$REPLY")"
    c_kv "Next due date" "${API_KV[nextduedate]:--}"
}
VIEW_HINT[v_node_subscription]="u:Upload_Key c:Check d:Remove_Key"
v_node_subscription__key() {
    case $1 in
        u)
            form_reset
            form_run "Upload Subscription Key" PUT "/nodes/$CTX_NODE/subscription" && content_load 1 ;;
        c)
            T "Check the subscription with the Proxmox server now?"; confirm "$REPLY" || return 0
            api_exec_sync "Check subscription" create "/nodes/$CTX_NODE/subscription" --force 1; content_load 1 ;;
        d)
            T "Remove the subscription key of this node?"; dlg_yesno "Remove Subscription" "$REPLY" || return 0
            api_exec_sync "Remove subscription" delete "/nodes/$CTX_NODE/subscription"; content_load 1 ;;
        *) return 1 ;;
    esac
    return 0
}
