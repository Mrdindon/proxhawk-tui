# shellcheck shell=bash
# form.sh - edit dialogs generated from the API schema.
#
# Every create/edit dialog of the web UI maps to one API call (POST or PUT).
# form_run reads the parameter definitions of that call from the API itself
# (types, allowed values, defaults, descriptions, property strings) and builds
# a menu-driven form: select a field to change it, then "OK". Only the
# changed values are sent; emptied values are removed with "delete".
#
#   form_reset
#   FORM_FIRST="name memory cores"     # basic fields, in this order
#   FORM_GET=/nodes/n/qemu/100/config  # prefill from this GET path (edit dialogs)
#   FORM_FIX[type]=dir                 # fixed parameters (not shown)
#   form_run "Add: Directory" POST /storage
#
# Options (globals, cleared by form_reset):
#   FORM_ONLY       space separated list: show only these fields
#   FORM_FIRST      fields shown first (the others are under "Advanced")
#   FORM_HIDE       fields never shown
#   FORM_GET        GET path used to prefill the values
#   FORM_FIX[k]     fixed parameters sent with the request
#   FORM_VAL[k]     initial values (override FORM_GET)
#   FORM_LABEL[k]   display labels
#   FORM_CHOICES[k] "value=Label,value2=Label2" choices offered for a free text field
#   FORM_PLUGIN     plugin family (storage, realm, sdnzone, ...) and
#   FORM_PLUGIN_TYPE  type: restricts the fields to the options of that type
#   FORM_CREATE_ONLY=1 with FORM_PLUGIN on an edit: hide "fixed" options
#   FORM_ASYNC      1 = run in the background, 0 = wait, "" = auto (task => background)
#   FORM_AUTO=1     no dialog: submit FORM_VAL directly (used by the tests)
#   FORM_SHOW_RESULT=1  display the output of the call (e.g. new API token secret)
# Result: rc 0 when the call succeeded; FORM_RESULT holds its output.

declare -gA FORM_FIX=() FORM_VAL=() FORM_LABEL=() FORM_CHOICES=()
declare -gA FORM_PRESET=()   # values applied on top of everything (tests, not reset)
FORM_ONLY="" FORM_FIRST="" FORM_HIDE="" FORM_GET="" FORM_ASYNC="" FORM_AUTO=${FORM_AUTO:-0}
FORM_PLUGIN="" FORM_PLUGIN_TYPE="" FORM_CREATE_ONLY=0 FORM_SHOW_RESULT=0 FORM_RESULT="" FORM_TEXT=""

# Parameters that are handled by the forms themselves.
_FORM_ALWAYS_HIDE=" digest delete revert skiplock background_delay "

form_reset() {
    FORM_FIX=() FORM_VAL=() FORM_LABEL=() FORM_CHOICES=()
    FORM_ONLY="" FORM_FIRST="" FORM_HIDE="" FORM_GET="" FORM_ASYNC=""
    FORM_PLUGIN="" FORM_PLUGIN_TYPE="" FORM_CREATE_ONLY=0 FORM_SHOW_RESULT=0 FORM_TEXT=""
}

