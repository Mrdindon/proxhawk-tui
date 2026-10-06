# shellcheck shell=bash
# views/storage.sh - "Storage", "Pool" and "SDN zone" panels.

# Menu depends on the content types of the storage.
menu_storage() {
    local content=",${R_CONTENT[$CTX_ID]-},"
    menu_add summary "Summary" m_summary 0
    [[ $content == *,backup,* ]] && menu_add backup "Backups" m_backups 0
    [[ $content == *,iso,* ]] && menu_add iso "ISO Images" m_iso 0
    [[ $content == *,vztmpl,* ]] && menu_add vztmpl "CT Templates" m_vztmpl 0
    [[ $content == *,images,* ]] && menu_add images "VM Disks" m_images 0
    [[ $content == *,rootdir,* ]] && menu_add rootdir "CT Volumes" m_rootdir 0
    [[ $content == *,snippets,* ]] && menu_add snippets "Snippets" m_snippets 0
    [[ $content == *,import,* ]] && menu_add import "Import" m_import 0
    menu_add permissions "Permissions" m_permissions 0
}

title_storage() { Tf "Storage '%s' on node '%s'" "$CTX_STORAGE" "$CTX_NODE"; }

v_storage_summary() {
    local w=$CONTENT_W
    api_kv "/storage/$CTX_STORAGE"
    local -A cfg=()
    local k; for k in "${!API_KV[@]}"; do cfg[$k]=${API_KV[$k]}; done
    if ! api_row "/nodes/$CTX_NODE/storage/$CTX_STORAGE/status" "" "type,content,active,enabled,shared,total:i,used:i,avail:i"; then
        c_api_error; return
    fi
    local -a s=("${API_F[@]}")
    c_kv "Type" "${s[0]}" 18
    c_kv "Content" "${s[1]//,/, }" 18
    local path=${cfg[path]:-${cfg[server]:-${cfg[pool]:-${cfg[vgname]:-}}}}
    [[ -n ${cfg[export]-} ]] && path+=":${cfg[export]}"
    [[ -n ${cfg[datastore]-} ]] && path+=":${cfg[datastore]}"
    c_kv "Path/Target" "$path" 18
    fmtv bool "${s[4]:-0}"; c_kv "Shared" "$REPLY" 18
    fmtv bool "${s[3]:-0}"; c_kv "Enabled" "$REPLY" 18
    fmtv bool "${s[2]:-0}"; c_kv "Active" "$REPLY" 18
    usage_line "Usage" "${s[6]:-0}" "${s[5]:-0}" "$w"; c_add "$REPLY"
    c_blank
    rrd_graphs "/nodes/$CTX_NODE/storage/$CTX_STORAGE/rrddata" "Usage|b|used:i|total:i"
}
v_storage_summary__key() { summary_key "$@"; }
VIEW_LIVE[v_storage_summary]=1
VIEW_HINT[v_storage_summary]="t:Timeframe"

