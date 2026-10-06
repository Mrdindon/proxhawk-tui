# shellcheck shell=bash
# views/firewall.sh - firewall panels shared by the Datacenter, nodes and
# guests: Rules, Options, Security Group, Alias, IPSet, Log.

FW_SPEC="pos:#:4:s:r|enable:On:4:bool|type:Direction:10|action:Action:8|macro:Macro:10|iface:Interface:10|source:Source:16|dest:Destination:16|proto:Protocol:9|dport:Dest. port:11|sport:Source port:11|log:Log level:10|comment:Comment:*"
FW_RULE_FIRST="type action macro iface source dest proto dport sport enable log comment icmp-type"

# Firewall options with the defaults shown by the web UI.
# fw_options <path> <dc|node|guest>
fw_options() {
    local path=$1 level=$2 e k v l d f
    local -a opts
    api_kv "$path" || { c_api_error; return; }
    case $level in
        dc) opts=("enable:Firewall:No:bool" "ebtables:ebtables:Yes:bool" "log_ratelimit:Log rate limit:Default (enable=1,rate1/second,burst=5)"
                  "policy_in:Input Policy:DROP" "policy_out:Output Policy:ACCEPT" "policy_forward:Forward Policy:ACCEPT") ;;
        node) opts=("enable:Firewall:Yes:bool" "smurfs:SMURFS filter:Yes:bool" "tcpflags:TCP flags filter:No:bool"
                  "nf_conntrack_max:nf_conntrack_max:262144" "nf_conntrack_tcp_timeout_established:nf_conntrack_tcp_timeout_established:432000"
                  "ndp:NDP:Yes:bool" "nftables:nftables (tech preview):No:bool" "log_level_in:log_level_in:nolog"
                  "log_level_out:log_level_out:nolog" "log_level_forward:log_level_forward:nolog"
                  "tcp_flags_log_level:tcp_flags_log_level:nolog" "smurf_log_level:smurf_log_level:nolog") ;;
        *) opts=("enable:Firewall:No:bool" "dhcp:DHCP:Yes:bool" "ndp:NDP:Yes:bool" "radv:Router Advertisement:No:bool"
                 "macfilter:MAC filter:Yes:bool" "ipfilter:IP filter:No:bool" "log_level_in:log_level_in:nolog"
                 "log_level_out:log_level_out:nolog" "policy_in:Input Policy:DROP" "policy_out:Output Policy:ACCEPT") ;;
    esac
    for e in "${opts[@]}"; do
        IFS=: read -r k l d f <<< "$e"
        v=${API_KV[$k]-}
        if [[ -n $v && $f == bool ]]; then fmtv bool "$v"; v=$REPLY; fi
        [[ -z $v ]] && { T "$d"; v="${C[dim]}${REPLY}${C[norm]}"; }
        c_kv_sel "$l" "$v" "$k" 36
    done
}

# Security groups / IPSets: parent rows followed by their children.
# _fw_nested <list path> <name field> <child path suffix> <parent prefix> <child prefix> <child spec> <child key field>
_fw_nested() {
    local list=$1 nf=$2 pre=$4 cpre=$5 cspec=$6 ckey=$7 name row n=0
    local -a names
    api_get rows "$list" "" "$nf,comment" || { c_api_error; return; }
    mapfile -t names < <(printf '%s\n' "${API_ROWS[@]}")
    table_spec "name:Name:24|comment:Comment:*"
    table_header
    for row in "${names[@]}"; do
        [[ -n $row ]] || continue
        name=${row%%$'\t'*}
        table_row "$row"
        c_sel "${C[title]}${REPLY}${C[norm]}" "$pre|$name"
        (( n++ ))
        local save_spec=("${TS_F[@]}")
        table_spec "$cspec"
        if api_get rows "$list/$name" "" "$TS_FIELDS"; then
            local r; local -a v
            for r in "${API_ROWS[@]}"; do
                tsv_split v "$r"
                table_row "$r"
                c_sel "    $REPLY" "$cpre|$name|${v[ckey]}"
            done
        fi
        table_spec "name:Name:24|comment:Comment:*"
    done
    (( n )) || c_msg dim "No items"
}

