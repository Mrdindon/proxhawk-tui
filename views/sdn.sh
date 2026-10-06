# shellcheck shell=bash
# views/sdn.sh - Datacenter > SDN (status, Zones, VNets, Options, IPAM,
# VNet Firewall, Fabrics, Route Maps, Prefix Lists) and the SDN zone panels.
# Changes are pending until "Apply" (PUT /cluster/sdn), like in the web UI.

SDN_EXTRA="A:Apply X:Rollback_pending"

# Shared keys: A = apply the pending SDN configuration, X = discard it.
sdn_keys() {
    case $1 in
        A)
            T "Apply the pending SDN configuration on all nodes?"; confirm "$REPLY" || return 0
            api_exec "SDN - Apply" set /cluster/sdn ;;
        X)
            T "Discard all pending SDN changes?"; confirm "$REPLY" || return 0
            api_exec_sync "SDN - Rollback" create /cluster/sdn/rollback
            content_load 1 ;;
        *) return 1 ;;
    esac
    return 0
}

v_dc_sdn() {
    local id n=0
    c_section "SDN Status"
    table_spec "network:SDN:24|node:Node:12|network-type:Type:10|status:Status:*:status"
    table_header
    for id in "${RES_IDS[@]}"; do
        [[ ${R_TYPE[$id]} == network ]] || continue
        table_row "${R_NET[$id]}"$'\t'"${R_NODE[$id]}"$'\t'"${R_NETTYPE[$id]}"$'\t'"${R_STATUS[$id]}"
        c_sel "$REPLY" "$id"; (( n++ ))
    done
    (( n )) || c_msg dim "No items"
    # Same warning as the web UI when the SDN configuration is not sourced.
    if [[ -r /etc/network/interfaces ]] && ! grep -qE '^[[:space:]]*source[[:space:]]+/etc/network/interfaces.d/\*' /etc/network/interfaces; then
        c_blank
        c_msg warn "The node's /etc/network/interfaces does not contain 'source /etc/network/interfaces.d/*': SDN VNets will not be created."
    fi
    c_blank
    T "Press 'A' to apply the pending configuration, 'X' to roll it back."
    c_add "  ${C[dim]}$REPLY${C[norm]}"
}
v_dc_sdn__enter() { grid_goto "$1"; }
v_dc_sdn__key() { sdn_keys "$1"; }
VIEW_HINT[v_dc_sdn]="Enter:Go_to A:Apply X:Rollback"

# Zones / VNets show the pending state ("new", "changed", "deleted").
v_dc_zones() { view_table /cluster/sdn/zones "pending=1" "zone:ID:12|type:Type:10|mtu:MTU:6|ipam:IPAM:10|dns:DNS:10|nodes:Nodes:*|state:State:10"; }
crud v_dc_zones label="Zone" add=/cluster/sdn/zones edit="/cluster/sdn/zones/{1}" del="/cluster/sdn/zones/{1}" \
    plugin=sdnzone first="zone bridge tag vlan-protocol peers controller vrf-vxlan mtu nodes ipam dns reversedns dnszone dhcp" \
    get="/cluster/sdn/zones/{1}" extra="$SDN_EXTRA"
v_dc_zones__key() { sdn_keys "$1"; }

# VNets and their subnets: "vnet|name" and "subnet|vnet|id".
v_dc_vnets() {
    local row v n=0
    local -a vnets f
    table_spec "vnet:ID:14|alias:Alias:16|zone:Zone:12|tag:Tag:6|vlanaware:VLAN Aware:11:bool|state:State:*"
    api_get rows /cluster/sdn/vnets "pending=1" "$TS_FIELDS" || { c_api_error; return; }
    vnets=("${API_ROWS[@]}")
    table_header
    for row in "${vnets[@]}"; do
        tsv_split f "$row"; v=${f[0]}
        table_row "$row"; c_sel "${C[title]}${REPLY}${C[norm]}" "vnet|$v"; (( n++ ))
        if api_get rows "/cluster/sdn/vnets/$v/subnets" "pending=1" "subnet,id,gateway,snat,dhcp-range,state"; then
            local r; local -a s
            for r in "${API_ROWS[@]}"; do
                tsv_split s "$r"
                fmtv bool "${s[3]:-0}"
                c_sel "    ${G[bullet]} ${s[0]}  gw ${s[2]:--}  snat $REPLY  ${s[4]}  ${s[5]}" "subnet|$v|${s[1]}"
            done
        fi
    done
    (( n )) || c_msg dim "No items"
}
crud v_dc_vnets:vnet label="VNet" add=/cluster/sdn/vnets edit="/cluster/sdn/vnets/{1}" del="/cluster/sdn/vnets/{1}" \
    first="vnet zone alias tag vlanaware isolate-ports" choices="zone:choice_zones"
