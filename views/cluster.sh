# shellcheck shell=bash
# views/cluster.sh - Datacenter panels: Cluster, Options, Storage, Backup,
# Replication, HA, Metric Server, Resource Mappings, Notifications, Support.

# ---------------------------------------------------------------------------
# Cluster: information, nodes, Create Cluster / Join Information / Join Cluster
# ---------------------------------------------------------------------------
v_dc_cluster() {
    c_section "Cluster Information"
    if [[ -z $CLUSTER_NAME ]]; then
        c_msg dim "Standalone node - no cluster defined"
    else
        c_kv "Cluster Name" "$CLUSTER_NAME"
        fmtv bool "$QUORATE"; c_kv "Quorate" "$REPLY"
        api_kv /cluster/config/totem && c_kv "Config Version" "${API_KV[config_version]-}"
    fi
    c_blank
    c_section "Cluster Nodes"
    view_table /cluster/config/nodes "" "name:Nodename:20|nodeid:ID:6:s:r|quorum_votes:Votes:8:s:r|ring0_addr:Link 0:*|ring1_addr:Link 1:*" 0 0
}
VIEW_HINT[v_dc_cluster]="C:Create_Cluster J:Join_Information j:Join_Cluster"
v_dc_cluster__key() {
    case $1 in
        C)
            [[ -z $CLUSTER_NAME ]] || { dlg_msg "Create Cluster" "This node is already part of cluster '$CLUSTER_NAME'."; return 0; }
            dlg_yesno "Create Cluster" "Creating a cluster changes the configuration of corosync and pmxcfs on this node. It cannot be undone from the interface. Continue?" || return 0
            form_reset
            FORM_FIRST="clustername link0 link1"
            form_run "Create Cluster" POST /cluster/config ;;
        J)
            if ! api_get json /cluster/config/join "" ""; then dlg_msg "Join Information" "$API_ERR"; return 0; fi
            api_kv /cluster/config/join
            {
                printf 'IP Address : %s\n' "${API_KV[nodelist.0.pve_addr]-}"
                printf 'Fingerprint: %s\n\n' "${API_KV[nodelist.0.pve_fp]-}"
                printf 'Join Information (copy it to the joining node):\n'
                printf '%s' "${API_ROWS[0]}" | base64 -w 0; echo
            } > "$RUN_DIR/join.txt"
            dlg_textbox "Join Information" "$RUN_DIR/join.txt" ;;
        j)
            [[ -z $CLUSTER_NAME ]] || { dlg_msg "Join Cluster" "This node is already part of a cluster."; return 0; }
            dlg_yesno "Join Cluster" "The node must not contain guests; its configuration is replaced by the cluster configuration. Continue?" || return 0
            form_reset
            FORM_FIRST="hostname fingerprint password link0 link1 force"
            form_run "Join Cluster" POST /cluster/config/join ;;
        *) return 1 ;;
    esac
    return 0
}

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------
v_dc_options() {
    api_kv /cluster/options || { c_api_error; return; }
    local -a keys=(keyboard http_proxy console email_from mac_prefix migration ha crs bwlimit max_workers
        next-id u2f webauthn tag-style user-tag-access registered-tags fencing consent-text replication)
    declare -A lbl=(
        [keyboard]="Keyboard Layout" [http_proxy]="HTTP proxy" [console]="Console Viewer"
        [email_from]="Email from address" [mac_prefix]="MAC address prefix" [migration]="Migration Settings"
        [ha]="HA Settings" [crs]="Cluster Resource Scheduling" [bwlimit]="Bandwidth Limits"
        [max_workers]="Maximal Workers/bulk-action" [next-id]="Next Free VMID Range" [u2f]="U2F Settings"
        [webauthn]="WebAuthn Settings" [tag-style]="Tag Style Override" [user-tag-access]="User Tag Access"
        [registered-tags]="Registered Tags" [fencing]="Fencing" [consent-text]="Consent Text"
        [replication]="Replication"
    )
    declare -A def=(
        [keyboard]="Default (Browser)" [http_proxy]="none" [console]="Default (xterm.js)"
        [email_from]="root@\$hostname" [mac_prefix]="BC:24:11" [migration]="Default"
        [ha]="Default (shutdown_policy=conditional)" [crs]="Default (ha=basic)" [bwlimit]="none"
        [max_workers]="4" [next-id]="Default" [u2f]="none" [webauthn]="none" [tag-style]="No Overrides"
        [user-tag-access]="Mode: free" [registered-tags]="none" [fencing]="Default (watchdog)"
        [consent-text]="none" [replication]="Default"
    )
    local k v
    for k in "${keys[@]}"; do
        v=${API_KV[$k]-}
        [[ -z $v ]] && { T "${def[$k]}"; v="${C[dim]}${REPLY}${C[norm]}"; }
        c_kv_sel "${lbl[$k]}" "${v//$'\x1f'/ }" "$k" 30
    done
}
v_dc_options__enter() { _option_form "Datacenter" /cluster/options "$1"; }
v_dc_options__key() { [[ $1 == e ]] && { v_dc_options__enter "$2"; return 0; }; return 1; }
VIEW_HINT[v_dc_options]="Enter:Edit"