# Labels used by the web UI for common parameters.
declare -gA FORM_LABELS_STD=(
    [userid]="User name" [firstname]="First Name" [lastname]="Last Name" [email]="E-Mail" [expire]="Expire"
    [enable]="Enabled" [comment]="Comment" [comments]="Comment" [groups]="Group" [keys]="Key IDs" [password]="Password"
    [groupid]="Name" [poolid]="Name" [roleid]="Name" [privs]="Privileges" [realm]="Realm" [tokenid]="Token ID"
    [privsep]="Privilege Separation" [storage]="ID" [content]="Content" [nodes]="Nodes" [disable]="Disable"
    [shared]="Shared" [path]="Path" [server]="Server" [export]="Export" [share]="Share" [username]="Username"
    [datastore]="Datastore" [fingerprint]="Fingerprint" [namespace]="Namespace" [vgname]="Volume group"
    [thinpool]="Thin Pool" [pool]="Pool" [monhost]="Monitor(s)" [portal]="Portal" [target]="Target"
    [schedule]="Schedule" [vmid]="Selection" [all]="All" [exclude]="Exclude" [mode]="Mode" [compress]="Compression"
    [node]="Node" [mailto]="Send email to" [notes-template]="Note Template" [sid]="VM" [state]="Request State"
    [max_restart]="Max. Restart" [max_relocate]="Max. Relocate" [failback]="Failback" [rule]="ID" [resources]="Resources"
    [affinity]="Affinity" [strict]="Strict" [zone]="ID" [vnet]="Name" [alias]="Alias" [tag]="Tag"
    [vlanaware]="VLAN Aware" [subnet]="Subnet" [gateway]="Gateway" [snat]="SNAT" [dhcp-range]="DHCP Ranges"
    [bridge]="Bridge" [mtu]="MTU" [ipam]="IPAM" [dns]="DNS Server" [reversedns]="Reverse DNS Server"
    [dnszone]="DNS Zone" [controller]="ID" [asn]="ASN #" [peers]="Peers" [id]="ID" [type]="Type"
    [action]="Action" [macro]="Macro" [iface]="Interface" [source]="Source" [dest]="Destination"
    [proto]="Protocol" [dport]="Dest. port" [sport]="Source port" [log]="Log level" [pos]="Position"
    [icmp-type]="ICMP type" [name]="Name" [cidr]="CIDR" [nomatch]="nomatch" [port]="Port"
    [map]="Mapping" [description]="Description" [cputype]="Name" [reported-model]="Base model" [flags]="Flags"
    [hidden]="Hidden" [contact]="E-Mail" [directory]="ACME Directory" [api]="DNS API" [data]="API Data"
    [validation-delay]="Validation Delay" [autostart]="Autostart" [bridge_ports]="Bridge ports"
    [bridge_vlan_aware]="VLAN aware" [slaves]="Slaves" [bond_mode]="Mode" [cidr6]="IPv6/CIDR" [gateway6]="Gateway (IPv6)"
    [vlan-raw-device]="Vlan raw device" [vlan-id]="VLAN Tag" [search]="Search domain" [dns1]="DNS server 1"
    [dns2]="DNS server 2" [dns3]="DNS server 3" [timezone]="Time zone" [device]="Disk" [devices]="Disks"
    [add_storage]="Add Storage" [filesystem]="Filesystem" [raidlevel]="RAID Level" [compression]="Compression"
    [ashift]="ashift" [memory]="Memory (MiB)" [balloon]="Minimum memory (MiB)" [shares]="Shares" [sockets]="Sockets"
    [cores]="Cores" [cpu]="Type" [cpulimit]="VCPU limit" [cpuunits]="CPU units" [numa]="Enable NUMA"
    [vcpus]="VCPUs" [swap]="Swap (MiB)" [onboot]="Start at boot" [startup]="Start/Shutdown order"
    [hostname]="Hostname" [searchdomain]="DNS domain" [nameserver]="DNS servers" [ciuser]="User"
    [cipassword]="Password" [sshkeys]="SSH public key" [protection]="Protection" [size]="Size" [min_size]="Min. Size"
    [pg_num]="# of PGs" [pg_autoscale_mode]="PG Autoscale Mode" [crush_rule]="Crush Rule"
    [application]="Application" [add_storages]="Add as Storage" [dev]="Disk" [db_dev]="DB Disk" [wal_dev]="WAL Disk"
    [encrypted]="Encrypt OSD" [crush-device-class]="Device Class" [network]="Public Network" [cluster-network]="Cluster Network"
    [clustername]="Cluster Name" [link0]="Link 0" [link1]="Link 1"
)

