# shellcheck shell=bash
# resources.sh - cluster resources (/cluster/resources) and the resource tree
# shown on the left (Server View, Folder View, Pool View, Storage View).

declare -ga RES_IDS=()
declare -gA R_TYPE=() R_NODE=() R_NAME=() R_STATUS=() R_VMID=() R_TMPL=() \
    R_CPU=() R_MAXCPU=() R_MEM=() R_MAXMEM=() R_DISK=() R_MAXDISK=() \
    R_UPTIME=() R_TAGS=() R_LOCK=() R_HA=() R_POOL=() R_STORAGE=() \
    R_PLUGIN=() R_CONTENT=() R_SHARED=() R_NET=() R_NETTYPE=()
CLUSTER_NAME=""
QUORATE=1

_RES_FIELDS="id,type,node,name,status,vmid,template,cpu*10000,maxcpu,mem:i,maxmem:i,disk:i,maxdisk:i,uptime:i,tags,lock,hastate,pool,storage,plugintype,content,shared,network,network-type"

res_load() {
    local row id
    local -a f
    api_get rows /cluster/resources "" "$_RES_FIELDS" || return 1
    RES_IDS=()
    R_TYPE=() R_NODE=() R_NAME=() R_STATUS=() R_VMID=() R_TMPL=() R_CPU=() R_MAXCPU=()
    R_MEM=() R_MAXMEM=() R_DISK=() R_MAXDISK=() R_UPTIME=() R_TAGS=() R_LOCK=() R_HA=()
    R_POOL=() R_STORAGE=() R_PLUGIN=() R_CONTENT=() R_SHARED=() R_NET=() R_NETTYPE=()
    for row in "${API_ROWS[@]}"; do
        tsv_split f "$row"
        id=${f[0]}
        [[ -n $id ]] || continue
        RES_IDS+=("$id")
        R_TYPE[$id]=${f[1]-} R_NODE[$id]=${f[2]-} R_NAME[$id]=${f[3]-} R_STATUS[$id]=${f[4]-}
        R_VMID[$id]=${f[5]-} R_TMPL[$id]=${f[6]-} R_CPU[$id]=${f[7]-} R_MAXCPU[$id]=${f[8]-}
        R_MEM[$id]=${f[9]-} R_MAXMEM[$id]=${f[10]-} R_DISK[$id]=${f[11]-} R_MAXDISK[$id]=${f[12]-}
        R_UPTIME[$id]=${f[13]-} R_TAGS[$id]=${f[14]-} R_LOCK[$id]=${f[15]-} R_HA[$id]=${f[16]-}
        R_POOL[$id]=${f[17]-} R_STORAGE[$id]=${f[18]-} R_PLUGIN[$id]=${f[19]-}
        R_CONTENT[$id]=${f[20]-} R_SHARED[$id]=${f[21]-} R_NET[$id]=${f[22]-} R_NETTYPE[$id]=${f[23]-}
    done
    # Cluster name and quorum (empty name = standalone node).
    CLUSTER_NAME="" QUORATE=1
    if api_get rows /cluster/status "" "type,name,quorate"; then
        for row in "${API_ROWS[@]}"; do
            tsv_split f "$row"
            if [[ ${f[0]} == cluster ]]; then CLUSTER_NAME=${f[1]}; QUORATE=${f[2]:-1}; fi
        done
    fi
    return 0
}

# Human readable label of a resource (as in the web UI tree).
res_label() {
    local id=$1
    case ${R_TYPE[$id]-} in
        node) REPLY=${R_NODE[$id]} ;;
        qemu|lxc) REPLY="${R_VMID[$id]} (${R_NAME[$id]})"; [[ -z ${R_NAME[$id]} ]] && REPLY=${R_VMID[$id]} ;;
        storage) REPLY="${R_STORAGE[$id]} (${R_NODE[$id]})" ;;
        network) REPLY="${R_NET[$id]} (${R_NODE[$id]})" ;;
        pool) REPLY=${id#pool/} ;;
        *) REPLY=$id ;;
    esac
}

