# shellcheck shell=bash
# crud.sh - Add / Edit / Remove buttons of the table panels.
#
# A panel declares its API calls once; keys, buttons and footer hints follow:
#
#   crud v_dc_users label="User" \
#       add="/access/users" edit="/access/users/{1}" del="/access/users/{1}" \
#       first="userid password realm groups expire enable firstname lastname email comment"
#
# Path templates:
#   {1} {2} ...  parts of the selected row key (row keys may hold "a|b|c")
#   {key}        the whole row key
#   {node} {vmid} {gtype} {storage} {pool} {net}   current context
#   {?name:Prompt}  asked to the user before the dialog (add only)
#   {?name:Prompt:choice_fn}  same, picked from a list (lib/choices.sh)
# Other attributes:
#   label=   noun used in titles          get=     prefill path (default: edit)
#   first=   basic fields (in order)      hide=    hidden fields
#   only=    show only these fields       fix=     "k=v k2=v2" fixed values on add
#   editfix= fixed values on edit         delargs= "--k v" extra arguments on delete
#   plugin=  plugin family: the add dialog asks for the type first (storage, realm...)
#   types=   explicit list of types for "plugin=" / "typefield="
#   typefield=  name of the type parameter (default "type")
#   typefields= "type:f1 f2;type2:f3" fields shown for each type
#   async=1  run in the background         sync=1  never in the background
#   result=1 show the output (secrets)     noedit=1 / noadd=1 / nodel=1
#   choices= "field:function ..." the function returns "v=Label,..." in REPLY
#   extra=   "K:Label ..." extra keys handled by the view (__key), shown as buttons

# Panels with several tables register one definition per table with
# "crud <view>:<sub> ..."; their row keys start with "<sub>|" and the add
# key first asks which kind of object to create.
#   {s1} {s2}   parts of the selected row key (for "add a child of the selected row")

declare -gA CRUD=() CRUD_SUBS=()

# Display names of object types, as in the "Add" menus of the web UI.
declare -gA TYPE_LABELS=(
    [dir]="Directory" [lvm]="LVM" [lvmthin]="LVM-Thin" [btrfs]="BTRFS" [nfs]="NFS" [cifs]="SMB/CIFS"
    [glusterfs]="GlusterFS" [cephfs]="CephFS" [rbd]="RBD" [zfspool]="ZFS" [zfs]="ZFS over iSCSI"
    [iscsi]="iSCSI" [iscsidirect]="iSCSI (direct)" [pbs]="Proxmox Backup Server" [esxi]="ESXi"
    [ad]="Active Directory Server" [ldap]="LDAP Server" [openid]="OpenID Connect Server"
    [bridge]="Linux Bridge" [bond]="Linux Bond" [vlan]="Linux VLAN" [eth]="Network Device" [alias]="Alias"
    [OVSBridge]="OVS Bridge" [OVSBond]="OVS Bond" [OVSPort]="OVS Port" [OVSIntPort]="OVS IntPort"
    [simple]="Simple" [qinq]="QinQ" [vxlan]="VXLAN" [evpn]="EVPN" [faucet]="Faucet" [bgp]="BGP" [isis]="ISIS"
    [pve]="PVE" [phpipam]="phpIPAM" [netbox]="NetBox" [powerdns]="PowerDNS"
    [influxdb]="InfluxDB" [graphite]="Graphite" [opentelemetry]="OpenTelemetry"
    [node-affinity]="Node Affinity" [resource-affinity]="Resource Affinity"
    [sendmail]="Sendmail" [smtp]="SMTP" [gotify]="Gotify" [webhook]="Webhook"
)

