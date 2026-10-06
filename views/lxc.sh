# shellcheck shell=bash
# views/lxc.sh - "Container" panels (shared ones are in guest.sh).

view_menu lxc \
    "summary|Summary|m_summary|0" \
    "console|Console|m_console|0" \
    "resources|Resources|m_resources|0" \
    "network|Network|m_network|0" \
    "dns|DNS|m_dns|0" \
    "options|Options|m_options|0" \
    "tasks|Task History|m_tasks|0" \
    "backup|Backup|m_backup|0" \
    "replication|Replication|m_replication|0" \
    "snapshots|Snapshots|m_snapshot|0" \
    "firewall|Firewall|m_firewall|0" \
    "fwoptions|Options|m_options|1" \
    "fwalias|Alias|m_firewall|1" \
    "fwipset|IPSet|m_firewall|1" \
    "fwlog|Log|m_syslog|1" \
    "permissions|Permissions|m_permissions|0"

v_lxc_resources() {
    guest_config || { c_api_error; return; }
    local v k
    fmt_bytes $(( ${CFGV[memory]:-512} * 1048576 )); cfg_line "Memory" memory "$REPLY"
    fmt_bytes $(( ${CFGV[swap]:-512} * 1048576 )); cfg_line "Swap" swap "$REPLY"
    v=${CFGV[cores]-}; [[ -z $v ]] && { T "unlimited"; v=$REPLY; }
    [[ -n ${CFGV[cpulimit]-} ]] && v+=" [cpulimit=${CFGV[cpulimit]}]"
    [[ -n ${CFGV[cpuunits]-} ]] && v+=" [cpuunits=${CFGV[cpuunits]}]"
    cfg_line "Cores" cores "$v"
    cfg_line "Root Disk" rootfs "${CFGV[rootfs]-}"
    local -a keys
    mapfile -t keys < <(printf '%s\n' "${!CFGV[@]}" | grep -E '^(mp|unused|dev)[0-9]+$' | sort -V)
    for k in "${keys[@]}"; do
        case $k in
            mp*) T "Mount Point" ;;
            dev*) T "Device Passthrough" ;;
            *) T "Unused Disk" ;;
        esac
        cfg_line "$REPLY (${k})" "$k" "${CFGV[$k]}"
    done
}
v_lxc_resources__enter() { guest_cfg_edit "$1"; }
v_lxc_resources__key() {
    case $1 in
        a|INS)
            local kind=${CRUD_ANSWER[device]-}
            if [[ -z $kind ]]; then
                dlg_menu "Add" "Resources" mp "$(T "Mount Point"; printf '%s' "$REPLY")" dev "$(T "Device Passthrough"; printf '%s' "$REPLY")" || return 0
                kind=$REPLY
            fi
            if [[ $kind == mp ]]; then
                _pick_store rootdir || return 0
                local st=$REPLY size=${CRUD_ANSWER[size]-}
                [[ -z $size ]] && { dlg_input "Mount Point" "Disk size (GiB):" "8" || return 0; size=$REPLY; }
                cfg_next mp 255; local key=$REPLY
                guest_add_device "$key" "$st:$size,mp=${CRUD_ANSWER[path]:-/mnt/$key}" "Mount Point ($key)"
            else
                cfg_next dev 255; guest_add_device "$REPLY" "${CRUD_ANSWER[value]:-}" "Device Passthrough ($REPLY)"
            fi ;;
        e) guest_cfg_edit "$2" ;;
        R) guest_disk_resize "$2" ;;
        m) guest_disk_move "$2" ;;
        *) guest_cfg_key "$@"; return ;;
    esac
    return 0
}
VIEW_HINT[v_lxc_resources]="a:Add e:Edit d:Remove R:Resize m:Move_volume v:Revert"