# Coloured icon (with status) of a tree entry.
res_icon() {
    local id=$1 t=${R_TYPE[$1]-} st=${R_STATUS[$1]-}
    case $t in
        node)
            if [[ $st == online ]]; then REPLY="${C[ok]}${G[node]}"; else REPLY="${C[err]}${G[node]}"; fi ;;
        qemu|lxc)
            local g=${G[$t]}
            [[ ${R_TMPL[$id]} == 1 ]] && g=${G[tmpl]}
            case $st in
                running) REPLY="${C[ok]}$g" ;;
                paused|suspended) REPLY="${C[warn]}$g" ;;
                stopped) REPLY="${C[dim]}$g" ;;
                *) REPLY="${C[err]}$g" ;;
            esac
            [[ ${R_TMPL[$id]} == 1 ]] && REPLY="${C[norm]}$g" ;;
        storage)
            if [[ $st == available ]]; then REPLY="${C[norm]}${G[storage]}"; else REPLY="${C[err]}${G[storage]}"; fi ;;
        network) REPLY="${C[norm]}${G[sdn]}" ;;
        pool) REPLY="${C[norm]}${G[pool]}" ;;
        *) REPLY="${C[norm]}${G[folder]}" ;;
    esac
}

# ---------------------------------------------------------------------------
# Tree model. TREE_* hold every entry in display order; TV_* the visible ones.
# ---------------------------------------------------------------------------
declare -ga TREE_ID=() TREE_DEPTH=() TV_IDX=()
declare -gA TREE_KIDS=() COLLAPSED=() FOLDER_LABEL=()
TREE_VIEW=server        # server | folder | storage | pool
TREE_VIEWS=(server folder pool storage)
TREE_CUR=0 TREE_SCROLL=0
SEL_ID=root

_tree_push() { TREE_ID+=("$1"); TREE_DEPTH+=("$2"); }