# Edit one option of a configuration object: _option_form <title> <path> <key> [method]
_option_form() {
    [[ -n $3 ]] || return 0
    form_reset
    FORM_GET=$2 FORM_ONLY=$3
    form_run "Edit: $1" "${4:-PUT}" "$2" && content_load 1
}

# ---------------------------------------------------------------------------
# Storage
# ---------------------------------------------------------------------------
v_dc_storage() {
    local row path
    local -a f
    table_spec "storage:ID:18|type:Type:10|content:Content:*|path:Path/Target:*|shared:Shared:7|enabled:Enabled:8|bw:Bandwidth Limit:15"
    api_get rows /storage "" "storage,type,content,path,server,export,pool,datastore,shared,disable,bwlimit" || { c_api_error; return; }
    table_header
    for row in "${API_ROWS[@]}"; do
        tsv_split f "$row"
        path=${f[3]}
        [[ -z $path && -n ${f[4]} ]] && path="${f[4]}${f[5]:+:${f[5]}}${f[7]:+:${f[7]}}"
        [[ -z $path && -n ${f[6]} ]] && path=${f[6]}
        fmtv bool "${f[8]:-0}"; local sh=$REPLY
        fmtv nbool "${f[9]:-0}"; local en=$REPLY
        table_row "${f[0]}"$'\t'"${f[1]}"$'\t'"${f[2]//,/, }"$'\t'"$path"$'\t'"$sh"$'\t'"$en"$'\t'"${f[10]:-}"
        c_sel "$REPLY" "${f[0]}"
    done
}
crud v_dc_storage label="Storage" add=/storage edit="/storage/{1}" del="/storage/{1}" plugin=storage \
    first="storage path server export share username password datastore fingerprint namespace vgname thinpool pool monhost fs-name portal target content nodes shared disable"

# ---------------------------------------------------------------------------
# Backup jobs
# ---------------------------------------------------------------------------
v_dc_backup() {
    view_table /cluster/backup "" "enabled:Enabled:8:bool|node:Node:10|schedule:Schedule:16|next-run:Next Run:19:t|storage:Storage:16|comment:Comment:*|vmid:Selection:16|mode:Mode:9|id:Job ID:*" 8
}
crud v_dc_backup label="Backup Job" add=/cluster/backup edit="/cluster/backup/{1}" del="/cluster/backup/{1}" \
    first="schedule storage vmid all pool exclude mode compress enabled node comment notes-template mailto notification-mode" \
    choices="storage:choice_storages_backup node:choice_nodes" extra="R:Run_now J:Job_Detail"
v_dc_backup__key() {
    local j=${2-} k
    [[ -n $j ]] || return 1
    case $1 in
        R)
            local -a args=()
            # Same as "Run now" in the web UI: start vzdump with the job parameters.
            api_kv "/cluster/backup/$j" || { status_msg err "$API_ERR"; return 0; }
            for k in vmid all storage mode compress pool exclude mailto mailnotification notes-template protected; do
                [[ -n ${API_KV[$k]-} ]] && args+=("--$k" "${API_KV[$k]}")
            done
            Tf "Run backup job '%s' now?" "$j"; confirm "$REPLY" || return 0
            api_exec "Backup job $j" create "/nodes/${API_KV[node]:-$LOCAL_NODE}/vzdump" "${args[@]}" ;;
        J)
            api_get kv "/cluster/backup/$j" || return 0
            printf '%s\n' "${API_ROWS[@]}" | tr '\t\036' '=,' > "$RUN_DIR/job.txt"
            if api_get rows "/cluster/backup/$j/included_volumes" "" "@children;id,name,type"; then
                { echo; echo "Included guests:"; printf '  %s\n' "${API_ROWS[@]}" | tr '\t' ' '; } >> "$RUN_DIR/job.txt"
            fi
            dlg_textbox "Job Detail: $j" "$RUN_DIR/job.txt" ;;
        *) return 1 ;;
    esac
    return 0
}