v_lxc_network() {
    guest_config || { c_api_error; return; }
    table_spec "id:ID:6|name:Name:8|bridge:Bridge:10|fw:Firewall:9|tag:VLAN Tag:9|hwaddr:MAC address:18|ip:IP address:18|gw:Gateway:15|ip6:IPv6 address:*|gw6:Gateway (IPv6):*"
    table_header
    local -a keys
    mapfile -t keys < <(printf '%s\n' "${!CFGV[@]}" | grep -E '^net[0-9]+$' | sort -V)
    (( ${#keys[@]} )) || { c_msg dim "No items"; return; }
    local k s row f
    for k in "${keys[@]}"; do
        s=${CFGV[$k]} row=$k
        for f in name bridge firewall tag hwaddr ip gw ip6 gw6; do
            prop_get "$s" "$f"
            [[ $f == firewall ]] && { fmtv bool "${REPLY:-0}"; }
            row+=$'\t'$REPLY
        done
        table_row "$row"
        c_sel "$REPLY" "$k"
    done
}
v_lxc_network__enter() { guest_cfg_edit "$1"; }
v_lxc_network__key() {
    case $1 in
        a|INS)
            cfg_next net 31; local key=$REPLY br=vmbr0
            choice_bridges && br=${REPLY%%=*}
            guest_add_device "$key" "name=eth${key#net},bridge=$br,firewall=1,ip=dhcp" "Network Device ($key)" ;;
        e) guest_cfg_edit "$2" ;;
        *) guest_cfg_key "$@"; return ;;
    esac
    return 0
}
VIEW_HINT[v_lxc_network]="a:Add e:Edit d:Remove"

v_lxc_dns() {
    guest_config || { c_api_error; return; }
    cfg_line "Hostname" hostname "${CFGV[hostname]-}" "CT$CTX_VMID"
    cfg_line "DNS domain" searchdomain "${CFGV[searchdomain]-}" "use host settings"
    cfg_line "DNS servers" nameserver "${CFGV[nameserver]-}" "use host settings"
}
v_lxc_dns__enter() { guest_cfg_edit "$1"; }
v_lxc_dns__key() { [[ $1 == e ]] && { guest_cfg_edit "$2"; return 0; }; guest_cfg_key "$@"; }
VIEW_HINT[v_lxc_dns]="Enter:Edit d:Reset"

v_lxc_options() {
    guest_config || { c_api_error; return; }
    fmtv bool "${CFGV[onboot]:-0}"; cfg_line "Start at boot" onboot "$REPLY"
    cfg_line "Start/Shutdown order" startup "${CFGV[startup]-}" "order=any"
    cfg_line "OS Type" ostype "${CFGV[ostype]-}"
    cfg_line "Architecture" arch "${CFGV[arch]-}" "amd64"
    fmtv bool "${CFGV[console]:-1}"; cfg_line "/dev/console" console "$REPLY"
    cfg_line "TTY count" tty "${CFGV[tty]-}" "2"
    cfg_line "Console mode" cmode "${CFGV[cmode]-}" "Default (tty)"
    fmtv bool "${CFGV[protection]:-0}"; cfg_line "Protection" protection "$REPLY"
    fmtv bool "${CFGV[unprivileged]:-0}"; cfg_line "Unprivileged container" unprivileged "$REPLY"
    cfg_line "Features" features "${CFGV[features]-}" "none"
    cfg_line "Hookscript" hookscript "${CFGV[hookscript]-}" "none"
    cfg_line "Time zone" timezone "${CFGV[timezone]-}" "Default"
    local k
    for k in "${!CFGV[@]}"; do
        [[ $k == lxc.* ]] && cfg_line "$k" "$k" "${CFGV[$k]}"
    done
}
v_lxc_options__enter() { guest_cfg_edit "$1"; }
v_lxc_options__key() { [[ $1 == e ]] && { guest_cfg_edit "$2"; return 0; }; guest_cfg_key "$@"; }
VIEW_HINT[v_lxc_options]="Enter:Edit d:Reset"
