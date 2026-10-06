# shellcheck shell=bash
# views/datacenter.sh - "Datacenter" panels and the shared resource grid
# (Search panel, folder content).

view_menu dc \
    "search|Search|m_search|0" \
    "summary|Summary|m_summary|0" \
    "notes|Notes|m_notes|0" \
    "cluster|Cluster|m_cluster|0" \
    "ceph|Ceph|m_ceph|0" \
    "options|Options|m_options|0" \
    "storage|Storage|m_storage|0" \
    "backup|Backup|m_backup|0" \
    "replication|Replication|m_replication|0" \
    "permissions|Permissions|m_permissions|0" \
    "users|Users|m_users|1" \
    "tokens|API Tokens|m_tokens|1" \
    "tfa|Two Factor|m_tfa|1" \
    "groups|Groups|m_groups|1" \
    "pools|Pools|m_pools|1" \
    "roles|Roles|m_roles|1" \
    "realms|Realms|m_realms|1" \
    "ha|HA|m_ha|0" \
    "harules|Affinity Rules|m_ha|1" \
    "hafencing|Fencing|m_ha|1" \
    "sdn|SDN|m_sdn|0" \
    "zones|Zones|m_zones|1" \
    "vnets|VNets|m_vnets|1" \
    "sdnoptions|Options|m_options|1" \
    "sdnipam|IPAM|m_sdn|1" \
    "sdnfirewall|VNet Firewall|m_firewall|1" \
    "fabrics|Fabrics|m_vnets|1" \
    "routemaps|Route Maps|m_mapping|1" \
    "prefixlists|Prefix Lists|m_mapping|1" \
    "acme|ACME|m_acme|0" \
    "firewall|Firewall|m_firewall|0" \
    "fwoptions|Options|m_options|1" \
    "fwgroups|Security Group|m_firewall|1" \
    "fwalias|Alias|m_firewall|1" \
    "fwipset|IPSet|m_firewall|1" \
    "metric|Metric Server|m_metric|0" \
    "mapping|Resource Mappings|m_mapping|0" \
    "dirmapping|Directory Mappings|m_dir|0" \
    "cputypes|Custom CPU Models|m_hardware|0" \
    "notifications|Notifications|m_notify|0" \
    "support|Support|m_support|0"

title_dc() {
    T "Datacenter"
    [[ -n $CLUSTER_NAME ]] && REPLY+=" ($CLUSTER_NAME)"
}

# ---------------------------------------------------------------------------
# Resource grid (Search panel): res_grid <filter function>
# ---------------------------------------------------------------------------
SEARCH_TERM=""

_grid_match_all() {
    [[ -z $SEARCH_TERM ]] && return 0
    res_label "$1"
    local hay="${R_TYPE[$1]} $REPLY ${R_TAGS[$1]-} ${R_NODE[$1]-} ${R_POOL[$1]-}"
    [[ ${hay,,} == *"${SEARCH_TERM,,}"* ]]
}