# Guests not covered by any backup job (Backup > "Guests without backup job").
v_dc_replication() {
    view_table /cluster/replication "" "guest:Guest:8|id:ID:10|target:Target:12|schedule:Schedule:12|rate:Rate limit:10|comment:Comment:*|disable:Enabled:8:nbool" 1
}
crud v_dc_replication label="Replication Job" add=/cluster/replication edit="/cluster/replication/{1}" \
    del="/cluster/replication/{1}" first="id target schedule rate comment disable" choices="target:choice_nodes"

# ---------------------------------------------------------------------------
# HA: status, resources, rules
# ---------------------------------------------------------------------------
v_dc_ha() {
    c_section "Status"
    view_table /cluster/ha/status/current "" "id:Type:16|status:Status:*" -1
    c_blank
    c_section "Resources"
    view_table /cluster/ha/resources "" "sid:ID:14|state:State:10|group:Group:12|max_restart:Max. Restart:13:s:r|max_relocate:Max. Relocate:14:s:r|failback:Failback:9:bool|comment:Description:*"
}
crud v_dc_ha label="HA Resource" add=/cluster/ha/resources edit="/cluster/ha/resources/{1}" del="/cluster/ha/resources/{1}" \
    first="sid state max_restart max_relocate failback comment" extra="M:Migrate L:Relocate A:Arm_HA D:Disarm_HA"
v_dc_ha__key() {
    case $1 in
        M|L)
            [[ -n $2 ]] || return 0
            local act=migrate; [[ $1 == L ]] && act=relocate
            form_reset
            choice_nodes && FORM_CHOICES[node]=$REPLY
            form_run "HA ${act^}: $2" POST "/cluster/ha/resources/$2/$act" ;;
        A) api_exec_sync "Arm HA" create /cluster/ha/status/arm-ha; content_load 1 ;;
        D)
            form_reset
            form_run "Disarm HA" POST /cluster/ha/status/disarm-ha && content_load 1 ;;
        *) return 1 ;;
    esac
    return 0
}
VIEW_LIVE[v_dc_ha]=1

v_dc_harules() {
    view_table /cluster/ha/rules "" "rule:ID:16|type:Type:18|disable:Enabled:8:nbool|resources:Resources:*|nodes:Nodes:*|affinity:Affinity:10|comment:Comment:*"
}
crud v_dc_harules label="HA Rule" add=/cluster/ha/rules edit="/cluster/ha/rules/{1}" del="/cluster/ha/rules/{1}" \
    plugin=harule first="rule resources nodes affinity strict disable comment"

# ---------------------------------------------------------------------------
# Metric servers
# ---------------------------------------------------------------------------
v_dc_metric() { view_table /cluster/metrics/server "" "id:Name:20|type:Type:12|disable:Enabled:8:nbool|server:Server:*|port:Port:6"; }
crud v_dc_metric label="Metric Server" add="/cluster/metrics/server/{?id:Name}" edit="/cluster/metrics/server/{1}" \
    del="/cluster/metrics/server/{1}" plugin=metric first="server port disable influxdbproto organization bucket token path mtu timeout"

# ---------------------------------------------------------------------------
# Resource mappings (PCI, USB, Directory). Row keys "pci|id"...
# ---------------------------------------------------------------------------
v_dc_mapping() {
    local t
    for t in pci usb; do
        case $t in pci) c_section "PCI Devices" ;; usb) c_section "USB Devices" ;; esac
        TABLE_KEY_PREFIX="$t|"
        view_table "/cluster/mapping/$t" "" "id:ID:20|description:Comment:*|map:Mapping:**"
        c_blank
    done
}
crud v_dc_mapping:pci label="PCI Mapping" add=/cluster/mapping/pci edit="/cluster/mapping/pci/{1}" del="/cluster/mapping/pci/{1}" first="id map description mdev live-migration-capable"
crud v_dc_mapping:usb label="USB Mapping" add=/cluster/mapping/usb edit="/cluster/mapping/usb/{1}" del="/cluster/mapping/usb/{1}" first="id map description"

