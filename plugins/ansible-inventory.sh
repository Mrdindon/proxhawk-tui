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
    local -A groups=() seen=()
    ANSIBLE_LINES=("all:" "  hosts:") ANSIBLE_HOSTS=0
    for id in "${RES_IDS[@]}"; do
        t=${R_TYPE[$id]}
        [[ $t == qemu || $t == lxc ]] || continue
        [[ ${R_TMPL[$id]} == 1 ]] && continue
        name=${R_NAME[$id]:-$t${R_VMID[$id]}}
        # Host names are YAML keys: a second guest with the same name gets
        # its VMID appended.
        [[ -n ${seen[$name]-} ]] && name="$name-${R_VMID[$id]}"
        seen[$name]=1
        guest_ip_cached "$id"; ip=${REPLY%%,*}
        ANSIBLE_LINES+=("    $name:"); (( ANSIBLE_HOSTS++ ))
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
    local l i=0
    ansible_inventory
    c_add " ${C[dim]}$(T "Ansible inventory of the guests (s: save to a file, v: view in the pager)"; printf '%s' "$REPLY")${C[norm]}"
    c_blank
    # Selectable lines: the cursor shows the position while scrolling.
    for l in "${ANSIBLE_LINES[@]}"; do c_sel " $l" "line|$(( i++ ))"; done
}
v_dc_ansible__key() {
    local file dir
    case $1 in
        s)
            dlg_input "Ansible Inventory" "Save to file:" "${ANSIBLE_FILE:-/root/proxhawk-tui-inventory.yml}" || return 0
            file=$REPLY                # ansible_inventory overwrites REPLY
            [[ -n $file ]] || return 0
            [[ $file == /* ]] || file="$HOME/$file"
            if [[ -d $file ]]; then file="${file%/}/proxhawk-tui-inventory.yml"; fi
            if [[ -e $file ]]; then
                Tf "%s already exists. Replace it?" "$file"
                dlg_yesno "Ansible Inventory" "$REPLY" || return 0
            fi
            dir=$(dirname "$file")
            ansible_inventory
            if mkdir -p "$dir" 2>/dev/null && printf '%s\n' "${ANSIBLE_LINES[@]}" > "$file" 2>/dev/null; then
                ANSIBLE_FILE=$file
                Tf "Inventory saved to %s (%d hosts, %d lines)" "$file" "$ANSIBLE_HOSTS" "${#ANSIBLE_LINES[@]}"
                status_msg ok "$REPLY"
            else
                Tf "Cannot write %s" "$file"; status_msg err "$REPLY"
            fi ;;
        v)
            ansible_inventory
            printf '%s\n' "${ANSIBLE_LINES[@]}" > "$RUN_DIR/inventory.yml"
            pager_show "$RUN_DIR/inventory.yml" "Ansible inventory" ;;
        *) return 1 ;;
    esac
    return 0
}
VIEW_HINT[v_dc_ansible]="s:Save v:View"
VIEW_LIVE[v_dc_ansible]=1