# Human label of a parameter: explicit label, web UI label, else "some-name_x" -> "Some name x".
_form_label() {
    local n=$1
    if [[ -n ${FORM_LABEL[$n]-} ]]; then T "${FORM_LABEL[$n]}"; return; fi
    if [[ -n ${FORM_LABELS_STD[$n]-} ]]; then T "${FORM_LABELS_STD[$n]}"; return; fi
    local l=${n//[-_]/ }
    REPLY="${l^}"
}

form_run() {
    local title=$1 method=$2 path=$3
    local row n returns="" has_delete=0
    local -a names=() f
    local -A ty=() opt=() def=() en=() tt=() desc=() kind=() pw=() allowed=() fixedopt=() FV=() FO=()
    FORM_RESULT=""
    T "$title"; title=$REPLY

    if ! api_get schema "$path" "method=$method" ""; then
        dlg_msg "$title" "$API_ERR"
        return 1
    fi
    for row in "${API_ROWS[@]}"; do
        if [[ $row == $'\x01returns\t'* ]]; then returns=${row#*$'\t'}; continue; fi
        tsv_split f "$row"
        n=${f[0]}
        # "delete" lists the options to remove (some calls use a boolean "delete").
        [[ $n == delete && ${f[1]} != boolean ]] && has_delete=1
        names+=("$n")
        ty[$n]=${f[1]-string} opt[$n]=${f[2]-1} def[$n]=${f[3]-} en[$n]=${f[4]-} tt[$n]=${f[5]-}
        desc[$n]=${f[6]-} kind[$n]=${f[7]-} pw[$n]=${f[10]-0}
    done

    # Restrict to the options of a plugin type (storage type, realm type...).
    if [[ -n $FORM_PLUGIN ]]; then
        if api_get pluginopts "$FORM_PLUGIN" "type=$FORM_PLUGIN_TYPE" ""; then
            for row in "${API_ROWS[@]}"; do
                [[ $row == $'\x01'* ]] && continue
                tsv_split f "$row"
                allowed[${f[0]}]=1
                [[ ${f[2]} == 1 ]] && fixedopt[${f[0]}]=1
                # Required for this plugin type: shown with the basic fields
                # (not enforced: the API fills some of them, e.g. NFS paths).
                [[ ${f[1]} == 0 ]] && FORM_FIRST+=" ${f[0]}"
            done
        fi
    fi

    # Current values.
    if [[ -n $FORM_GET ]] && api_kv "$FORM_GET"; then
        for n in "${!API_KV_RAW[@]}"; do
            FO[$n]=${API_KV_RAW[$n]//$'\x1f'/$'\n'}
            FO[$n]=${FO[$n]//$'\x1e'/ ; }
            FV[$n]=${FO[$n]}
        done
    fi
    for n in "${!FORM_VAL[@]}"; do FV[$n]=${FORM_VAL[$n]}; done
    for n in "${!FORM_PRESET[@]}"; do FV[$n]=${FORM_PRESET[$n]}; done

    # Visible fields: FORM_FIRST order, then required ones, then the rest.
    local -a vis=() basic=()
    local -A seen=()
    _form_visible() {
        local x=$1
        [[ -n ${seen[$x]-} || -z ${ty[$x]-} ]] && return 1
        [[ $_FORM_ALWAYS_HIDE == *" $x "* || " $FORM_HIDE " == *" $x "* || -v FORM_FIX[$x] ]] && return 1
        [[ -n $FORM_ONLY && " $FORM_ONLY " != *" $x "* ]] && return 1
        if [[ -n $FORM_PLUGIN ]]; then
            # Options of the plugin type, plus the required parameters of the
            # call (object ID such as "storage", "realm", "rule"...).
            [[ -n ${allowed[$x]-} || ${opt[$x]} == 0 ]] || return 1
            [[ $method == PUT && -n ${fixedopt[$x]-} ]] && return 1
        fi
        seen[$x]=1
        return 0
    }
    for n in $FORM_FIRST; do _form_visible "$n" && { vis+=("$n"); basic+=("$n"); }; done
    for n in "${names[@]}"; do [[ ${opt[$n]} == 0 ]] && _form_visible "$n" && { vis+=("$n"); basic+=("$n"); }; done
    for n in "${names[@]}"; do _form_visible "$n" && vis+=("$n"); done

    local adv=0
    [[ -n $FORM_ONLY || ${#basic[@]} -eq 0 || ${#vis[@]} -le 8 ]] && adv=1

    while :; do
        if (( FORM_AUTO )); then
            _form_submit && return 0
            return 1
        fi
        local -a items=()
        if [[ $method == POST ]]; then T "Create"; elif [[ $method == DELETE ]]; then T "Remove"; else T "OK"; fi
        items+=(_ok "${G[st_ok]} $REPLY")
        local shown=0 hidden=0 v lab
        for n in "${vis[@]}"; do
            if (( ! adv )) && [[ " ${basic[*]} " != *" $n "* && -z ${FV[$n]-} ]]; then (( hidden++ )); continue; fi
            _form_label "$n"; lab=$REPLY
            [[ ${opt[$n]} == 0 ]] && lab+=" *"
            v=${FV[$n]-}
            [[ ${pw[$n]} == 1 && -n $v ]] && v="********"
            if [[ -z $v ]]; then
                if [[ -n ${def[$n]} ]]; then T "Default"; v="($REPLY: ${def[$n]})"; else v=""; fi
            fi
            v=${v//$'\n'/ }
            printf -v lab '%-28.28s %s' "$lab" "${v:0:60}"
            items+=("$n" "$lab")
            (( shown++ ))
        done
        if (( hidden )); then Tf "Advanced (%d more options)" "$hidden"; items+=(_adv "${G[exp_closed]} $REPLY"); fi
        local text=${FORM_TEXT:-}
        [[ -z $text ]] && { T "Select a field to change it, then the first line to apply.  * = required"; text=$REPLY; }
        DLG_NOTAGS=1
        DLG_OK_LABEL="Select" DLG_CANCEL_LABEL="Cancel" dlg_menu "$title" "$text" "${items[@]}" || { DLG_NOTAGS=0; return 1; }
        DLG_NOTAGS=0
        case $REPLY in
            _ok) _form_submit && return 0 ;;
            _adv) adv=1 ;;
            *) _form_field "$REPLY" ;;
        esac
    done
}

# Edit one field (uses the arrays of form_run through dynamic scoping).
_form_field() {
    local n=$1 cur=${FV[$1]-} lab text
    _form_label "$n"; lab=$REPLY
    text=${desc[$n]}
    [[ -n ${tt[$n]} && ${tt[$n]} != "<string>" ]] && text+=$'\n\n'"Format: ${tt[$n]}"
    [[ -n ${def[$n]} ]] && text+=$'\n'"Default: ${def[$n]}"
    local -a items=()
    if [[ -n ${FORM_CHOICES[$n]-} ]]; then
        local c
        local -a cl
        IFS=, read -r -a cl <<< "${FORM_CHOICES[$n]}"
        for c in "${cl[@]}"; do items+=("${c%%=*}" "${c#*=}"); done
        T "Other..."; items+=(_other "$REPLY")
        dlg_menu "$lab" "$text" "${items[@]}" || return
        if [[ $REPLY == _other ]]; then dlg_input "$lab" "$text" "$cur" || return; fi
        FV[$n]=$REPLY
    elif [[ ${ty[$n]} == boolean ]]; then
        T "Yes"; items+=(1 "$REPLY"); T "No"; items+=(0 "$REPLY")
        T "Default"; items+=(_def "$REPLY${def[$n]:+ (${def[$n]})}")
        dlg_menu "$lab" "$text" "${items[@]}" || return
        [[ $REPLY == _def ]] && REPLY=""
        FV[$n]=$REPLY
    elif [[ -n ${en[$n]} ]]; then
        local e
        for e in ${en[$n]//,/ }; do items+=("$e" ""); done
        T "Default"; items+=(_def "$REPLY${def[$n]:+ (${def[$n]})}")
        dlg_menu "$lab" "$text" "${items[@]}" || return
        [[ $REPLY == _def ]] && REPLY=""
        FV[$n]=$REPLY
    elif [[ ${kind[$n]} == propstr ]]; then
        _form_propstr "$n" || return
        FV[$n]=$REPLY
    elif [[ ${pw[$n]} == 1 ]]; then
        dlg_password "$lab" "$text" || return
        FV[$n]=$REPLY
    else
        [[ ${kind[$n]} == array ]] && text+=$'\n'"Several values: separate them with ' ; '"
        dlg_input "$lab" "$text" "${cur//$'\n'/ ; }" || return
        FV[$n]=$REPLY
    fi
}

# Sub-form of a property string ("virtio,bridge=vmbr0,firewall=1").
_form_propstr() {
    local n=$1 row sn
    local -a f snames=()
    local -A sty=() sopt=() sdef=() sen=() stt=() sdesc=() SV=()
    api_get schema "$path" "method=$method&param=$n" "" || { dlg_msg "$n" "$API_ERR"; return 1; }
    for row in "${API_ROWS[@]}"; do
        tsv_split f "$row"
        sn=${f[0]}; snames+=("$sn")
        sty[$sn]=${f[1]} sopt[$sn]=${f[2]} sdef[$sn]=${f[3]} sen[$sn]=${f[4]} stt[$sn]=${f[5]} sdesc[$sn]=${f[6]}
    done
    if [[ -n ${FV[$n]-} ]]; then
        urlenc "${FV[$n]}"
        if api_get propparse "$path" "method=$method&param=$n&value=$REPLY" ""; then
            for row in "${API_ROWS[@]}"; do SV[${row%%$'\t'*}]=${row#*$'\t'}; done
        fi
    fi
    while :; do
        local -a items=()
        T "OK"; items+=(_ok "${G[st_ok]} $REPLY")
        local lab v
        for sn in "${snames[@]}"; do
            lab=$sn; [[ ${sopt[$sn]} == 0 ]] && lab+=" *"
            v=${SV[$sn]-}
            [[ -z $v && -n ${sdef[$sn]} ]] && { T "Default"; v="($REPLY: ${sdef[$sn]})"; }
            printf -v lab '%-24.24s %s' "$lab" "${v:0:60}"
            items+=("$sn" "$lab")
        done
        _form_label "$n"
        DLG_NOTAGS=1
        DLG_OK_LABEL="Select" DLG_CANCEL_LABEL="Cancel" dlg_menu "$REPLY" "${desc[$n]}" "${items[@]}" || { DLG_NOTAGS=0; return 1; }
        DLG_NOTAGS=0
        sn=$REPLY
        if [[ $sn == _ok ]]; then
            local q="method=$method&param=$n"
            for sn in "${!SV[@]}"; do
                [[ -n ${SV[$sn]} ]] || continue
                urlenc "${SV[$sn]}"; q+="&$sn=$REPLY"
            done
            api_get propprint "$path" "$q" "" || { dlg_msg "$n" "$API_ERR"; continue; }
            REPLY=${API_ROWS[0]-}
            return 0
        fi
        local text=${sdesc[$sn]}
        [[ -n ${stt[$sn]} ]] && text+=$'\n\n'"Format: ${stt[$sn]}"
        [[ -n ${sdef[$sn]} ]] && text+=$'\n'"Default: ${sdef[$sn]}"
        local -a opts=()
        if [[ ${sty[$sn]} == boolean ]]; then
            opts=(1 Yes 0 No _def Default)
            dlg_menu "$sn" "$text" "${opts[@]}" || continue
            [[ $REPLY == _def ]] && REPLY=""
        elif [[ -n ${sen[$sn]} ]]; then
            local e; for e in ${sen[$sn]//,/ }; do opts+=("$e" ""); done
            opts+=(_def Default)
            dlg_menu "$sn" "$text" "${opts[@]}" || continue
            [[ $REPLY == _def ]] && REPLY=""
        else
            dlg_input "$sn" "$text" "${SV[$sn]-}" || continue
        fi
        SV[$sn]=$REPLY
    done
}

# Build the arguments and run the call. rc 0 = success.
_form_submit() {
    local n v cmd=create
    local -a args=() del=()
    [[ $method == PUT ]] && cmd=set
    [[ $method == DELETE ]] && cmd=delete
    # Required values are only marked with "*": the schema of some calls
    # (one-of variants per type) is stricter than the API itself, which
    # validates the request and reports the precise error.
    for n in "${names[@]}"; do
        [[ -v FORM_FIX[$n] ]] && continue
        [[ $_FORM_ALWAYS_HIDE == *" $n "* ]] && continue
        v=${FV[$n]-}
        if [[ $method == PUT ]]; then
            # Unchanged values are normally not sent. Exceptions: parameters
            # required by the call, arrays (replaced as a whole) and calls
            # without a "delete" parameter, which replace the whole object
            # (e.g. node DNS): omitting a value there would remove it.
            if [[ $v == "${FO[$n]-}" ]]; then
                [[ ( ${opt[$n]} == 0 || ${kind[$n]} == array || $has_delete == 0 ) && -n $v ]] || continue
            fi
            if [[ -z $v ]]; then [[ -n ${FO[$n]-} ]] && del+=("$n"); continue; fi
        else
            [[ -z $v ]] && continue
        fi
        if [[ ${kind[$n]} == array ]]; then
            local item
            local -a items
            IFS=';' read -r -a items <<< "${v//$'\n'/;}"
            for item in "${items[@]}"; do
                item=${item#"${item%%[![:space:]]*}"}; item=${item%"${item##*[![:space:]]}"}
                [[ -n $item ]] && args+=("--$n" "$item")
            done
        else
            args+=("--$n" "$v")
        fi
    done
    for n in "${!FORM_FIX[@]}"; do args+=("--$n" "${FORM_FIX[$n]}"); done
    if (( ${#del[@]} )); then
        # Without a "delete" parameter the call replaces the object: the
        # emptied values are simply not sent.
        if (( has_delete )); then local IFS=,; args+=(--delete "${del[*]}"); unset IFS; fi
    fi
    if [[ $method == PUT && ${#args[@]} -eq 0 && ${#del[@]} -eq 0 ]]; then
        T "No changes"; status_msg info "$REPLY"; return 0
    fi
    local async=$FORM_ASYNC
    if [[ -z $async ]]; then
        async=0
        [[ $returns == string && $method == POST ]] && async=1
    fi
    log "form: pvesh $cmd $path ${args[*]}"
    if (( async )) && (( ! FORM_AUTO )); then
        api_exec "$title" "$cmd" "$path" "${args[@]}"
        return 0
    fi
    if api_exec_sync "$title" "$cmd" "$path" "${args[@]}"; then
        FORM_RESULT=$(< "$RUN_DIR/job.sync.log")
        if (( FORM_SHOW_RESULT && ! FORM_AUTO )); then
            printf '%s\n' "$FORM_RESULT" > "$RUN_DIR/result.txt"
            dlg_textbox "$title" "$RUN_DIR/result.txt"
        fi
        return 0
    fi
    FORM_RESULT=$(< "$RUN_DIR/job.sync.log")
    API_ERR=$(api_error_line "$RUN_DIR/job.sync.log")
    (( FORM_AUTO )) || dlg_msg "$title" "$API_ERR"
    return 1
}