crud v_dc_vnets:subnet label="Subnet" add="/cluster/sdn/vnets/{s1}/subnets" edit="/cluster/sdn/vnets/{1}/subnets/{2}" \
    del="/cluster/sdn/vnets/{1}/subnets/{2}" fix="type=subnet" first="subnet gateway snat dhcp-range dnszoneprefix"
CRUD[v_dc_vnets|extra]=$SDN_EXTRA
v_dc_vnets__key() { sdn_keys "$1"; }

# Options: controllers, IPAMs and DNS servers.
v_dc_sdnoptions() {
    c_section "Controllers"
    TABLE_KEY_PREFIX="controller|"
    view_table /cluster/sdn/controllers "pending=1" "controller:ID:16|type:Type:10|node:Node:12|state:State:*"
    c_blank
    c_section "IPAM"
    TABLE_KEY_PREFIX="ipam|"
    view_table /cluster/sdn/ipams "" "ipam:ID:16|type:Type:10|url:URL:*"
    c_blank
    c_section "DNS"
    TABLE_KEY_PREFIX="dns|"
    view_table /cluster/sdn/dns "" "dns:ID:16|type:Type:10|url:URL:*"
}
crud v_dc_sdnoptions:controller label="Controller" add=/cluster/sdn/controllers edit="/cluster/sdn/controllers/{1}" \
    del="/cluster/sdn/controllers/{1}" plugin=sdncontroller first="controller asn peers node bgp-multipath-as-path-relax ebgp loopback fabric"
crud v_dc_sdnoptions:ipam label="IPAM" add=/cluster/sdn/ipams edit="/cluster/sdn/ipams/{1}" del="/cluster/sdn/ipams/{1}" \
    plugin=sdnipam first="ipam url token section"
crud v_dc_sdnoptions:dns label="DNS" add=/cluster/sdn/dns edit="/cluster/sdn/dns/{1}" del="/cluster/sdn/dns/{1}" \
    plugin=sdndns first="dns url key ttl reversev6mask"
CRUD[v_dc_sdnoptions|extra]=$SDN_EXTRA
v_dc_sdnoptions__key() { sdn_keys "$1"; }

# IPAM content (PVE IPAM): IP mappings of the VNets of zones using the
# "pve" IPAM with DHCP enabled (same data as the web UI). Row keys "vnet|zone|ip|mac".
v_dc_sdnipam() {
    local row n=0
    local -a f
    table_spec "zone:Zone:12|vnet:VNet:12|ip:IP Address:18|mac:MAC:18|hostname:Hostname:*|vmid:VMID:6|gateway:Gateway:8:bool"
    api_get rows /cluster/sdn/ipams/pve/status "" "$TS_FIELDS" || { c_api_error; return; }
    table_header
    for row in "${API_ROWS[@]}"; do
        tsv_split f "$row"
        table_row "$row"; c_sel "$REPLY" "${f[1]}|${f[0]}|${f[2]}|${f[3]}"; (( n++ ))
    done
    (( n )) || c_msg dim "No items (only zones using the 'pve' IPAM with DHCP enabled are listed)."
}
crud v_dc_sdnipam label="IP Mapping" add="/cluster/sdn/vnets/{?vnet:VNet}/ips" first="zone ip mac vmid" \
    edit="/cluster/sdn/vnets/{1}/ips" editfix="zone={2} ip={3}" editonly="mac vmid" \
    del="/cluster/sdn/vnets/{1}/ips" delargs="--zone {2} --ip {3} --mac {4}"