# Sorted list of resource ids of a given type (optionally on a node / pool).
_res_list() {
    local type=$1 node=${2:-} pool=${3:-} id key
    local -a out=()
    for id in "${RES_IDS[@]}"; do
        [[ ${R_TYPE[$id]} == "$type" ]] || continue
        [[ -n $node && ${R_NODE[$id]} != "$node" ]] && continue
        [[ -n $pool && ${R_POOL[$id]} != "$pool" ]] && continue
        case $type in
            qemu|lxc) printf -v key '%012d' "${R_VMID[$id]:-0}" ;;
            *) res_label "$id"; key=$REPLY ;;
        esac
        out+=("$key"$'\t'"$id")
    done
    RES_LIST=()
    (( ${#out[@]} )) || return 0
    mapfile -t RES_LIST < <(printf '%s\n' "${out[@]}" | sort -f | cut -f2)
}

_guests_of() {   # guests (VM + CT) of a node or a pool, ordered by VMID
    local id key
    local -a out=()
    for id in "${RES_IDS[@]}"; do
        [[ ${R_TYPE[$id]} == qemu || ${R_TYPE[$id]} == lxc ]] || continue
        [[ -n $1 && ${R_NODE[$id]} != "$1" ]] && continue
        [[ -n ${2:-} && ${R_POOL[$id]} != "$2" ]] && continue
        printf -v key '%012d' "${R_VMID[$id]:-0}"
        out+=("$key"$'\t'"$id")
    done
    RES_LIST=()
    (( ${#out[@]} )) || return 0
    mapfile -t RES_LIST < <(printf '%s\n' "${out[@]}" | sort | cut -f2)
}

tree_build() {
    local n id p
    TREE_ID=() TREE_DEPTH=() TREE_KIDS=()
    _tree_push root 0
    local -a nodes
    _res_list node; nodes=("${RES_LIST[@]}")
    case $TREE_VIEW in
        server)
            for n in "${nodes[@]}"; do
                _tree_push "$n" 1
                _guests_of "${R_NODE[$n]}"; for id in "${RES_LIST[@]}"; do _tree_push "$id" 2; done
                _res_list network "${R_NODE[$n]}"; for id in "${RES_LIST[@]}"; do _tree_push "$id" 2; done
                _res_list storage "${R_NODE[$n]}"; for id in "${RES_LIST[@]}"; do _tree_push "$id" 2; done
            done ;;
        storage)
            for n in "${nodes[@]}"; do
                _tree_push "$n" 1
                _res_list storage "${R_NODE[$n]}"; for id in "${RES_LIST[@]}"; do _tree_push "$id" 2; done
            done ;;
        pool)
            _res_list pool
            for p in "${RES_LIST[@]}"; do
                _tree_push "$p" 1
                _guests_of "" "${p#pool/}"; for id in "${RES_LIST[@]}"; do _tree_push "$id" 2; done
                _res_list storage "" "${p#pool/}"; for id in "${RES_LIST[@]}"; do _tree_push "$id" 2; done
            done ;;
        folder)
            local -a folders=(lxc node pool sdn storage qemu)
            T "LXC Container"; FOLDER_LABEL[lxc]=$REPLY
            T "Nodes"; FOLDER_LABEL[node]=$REPLY
            T "Pools"; FOLDER_LABEL[pool]=$REPLY
            T "SDN"; FOLDER_LABEL[sdn]=$REPLY
            T "Storage"; FOLDER_LABEL[storage]=$REPLY
            T "Virtual Machine"; FOLDER_LABEL[qemu]=$REPLY
            for p in "${folders[@]}"; do
                if [[ $p == sdn ]]; then _res_list network; else _res_list "$p"; fi
                (( ${#RES_LIST[@]} )) || continue
                local -a items=("${RES_LIST[@]}")
                _tree_push "folder/$p" 1
                for id in "${items[@]}"; do
                    _tree_push "$id" 2
                    if [[ $p == pool ]]; then
                        _guests_of "" "${id#pool/}"
                        local m; for m in "${RES_LIST[@]}"; do _tree_push "$m" 3; done
                    fi
                done
            done ;;
    esac
    # Record which entries have children.
    local i
    for (( i = 0; i < ${#TREE_ID[@]} - 1; i++ )); do
        (( TREE_DEPTH[i + 1] > TREE_DEPTH[i] )) && TREE_KIDS[$i]=1
    done
    tree_visible
}

# Compute the visible entries (children of collapsed entries are hidden).
tree_visible() {
    local i hide=-1 sel_found=0
    TV_IDX=()
    for (( i = 0; i < ${#TREE_ID[@]}; i++ )); do
        if (( hide >= 0 )); then
            (( TREE_DEPTH[i] > hide )) && continue
            hide=-1
        fi
        TV_IDX+=("$i")
        [[ -n ${COLLAPSED[${TREE_ID[i]}]-} && -n ${TREE_KIDS[$i]-} ]] && hide=${TREE_DEPTH[i]}
    done
    # Keep the cursor on the selected id when possible.
    for i in "${!TV_IDX[@]}"; do
        if [[ ${TREE_ID[TV_IDX[i]]} == "$SEL_ID" ]]; then TREE_CUR=$i; sel_found=1; break; fi
    done
    (( sel_found )) || { (( TREE_CUR >= ${#TV_IDX[@]} )) && TREE_CUR=$(( ${#TV_IDX[@]} - 1 )); }
    (( TREE_CUR < 0 )) && TREE_CUR=0
    return 0
}

tree_toggle() {
    local i=${TV_IDX[TREE_CUR]} id=${TREE_ID[${TV_IDX[TREE_CUR]}]}
    [[ -n ${TREE_KIDS[$i]-} ]] || return 0
    if [[ -n ${COLLAPSED[$id]-} ]]; then unset "COLLAPSED[$id]"; else COLLAPSED[$id]=1; fi
    tree_visible
}

tree_cycle_view() {
    local i
    for i in "${!TREE_VIEWS[@]}"; do
        if [[ ${TREE_VIEWS[i]} == "$TREE_VIEW" ]]; then
            TREE_VIEW=${TREE_VIEWS[(i + 1) % ${#TREE_VIEWS[@]}]}
            break
        fi
    done
    tree_build
}

tree_view_label() {
    case $TREE_VIEW in
        server) T "Server View" ;;
        folder) T "Folder View" ;;
        pool) T "Pool View" ;;
        storage) T "Storage View" ;;
    esac
}
