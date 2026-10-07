# shellcheck shell=bash
# Firewall of the Datacenter and of the node (guest firewalls: vm / ct sections).

# fw_suite <context id> <base path> <label>: rules, aliases, IPSets, log.
fw_suite() {
    local id=$1 base=$2 lbl=$3 k pos
    ctx "$id"
    check "$lbl Firewall: view" view firewall
    reset_step; preset type=in action=ACCEPT proto=tcp dport=12345 enable=0 comment="proxhawk-tui rule A"
    check "$lbl Firewall: add rule" key a ""
    reset_step; preset type=out action=DROP macro=SSH enable=0 comment="proxhawk-tui rule B"
    check "$lbl Firewall: add rule with macro" key a ""
    view firewall
    pos=""
    api_get rows "$base/rules" "" "pos,comment"
    for k in "${API_ROWS[@]}"; do [[ ${k#*$'\t'} == "proxhawk-tui rule A" ]] && pos=${k%%$'\t'*}; done
    if [[ -n $pos ]]; then
        reset_step; preset comment="proxhawk-tui rule A edited" dport=12346
        check "$lbl Firewall: edit rule" key e "$pos"
        check "$lbl Firewall: rule edited" kv_is "$base/rules/$pos" dport 12346
        reset_step; answers 0
        check "$lbl Firewall: move rule" key m "$pos"
    else ko "$lbl Firewall: rule listed" "not found"; fi
    # Remove both test rules (positions change after each removal).
    local n
    for n in 1 2; do
        api_get rows "$base/rules" "" "pos,comment"; pos=""
        for k in "${API_ROWS[@]}"; do [[ ${k#*$'\t'} == proxhawk-tui\ rule* ]] && { pos=${k%%$'\t'*}; break; }; done
        [[ -n $pos ]] || break
        view firewall; reset_step
        check "$lbl Firewall: remove rule $n" key d "$pos"
    done
    check "$lbl Firewall: rules removed" api_lacks "$base/rules" comment "proxhawk-tui rule B"

    check "$lbl Firewall: Options view" view fwoptions
    [[ $id != root ]] && check "$lbl Firewall: Log view" view fwlog
}

test_firewall() {
    local k
    # Datacenter.
    fw_suite root /cluster/firewall "Datacenter"
    ctx root
    view fwoptions
    reset_step; preset enable=1
    check "Datacenter Firewall: enable" enter enable
    check "Datacenter Firewall: enabled" kv_is /cluster/firewall/options enable 1
    sleep 12   # let pve-firewall compile and apply the ruleset
    check "Datacenter Firewall: rules active" bash -c 'pve-firewall status | grep -q "enabled/running"'
    check "Datacenter Firewall: API still reachable" bash -c 'curl -sk -o /dev/null -w "%{http_code}" https://127.0.0.1:8006/ | grep -q 200'
    reset_step; preset enable=""
    check "Datacenter Firewall: disable (default)" enter enable
    check "Datacenter Firewall: disabled" kv_is /cluster/firewall/options enable ""
    reset_step; preset policy_in=REJECT
    check "Datacenter Firewall: edit input policy" enter policy_in
    reset_step; preset policy_in=""
    check "Datacenter Firewall: reset input policy" enter policy_in

    # Security groups and their rules.
    check "Security Group: view" view fwgroups
    reset_step; crud_answers sub=group; preset group=pvtgrp comment="proxhawk-tui group"
    check "Security Group: add group" key a ""
    view fwgroups; reset_step; crud_answers sub=grule; CRUD_SEL="pvtgrp"
    preset type=in action=ACCEPT proto=udp dport=5353 enable=1 comment="proxhawk-tui group rule"
    STATUS_LVL=none; crud_add v_dc_fwgroups; [[ $STATUS_LVL != err ]] && ok "Security Group: add rule" || ko "Security Group: add rule" "$STATUS_MSG"
    check "Security Group: rule created" api_has /cluster/firewall/groups/pvtgrp comment "proxhawk-tui group rule"
    view fwgroups; reset_step; preset comment="edited group rule"
    check "Security Group: edit rule" key e "grule|pvtgrp|0"
    reset_step; check "Security Group: remove rule" key d "grule|pvtgrp|0"
    reset_step; check "Security Group: remove group" key d "group|pvtgrp"
    check "Security Group: removed" api_lacks /cluster/firewall/groups group pvtgrp

    # Aliases.
    check "Alias: view" view fwalias
    reset_step; preset name=pvtalias cidr=192.0.2.10 comment="proxhawk-tui alias"
    check "Alias: add" key a ""
    view fwalias; reset_step; preset cidr=192.0.2.11
    check "Alias: edit" key e pvtalias
    check "Alias: edited" kv_is /cluster/firewall/aliases/pvtalias cidr 192.0.2.11
    reset_step; check "Alias: remove" key d pvtalias

    # IPSets and entries.
    check "IPSet: view" view fwipset
    reset_step; crud_answers sub=ipset; preset name=pvtset comment="proxhawk-tui ipset"
    check "IPSet: add" key a ""
    view fwipset; reset_step; crud_answers sub=cidr; CRUD_SEL=pvtset; preset cidr=198.51.100.0/24 comment="proxhawk-tui cidr"
    STATUS_LVL=none; crud_add v_dc_fwipset; [[ $STATUS_LVL != err ]] && ok "IPSet: add CIDR" || ko "IPSet: add CIDR" "$STATUS_MSG"
    check "IPSet: CIDR created" api_has /cluster/firewall/ipset/pvtset cidr 198.51.100.0/24
    view fwipset; reset_step; preset nomatch=1
    check "IPSet: edit CIDR" key e "cidr|pvtset|198.51.100.0/24"
    reset_step; check "IPSet: remove CIDR" key d "cidr|pvtset|198.51.100.0/24"
    reset_step; check "IPSet: remove" key d "ipset|pvtset"

    # Node firewall.
    fw_suite "node/$NODE" "/nodes/$NODE/firewall" "Node"
    ctx "node/$NODE"; view fwoptions
    reset_step; preset log_level_in=info
    check "Node Firewall: edit log level" enter log_level_in
    check "Node Firewall: log level saved" kv_is "/nodes/$NODE/firewall/options" log_level_in info
    reset_step; preset log_level_in=""
    check "Node Firewall: log level reset" enter log_level_in
}