# VNet firewall: VNets with their rules ("fwvnet|vnet", "fwrule|vnet|pos").
v_dc_sdnfirewall() {
    local row v n=0
    local -a vnets f
    api_get rows /cluster/sdn/vnets "" "vnet,zone" || { c_api_error; return; }
    vnets=("${API_ROWS[@]}")
    table_spec "$FW_SPEC"
    table_header
    for row in "${vnets[@]}"; do
        v=${row%%$'\t'*}
        c_sel "${C[title]}${G[m_vnets]:-} $v${C[norm]}" "fwvnet|$v"; (( n++ ))
        if api_get rows "/cluster/sdn/vnets/$v/firewall/rules" "" "$TS_FIELDS"; then
            local r
            for r in "${API_ROWS[@]}"; do
                tsv_split f "$r"; table_row "$r"; c_sel "  $REPLY" "fwrule|$v|${f[0]}"
            done
        fi
    done
    (( n )) || c_msg dim "No items"
}
crud v_dc_sdnfirewall:fwvnet label="VNet Firewall Options" edit="/cluster/sdn/vnets/{1}/firewall/options"
crud v_dc_sdnfirewall:fwrule label="Rule" add="/cluster/sdn/vnets/{s1}/firewall/rules" \
    edit="/cluster/sdn/vnets/{1}/firewall/rules/{2}" del="/cluster/sdn/vnets/{1}/firewall/rules/{2}" \
    first="$FW_RULE_FIRST" choices="macro:choice_fw_macros"

# Fabrics and their nodes ("fabric|id", "fnode|fabric|node").
v_dc_fabrics() {
    local row id n=0
    local -a fabrics f
    table_spec "id:Name:16|protocol:Protocol:12|ip_prefix:IPv4 Prefix:18|ip6_prefix:IPv6 Prefix:*|area:Area:10"
    api_get rows /cluster/sdn/fabrics/fabric "" "$TS_FIELDS" || { c_api_error; return; }
    fabrics=("${API_ROWS[@]}")
    table_header
    for row in "${fabrics[@]}"; do
        tsv_split f "$row"; id=${f[0]}
        table_row "$row"; c_sel "${C[title]}${REPLY}${C[norm]}" "fabric|$id"; (( n++ ))
        if api_get rows "/cluster/sdn/fabrics/node/$id" "" "node_id,ip,ip6,interfaces"; then
            local r; local -a v
            for r in "${API_ROWS[@]}"; do
                tsv_split v "$r"
                c_sel "    ${G[node]} ${v[0]}  ${v[1]} ${v[2]}  ${v[3]}" "fnode|$id|${v[0]}"
            done
        fi
    done
    (( n )) || c_msg dim "No items"
}
crud v_dc_fabrics:fabric label="Fabric" add=/cluster/sdn/fabrics/fabric edit="/cluster/sdn/fabrics/fabric/{1}" \
    del="/cluster/sdn/fabrics/fabric/{1}" first="id protocol ip_prefix ip6_prefix area hello_interval csnp_interval"
crud v_dc_fabrics:fnode label="Fabric Node" add="/cluster/sdn/fabrics/node/{s1}" edit="/cluster/sdn/fabrics/node/{1}/{2}" \
    del="/cluster/sdn/fabrics/node/{1}/{2}" first="node_id protocol ip ip6 interfaces role" choices="node_id:choice_nodes"
CRUD[v_dc_fabrics|extra]=$SDN_EXTRA
v_dc_fabrics__key() { sdn_keys "$1"; }

# Route maps (entries "rmap|id|order").
v_dc_routemaps() {
    local row n=0
    local -a f
    table_spec "route-map-id:Route Map:16|order:Order:6:s:r|action:Action:8|match:Match:*|set:Set:*|exit-action:Exit Action:12"
    api_get rows /cluster/sdn/route-maps/entries "" "$TS_FIELDS" || { c_api_error; return; }
    table_header
    for row in "${API_ROWS[@]}"; do
        tsv_split f "$row"; table_row "$row"; c_sel "$REPLY" "rmap|${f[0]}|${f[1]}"; (( n++ ))
    done
    (( n )) || c_msg dim "No items"
}
crud v_dc_routemaps:rmap label="Route Map Entry" add=/cluster/sdn/route-maps/entries \
    edit="/cluster/sdn/route-maps/entries/{1}/entry/{2}" del="/cluster/sdn/route-maps/entries/{1}/entry/{2}" \
    first="route-map-id order action match set exit-action call"