crud() {
    local fn=$1 kv k; shift
    for kv; do k=${kv%%=*}; CRUD["$fn|$k"]=${kv#*=}; done
    CRUD[$fn|on]=1
    if [[ $fn == *:* ]]; then
        CRUD[${fn%%:*}|on]=1
        CRUD_SUBS[${fn%%:*}]+="${fn#*:} "
    fi
}

crud_has() { [[ -n ${CRUD[$1|on]-} ]]; }

# Resolve the definition of a row: sets CRUD_FN and CRUD_KEY (key without prefix).
_crud_resolve() {
    local fn=$1 key=${2-}
    CRUD_FN=$fn CRUD_KEY=$key
    [[ -n ${CRUD_SUBS[$fn]-} ]] || return 0
    local sub=${key%%|*}
    if [[ -n $key && " ${CRUD_SUBS[$fn]} " == *" $sub "* ]]; then
        CRUD_FN="$fn:$sub" CRUD_KEY=${key#*|}
        return 0
    fi
    return 1
}

# Expand a path template with the row key and the context.
_crud_path() {
    local t=$1 key=${2-} i
    local -a parts
    IFS='|' read -r -a parts <<< "$key"
    t=${t//\{key\}/$key}
    for i in "${!parts[@]}"; do t=${t//\{$(( i + 1 ))\}/${parts[i]}}; done
    local -a sel
    IFS='|' read -r -a sel <<< "${CRUD_SEL-}"
    for i in "${!sel[@]}"; do t=${t//\{s$(( i + 1 ))\}/${sel[i]}}; done
    t=${t//\{node\}/$CTX_NODE}
    t=${t//\{vmid\}/$CTX_VMID}
    t=${t//\{gtype\}/$CTX_TYPE}
    t=${t//\{storage\}/$CTX_STORAGE}
    t=${t//\{pool\}/$CTX_POOL}
    t=${t//\{net\}/$CTX_NET}
    # {?name:Prompt} placeholders.
    while [[ $t =~ \{\?([a-zA-Z0-9_-]+):([^}:]*)(:([a-z_]+))?\} ]]; do
        local whole=${BASH_REMATCH[0]} name=${BASH_REMATCH[1]} prompt=${BASH_REMATCH[2]} cfn=${BASH_REMATCH[4]}
        if [[ -n ${CRUD_ANSWER[$name]-} ]]; then REPLY=${CRUD_ANSWER[$name]}
        elif [[ -n $cfn ]] && "$cfn"; then
            # Pick from a list (function from choices.sh).
            local c; local -a cl it=()
            IFS=, read -r -a cl <<< "$REPLY"
            for c in "${cl[@]}"; do it+=("${c%%=*}" "${c#*=}"); done
            dlg_menu "${CRUD[$fn|label]:-}" "$prompt" "${it[@]}" || return 1
        else dlg_input "${CRUD[$fn|label]:-}" "$prompt" "" || return 1
        fi
        [[ -n $REPLY ]] || return 1
        t=${t//"$whole"/$REPLY}
    done
    REPLY=$t
}
declare -gA CRUD_ANSWER=()   # preset answers for {?name:...} (tests)

# typefields="type1:f1 f2 ...;type2:..." restricts the fields per type.
_crud_typefields() {
    local e
    local -a list
    IFS=';' read -r -a list <<< "${CRUD[$1|typefields]-}"
    for e in "${list[@]}"; do
        [[ ${e%%:*} == "$2" ]] && { FORM_ONLY=${e#*:}; FORM_FIRST=$FORM_ONLY; }
    done
    return 0
}

# Fill FORM_CHOICES from "field:function" pairs.
_crud_choices() {
    local c
    for c in ${CRUD[$1|choices]-}; do
        "${c#*:}" && FORM_CHOICES[${c%%:*}]=$REPLY
    done
    return 0
}

# Apply "k=v k2=v2" to FORM_FIX.
_crud_fix() {
    local kv
    for kv in $1; do
        _crud_path "${kv#*=}" "$2" || return 1
        FORM_FIX[${kv%%=*}]=$REPLY
    done
}

crud_add() {
    local fn=$1 path label
    if [[ -n ${CRUD_SUBS[$fn]-} ]]; then
        # Several kinds of objects: ask which one (default: kind of the selected row).
        local sub; local -a items=()
        for sub in ${CRUD_SUBS[$fn]}; do
            [[ -n ${CRUD[$fn:$sub|add]-} && -z ${CRUD[$fn:$sub|noadd]-} ]] || continue
            T "${CRUD[$fn:$sub|label]:-$sub}"; items+=("$sub" "$REPLY")
        done
        (( ${#items[@]} )) || return 1
        if [[ -n ${CRUD_ANSWER[sub]-} ]]; then sub=${CRUD_ANSWER[sub]}
        elif (( ${#items[@]} == 2 )); then sub=${items[0]}
        else T "Add"; dlg_menu "$REPLY" "" "${items[@]}" || return 0; sub=$REPLY
        fi
        fn="$fn:$sub"
    fi
    label=${CRUD[$fn|label]:-item}
    [[ -n ${CRUD[$fn|add]-} ]] || return 1
    form_reset
    _crud_path "${CRUD[$fn|add]}" "" || return 0
    path=$REPLY
    FORM_FIRST=${CRUD[$fn|first]-} FORM_HIDE=${CRUD[$fn|hide]-} FORM_ONLY=${CRUD[$fn|only]-}
    [[ -n ${CRUD[$fn|async]-} ]] && FORM_ASYNC=1
    [[ -n ${CRUD[$fn|sync]-} ]] && FORM_ASYNC=0
    [[ -n ${CRUD[$fn|result]-} ]] && FORM_SHOW_RESULT=1
    _crud_fix "${CRUD[$fn|fix]-}" "" || return 0
    _crud_choices "$fn"
    local tf=${CRUD[$fn|typefield]:-type}
    if [[ -n ${CRUD[$fn|plugin]-} || -n ${CRUD[$fn|types]-} ]]; then
        local types=${CRUD[$fn|types]-} t
        if [[ -z $types && -n ${CRUD[$fn|pathtype]-} ]]; then types=${CRUD[$fn|types]}
        elif [[ -z $types ]]; then
            # Allowed values of the type parameter, from the API schema.
            api_get schema "$path" "method=POST" ""
            local row; local -a f
            for row in "${API_ROWS[@]}"; do
                tsv_split f "$row"; [[ ${f[0]} == "$tf" ]] && types=${f[4]}
            done
        fi
        if [[ -n ${CRUD_ANSWER[type]-} ]]; then t=${CRUD_ANSWER[type]}
        else
            local -a items=()
            for t in ${types//,/ }; do T "${TYPE_LABELS[$t]:-$t}"; items+=("$t" "$REPLY"); done
            Tf "Add: %s" "$label"
            dlg_menu "$REPLY" "Type:" "${items[@]}" || return 0
            t=$REPLY
        fi
        if [[ -n ${CRUD[$fn|pathtype]-} ]]; then path=${path//\{type\}/$t}; else FORM_FIX[$tf]=$t; fi
        if [[ -n ${CRUD[$fn|plugin]-} ]]; then FORM_PLUGIN=${CRUD[$fn|plugin]} FORM_PLUGIN_TYPE=$t; fi
        _crud_typefields "$fn" "$t"
        T "${TYPE_LABELS[$t]:-$t}"; label="$label: $REPLY"
    fi
    Tf "Add: %s" "$label"
    form_run "$REPLY" POST "$path" && content_load 1
    return 0
}

crud_edit() {
    local fn=$1 key=$2 path label=${CRUD[$1|label]:-item}
    [[ -n ${CRUD[$fn|edit]-} && -z ${CRUD[$fn|noedit]-} && -n $key ]] || return 1
    form_reset
    _crud_path "${CRUD[$fn|edit]}" "$key" || return 0
    path=$REPLY
    _crud_path "${CRUD[$fn|get]:-${CRUD[$fn|edit]}}" "$key"; FORM_GET=$REPLY
    FORM_FIRST=${CRUD[$fn|first]-} FORM_HIDE=${CRUD[$fn|hide]-} FORM_ONLY=${CRUD[$fn|editonly]:-${CRUD[$fn|only]-}}
    [[ -n ${CRUD[$fn|result]-} ]] && FORM_SHOW_RESULT=1
    _crud_fix "${CRUD[$fn|editfix]-}" "$key" || return 0
    _crud_choices "$fn"
    if [[ -n ${CRUD[$fn|plugin]-} ]]; then
        api_kv "$FORM_GET"
        FORM_PLUGIN=${CRUD[$fn|plugin]} FORM_PLUGIN_TYPE=${API_KV[${CRUD[$fn|typefield]:-type}]-}
        FORM_HIDE+=" ${CRUD[$fn|typefield]:-type}"
    fi
    if [[ -n ${CRUD[$fn|typefields]-} ]]; then
        api_kv "$FORM_GET"
        _crud_typefields "$fn" "${API_KV[${CRUD[$fn|typefield]:-type}]-}"
    fi
    Tf "Edit: %s" "$label"
    form_run "$REPLY ${key//|/ }" PUT "$path" && content_load 1
    return 0
}

crud_del() {
    local fn=$1 key=$2 path label=${CRUD[$1|label]:-item}
    [[ -n ${CRUD[$fn|del]-} && -n $key ]] || return 1
    _crud_path "${CRUD[$fn|del]}" "$key" || return 0
    path=$REPLY
    Tf "Remove %s '%s'?" "$label" "${key//|/ }"
    confirm "$REPLY" || return 0
    local -a extra=()
    if [[ -n ${CRUD[$fn|delargs]-} ]]; then
        _crud_path "${CRUD[$fn|delargs]}" "$key"
        read -r -a extra <<< "$REPLY"
    fi
    Tf "Remove: %s %s" "$label" "${key//|/ }"
    if [[ -n ${CRUD[$fn|async]-} ]]; then
        api_exec "$REPLY" delete "$path" "${extra[@]}"
    else
        api_exec_sync "$REPLY" delete "$path" "${extra[@]}" && content_load 1
    fi
    return 0
}

# Key dispatcher: a/Insert = add, e = edit, d/Delete = remove.
crud_key() {
    local fn=$1 k=$2 key=$3
    crud_has "$fn" || return 1
    CRUD_SEL=$key
    [[ -n ${CRUD_SUBS[$fn]-} ]] && CRUD_SEL=${key#*|}
    case $k in
        a|INS) [[ -z ${CRUD[$fn|noadd]-} ]] && crud_add "$fn" && return 0 ;;
        e) _crud_resolve "$fn" "$key" && crud_edit "$CRUD_FN" "$CRUD_KEY" && return 0 ;;
        d|DEL) _crud_resolve "$fn" "$key" && [[ -z ${CRUD[$CRUD_FN|nodel]-} ]] && crud_del "$CRUD_FN" "$CRUD_KEY" && return 0 ;;
    esac
    return 1
}

# Enter on a row of a CRUD panel = edit.
crud_enter() {
    CRUD_SEL=$2
    [[ -n ${CRUD_SUBS[$1]-} ]] && CRUD_SEL=${2#*|}
    _crud_resolve "$1" "$2" && crud_edit "$CRUD_FN" "$CRUD_KEY"
}

# Capabilities of multi-table panels (union of their sub tables); the buttons
# themselves are drawn by the layout from crud_hints (see panel_buttons).
crud_buttons() {
    local fn=$1 b="" sub
    if [[ -n ${CRUD_SUBS[$fn]-} ]]; then
        # Union of the capabilities of the sub tables.
        for sub in ${CRUD_SUBS[$fn]}; do
            [[ -n ${CRUD[$fn:$sub|add]-} ]] && CRUD[$fn|add]=1
            [[ -n ${CRUD[$fn:$sub|edit]-} ]] && CRUD[$fn|edit]=1
            [[ -n ${CRUD[$fn:$sub|del]-} ]] && CRUD[$fn|del]=1
        done
    fi
    REPLY=""
}
crud_hints() {
    local fn=$1 h=""
    [[ -n ${CRUD[$fn|add]-} && -z ${CRUD[$fn|noadd]-} ]] && h+="a:Add "
    [[ -n ${CRUD[$fn|edit]-} && -z ${CRUD[$fn|noedit]-} ]] && h+="e:Edit "
    [[ -n ${CRUD[$fn|del]-} && -z ${CRUD[$fn|nodel]-} ]] && h+="d:Remove "
    h+=${CRUD[$fn|extra]-}
    REPLY=$h
}