v_dc_dirmapping() { view_table /cluster/mapping/dir "" "id:ID:20|description:Comment:*|map:Mapping:**"; }
crud v_dc_dirmapping label="Directory Mapping" add=/cluster/mapping/dir edit="/cluster/mapping/dir/{1}" del="/cluster/mapping/dir/{1}" first="id map description"

# Custom CPU models (cpu-models.conf).
v_dc_cputypes() { view_table /cluster/qemu/custom-cpu-models "" "cputype:Name:24|reported-model:Base model:20|flags:Flags:*|hidden:Hidden:8:bool"; }
crud v_dc_cputypes label="CPU Model" add=/cluster/qemu/custom-cpu-models edit="/cluster/qemu/custom-cpu-models/{1}" \
    del="/cluster/qemu/custom-cpu-models/{1}" first="cputype reported-model flags hidden hv-vendor-id phys-bits"

v_dc_hafencing() {
    c_blank
    c_msg dim "Use watchdog based fencing."
    c_add ""
    c_add "  ${C[dim]}See: https://pve.proxmox.com/pve-docs/chapter-ha-manager.html#ha_manager_fencing${C[norm]}"
}

# ---------------------------------------------------------------------------
# Notifications: targets and matchers. Row keys "target|type|name", "matcher|name".
# ---------------------------------------------------------------------------
v_dc_notifications() {
    local row n=0
    local -a f
    c_section "Notification Targets"
    table_spec "name:Target Name:20|type:Type:10|disable:Enable:8:nbool|comment:Comment:*|origin:Origin:14"
    api_get rows /cluster/notifications/targets "" "name,type,disable,comment,origin" || { c_api_error; return; }
    table_header
    for row in "${API_ROWS[@]}"; do
        tsv_split f "$row"; table_row "$row"; c_sel "$REPLY" "target|${f[1]}|${f[0]}"; (( n++ ))
    done
    (( n )) || c_msg dim "No items"
    c_blank
    c_section "Notification Matchers"
    TABLE_KEY_PREFIX="matcher|"
    view_table /cluster/notifications/matchers "" "name:Matcher Name:20|disable:Enable:8:nbool|target:Targets to notify:*|comment:Comment:*|origin:Origin:14"
}
crud v_dc_notifications:target label="Notification Target" add="/cluster/notifications/endpoints/{type}" pathtype=1 \
    types="sendmail,smtp,gotify,webhook" edit="/cluster/notifications/endpoints/{1}/{2}" del="/cluster/notifications/endpoints/{1}/{2}" \
    first="name mailto mailto-user from-address server port mode username password url token method author comment disable"
crud v_dc_notifications:matcher label="Notification Matcher" add=/cluster/notifications/matchers \
    edit="/cluster/notifications/matchers/{1}" del="/cluster/notifications/matchers/{1}" \
    first="name target match-severity match-field match-calendar mode invert-match comment disable"
CRUD[v_dc_notifications|extra]="t:Test"
v_dc_notifications__key() {
    [[ $1 == t && $2 == target\|* ]] || return 1
    local name=${2##*|}
    api_exec_sync "Test notification target $name" create "/cluster/notifications/targets/$name/test"
    return 0
}

# ---------------------------------------------------------------------------
# Support / subscription of the local node
# ---------------------------------------------------------------------------
v_dc_support() {
    api_kv "/nodes/$LOCAL_NODE/subscription" || { c_api_error; return; }
    c_section "Subscription"
    c_kv "Product Name" "${API_KV[productname]:-${C[dim]}-${C[norm]}}"
    c_kv "Status" "${API_KV[status]-}"
    c_kv "Subscription Key" "${API_KV[key]:--}"
    c_kv "Server ID" "${API_KV[serverid]-}"
    c_kv "Next due date" "${API_KV[nextduedate]:--}"
    c_blank
    c_section "Support"
    c_add "  Documentation:  https://pve.proxmox.com/pve-docs/"
    c_add "  Forum:          https://forum.proxmox.com/"
    c_add "  Bugtracker:     https://bugzilla.proxmox.com/"
}