CRUD[v_dc_routemaps|extra]=$SDN_EXTRA
v_dc_routemaps__key() { sdn_keys "$1"; }

# Prefix lists and entries ("plist|id", "pentry|id|seq").
v_dc_prefixlists() {
    local row id n=0
    local -a lists f
    api_get rows /cluster/sdn/prefix-lists "" "id" || { c_api_error; return; }
    lists=("${API_ROWS[@]}")
    table_spec "seq:Seq:6:s:r|action:Action:8|prefix:Prefix:*|le:le:5|ge:ge:5"
    table_header
    for id in "${lists[@]}"; do
        c_sel "${C[title]}${G[m_mapping]:-} $id${C[norm]}" "plist|$id"; (( n++ ))
        if api_get rows "/cluster/sdn/prefix-lists/$id/entries" "" "$TS_FIELDS"; then
            local r
            for r in "${API_ROWS[@]}"; do
                tsv_split f "$r"; table_row "$r"; c_sel "  $REPLY" "pentry|$id|${f[0]}"
            done
        fi
    done
    (( n )) || c_msg dim "No items"
}
crud v_dc_prefixlists:plist label="Prefix List" add=/cluster/sdn/prefix-lists edit="/cluster/sdn/prefix-lists/{1}" \
    del="/cluster/sdn/prefix-lists/{1}" first="id"
crud v_dc_prefixlists:pentry label="Prefix List Entry" add="/cluster/sdn/prefix-lists/{s1}/entries" \
    edit="/cluster/sdn/prefix-lists/{1}/entries/{2}" del="/cluster/sdn/prefix-lists/{1}/entries/{2}" first="seq action prefix le ge"
CRUD[v_dc_prefixlists|extra]=$SDN_EXTRA
v_dc_prefixlists__key() { sdn_keys "$1"; }

# ---------------------------------------------------------------------------
# SDN zone selected in the tree: Content, IP-VRF, MAC-VRFs, Permissions.
# ---------------------------------------------------------------------------
view_menu sdn "content|Content|m_content|0" "ipvrf|IP-VRF|m_network|0" "macvrf|MAC-VRFs|m_network|0" "permissions|Permissions|m_permissions|0"
title_sdn() { Tf "Zone '%s' on node '%s'" "$CTX_NET" "$CTX_NODE"; }
v_sdn_content() {
    if ! view_table "/nodes/$CTX_NODE/sdn/zones/$CTX_NET/content" "" "vnet:VNet:20|status:Status:10:status|statusmsg:Details:*"; then
        c_reset
        if [[ $CTX_NET == localnetwork ]]; then
            c_msg dim "Default local network zone (Linux bridges of the node)."
            c_blank
            view_table "/nodes/$CTX_NODE/network" "type=any_bridge" "iface:Bridge:12|active:Active:7:bool|bridge_ports:Ports/Slaves:14|cidr:CIDR:18|comments:Comment:*"
        else
            c_api_error
        fi
    fi
}
v_sdn_ipvrf() {
    view_table "/nodes/$CTX_NODE/sdn/zones/$CTX_NET/ip-vrf" "" "ip:Destination:20|protocol:Protocol:10|metric:Metric:8|nexthops:Nexthops:*" -1 \
        || { c_reset; c_msg dim "IP-VRF information is only available for EVPN zones."; }
}
v_sdn_macvrf() {
    local row v
    api_get rows "/nodes/$CTX_NODE/sdn/zones/$CTX_NET/content" "" "vnet" || { c_msg dim "MAC-VRFs are only available for EVPN zones."; return; }
    local -a vnets=("${API_ROWS[@]}")
    for v in "${vnets[@]}"; do
        c_section "VNet $v"
        view_table "/nodes/$CTX_NODE/sdn/vnets/$v/mac-vrf" "" "ip:IP Address:18|mac:MAC:18|nexthop:Nexthop:*" -1 || { c_reset; c_msg dim "MAC-VRFs are only available for EVPN zones."; return; }
    done
}
v_sdn_permissions() { acl_table "/sdn/zones/$CTX_NET"; }
v_sdn_permissions__key() { acl_keys "/sdn/zones/$CTX_NET" "$@"; }
VIEW_HINT[v_sdn_permissions]="a:Add d:Remove"
