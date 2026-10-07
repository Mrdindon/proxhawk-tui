# shellcheck shell=bash
# views/qemu.sh - "Virtual Machine" panels (shared ones are in guest.sh).

view_menu qemu \
    "summary|Summary|m_summary|0" \
    "console|Console|m_console|0" \
    "hardware|Hardware|m_hardware|0" \
    "cloudinit|Cloud-Init|m_cloudinit|0" \
    "options|Options|m_options|0" \
    "tasks|Task History|m_tasks|0" \
    "monitor|Monitor|m_monitor|0" \
    "backup|Backup|m_backup|0" \
    "replication|Replication|m_replication|0" \
    "snapshots|Snapshots|m_snapshot|0" \
    "firewall|Firewall|m_firewall|0" \
    "fwoptions|Options|m_options|1" \
    "fwalias|Alias|m_firewall|1" \
    "fwipset|IPSet|m_firewall|1" \
    "fwlog|Log|m_syslog|1" \
    "permissions|Permissions|m_permissions|0"

declare -gA QEMU_OSTYPE=(
    [l26]="Linux 6.x - 2.6 Kernel" [l24]="Linux 2.4 Kernel" [other]="Other"
    [win11]="Microsoft Windows 11/2022/2025" [win10]="Microsoft Windows 10/2016/2019"
    [win8]="Microsoft Windows 8.x/2012/2012r2" [win7]="Microsoft Windows 7/2008r2"
    [w2k8]="Microsoft Windows Vista/2008" [wvista]="Microsoft Windows Vista"
    [wxp]="Microsoft Windows XP/2003" [w2k3]="Microsoft Windows 2003" [w2k]="Microsoft Windows 2000"
    [solaris]="Solaris Kernel"
)
declare -gA QEMU_SCSIHW=(
    [lsi]="LSI 53C895A" [lsi53c810]="LSI 53C810" [megasas]="MegaRAID SAS 8708EM2"
    [virtio-scsi-pci]="VirtIO SCSI" [virtio-scsi-single]="VirtIO SCSI single" [pvscsi]="VMware PVSCSI"
)
declare -gA QEMU_VGA=(
    [std]="Standard VGA" [cirrus]="Cirrus Logic GD5446" [vmware]="VMware compatible" [qxl]="SPICE"
    [qxl2]="SPICE dual monitor" [qxl3]="SPICE three monitors" [qxl4]="SPICE four monitors"
    [serial0]="Serial terminal 0" [serial1]="Serial terminal 1" [virtio]="VirtIO-GPU"
    [virtio-gl]="VirGL GPU" [none]="none"
)