# Generic content list: _storage_content <content type>
_storage_content() {
    local ct=$1 spec
    case $ct in
        images|rootdir) spec="volid:Name:*|ctime:Date:19:t|format:Format:8|size:Size:11:b:r|vmid:VMID:6:s:r" ;;
        backup) spec="volid:Name:*|notes:Notes:*|protected:Protected:10:bool|ctime:Date:19:t|format:Format:10|size:Size:11:b:r|vmid:VMID:6:s:r|verification.state:Verify State:12" ;;
        *) spec="volid:Name:*|ctime:Date:19:t|format:Format:8|size:Size:11:b:r" ;;
    esac
    view_table "/nodes/$CTX_NODE/storage/$CTX_STORAGE/content" "content=$ct" "$spec" 0 0
}
_storage_remove() {
    local vol=$1
    [[ -n $vol ]] || return 0
    Tf "Remove '%s'?" "$vol"; confirm "$REPLY" || return 0
    api_exec "Remove $vol" delete "/nodes/$CTX_NODE/storage/$CTX_STORAGE/content/$vol"
    return 0
}
_storage_download() {
    local ct=$1 url name
    dlg_input "Download from URL" "URL:" "" || return 0
    url=$REPLY; [[ -n $url ]] || return 0
    name=${url##*/}; name=${name%%\?*}
    dlg_input "Download from URL" "File name:" "$name" || return 0
    api_exec "$REPLY - Download" create "/nodes/$CTX_NODE/storage/$CTX_STORAGE/download-url" \
        --content "$ct" --filename "$REPLY" --url "$url"
    return 0
}
_storage_templates() {
    # Appliance templates (pveam) available for download.
    local -a items=()
    local row
    api_get rows "/nodes/$CTX_NODE/aplinfo" "" "template,headline" || { status_msg err "$API_ERR"; return 0; }
    for row in "${API_ROWS[@]}"; do items+=("${row%%$'\t'*}" "${row#*$'\t'}"); done
    (( ${#items[@]} )) || { dlg_msg "Templates" "No template list - run 'pveam update' on the node."; return 0; }
    dlg_menu "Templates" "Download a container template to $CTX_STORAGE:" "${items[@]}" || return 0
    api_exec "$REPLY - Download" create "/nodes/$CTX_NODE/aplinfo" --storage "$CTX_STORAGE" --template "$REPLY"
    return 0
}

# Upload a local file of this host (like the web UI "Upload" button).
_storage_upload() {
    local ct=$1 src tmp
    dlg_input "Upload" "Local file to upload ($ct):" "${CRUD_ANSWER[file]-}" || return 0
    src=$REPLY
    [[ -r $src && -f $src ]] || { dlg_msg "Upload" "Cannot read '$src'."; return 0; }
    if [[ $ct == snippets ]]; then
        # The API has no upload for snippets (the web UI neither): copy the
        # file into the snippets directory of a path based storage.
        local spath
        api_kv "/storage/$CTX_STORAGE"; spath=${API_KV[path]-}
        [[ -n $spath && $CTX_NODE == "$LOCAL_NODE" ]] || { dlg_msg "Upload" "Snippets can only be copied to a local path based storage."; return 0; }
        mkdir -p "$spath/snippets" && cp -- "$src" "$spath/snippets/" \
            && { Tf "%s copied to %s" "${src##*/}" "$spath/snippets"; status_msg ok "$REPLY"; } \
            || status_msg err "Copy to $spath/snippets failed"
        content_load 1
        return 0
    fi
    # The API moves its temporary file (/var/tmp/pveupload-<hex>): work on a copy.
    tmp="/var/tmp/pveupload-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
    T "Copying"; spinner_start "$REPLY ${src##*/}"
    cp -- "$src" "$tmp"; spinner_stop
    api_exec_sync "Upload ${src##*/}" create "/nodes/$CTX_NODE/storage/$CTX_STORAGE/upload" \
        --content "$ct" --filename "${src##*/}" --tmpfilename "$tmp"
    rm -f "$tmp"
    content_load 1
    return 0
}

# Restore a backup of the storage to a new or existing guest.
_storage_restore() {
    local vol=$1 vmid type=qemu
    [[ -n $vol ]] || return 0
    [[ $vol == */lxc/* || $vol == *vzdump-lxc-* ]] && type=lxc
    api_get rows /cluster/nextid "" ""
    dlg_input "Restore" "Restore '$vol' to VM ID:" "${CRUD_ANSWER[vmid]:-${API_ROWS[0]-}}" || return 0
    vmid=$REPLY
    local st=${CRUD_ANSWER[storage]-}
    if [[ -z $st ]]; then
        local ct=images; [[ $type == lxc ]] && ct=rootdir
        _pick_store "$ct" || return 0; st=$REPLY
    fi
    local -a args=(--vmid "$vmid" --storage "$st")
    if [[ $type == qemu ]]; then args+=(--archive "$vol")
    else args+=(--ostemplate "$vol" --restore 1)
    fi
    [[ -n ${R_TYPE[$type/$vmid]-} ]] && { dlg_yesno "Restore" "Guest $vmid exists and will be OVERWRITTEN. Continue?" || return 0; args+=(--force 1); }
    api_exec "${type^^} $vmid - Restore" create "/nodes/$CTX_NODE/$type" "${args[@]}"
    return 0
}

_storage_prune() {
    local vol=$1 vmid type
    [[ $vol =~ /(vm|ct)/([0-9]+)/ || $vol =~ vzdump-(qemu|lxc)-([0-9]+)- ]] || { status_msg warn "Select a backup"; return 0; }
    vmid=${BASH_REMATCH[2]} type=qemu
    [[ ${BASH_REMATCH[1]} == ct || ${BASH_REMATCH[1]} == lxc ]] && type=lxc
    form_reset
    FORM_FIX[vmid]=$vmid FORM_FIX[type]=$type
    FORM_TEXT="Prune the backups of $type $vmid on $CTX_STORAGE (keep-last=3,keep-weekly=2 ...)"
    form_run "Prune Backups" DELETE "/nodes/$CTX_NODE/storage/$CTX_STORAGE/prunebackups" && content_load 1
}

for _c in backup iso vztmpl images rootdir snippets import; do
    eval "
v_storage_${_c}() { _storage_content ${_c}; }
v_storage_${_c}__key() {
    REPLY=\${2-}
    case \$1 in
        d|DEL) _storage_remove \"\$REPLY\" ;;
        u) [[ ${_c} == iso || ${_c} == vztmpl || ${_c} == import ]] && _storage_download ${_c} || return 1 ;;
        U) [[ ${_c} == iso || ${_c} == vztmpl || ${_c} == import || ${_c} == snippets ]] && _storage_upload ${_c} || return 1 ;;
        T) [[ ${_c} == vztmpl ]] && _storage_templates || return 1 ;;
        r) [[ ${_c} == backup ]] && _storage_restore \"\$REPLY\" || return 1 ;;
        P) [[ ${_c} == backup ]] && _storage_prune \"\$REPLY\" || return 1 ;;
        e) [[ ${_c} == backup ]] || return 1
           local vol=\$REPLY
           form_reset; FORM_GET=\"/nodes/\$CTX_NODE/storage/\$CTX_STORAGE/content/\$vol\"; FORM_ONLY=\"notes protected\"
           form_run \"Edit: \$vol\" PUT \"\$FORM_GET\" && content_load 1 ;;
        *) return 1 ;;
    esac
    return 0
}"
    VIEW_HINT[v_storage_${_c}]="d:Remove"
done
unset _c
v_storage_backup__enter() {
    [[ -n $1 ]] || return
    urlenc "$1"
    api_get rows "/nodes/$CTX_NODE/vzdump/extractconfig" "volume=$REPLY" "" || { dlg_msg "Backup" "$API_ERR"; return; }
    printf '%s\n' "${API_ROWS[@]}" | tr '\037' '\n' > "$RUN_DIR/backup.conf"
    pager_show "$RUN_DIR/backup.conf" "$1"
}
VIEW_HINT[v_storage_backup]="Enter:Show_Configuration r:Restore e:Edit_Notes/Protection P:Prune d:Remove"
VIEW_HINT[v_storage_iso]="U:Upload u:Download_from_URL d:Remove"
VIEW_HINT[v_storage_import]="U:Upload u:Download_from_URL d:Remove"
VIEW_HINT[v_storage_snippets]="U:Upload d:Remove"
VIEW_HINT[v_storage_vztmpl]="T:Templates U:Upload u:Download_from_URL d:Remove"
v_storage_permissions() { acl_table "/storage/$CTX_STORAGE"; }
v_storage_permissions__key() { acl_keys "/storage/$CTX_STORAGE" "$@"; }
VIEW_HINT[v_storage_permissions]="a:Add d:Remove"

# ---------------------------------------------------------------------------
# Pools
# ---------------------------------------------------------------------------
view_menu pool \
    "summary|Summary|m_summary|0" \
    "members|Members|m_members|0" \
    "permissions|Permissions|m_permissions|0"

title_pool() { Tf "Resource Pool: %s" "$CTX_POOL"; }

v_pool_summary() {
    api_get rows /pools "poolid=$CTX_POOL" "comment"
    c_section "Status"
    c_kv "Comment" "${API_ROWS[0]-}"
    local id n=0 r=0
    for id in "${RES_IDS[@]}"; do
        [[ ${R_POOL[$id]-} == "$CTX_POOL" ]] || continue
        (( n++ ))
        [[ ${R_STATUS[$id]} == running ]] && (( r++ ))
    done
    c_kv "Members" "$n"
    T "Running"; c_kv "$REPLY" "$r"
    c_blank
    c_section "Members"
    _grid_match_pool() { [[ ${R_POOL[$1]-} == "$CTX_POOL" ]]; }
    res_grid _grid_match_pool
}
v_pool_summary__enter() { grid_goto "$1"; }
VIEW_LIVE[v_pool_summary]=1
v_pool_summary__key() { [[ $1 == e ]] && { act_edit_notes; return 0; }; grid_key "$@"; }
VIEW_HINT[v_pool_summary]="e:Edit_comment $GRID_HINT"

v_pool_members() {
    view_table "/pools/$CTX_POOL" "" "@members;id:ID:24|type:Type:8|node:Node:12|name:Name:*|status:Status:10:status"
}
v_pool_members__enter() { grid_goto "$1"; }
VIEW_HINT[v_pool_members]="a:Add d:Remove Enter:Go_to"
v_pool_members__key() {
    case $1 in
        a|INS)
            local kind=${CRUD_ANSWER[kind]-} v
            [[ -z $kind ]] && { dlg_menu "Add" "Pool member" vm "$(T "Virtual Machine"; printf '%s' "$REPLY")" storage "$(T "Storage"; printf '%s' "$REPLY")" || return 0; kind=$REPLY; }
            form_reset
            if [[ $kind == vm ]]; then FORM_ONLY="vms"; choice_guests && FORM_CHOICES[vms]=$REPLY
            else FORM_ONLY="storage"; choice_storages && FORM_CHOICES[storage]=$REPLY
            fi
            form_run "Add: Pool member" PUT "/pools/$CTX_POOL" && { content_load 1; NEED_REFRESH=1; } ;;
        d|DEL)
            [[ -n $2 ]] || return 0
            Tf "Remove '%s' from pool '%s'?" "$2" "$CTX_POOL"; confirm "$REPLY" || return 0
            if [[ $2 == storage/* ]]; then api_exec_sync "Pool member" set "/pools/$CTX_POOL" --storage "${2##*/}" --delete 1
            else api_exec_sync "Pool member" set "/pools/$CTX_POOL" --vms "${2#*/}" --delete 1
            fi
            content_load 1; NEED_REFRESH=1 ;;
        *) return 1 ;;
    esac
    return 0
}
v_pool_permissions() { acl_table "/pool/$CTX_POOL"; }
v_pool_permissions__key() { acl_keys "/pool/$CTX_POOL" "$@"; }
VIEW_HINT[v_pool_permissions]="a:Add d:Remove"

