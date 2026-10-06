# shellcheck shell=bash
# Container panels and actions on a test container (TEST_CT, default 9911).

ct_running() { pct status "$TEST_CT" 2>/dev/null | grep -q running; }
ct_cfg() { kv_is "/nodes/$NODE/lxc/$TEST_CT/config" "$@"; }
ct_cfg_like() { kv_like "/nodes/$NODE/lxc/$TEST_CT/config" "$@"; }

test_ct() {
    local id="lxc/$TEST_CT" k st=${TEST_STORAGE:-VM} br tmpl
    br=$(pvesh get "/nodes/$NODE/network" --type any_bridge --output-format json | grep -o '"iface":"[^"]*"' | head -1 | cut -d'"' -f4)
    tmpl=$(pvesh get "/nodes/$NODE/storage/local/content" --content vztmpl --output-format json | grep -o '"volid":"[^"]*debian[^"]*"' | head -1 | cut -d'"' -f4)
    [[ -n $tmpl ]] || { skip "Containers" "no Debian template on 'local'"; return; }
    pct status "$TEST_CT" >/dev/null 2>&1 && { pct stop "$TEST_CT" >/dev/null 2>&1; pct destroy "$TEST_CT" --purge >/dev/null 2>&1; }
    # Container snapshots need a snapshot capable storage: a temporary
    # LVM-Thin pool on the test disk (unless TEST_STORAGE is given).
    local made_thin=0 disk=${DISK_A:-/dev/sdb}
    if [[ -z ${TEST_STORAGE-} && -b $disk ]]; then
        pvesh set "/nodes/$NODE/disks/wipedisk" --disk "$disk" >/dev/null 2>&1; sleep 2
        if pvesh create "/nodes/$NODE/disks/lvmthin" --device "$disk" --name pvtct --add_storage 1 >/dev/null 2>&1 \
            && wait_for 60 pvesh get /storage/pvtct; then
            st=pvtct made_thin=1
            wait_for 60 bash -c "pvesh get /cluster/resources --type storage --output-format json | grep -q 'storage/$NODE/pvtct'"
            res_load
            ok "CT storage: temporary LVM-Thin pool on $disk"
        fi
    fi

    # Create CT wizard.
    ctx root
    reset_step
    answers "$TEST_CT" pvetty-test-ct 512 1 "$st" 4 "$br" "$tmpl" Pvetty-Test-123 no yes
    check "Create CT wizard" act_create_ct
    check "CT created" wait_for 120 pvesh get "/nodes/$NODE/lxc/$TEST_CT/config"
    ctx "$id"
    for k in summary console resources network dns options tasks backup replication snapshots firewall fwoptions fwalias fwipset fwlog permissions; do
        check "CT > $k: view" view "$k"
    done

    # Resources.
    view resources
    reset_step; preset memory=768 swap=256
    check "Resources: edit memory/swap" enter memory
    check "Resources: memory 768" ct_cfg memory 768
    reset_step; preset cores=2
    check "Resources: edit cores" enter cores
    reset_step; crud_answers device=mp storage=$st size=1 path=/mnt/pvt
    check "Resources: add Mount Point" key a ""
    check "Resources: mp0 present" ct_cfg_like mp0 "$st:*mp=/mnt/pvt*"
    reset_step; answers "+1G"
    check "Resources: resize rootfs" key R rootfs
    check "Resources: rootfs 5G" ct_cfg_like rootfs "*size=5G*"
    reset_step; crud_answers storage=local
    check "Resources: move mp0 to local" key m mp0
    check "Resources: mp0 on local" ct_cfg_like mp0 "local:*"
    reset_step; check "Resources: detach mp0" key d mp0
    check "Resources: mp0 -> unused0" ct_cfg_like unused0 "local:*"
    reset_step; check "Resources: delete unused0" key d unused0

    # Network.
    view network
    reset_step
    check "Network: add device" key a ""
    check "Network: net1 present" ct_cfg_like net1 "name=eth1*"
    reset_step; preset net1="name=eth1,bridge=$br,ip=10.96.1.5/24,firewall=0"
    check "Network: edit device" enter net1
    check "Network: net1 edited" ct_cfg_like net1 "*ip=10.96.1.5/24*"
    reset_step; check "Network: remove device" key d net1

    # DNS and options.
    view dns
    reset_step; preset nameserver=9.9.9.9 searchdomain=example.invalid
    check "DNS: edit" enter nameserver
    reset_step; preset hostname=pvetty-ct2
    check "DNS: hostname" enter hostname
    check "DNS: hostname saved" ct_cfg hostname pvetty-ct2
    reset_step; check "DNS: reset nameserver" key d nameserver
    view options
    reset_step; preset features="nesting=1"
    check "Options: features" enter features
    check "Options: nesting" ct_cfg features "nesting=1"
    reset_step; preset onboot=0 startup="order=3"
    check "Options: startup" enter startup
    reset_step; preset protection=1
    check "Options: protection" enter protection
    reset_step; check "Options: reset protection" key d protection

    # Power, console, snapshots.
    ctx "$id"
    reset_step; check "Start" act_start
    check "CT running" wait_for 60 ct_running
    TERM_CMDS=()
    act_console
    check "Console: pct enter used" bash -c "[[ '${TERM_CMDS[*]}' == *'pct enter $TEST_CT'* ]]"
    check "CT: command runs inside" bash -c "pct exec $TEST_CT -- hostname | grep -q pvetty-ct2"
    res_load; ctx "$id"
    check "Summary with IPs" view summary
    reset_step; answers reboot; check "Reboot" act_shutdown_menu
    check "CT running after reboot" wait_for 60 ct_running
    view snapshots
    reset_step; answers pvtsnap "pvetty ct snapshot"
    check "Snapshots: take" key n ""
    check "Snapshots: listed" api_has "/nodes/$NODE/lxc/$TEST_CT/snapshot" name pvtsnap
    view snapshots; reset_step; answers edit "edited"
    check "Snapshots: edit" enter pvtsnap
    res_load; ctx "$id"
    reset_step; answers shutdown; check "Shutdown" act_shutdown_menu
    check "CT stopped" wait_for 90 bash -c "! pct status $TEST_CT | grep -q running"
    view snapshots
    reset_step; check "Snapshots: rollback" key R pvtsnap
    reset_step; check "Snapshots: remove" key d pvtsnap

    # Firewall, permissions.
    fw_suite "$id" "/nodes/$NODE/lxc/$TEST_CT/firewall" "CT"
    ctx "$id"; view permissions
    reset_step; crud_answers acltype=users; preset users=root@pam roles=PVEVMUser
    check "Permissions: add" key a ""
    view permissions; rowkey "/vms/$TEST_CT|*"
    reset_step; check "Permissions: remove" key d "$REPLY"

    # Backup, restore (overwrite), clone, template, remove.
    view backup
    reset_step; answers local stop
    check "Backup now" key n ""
    view backup; k=${C_SELK[0]-}
    check "Backup: listed" test -n "$k"
    reset_step; answers yes
    check "Backup: restore over the container" key r "$k"
    check "CT still present after restore" wait_for 120 pvesh get "/nodes/$NODE/lxc/$TEST_CT/config"
    view backup; reset_step; answers remove
    check "Backup: remove" enter "$k"
    res_load; ctx "$id"
    reset_step; answers 9913 pvetty-ct-clone yes
    check "Clone (full)" act_clone
    check "Clone 9913 exists" wait_for 120 pvesh get "/nodes/$NODE/lxc/9913/config"
    res_load; ctx lxc/9913
    reset_step; check "Convert clone to template" act_template
    check "9913 is a template" kv_is "/nodes/$NODE/lxc/9913/config" template 1
    reset_step; answers 9913 yes
    check "Remove template 9913" act_remove
    res_load; ctx "$id"
    reset_step; answers "$TEST_CT" yes
    check "Remove CT $TEST_CT" act_remove
    check "CT removed" wait_for 60 bash -c "! pvesh get /nodes/$NODE/lxc/$TEST_CT/config >/dev/null 2>&1"
    if (( made_thin )); then
        pvesh delete "/nodes/$NODE/disks/lvmthin/pvtct" --volume-group pvtct --cleanup-config 1 --cleanup-disks 1 >/dev/null 2>&1
        check "CT storage: temporary LVM-Thin pool removed" wait_for 60 bash -c '! vgs pvtct >/dev/null 2>&1'
    fi
}