# Hardware panel, in the same order as the web UI.
v_qemu_hardware() {
    guest_config || { c_api_error; return; }
    local v k mem bal
    # Memory
    mem=${CFGP[memory]:-${CFGV[memory]:-512}}
    mem=${mem#current=}; mem=${mem%%,*}
    fmt_bytes $(( mem * 1048576 )); v=$REPLY
    bal=${CFGV[balloon]-}
    if [[ $bal == 0 ]]; then v+=" [balloon=0]"
    elif [[ -n $bal && $bal != "$mem" ]]; then fmt_bytes $(( bal * 1048576 )); v="$REPLY/$v"
    fi
    cfg_line "Memory" memory "$v"
    # Processors
    local so=${CFGV[sockets]:-1} co=${CFGV[cores]:-1}
    v="$(( so * co )) ($so sockets, $co cores)"
    [[ -n ${CFGV[cpu]-} ]] && v+=" [${CFGV[cpu]}]"
    [[ ${CFGV[numa]-} == 1 ]] && v+=" [numa=1]"
    [[ -n ${CFGV[vcpus]-} ]] && v+=" [vcpus=${CFGV[vcpus]}]"
    [[ -n ${CFGV[cpulimit]-} ]] && v+=" [cpulimit=${CFGV[cpulimit]}]"
    [[ -n ${CFGV[affinity]-} ]] && v+=" [affinity=${CFGV[affinity]}]"
    cfg_line "Processors" cores "$v"
    # BIOS / Display / Machine / SCSI controller
    case ${CFGV[bios]-} in
        ovmf) v="OVMF (UEFI)" ;; seabios) v="SeaBIOS" ;; *) v="" ;;
    esac
    cfg_line "BIOS" bios "$v" "Default (SeaBIOS)"
    v=${CFGV[vga]-}
    if [[ -n $v ]]; then local vt=${v%%,*}; vt=${vt#type=}; v="${QEMU_VGA[$vt]:-$vt} ($v)"; fi
    cfg_line "Display" vga "$v" "Default"
    cfg_line "Machine" machine "${CFGV[machine]-}" "Default (i440fx)"
    v=${CFGV[scsihw]-}; [[ -n $v ]] && v=${QEMU_SCSIHW[$v]:-$v}
    cfg_line "SCSI Controller" scsihw "$v" "Default (LSI 53C895A)"
    # Drives, network devices and the other devices.
    local -a keys
    mapfile -t keys < <(printf '%s\n' "${!CFGV[@]}" "${!CFGP[@]}" | sort -u | sort -V)
    local bus label
    for bus in ide sata scsi virtio; do
        for k in "${keys[@]}"; do
            [[ $k =~ ^${bus}[0-9]+$ ]] || continue
            v=${CFGV[$k]:-${CFGP[$k]}}
            if [[ $v == *cloudinit* ]]; then label="CloudInit Drive"
            elif [[ $v == *media=cdrom* ]]; then label="CD/DVD Drive"
            else label="Hard Disk"
            fi
            T "$label"; cfg_line "$REPLY ($k)" "$k" "$v"
        done
    done
    local -a other=(
        "net:Network Device" "efidisk:EFI Disk" "tpmstate:TPM State" "usb:USB Device"
        "hostpci:PCI Device" "serial:Serial Port" "parallel:Parallel Port" "audio:Audio Device"
        "rng:VirtIO RNG" "virtiofs:Virtiofs" "unused:Unused Disk"
    )
    local o pre
    for o in "${other[@]}"; do
        pre=${o%%:*} label=${o#*:}
        for k in "${keys[@]}"; do
            [[ $k =~ ^${pre}[0-9]+$ ]] || continue
            T "$label"
            cfg_line "$REPLY ($k)" "$k" "${CFGV[$k]:-${CFGP[$k]}}"
        done
    done
}
v_qemu_hardware__enter() { guest_cfg_edit "$1"; }
v_qemu_hardware__key() {
    case $1 in
        a|INS) qemu_hw_add ;;
        e) guest_cfg_edit "$2" ;;
        R) guest_disk_resize "$2" ;;
        m) guest_disk_move "$2" ;;
        *) guest_cfg_key "$@"; return ;;
    esac
    return 0
}
VIEW_HINT[v_qemu_hardware]="a:Add e:Edit d:Remove/Detach R:Resize m:Move_disk v:Revert"

