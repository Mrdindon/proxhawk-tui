# shellcheck shell=bash
# choices.sh - value lists offered by the forms (FORM_CHOICES) and pickers.
# Every function returns "value=Label,value2=Label2" in REPLY (rc 1 if empty).

_choices_from_rows() {   # rows "value<TAB>label" in API_ROWS
    local row out=""
    for row in "${API_ROWS[@]}"; do
        [[ -n ${row%%$'\t'*} ]] || continue
        out+="${row%%$'\t'*}=${row#*$'\t'},"
    done
    REPLY=${out%,}
    [[ -n $REPLY ]]
}

# Disks without partitions / not in use on the current node.
choice_unused_disks() {
    local row out="" f
    local -a v
    api_get rows "/nodes/$CTX_NODE/disks/list" "include-partitions=0" "devpath,size,model,used" || return 1
    for row in "${API_ROWS[@]}"; do
        tsv_split v "$row"
        [[ -z ${v[3]} || ${v[3]} == unused ]] || continue
        fmt_bytes "${v[1]}"
        out+="${v[0]}=$REPLY ${v[2]},"
    done
    REPLY=${out%,}
    [[ -n $REPLY ]]
}

# All disks of the node (for wipe / GPT), with their usage.
choice_all_disks() {
    local row out=""
    local -a v
    api_get rows "/nodes/$CTX_NODE/disks/list" "include-partitions=1" "devpath,size,model,used" || return 1
    for row in "${API_ROWS[@]}"; do
        tsv_split v "$row"
        fmt_bytes "${v[1]}"
        out+="${v[0]}=$REPLY ${v[2]} [${v[3]:-unused}],"
    done
    REPLY=${out%,}
    [[ -n $REPLY ]]
}

choice_nodes() {
    local id out=""
    for id in "${RES_IDS[@]}"; do [[ ${R_TYPE[$id]} == node ]] && out+="${R_NODE[$id]}=${R_STATUS[$id]},"; done
    REPLY=${out%,}
    [[ -n $REPLY ]]
}

choice_storages() {   # storages of the current node (optionally with a content type)
    local id out="" ct=${1:-}
    for id in "${RES_IDS[@]}"; do
        [[ ${R_TYPE[$id]} == storage && ${R_NODE[$id]} == "${CTX_NODE:-$LOCAL_NODE}" ]] || continue
        [[ -z $ct || ,${R_CONTENT[$id]}, == *,$ct,* ]] || continue
        out+="${R_STORAGE[$id]}=${R_PLUGIN[$id]},"
    done
    REPLY=${out%,}
    [[ -n $REPLY ]]
}
choice_storages_images() { choice_storages images; }
choice_storages_rootdir() { choice_storages rootdir; }
choice_storages_backup() { choice_storages backup; }

choice_bridges() {
    api_get rows "/nodes/${CTX_NODE:-$LOCAL_NODE}/network" "type=any_bridge" "iface,type" || return 1
    _choices_from_rows
}

choice_guests() {
    local id out=""
    for id in "${RES_IDS[@]}"; do
        [[ ${R_TYPE[$id]} == qemu || ${R_TYPE[$id]} == lxc ]] && out+="${R_VMID[$id]}=${R_TYPE[$id]} ${R_NAME[$id]},"
    done
    REPLY=${out%,}
    [[ -n $REPLY ]]
}

choice_users() { api_get rows /access/users "" "userid,comment" && _choices_from_rows; }
choice_groups() { api_get rows /access/groups "" "groupid,comment" && _choices_from_rows; }
choice_roles() { api_get rows /access/roles "" "roleid,special" && _choices_from_rows; }
choice_pools() { api_get rows /pools "" "poolid,comment" && _choices_from_rows; }
choice_realms() { api_get rows /access/domains "" "realm,type" && _choices_from_rows; }
choice_zones() { api_get rows /cluster/sdn/zones "" "zone,type" && _choices_from_rows; }
choice_acme_accounts() { api_get rows /cluster/acme/account "" "name,name" && _choices_from_rows; }
choice_acme_plugins() { api_get rows /cluster/acme/plugins "" "plugin,type" && _choices_from_rows; }
choice_acme_directories() { api_get rows /cluster/acme/directories "" "url,name" && _choices_from_rows; }
choice_fw_macros() { api_get rows /cluster/firewall/macros "" "macro,descr" && _choices_from_rows; }
choice_ceph_rules() { api_get rows "/nodes/$CTX_NODE/ceph/rules" "" "name,name" && _choices_from_rows; }
choice_timezones() {
    local out="" z
    while IFS= read -r z; do out+="$z=,"; done < <(timedatectl list-timezones 2>/dev/null)
    REPLY=${out%,}
    [[ -n $REPLY ]]
}

# Access control paths used by the permission dialogs.
choice_acl_paths() {
    local id out="/=,/access=,/nodes=,/pool=,/sdn=,/storage=,/vms=,/mapping=,"
    for id in "${RES_IDS[@]}"; do
        case ${R_TYPE[$id]} in
            node) out+="/nodes/${R_NODE[$id]}=," ;;
            qemu|lxc) out+="/vms/${R_VMID[$id]}=${R_NAME[$id]}," ;;
            storage) [[ $out == *"/storage/${R_STORAGE[$id]}="* ]] || out+="/storage/${R_STORAGE[$id]}=," ;;
            pool) out+="/pool/${id#pool/}=," ;;
        esac
    done
    REPLY=${out%,}
}