res_grid() {
    local filter=${1:-_grid_match_all} id t row cpu mem disk up ip mark spec
    spec="type:Type:7|d:Description:**"
    [[ ${CFG[ip_column]} == 1 ]] && spec+="|ip:IP address:15"
    spec+="|disk:Disk usage %:9:s:r|mem:Memory usage %:9:s:r|cpu:CPU usage:17:s:r|up:Uptime:15|tags:Tags:*"
    grid_filter_line
    table_spec "$spec"
    table_header
    local -a ids=()
    # Same order as the web UI: type, then description.
    local -a keyed=()
    for id in "${RES_IDS[@]}"; do
        "$filter" "$id" || continue
        grid_filter_match "$id" || continue
        res_label "$id"
        keyed+=("${R_TYPE[$id]}"$'\t'"$REPLY"$'\t'"$id")
    done
    (( ${#keyed[@]} )) || { c_msg dim "No items"; return; }
    mapfile -t ids < <(printf '%s\n' "${keyed[@]}" | sort -t $'\t' -k1,1 -k2,2V | cut -f3)
    for id in "${ids[@]}"; do
        t=${R_TYPE[$id]}
        [[ $t == network ]] && t=sdn
        disk="" mem="" cpu="" up="" ip=""
        if [[ -n ${R_MAXDISK[$id]-} && ${R_MAXDISK[$id]} != 0 && $t != qemu ]]; then
            fmt_pct $(( ${R_DISK[$id]:-0} * 10000 / R_MAXDISK[$id] )); disk=$REPLY
        fi
        if [[ -n ${R_MAXMEM[$id]-} && ${R_MAXMEM[$id]} != 0 && ${R_STATUS[$id]} != stopped ]]; then
            fmt_pct $(( ${R_MEM[$id]:-0} * 10000 / R_MAXMEM[$id] )); mem=$REPLY
        fi
        if [[ -n ${R_MAXCPU[$id]-} && ${R_STATUS[$id]} != stopped ]]; then
            fmt_pct "${R_CPU[$id]:-0}"; Tf "%s of %s CPU(s)" "$REPLY" "${R_MAXCPU[$id]}"; cpu=$REPLY
        fi
        [[ -n ${R_UPTIME[$id]-} && ${R_UPTIME[$id]} != 0 ]] && { fmt_uptime "${R_UPTIME[$id]}"; up=$REPLY; }
        res_icon "$id"; local ic=$REPLY
        [[ -n ${PENDING[$id]-} ]] && ic="${C[warn]}${SPIN_MARK}"
        # Guests marked with Space for batch actions.
        mark=" "; [[ -n ${SELECTED[$id]-} ]] && mark="${C[accent]}${G[st_ok]}${C[norm]}"
        res_label "$id"
        row="$t"$'\t'"$REPLY"
        if [[ ${CFG[ip_column]} == 1 ]]; then
            [[ $t == qemu || $t == lxc ]] && { guest_ip_cached "$id"; ip=$REPLY; }
            row+=$'\t'"$ip"
        fi
        table_row "$row"$'\t'"$disk"$'\t'"$mem"$'\t'"$cpu"$'\t'"$up"$'\t'"${R_TAGS[$id]//;/,}"
        c_sel "${mark}${ic}${C[norm]}${REPLY}" "$id"
    done
}

# ---------------------------------------------------------------------------
# Grid filter (status, type, node, tag) and keys shared by the grids:
#   Space mark a guest, m batch actions, f filter, Enter go to.
# ---------------------------------------------------------------------------
declare -gA GRID_FILTER=()

grid_filter_match() {
    local id=$1 f
    f=${GRID_FILTER[status]-}; [[ -z $f || ${R_STATUS[$id]-} == "$f" ]] || return 1
    f=${GRID_FILTER[type]-}; [[ -z $f || ${R_TYPE[$id]-} == "$f" ]] || return 1
    f=${GRID_FILTER[node]-}; [[ -z $f || ${R_NODE[$id]-} == "$f" ]] || return 1
    f=${GRID_FILTER[tag]-}; [[ -z $f || ";${R_TAGS[$id]-};" == *";$f;"* ]] || return 1
    return 0
}

grid_filter_line() {
    local k txt=""
    for k in status type node tag; do [[ -n ${GRID_FILTER[$k]-} ]] && txt+="$k=${GRID_FILTER[$k]} "; done
    [[ -n $txt ]] || return 0
    T "Filter"; c_add " ${C[accent]}${G[search]:+${G[search]} }$REPLY: ${txt}${C[norm]}${C[dim]}(f)${C[norm]}"
}

grid_filter_dialog() {
    local what id v
    local -a items=() vals=()
    local -A seen=()
    T "Status"; items+=(status "$REPLY: ${GRID_FILTER[status]:-*}")
    T "Type"; items+=(type "$REPLY: ${GRID_FILTER[type]:-*}")
    T "Node"; items+=(node "$REPLY: ${GRID_FILTER[node]:-*}")
    T "Tag"; items+=(tag "$REPLY: ${GRID_FILTER[tag]:-*}")
    T "Clear all filters"; items+=(clear "$REPLY")
    if [[ -n ${CRUD_ANSWER[filter]-} ]]; then what=${CRUD_ANSWER[filter]}
    else T "Filter"; dlg_menu "$REPLY" "" "${items[@]}" || return; what=$REPLY
    fi
    [[ $what == clear ]] && { GRID_FILTER=(); content_load 1; return; }
    for id in "${RES_IDS[@]}"; do
        case $what in
            status) v=${R_STATUS[$id]-} ;;
            type) v=${R_TYPE[$id]-} ;;
            node) v=${R_NODE[$id]-} ;;
            tag) for v in ${R_TAGS[$id]//;/ }; do [[ -n ${seen[$v]-} ]] || { seen[$v]=1; vals+=("$v" ""); }; done; continue ;;
        esac
        [[ -n $v && -z ${seen[$v]-} ]] && { seen[$v]=1; vals+=("$v" ""); }
    done
    T "(any)"; vals+=(_any "$REPLY")
    if [[ -n ${CRUD_ANSWER[value]-} ]]; then v=${CRUD_ANSWER[value]}
    else dlg_menu "$what" "" "${vals[@]}" || return; v=$REPLY
    fi
    if [[ $v == _any ]]; then unset "GRID_FILTER[$what]"; else GRID_FILTER[$what]=$v; fi
    content_load 1
}