# Add menu of the Hardware panel (same entries as the web UI).
qemu_hw_add() {
    local kind=${CRUD_ANSWER[device]-} key st bus
    local -a items=()
    if [[ -z $kind ]]; then
        T "Hard Disk"; items+=(disk "$REPLY")
        T "CD/DVD Drive"; items+=(cdrom "$REPLY")
        T "Network Device"; items+=(net "$REPLY")
        T "EFI Disk"; items+=(efidisk "$REPLY")
        T "TPM State"; items+=(tpmstate "$REPLY")
        T "USB Device"; items+=(usb "$REPLY")
        T "PCI Device"; items+=(hostpci "$REPLY")
        T "Serial Port"; items+=(serial "$REPLY")
        T "CloudInit Drive"; items+=(cloudinit "$REPLY")
        T "Audio Device"; items+=(audio "$REPLY")
        T "VirtIO RNG"; items+=(rng "$REPLY")
        T "Virtiofs"; items+=(virtiofs "$REPLY")
        T "Add"; dlg_menu "$REPLY" "Hardware" "${items[@]}" || return
        kind=$REPLY
    fi
    _bus() {
        bus=${CRUD_ANSWER[bus]-}
        [[ -n $bus ]] && return 0
        dlg_menu "Bus/Device" "Bus:" scsi SCSI virtio "VirtIO Block" sata SATA ide IDE || return 1
        bus=$REPLY
    }
    case $kind in
        disk)
            _bus || return; _pick_store images || return; st=$REPLY
            local size=${CRUD_ANSWER[size]-}
            [[ -z $size ]] && { dlg_input "Hard Disk" "Disk size (GiB):" "32" || return; size=$REPLY; }
            cfg_next "$bus" 30; key=$REPLY
            local opts=""; [[ $bus == scsi || $bus == virtio ]] && opts=",iothread=1"
            guest_add_device "$key" "$st:$size$opts" "Hard Disk ($key)" ;;
        cdrom)
            _bus || return
            local iso=${CRUD_ANSWER[iso]-none}
            if [[ -z ${CRUD_ANSWER[iso]-} ]]; then _pick_volume "CD/DVD Drive" "$CTX_NODE" iso || return; iso=$REPLY; fi
            cfg_next "$bus" 30; key=$REPLY
            guest_add_device "$key" "$iso,media=cdrom" "CD/DVD Drive ($key)" ;;
        cloudinit)
            _bus || return; _pick_store images || return; st=$REPLY
            cfg_next "$bus" 30; key=$REPLY
            guest_add_device "$key" "$st:cloudinit" "CloudInit Drive ($key)" ;;
        net)
            cfg_next net 31; key=$REPLY
            local br=vmbr0; choice_bridges && br=${REPLY%%=*}
            guest_add_device "$key" "virtio,bridge=$br,firewall=1" "Network Device ($key)" ;;
        efidisk) _pick_store images || return; guest_add_device efidisk0 "$REPLY:1,efitype=4m,pre-enrolled-keys=1" "EFI Disk" ;;
        tpmstate) _pick_store images || return; guest_add_device tpmstate0 "$REPLY:1,version=v2.0" "TPM State" ;;
        usb) cfg_next usb 13; guest_add_device "$REPLY" "${CRUD_ANSWER[value]:-}" "USB Device ($REPLY)" ;;
        hostpci) cfg_next hostpci 15; guest_add_device "$REPLY" "${CRUD_ANSWER[value]:-}" "PCI Device ($REPLY)" ;;
        serial) cfg_next serial 3; guest_add_device "$REPLY" socket "Serial Port ($REPLY)" ;;
        audio) guest_add_device audio0 "device=ich9-intel-hda,driver=none" "Audio Device" ;;
        rng) guest_add_device rng0 "source=/dev/urandom" "VirtIO RNG" ;;
        virtiofs) cfg_next virtiofs 9; guest_add_device "$REPLY" "${CRUD_ANSWER[value]:-}" "Virtiofs ($REPLY)" ;;
    esac
}

