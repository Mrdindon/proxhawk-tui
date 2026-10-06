# shellcheck shell=bash
# Virtual machine panels and actions on a test VM (TEST_VM, default 9901).

vm_running() { [[ $(pvesh get "/nodes/$NODE/qemu/$TEST_VM/status/current" --output-format json 2>/dev/null) == *'"qmpstatus":"running"'* ]]; }
vm_status_is() { pvesh get "/nodes/$NODE/qemu/$TEST_VM/status/current" --output-format json 2>/dev/null | grep -q "\"qmpstatus\":\"$1\""; }
vm_cfg() { kv_is "/nodes/$NODE/qemu/$TEST_VM/config" "$@"; }
vm_cfg_like() { kv_like "/nodes/$NODE/qemu/$TEST_VM/config" "$@"; }

test_vm() {
    local id="qemu/$TEST_VM" k st=${TEST_STORAGE:-VM} br
    br=$(pvesh get "/nodes/$NODE/network" --type any_bridge --output-format json | grep -o '"iface":"[^"]*"' | head -1 | cut -d'"' -f4)
    pvesh get "/nodes/$NODE/qemu/$TEST_VM/status/current" >/dev/null 2>&1 && { qm stop $TEST_VM >/dev/null 2>&1; qm destroy $TEST_VM --purge >/dev/null 2>&1; }

    # Create VM wizard.
    ctx root
    reset_step
    answers "$TEST_VM" "pvetty-test-vm" 512 1 "$st" 2 qcow2 "$br" none l26 yes
    check "Create VM wizard" act_create_vm
    check "VM created" wait_for 30 pvesh get "/nodes/$NODE/qemu/$TEST_VM/config"
    ctx "$id"
    for k in summary console hardware cloudinit options tasks monitor backup replication snapshots firewall fwoptions fwalias fwipset fwlog permissions; do
        check "VM > $k: view" view "$k"
    done

    # Hardware: add every kind of device.
    view hardware
    reset_step; crud_answers device=disk bus=scsi storage=$st size=1
    check "Hardware: add Hard Disk" key a ""
    check "Hardware: scsi1 present" vm_cfg_like scsi1 "$st:*"
    reset_step; crud_answers device=cdrom bus=ide iso=none
    check "Hardware: add CD/DVD Drive" key a ""
    reset_step; crud_answers device=net
    check "Hardware: add Network Device" key a ""
    check "Hardware: net1 present" vm_cfg_like net1 "virtio=*"
    reset_step; crud_answers device=efidisk storage=$st
    check "Hardware: add EFI Disk" key a ""
    check "Hardware: efidisk0 present" vm_cfg_like efidisk0 "$st:*"
    reset_step; crud_answers device=tpmstate storage=$st
    check "Hardware: add TPM State" key a ""
    reset_step; crud_answers device=serial
    check "Hardware: add Serial Port" key a ""
    check "Hardware: serial0 = socket" vm_cfg serial0 socket
    reset_step; crud_answers device=cloudinit bus=ide storage=$st
    check "Hardware: add CloudInit Drive" key a ""
    check "Hardware: CloudInit drive present" bash -c "qm config $TEST_VM | grep -q cloudinit"
    reset_step; crud_answers device=audio
    check "Hardware: add Audio Device" key a ""
    reset_step; crud_answers device=rng
    check "Hardware: add VirtIO RNG" key a ""
    reset_step; crud_answers device=usb value="host=0bda:8812"
    check "Hardware: add USB Device" key a ""
    reset_step; crud_answers device=hostpci value="host=$(lspci -D | awk 'NR==1{print $1}')"
    check "Hardware: add PCI Device" key a ""
    pvesh create /cluster/mapping/dir --id pvtvfs --map "node=$NODE,path=/var/tmp" >/dev/null 2>&1
    reset_step; crud_answers device=virtiofs value="dirid=pvtvfs"
    check "Hardware: add Virtiofs" key a ""
    view hardware
    # Edit memory / processors (grouped dialogs).
    reset_step; preset memory=768 balloon=512
    check "Hardware: edit Memory" enter memory
    check "Hardware: memory 768" vm_cfg memory 768
    reset_step; preset cores=2 cpu=host
    check "Hardware: edit Processors" enter cores
    check "Hardware: 2 cores" vm_cfg cores 2
    reset_step; preset net1="e1000,bridge=$br,firewall=0"
    check "Hardware: edit Network Device" enter net1
    check "Hardware: net1 model e1000" vm_cfg_like net1 "e1000=*"
    # Disk actions.
    reset_step; answers "+1G"
    check "Hardware: resize scsi1" key R scsi1
    check "Hardware: scsi1 resized to 2G" vm_cfg_like scsi1 "*size=2G*"
    reset_step; crud_answers storage=local
    check "Hardware: move scsi1 to local" key m scsi1
    check "Hardware: scsi1 on local" vm_cfg_like scsi1 "local:*"
    reset_step
    check "Hardware: detach scsi1" key d scsi1
    check "Hardware: scsi1 became unused0" vm_cfg_like unused0 "local:*"
    reset_step
    check "Hardware: delete unused0" key d unused0
    for k in usb0 hostpci0 virtiofs0 audio0 rng0 tpmstate0 efidisk0 ide0; do
        reset_step; check "Hardware: remove $k" key d "$k"
    done
    pvesh delete /cluster/mapping/dir/pvtvfs >/dev/null 2>&1

    # Cloud-Init.
    view cloudinit
    reset_step; preset ciuser=pvetty
    check "Cloud-Init: edit user" enter ciuser
    reset_step; preset ipconfig0="ip=dhcp"
    check "Cloud-Init: edit IP config" enter ipconfig0
    check "Cloud-Init: ipconfig0 saved" vm_cfg ipconfig0 "ip=dhcp"
    reset_step; check "Cloud-Init: regenerate image" key R ""

    # Options.
    view options
    reset_step; preset name=pvetty-test-vm2
    check "Options: rename" enter name
    reset_step; preset onboot=0 startup="order=5"
    check "Options: start at boot / order" enter startup
    check "Options: startup saved" vm_cfg startup "order=5"
    reset_step; preset agent="enabled=1"
    check "Options: QEMU Guest Agent" enter agent
    reset_step; preset protection=1
    check "Options: protection on" enter protection
    reset_step; preset protection=""
    check "Options: protection reset" enter protection
    reset_step; check "Options: reset startup to default" key d startup

    # Notes, pool membership, permissions, HA.
    editor_writes "pvetty vm note"
    CTX_TYPE=qemu; check "Notes: edit" act_edit_notes
    check "Notes: saved" vm_cfg description "pvetty vm note"
    view permissions
    reset_step; crud_answers acltype=users; preset users=root@pam roles=PVEVMUser
    check "Permissions: add" key a ""
    view permissions; rowkey "/vms/$TEST_VM|*"
    reset_step; check "Permissions: remove" key d "$REPLY"
    CTX_TYPE=qemu
    reset_step; answers yes
    check "Manage HA: add" act_ha
    res_load; ctx "$id"
    reset_step; answers stopped
    check "Manage HA: change state" act_ha
    ctx root; view ha
    check "HA: resource listed" bash -c "[[ ' ${C_SELK[*]} ' == *' vm:$TEST_VM '* ]]"
    reset_step; preset comment="pvetty ha"
    check "HA: edit resource" key e "vm:$TEST_VM"
    view harules
    reset_step; crud_answers type=node-affinity; preset rule=pvtrule resources="vm:$TEST_VM" nodes="$NODE"
    check "HA Rules: add node affinity" key a ""
    view harules; reset_step; preset comment="pvetty rule"
    check "HA Rules: edit" key e pvtrule
    reset_step; check "HA Rules: remove" key d pvtrule
    ctx "$id"; CTX_TYPE=qemu
    reset_step; answers remove
    check "Manage HA: remove" act_ha
    pvesh create /pools --poolid pvetty-test-pool >/dev/null 2>&1
    ctx pool/pvetty-test-pool 2>/dev/null; ctx_set pool/pvetty-test-pool; menu_load
    check "Pool: members view" view members
    reset_step; crud_answers kind=vm; preset vms=$TEST_VM
    check "Pool: add VM" key a ""
    check "Pool: VM member" bash -c "pvesh get /pools/pvetty-test-pool --output-format json | grep -q 'qemu/$TEST_VM'"
    reset_step; crud_answers kind=storage; preset storage=local
    check "Pool: add storage" key a ""
    view members
    reset_step; check "Pool: remove VM" key d "qemu/$TEST_VM"
    reset_step; check "Pool: remove storage" key d "storage/$NODE/local"
    check "Pool: summary view" view summary
    check "Pool: permissions view" view permissions
    pvesh delete /pools/pvetty-test-pool >/dev/null 2>&1

    # Power actions (no OS installed: shutdown is replaced by stop).
    ctx "$id"
    reset_step; check "Start" act_start
    check "VM running" wait_for 30 vm_running
    res_load; ctx "$id"
    reset_step; answers pause; check "Pause" act_shutdown_menu
    check "VM paused" wait_for 15 vm_status_is paused
    res_load; ctx "$id"
    reset_step; answers pause; check "Resume" act_shutdown_menu
    check "VM resumed" wait_for 15 vm_status_is running
    reset_step; answers reset; check "Reset" act_shutdown_menu
    # Without an OS the guest ignores ACPI: reboot/shutdown must time out and
    # the error be reported; the VM is then started again.
    reset_step; answers reboot
    if act_shutdown_menu && [[ $STATUS_LVL != err ]]; then ok "Reboot"
    else ok "Reboot: ACPI timeout reported (no guest OS: $STATUS_MSG)"; fi
    res_load; ctx "$id"
    vm_running || { reset_step; check "Start again" act_start; }
    check "VM running" wait_for 60 vm_running
    # Monitor.
    view monitor
    reset_step; answers "info version"
    check "Monitor: command" enter cmd
    check "Monitor: output" bash -c "[[ '${MONITOR_LOG[*]}' == *[0-9].[0-9]* ]]"
    # Console: serial port -> qm terminal.
    TERM_CMDS=()
    act_console
    check "Console: qm terminal used (serial port)" bash -c "[[ '${TERM_CMDS[*]}' == *'qm terminal $TEST_VM'* ]]"
    # Snapshots with RAM.
    view snapshots
    reset_step; answers pvtsnap1 "pvetty snapshot" yes
    check "Snapshots: take (with RAM)" key n ""
    check "Snapshots: listed" api_has "/nodes/$NODE/qemu/$TEST_VM/snapshot" name pvtsnap1
    view snapshots; reset_step; answers edit "edited snapshot"
    check "Snapshots: edit description" enter pvtsnap1
    reset_step; check "Snapshots: rollback" key R pvtsnap1
    # After a rollback with RAM, QEMU loads the memory state while PVE still
    # holds the VM lock: wait for it (the web UI shows the same lock error).
    check "VM lock released after rollback" wait_for 180 flock -n "/var/lock/qemu-server/lock-$TEST_VM.conf" true
    reset_step; check "Snapshots: remove" key d pvtsnap1
    check "Snapshots: removed" api_lacks "/nodes/$NODE/qemu/$TEST_VM/snapshot" name pvtsnap1
    # Hibernate, then stop.
    res_load; ctx "$id"
    reset_step; answers hibernate; check "Hibernate" act_shutdown_menu
    check "VM hibernated (stopped with state)" wait_for 60 bash -c "! pvesh get /nodes/$NODE/qemu/$TEST_VM/status/current --output-format json | grep -q '\"status\":\"running\"'"
    res_load; ctx "$id"
    reset_step; check "Start (resume from hibernation)" act_start
    reset_step; answers stop; check "Stop" act_shutdown_menu
    check "VM stopped" wait_for 30 bash -c "! vm_running"

    # Guest firewall: rules, options, alias, IPSet.
    fw_suite "$id" "/nodes/$NODE/qemu/$TEST_VM/firewall" "VM"
    ctx "$id"; view fwoptions
    reset_step; preset enable=1
    check "VM Firewall: enable" enter enable
    reset_step; preset enable=""
    check "VM Firewall: disable" enter enable
    view fwalias
    reset_step; preset name=pvtvmalias cidr=192.0.2.20
    check "VM Alias: add" key a ""
    view fwalias; reset_step; check "VM Alias: remove" key d pvtvmalias
    view fwipset
    reset_step; crud_answers sub=ipset; preset name=pvtvmset
    check "VM IPSet: add" key a ""
    view fwipset; reset_step; check "VM IPSet: remove" key d "ipset|pvtvmset"

    # Backup now, backup panel actions, restore to a new VM.
    view backup
    reset_step; answers local snapshot
    check "Backup now" key n ""
    view backup; k=${C_SELK[0]-}
    check "Backup: listed" test -n "$k"
    reset_step; answers notes "pvetty backup"
    check "Backup: edit notes" enter "$k"
    reset_step; answers protect
    check "Backup: protect" enter "$k"
    reset_step; answers protect
    check "Backup: unprotect" enter "$k"
    reset_step; answers config
    check "Backup: show configuration" enter "$k"
    ctx "storage/$NODE/local"; view backup
    reset_step; crud_answers vmid=9902 storage=$st
    check "Storage Backups: restore to VM 9902" key r "$k"
    check "Restored VM 9902 exists" wait_for 60 pvesh get "/nodes/$NODE/qemu/9902/config"
    reset_step; preset keep-last=1
    check "Storage Backups: prune" key P "$k"
    ctx "$id"; view backup
    reset_step; answers remove
    check "Backup: remove" enter "$k"

    # Replication needs another node: the API must refuse it.
    view replication
    reset_step; preset target=$NODE schedule="*/15"
    if key a ""; then ko "Replication: add (single node)" "unexpected success"
    else ok "Replication: refused on a single node ($STATUS_MSG)"; fi

    # More: clone, template, migrate (no target), remove.
    reset_step; answers 9903 pvetty-clone yes
    check "Clone (full)" act_clone
    check "Clone 9903 exists" wait_for 120 pvesh get "/nodes/$NODE/qemu/9903/config"
    res_load; ctx qemu/9903
    reset_step; check "Convert clone to template" act_template
    check "9903 is a template" kv_is "/nodes/$NODE/qemu/9903/config" template 1
    reset_step; check "Migrate (no other node)" act_migrate
    reset_step; answers 9903 yes
    check "Remove template 9903" act_remove
    res_load; ctx qemu/9902
    reset_step; answers 9902 yes
    check "Remove restored VM 9902" act_remove

    # SSH proposal for a Linux VM without serial port (VM 100 if present).
    if pvesh get "/nodes/$NODE/qemu/100/config" >/dev/null 2>&1; then
        res_load; ctx qemu/100
        guest_ip_candidates
        (( ${#GUEST_IPS[@]} )) || guest_ip_candidates scan
        if (( ${#GUEST_IPS[@]} )); then ok "SSH: IP addresses found for VM 100 (${GUEST_IPS[*]})"
        else skip "SSH: IP addresses for VM 100" "no guest agent and no answer to the network scan"; fi
        TERM_CMDS=(); reset_step; answers "${GUEST_IPS[0]:-_other}" root
        [[ -z ${GUEST_IPS[0]-} ]] && answers _other 127.0.0.1 root
        api_kv /nodes/$NODE/qemu/100/config
        if [[ -z ${API_KV[serial0]-} && ${API_KV[ostype]-} == l26 ]]; then
            act_console
            check "SSH: proposed instead of the serial console" bash -c "[[ '${TERM_CMDS[*]}' == *ssh* ]]"
        fi
    fi

    # Remove the test VM.
    res_load; ctx "$id"
    reset_step; answers "$TEST_VM" yes
    check "Remove VM $TEST_VM" act_remove
    check "VM removed" wait_for 60 bash -c "! pvesh get /nodes/$NODE/qemu/$TEST_VM/config >/dev/null 2>&1"
}