# Keys of the grid panels: grid_key <KEY> <row key>
grid_key() {
    case $1 in
        SPACE) batch_toggle "$2" && { content_load 1; content_move 1 2>/dev/null; } ;;
        m) batch_menu "$2" ;;
        f) grid_filter_dialog ;;
        *) return 1 ;;
    esac
    return 0
}
GRID_HINT="Enter:Go_to Space:Mark m:Batch_actions f:Filter"

# Enter on a grid row selects the resource in the tree.
grid_goto() {
    local id=$1 i
    [[ -n $id ]] || return
    unset "COLLAPSED[root]" "COLLAPSED[node/${R_NODE[$id]-}]" "COLLAPSED[folder/${R_TYPE[$id]-}]"
    SEL_ID=$id
    tree_visible
    for i in "${!TV_IDX[@]}"; do [[ ${TREE_ID[TV_IDX[i]]} == "$id" ]] && TREE_CUR=$i; done
    FOCUS=tree
    select_id "$id"
}

v_dc_search() {
    if [[ -n $SEARCH_TERM ]]; then
        Tf "Filter: %s" "$SEARCH_TERM"; c_add " ${C[accent]}${G[search]} ${REPLY}${C[norm]}"
    fi
    res_grid _grid_match_all
}
v_dc_search__enter() { grid_goto "$1"; }
v_dc_search__key() { grid_key "$@"; }
VIEW_HINT[v_dc_search]="$GRID_HINT"
VIEW_LIVE[v_dc_search]=1

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
v_dc_summary() {
    local id on=0 off=0 vr=0 vs=0 vt=0 cr=0 cs=0 ct=0 cpu=0 maxcpu=0 mem=0 maxmem=0 disk=0 maxdisk=0
    local -A seen=()
    for id in "${RES_IDS[@]}"; do
        case ${R_TYPE[$id]} in
            node)
                if [[ ${R_STATUS[$id]} == online ]]; then
                    (( on++ ))
                    (( cpu += ${R_CPU[$id]:-0} * ${R_MAXCPU[$id]:-0}, maxcpu += ${R_MAXCPU[$id]:-0} ))
                    (( mem += ${R_MEM[$id]:-0}, maxmem += ${R_MAXMEM[$id]:-0} ))
                else (( off++ )); fi ;;
            qemu)
                if [[ ${R_TMPL[$id]} == 1 ]]; then (( vt++ ))
                elif [[ ${R_STATUS[$id]} == running ]]; then (( vr++ )); else (( vs++ )); fi ;;
            lxc)
                if [[ ${R_TMPL[$id]} == 1 ]]; then (( ct++ ))
                elif [[ ${R_STATUS[$id]} == running ]]; then (( cr++ )); else (( cs++ )); fi ;;
            storage)
                # Shared storages are counted once.
                local key=$id
                [[ ${R_SHARED[$id]} == 1 ]] && key=${R_STORAGE[$id]}
                [[ -n ${seen[$key]-} || ${R_STATUS[$id]} != available ]] && continue
                seen[$key]=1
                (( disk += ${R_DISK[$id]:-0}, maxdisk += ${R_MAXDISK[$id]:-0} )) ;;
        esac
    done

    c_section "Health"
    if [[ -n $CLUSTER_NAME ]]; then
        if [[ $QUORATE == 1 ]]; then Tf "Cluster: %s, Quorate: Yes" "$CLUSTER_NAME"; c_kv "Status" "${C[ok]}${G[st_ok]}${C[norm]} $REPLY"
        else Tf "Cluster: %s, Quorate: No" "$CLUSTER_NAME"; c_kv "Status" "${C[err]}${G[st_err]}${C[norm]} $REPLY"
        fi
    else
        T "Standalone node - no cluster defined"; c_kv "Status" "${C[ok]}${G[st_ok]}${C[norm]} $REPLY"
    fi
    local l1 l2
    T "Online"; l1=$REPLY; T "Offline"; l2=$REPLY
    c_kv "Nodes" "${C[ok]}${G[st_online]}${C[norm]} $l1 $on    ${C[err]}${G[st_offline]}${C[norm]} $l2 $off"
    c_blank

    c_section "Guests"
    local r s t
    T "Running"; r=$REPLY; T "Stopped"; s=$REPLY; T "Templates"; t=$REPLY
    c_kv "Virtual Machines" "${C[ok]}${G[st_running]}${C[norm]} $r $vr    ${C[dim]}${G[st_stopped]}${C[norm]} $s $vs    ${G[tmpl]} $t $vt"
    c_kv "LXC Container" "${C[ok]}${G[st_running]}${C[norm]} $r $cr    ${C[dim]}${G[st_stopped]}${C[norm]} $s $cs    ${G[tmpl]} $t $ct"
    c_blank

    c_section "Resources"
    local w=$CONTENT_W
    (( maxcpu > 0 )) && cpu=$(( cpu / maxcpu ))
    usage_line "CPU" "$cpu" "$maxcpu" "$w" cpu; c_add "$REPLY"
    usage_line "Memory" "$mem" "$maxmem" "$w"; c_add "$REPLY"
    usage_line "Storage" "$disk" "$maxdisk" "$w"; c_add "$REPLY"
    c_blank

    c_section "Nodes"
    table_spec "name:Name:16|id:ID:4:s:r|online:Online:8|support:Support:12|ip:Server Address:16|cpu:CPU usage:10:s:r|mem:Memory usage:13:s:r|up:Uptime:*"
    table_header
    local row nm nid ip lvl
    local -a f
    api_get rows /cluster/status "" "type,name,nodeid,ip,level,online"
    for row in "${API_ROWS[@]}"; do
        tsv_split f "$row"
        [[ ${f[0]} == node ]] || continue
        nm=${f[1]} nid=${f[2]} ip=${f[3]} lvl=${f[4]}
        id="node/$nm"
        local onl sup cpus mems
        if [[ ${f[5]} == 1 ]]; then T Yes; onl="${C[ok]}${G[st_online]} $REPLY${C[norm]}"; else T No; onl="${C[err]}${G[st_offline]} $REPLY${C[norm]}"; fi
        case $lvl in
            c) sup=Community ;; b) sup=Basic ;; s) sup=Standard ;; p) sup=Premium ;; *) sup="-" ;;
        esac
        T "$sup"; sup=$REPLY
        fmt_pct "${R_CPU[$id]:-0}"; cpus=$REPLY
        mems=""
        [[ ${R_MAXMEM[$id]:-0} != 0 ]] && { fmt_pct $(( ${R_MEM[$id]:-0} * 10000 / R_MAXMEM[$id] )); mems=$REPLY; }
        fmt_uptime "${R_UPTIME[$id]:-0}"
        table_row "$nm"$'\t'"${nid:-0}"$'\t'"$onl"$'\t'"$sup"$'\t'"$ip"$'\t'"$cpus"$'\t'"$mems"$'\t'"$REPLY"
        c_sel "$REPLY" "$id"
    done
}
v_dc_summary__enter() { grid_goto "$1"; }
VIEW_LIVE[v_dc_summary]=1

# ---------------------------------------------------------------------------
v_dc_notes() {
    api_kv /cluster/options
    if [[ -n ${API_KV[description]-} ]]; then c_text "${API_KV[description]}"
    else c_msg dim "No notes. Press 'e' to edit."
    fi
}
v_dc_notes__key() { [[ $1 == e ]] && { act_edit_notes /cluster/options; return 0; }; return 1; }
VIEW_HINT[v_dc_notes]="e:Edit"

# ---------------------------------------------------------------------------
# Folder (Folder View) - resource grid of the folder type.
# ---------------------------------------------------------------------------
_grid_match_folder() {
    local t=${CTX_ID#folder/}
    [[ $t == sdn ]] && t=network
    [[ ${R_TYPE[$1]} == "$t" ]]
}
view_menu folder "content|Search|m_search|0"
title_folder() { REPLY=${FOLDER_LABEL[${CTX_ID#folder/}]-$CTX_ID}; }
v_folder_content() { res_grid _grid_match_folder; }
v_folder_content__enter() { grid_goto "$1"; }
v_folder_content__key() { grid_key "$@"; }
VIEW_HINT[v_folder_content]="$GRID_HINT"
VIEW_LIVE[v_folder_content]=1