# Register the firewall panels of a context: fw_register <type> <base path> <level>
fw_register() {
    local t=$1 base=$2 level=$3
    eval "
v_${t}_firewall() { _crud_path '$base/rules'; view_table \"\$REPLY\" \"\" \"\$FW_SPEC\"; }
v_${t}_fwoptions() { fw_options \"\$(_crud_path '$base/options'; printf '%s' \"\$REPLY\")\" $level; }
v_${t}_fwoptions__enter() { _crud_path '$base/options'; _option_form Firewall \"\$REPLY\" \"\$1\"; }
v_${t}_fwoptions__key() { [[ \$1 == e ]] && { v_${t}_fwoptions__enter \"\$2\"; return 0; }; return 1; }
v_${t}_fwalias() { _crud_path '$base/aliases'; view_table \"\$REPLY\" \"\" \"name:Name:24|cidr:IP/CIDR:24|comment:Comment:*\"; }
v_${t}_fwipset() { _crud_path '$base/ipset'; _fw_nested \"\$REPLY\" name '' ipset cidr 'cidr:IP/CIDR:30|nomatch:nomatch:8:bool|comment:Comment:*' 0; }
v_${t}_fwlog() {
    local l
    _crud_path '$base/log'
    api_get rows \"\$REPLY\" \"limit=1000\" \"t\" || { c_api_error; return; }
    for l in \"\${API_ROWS[@]}\"; do c_add \"\$l\"; done
    (( \${#API_ROWS[@]} )) || c_msg dim \"No items\"
    C_SCROLL=999999
}
v_${t}_firewall__key() {
    [[ \$1 == m && -n \$2 ]] || return 1
    dlg_input \"Move rule\" \"New position of rule \$2:\" \"\" || return 0
    local to=\$REPLY
    _crud_path '$base/rules/'\"\$2\"
    api_exec_sync \"Move rule \$2\" set \"\$REPLY\" --moveto \"\$to\"
    content_load 1
    return 0
}
"
    crud "v_${t}_firewall" label="Rule" add="$base/rules" edit="$base/rules/{1}" del="$base/rules/{1}" \
        first="$FW_RULE_FIRST" choices="macro:choice_fw_macros" extra="m:Move"
    crud "v_${t}_fwalias" label="Alias" add="$base/aliases" edit="$base/aliases/{1}" del="$base/aliases/{1}" first="name cidr comment"
    crud "v_${t}_fwipset:ipset" label="IPSet" add="$base/ipset" del="$base/ipset/{1}" noedit=1 first="name comment"
    crud "v_${t}_fwipset:cidr" label="IP/CIDR" add="$base/ipset/{s1}" edit="$base/ipset/{1}/{2}" del="$base/ipset/{1}/{2}" first="cidr nomatch comment"
    VIEW_HINT[v_${t}_fwoptions]="Enter:Edit"
}

fw_register dc /cluster/firewall dc
fw_register node "/nodes/{node}/firewall" node
fw_register qemu "/nodes/{node}/{gtype}/{vmid}/firewall" guest
fw_register lxc "/nodes/{node}/{gtype}/{vmid}/firewall" guest

# Datacenter security groups: groups and their rules ("group|name", "grule|name|pos").
v_dc_fwgroups() { _fw_nested /cluster/firewall/groups group '' group grule "$FW_SPEC" 0; }
crud v_dc_fwgroups:group label="Security Group" add=/cluster/firewall/groups del="/cluster/firewall/groups/{1}" noedit=1 first="group comment"
crud v_dc_fwgroups:grule label="Rule" add="/cluster/firewall/groups/{s1}" edit="/cluster/firewall/groups/{1}/{2}" \
    del="/cluster/firewall/groups/{1}/{2}" first="$FW_RULE_FIRST" choices="macro:choice_fw_macros"