v_qemu_cloudinit() {
    guest_config || { c_api_error; return; }
    local has=0 k
    for k in "${!CFGV[@]}"; do [[ ${CFGV[$k]} == *cloudinit* ]] && has=1; done
    (( has )) || { c_msg warn "No CloudInit Drive found"; c_blank; }
    cfg_line "User" ciuser "${CFGV[ciuser]-}" "Default"
    local pw=""; [[ -n ${CFGV[cipassword]-} ]] && pw="**********"
    cfg_line "Password" cipassword "$pw" "none"
    cfg_line "DNS domain" searchdomain "${CFGV[searchdomain]-}" "use host settings"
    cfg_line "DNS servers" nameserver "${CFGV[nameserver]-}" "use host settings"
    local keys=""; [[ -n ${CFGV[sshkeys]-} ]] && { printf -v keys '%b' "${CFGV[sshkeys]//%/\\x}"; keys=${keys%%$'\n'*}; }
    cfg_line "SSH public key" sshkeys "${keys:0:60}" "none"
    cfg_line "Upgrade packages" ciupgrade "${CFGV[ciupgrade]-}" "Default (Yes)"
    local -a ks
    mapfile -t ks < <(printf '%s\n' "${!CFGV[@]}" | grep '^ipconfig' | sort -V)
    (( ${#ks[@]} )) || ks=(ipconfig0)
    for k in "${ks[@]}"; do
        cfg_line "IP Config (net${k#ipconfig})" "$k" "${CFGV[$k]-}" "none"
    done
}
v_qemu_cloudinit__enter() { guest_cfg_edit "$1"; }
VIEW_HINT[v_qemu_cloudinit]="Enter:Edit R:Regenerate_Image"
v_qemu_cloudinit__key() {
    [[ $1 == e ]] && { guest_cfg_edit "$2"; return 0; }
    if [[ $1 == R ]]; then
        api_exec_sync "Regenerate Cloud-Init image" set "/nodes/$CTX_NODE/qemu/$CTX_VMID/cloudinit"
        return 0
    fi
    guest_cfg_key "$@"
}
VIEW_HINT[v_qemu_cloudinit]="Enter:Edit R:Regenerate_Image"

v_qemu_options() {
    guest_config || { c_api_error; return; }
    local v
    cfg_line "Name" name "${CFGV[name]-}"
    fmtv bool "${CFGV[onboot]:-0}"; cfg_line "Start at boot" onboot "$REPLY"
    cfg_line "Start/Shutdown order" startup "${CFGV[startup]-}" "order=any"
    v=${CFGV[ostype]-}; [[ -n $v ]] && v="${QEMU_OSTYPE[$v]:-$v}"
    cfg_line "OS Type" ostype "$v" "Other"
    v=${CFGV[boot]-}; v=${v#order=}; v=${v//;/, }
    cfg_line "Boot Order" boot "$v" "Default"
    fmtv bool "${CFGV[tablet]:-1}"; cfg_line "Use tablet for pointer" tablet "$REPLY"
    cfg_line "Hotplug" hotplug "${CFGV[hotplug]-}" "Disk, Network, USB"
    fmtv bool "${CFGV[acpi]:-1}"; cfg_line "ACPI support" acpi "$REPLY"
    fmtv bool "${CFGV[kvm]:-1}"; cfg_line "KVM hardware virtualization" kvm "$REPLY"
    fmtv bool "${CFGV[freeze]:-0}"; cfg_line "Freeze CPU at startup" freeze "$REPLY"
    v=${CFGV[localtime]-}; [[ -n $v ]] && { fmtv bool "$v"; v=$REPLY; }
    cfg_line "Use local time for RTC" localtime "$v" "Default (Enabled for Windows)"
    cfg_line "RTC start date" startdate "${CFGV[startdate]-}" "now"
    cfg_line "SMBIOS settings (type1)" smbios1 "${CFGV[smbios1]-}"
    v=${CFGV[agent]-}; [[ $v == 1* || $v == *enabled=1* ]] && v="Enabled${v#1}"
    cfg_line "QEMU Guest Agent" agent "$v" "Default (Disabled)"
    fmtv bool "${CFGV[protection]:-0}"; cfg_line "Protection" protection "$REPLY"
    cfg_line "Spice Enhancements" spice_enhancements "${CFGV[spice_enhancements]-}" "none"
    cfg_line "VM State storage" vmstatestorage "${CFGV[vmstatestorage]-}" "Automatic"
    cfg_line "AMD SEV" amd-sev "${CFGV[amd-sev]-}" "Default (Disabled)"
    cfg_line "Hookscript" hookscript "${CFGV[hookscript]-}" "none"
}
v_qemu_options__enter() { guest_cfg_edit "$1"; }
v_qemu_options__key() { [[ $1 == e ]] && { guest_cfg_edit "$2"; return 0; }; guest_cfg_key "$@"; }
VIEW_HINT[v_qemu_options]="Enter:Edit d:Reset_to_default"

# QEMU monitor: commands typed in a dialog, output kept in the panel.
declare -ga MONITOR_LOG=()
MONITOR_VMID=""
v_qemu_monitor() {
    [[ $MONITOR_VMID == "$CTX_VMID" ]] || { MONITOR_LOG=(); MONITOR_VMID=$CTX_VMID; }
    c_sel "${C[accent]}${G[btn_console]}${C[norm]} $(T "Press Enter to type a monitor command (e.g. 'info version', 'help')."; printf '%s' "$REPLY")" cmd
    c_blank
    local l
    for l in "${MONITOR_LOG[@]}"; do c_add "$l"; done
}
v_qemu_monitor__enter() {
    if [[ ${R_STATUS[$CTX_ID]} != running ]]; then status_msg warn "VM $CTX_VMID is not running"; return; fi
    dlg_input "Monitor" "Command:" "" || return
    local cmd=$REPLY out
    [[ -n $cmd ]] || return
    spinner_start "qm monitor $CTX_VMID"
    out=$(pvesh create "/nodes/$CTX_NODE/qemu/$CTX_VMID/monitor" --command "$cmd" --output-format json 2>&1 \
        | perl "$PROXHAWK_TUI_HOME/lib/broker.pl" --filter rows "")
    spinner_stop
    MONITOR_LOG+=("${C[accent]}# ${cmd}${C[norm]}")
    local -a lines
    IFS=$'\x1f' read -r -d '' -a lines <<< "${out//$'\n'/$'\x1f'}"$'\x1f'
    MONITOR_LOG+=("${lines[@]}")
    content_load 1
    C_SCROLL=999999
}
