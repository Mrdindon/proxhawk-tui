# shellcheck shell=bash
# plugin: ansible-inventory
# description: Generate an Ansible inventory (YAML) of the guests, grouped by node, type and tag
#
# Adds Datacenter > "Ansible Inventory": the inventory is shown in the panel
# and can be saved to a file (s). Hosts use the guest name; ansible_host is
# the first IP address found (guest agent, container interfaces, neighbours).

menu_extend dc "ansible|Ansible Inventory|m_content|0"

ansible_inventory() {
    local id name ip t tag
    local -A groups=()
    ANSIBLE_LINES=("all:" "  hosts:")
    for id in "${RES_IDS[@]}"; do
        t=${R_TYPE[$id]}
        [[ $t == qemu || $t == lxc ]] || continue
        [[ ${R_TMPL[$id]} == 1 ]] && continue
        name=${R_NAME[$id]:-$t${R_VMID[$id]}}
        guest_ip_cached "$id"; ip=${REPLY%%,*}
        ANSIBLE_LINES+=("    $name:")
        [[ -n $ip ]] && ANSIBLE_LINES+=("      ansible_host: $ip")
        ANSIBLE_LINES+=("      proxmox_vmid: ${R_VMID[$id]}" "      proxmox_node: ${R_NODE[$id]}" "      proxmox_type: $t" "      proxmox_status: ${R_STATUS[$id]}")
        groups["node_${R_NODE[$id]//-/_}"]+="$name "
        groups["$t"]+="$name "
        groups["${R_STATUS[$id]}"]+="$name "
        for tag in ${R_TAGS[$id]//;/ }; do groups["tag_${tag//-/_}"]+="$name "; done
    done
    ANSIBLE_LINES+=("  children:")
    local g h
    for g in $(printf '%s\n' "${!groups[@]}" | sort); do
        ANSIBLE_LINES+=("    $g:" "      hosts:")
        for h in ${groups[$g]}; do ANSIBLE_LINES+=("        $h:"); done
    done
}

v_dc_ansible() {
    local l
    ansible_inventory
    c_add " ${C[dim]}$(T "Ansible inventory of the guests (s: save to a file)"; printf '%s' "$REPLY")${C[norm]}"
    c_blank
    for l in "${ANSIBLE_LINES[@]}"; do c_add " $l"; done
}
v_dc_ansible__key() {
    [[ $1 == s ]] || return 1
    dlg_input "Ansible Inventory" "Save to file:" "/root/pvetty-inventory.yml" || return 0
    ansible_inventory
    if printf '%s\n' "${ANSIBLE_LINES[@]}" > "$REPLY"; then Tf "Inventory saved to %s" "$REPLY"; status_msg ok "$REPLY"
    else Tf "Cannot write %s" "$REPLY"; status_msg err "$REPLY"; fi
    return 0
}
VIEW_HINT[v_dc_ansible]="s:Save"
VIEW_LIVE[v_dc_ansible]=1
