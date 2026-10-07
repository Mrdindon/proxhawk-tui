# shellcheck shell=bash
# Datacenter > SDN: zones, VNets, subnets, options (controllers, IPAM, DNS),
# IPAM mappings, VNet firewall, fabrics, prefix lists, route maps, apply.

test_sdn() {
    local k
    # SDN needs "source /etc/network/interfaces.d/*" (added for the test, restored at the end).
    cp /etc/network/interfaces "$RUN_DIR/interfaces.orig"
    if ! grep -q '^source /etc/network/interfaces.d/\*' /etc/network/interfaces; then
        printf '\nsource /etc/network/interfaces.d/*\n' >> /etc/network/interfaces
        ok "SDN: source line added to /etc/network/interfaces for the test"
    fi
    ctx root
    check "SDN: view" view sdn

    # Zone, VNet, subnet.
    check "Zones: view" view zones
    reset_step; crud_answers type=simple; preset zone=pvtz1 ipam=pve
    check "Zones: add Simple" key a ""
    check "Zones: created (pending)" api_has /cluster/sdn/zones zone pvtz1 "pending=1"
    view zones; reset_step; preset mtu=1450
    check "Zones: edit" key e pvtz1
    check "Zones: edited" kv_is /cluster/sdn/zones/pvtz1 mtu 1450
    reset_step; crud_answers type=vlan; preset zone=pvtz2 bridge=vmbr1
    check "Zones: add VLAN" key a ""

    check "VNets: view" view vnets
    reset_step; crud_answers sub=vnet; preset vnet=pvtvn1 zone=pvtz1 alias="proxhawk-tui vnet"
    check "VNets: add" key a ""
    check "VNets: created" api_has /cluster/sdn/vnets vnet pvtvn1 "pending=1"
    view vnets; reset_step; preset alias="edited vnet"
    check "VNets: edit" key e "vnet|pvtvn1"
    reset_step; crud_answers sub=subnet; CRUD_SEL=pvtvn1; preset subnet=10.99.0.0/24 gateway=10.99.0.1 snat=1
    STATUS_LVL=none; crud_add v_dc_vnets; [[ $STATUS_LVL != err ]] && ok "Subnets: add" || ko "Subnets: add" "$STATUS_MSG"
    view vnets; rowkey "subnet|pvtvn1|*"; k=$REPLY
    if [[ -n $k ]]; then
        reset_step; preset snat=0
        check "Subnets: edit" key e "$k"
    else ko "Subnets: listed" "not found"; fi

    # Options: controller, IPAM, DNS.
    check "SDN Options: view" view sdnoptions
    reset_step; crud_answers sub=controller type=evpn; preset controller=pvtctl asn=65000 peers=192.0.2.1
    check "Controllers: add EVPN" key a ""
    view sdnoptions; reset_step; preset asn=65001
    check "Controllers: edit" key e "controller|pvtctl"
    reset_step; crud_answers sub=ipam type=pve; preset ipam=pvtipam
    check "IPAM: add PVE IPAM" key a ""
    check "IPAM: created" api_has /cluster/sdn/ipams ipam pvtipam
    reset_step; crud_answers sub=ipam type=phpipam; preset ipam=pvtphp url=https://ipam.example.invalid/api/x token=abc section=1
    if key a ""; then ko "IPAM: phpIPAM without server" "unexpected success"; key d "ipam|pvtphp"
    else ok "IPAM: phpIPAM connection error reported ($STATUS_MSG)"; fi
    reset_step; crud_answers sub=dns type=powerdns; preset dns=pvtdns url=https://dns.example.invalid/api/v1/servers/localhost key=abc
    if key a ""; then ko "DNS: PowerDNS without server" "unexpected success"; key d "dns|pvtdns"
    else ok "DNS: PowerDNS connection error reported ($STATUS_MSG)"; fi

    # Fabrics, prefix lists, route maps.
    check "Fabrics: view" view fabrics
    reset_step; crud_answers sub=fabric; preset id=pvtfab protocol=openfabric ip_prefix=10.98.0.0/24
    check "Fabrics: add OpenFabric" key a ""
    view fabrics; reset_step; preset hello_interval=5
    check "Fabrics: edit" key e "fabric|pvtfab"
    check "Prefix Lists: view" view prefixlists
    reset_step; crud_answers sub=plist; preset id=pvtpl
    check "Prefix Lists: add" key a ""
    view prefixlists; reset_step; crud_answers sub=pentry; CRUD_SEL=pvtpl; preset seq=10 action=permit prefix=10.0.0.0/8 le=24
    STATUS_LVL=none; crud_add v_dc_prefixlists; [[ $STATUS_LVL != err ]] && ok "Prefix Lists: add entry" || ko "Prefix Lists: add entry" "$STATUS_MSG"
    view prefixlists; rowkey "pentry|pvtpl|*"; k=$REPLY
    if [[ -n $k ]]; then
        reset_step; preset le=28
        check "Prefix Lists: edit entry" key e "$k"
        reset_step; check "Prefix Lists: remove entry" key d "$k"
    else ko "Prefix Lists: entry listed" "not found"; fi
    check "Route Maps: view" view routemaps
    reset_step; crud_answers sub=rmap; preset route-map-id=pvtrm order=10 action=permit
    check "Route Maps: add entry" key a ""
    view routemaps; rowkey "rmap|pvtrm|*"; k=$REPLY
    if [[ -n $k ]]; then
        reset_step; preset action=deny
        check "Route Maps: edit entry" key e "$k"
        reset_step; check "Route Maps: remove entry" key d "$k"
    else ko "Route Maps: entry listed" "not found"; fi

    # Apply the configuration: the VNet bridge must appear on the node.
    view sdn; reset_step
    check "SDN: Apply" key A ""
    check "SDN: VNet bridge pvtvn1 created" wait_for 30 ip link show pvtvn1
    check "SDN: zone pvtz1 in the tree" wait_for 90 bash -c "pvesh get /cluster/resources --type sdn --output-format json | grep -q pvtz1 || pvesh get /cluster/resources --output-format json | grep -q zone/pvtz1"
    res_load
    ctx "network/$NODE/zone/pvtz1"
    for k in content ipvrf macvrf permissions; do check "SDN zone: $k view" view "$k"; done
    reset_step; crud_answers acltype=users; preset users=root@pam roles=PVESDNUser
    check "SDN zone: add permission" key a ""
    view permissions; rowkey "/sdn/zones/pvtz1|*"; k=$REPLY
    reset_step; check "SDN zone: remove permission" key d "$k"

    # IPAM content: needs a zone with DHCP (dnsmasq is not required to store mappings).
    ctx root
    view zones; reset_step; crud_answers type=simple; preset zone=pvtz4 ipam=pve dhcp=dnsmasq
    check "Zones: add Simple zone with DHCP" key a ""
    view vnets; reset_step; crud_answers sub=vnet; preset vnet=pvtvn4 zone=pvtz4
    check "VNets: add second VNet" key a ""
    reset_step; crud_answers sub=subnet; CRUD_SEL=pvtvn4; preset subnet=10.96.0.0/24 gateway=10.96.0.1
    STATUS_LVL=none; crud_add v_dc_vnets; [[ $STATUS_LVL != err ]] && ok "Subnets: add (DHCP zone)" || ko "Subnets: add (DHCP zone)" "$STATUS_MSG"
    view sdn; reset_step; key A "" >/dev/null
    check "IPAM: view" view sdnipam
    reset_step; crud_answers vnet=pvtvn4; preset zone=pvtz4 ip=10.96.0.50 mac=BC:24:11:00:99:50
    check "IPAM: add IP mapping" key a ""
    check "IPAM: mapping listed" api_has /cluster/sdn/ipams/pve/status ip 10.96.0.50
    view sdnipam; rowkey "pvtvn4|pvtz4|10.96.0.50|*"; k=$REPLY
    reset_step; preset mac=BC:24:11:00:99:51
    # PVE 9.2 bug: PUT /cluster/sdn/vnets/{vnet}/ips fails with pvesh too
    # ("can't find any subnet for ip"); the error must be reported.
    if key e "$k"; then ok "IPAM: edit IP mapping"
    else ok "IPAM: edit IP mapping - API error reported (known PVE issue: $STATUS_MSG)"; fi
    view sdnipam; rowkey "pvtvn4|pvtz4|10.96.0.50|*"; k=$REPLY
    reset_step; check "IPAM: remove IP mapping" key d "$k"
    check "VNet Firewall: view" view sdnfirewall
    reset_step; crud_answers sub=fwrule; CRUD_SEL=pvtvn1; preset type=forward action=ACCEPT proto=icmp enable=0 comment="proxhawk-tui vnet rule"
    STATUS_LVL=none; crud_add v_dc_sdnfirewall; [[ $STATUS_LVL != err ]] && ok "VNet Firewall: add rule" || ko "VNet Firewall: add rule" "$STATUS_MSG"
    view sdnfirewall; reset_step; preset comment="edited vnet rule"
    check "VNet Firewall: edit rule" key e "fwrule|pvtvn1|0"
    reset_step; check "VNet Firewall: remove rule" key d "fwrule|pvtvn1|0"
    reset_step; preset enable=1
    check "VNet Firewall: edit options" key e "fwvnet|pvtvn1"

    # Cleanup, then apply again.
    view vnets
    for k in pvtvn1 pvtvn4; do
        reset_step; rowkey "subnet|$k|*" && check "Subnets: remove ($k)" key d "$REPLY"
        view vnets; reset_step; check "VNets: remove $k" key d "vnet|$k"
        view vnets
    done
    view zones
    for k in pvtz1 pvtz2 pvtz4; do reset_step; check "Zones: remove $k" key d "$k"; done
    view sdnoptions
    reset_step; check "Controllers: remove" key d "controller|pvtctl"
    reset_step; check "IPAM: remove" key d "ipam|pvtipam"
    view fabrics; reset_step; check "Fabrics: remove" key d "fabric|pvtfab"
    view prefixlists; reset_step; check "Prefix Lists: remove" key d "plist|pvtpl"
    view sdn; reset_step
    check "SDN: Apply (cleanup)" key A ""
    check "SDN: VNet bridge removed" wait_for 30 bash -c '! ip link show pvtvn1'
    # Pending changes can also be rolled back.
    view zones; reset_step; crud_answers type=simple; preset zone=pvtz3
    key a "" >/dev/null
    view sdn; reset_step
    check "SDN: Rollback pending changes" key X ""
    check "SDN: pending zone discarded" api_lacks /cluster/sdn/zones zone pvtz3 "pending=1"
    cp "$RUN_DIR/interfaces.orig" /etc/network/interfaces
    check "SDN: /etc/network/interfaces restored" cmp -s "$RUN_DIR/interfaces.orig" /etc/network/interfaces
}
