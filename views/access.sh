# shellcheck shell=bash
# views/access.sh - Datacenter > Permissions: ACL, Users, API Tokens,
# Two Factor, Groups, Pools, Roles, Realms.

# ---------------------------------------------------------------------------
# Permissions (ACL) - shared by the Datacenter, guests, storages and pools.
# Row keys: "path|type|ugid|role".
# ---------------------------------------------------------------------------
acl_table() {
    local filter=${1:-} row n=0
    local -a f
    table_spec "path:Path:24|type:Type:8|ugid:User/Group/API Token:28|roleid:Role:20|propagate:Propagate:10:bool"
    api_get rows /access/acl "" "path,type,ugid,roleid,propagate" || { c_api_error; return; }
    table_header
    for row in "${API_ROWS[@]}"; do
        tsv_split f "$row"
        [[ -n $filter && ${f[0]} != "$filter" ]] && continue
        table_row "$row"
        c_sel "$REPLY" "${f[0]}|${f[1]}|${f[2]}|${f[3]}"
        (( n++ ))
    done
    (( n )) || c_msg dim "No items"
}

# acl_add [fixed path]: User / Group / API Token permission dialog.
acl_add() {
    local fixed=${1:-} kind
    local -a items=()
    T "User Permission"; items+=(users "$REPLY")
    T "Group Permission"; items+=(groups "$REPLY")
    T "API Token Permission"; items+=(tokens "$REPLY")
    if [[ -n ${CRUD_ANSWER[acltype]-} ]]; then kind=${CRUD_ANSWER[acltype]}
    else T "Add"; dlg_menu "$REPLY" "Permissions" "${items[@]}" || return 0; kind=$REPLY
    fi
    form_reset
    FORM_ONLY="path $kind roles propagate"
    FORM_FIRST=$FORM_ONLY
    FORM_LABEL=([path]="Path" [users]="User" [groups]="Group" [tokens]="API Token" [roles]="Role" [propagate]="Propagate")
    [[ -n $fixed ]] && FORM_FIX[path]=$fixed
    choice_acl_paths; FORM_CHOICES[path]=$REPLY
    choice_roles && FORM_CHOICES[roles]=$REPLY
    case $kind in
        users) choice_users && FORM_CHOICES[users]=$REPLY ;;
        groups) choice_groups && FORM_CHOICES[groups]=$REPLY ;;
    esac
    form_run "Add: Permission" PUT /access/acl && content_load 1
    return 0
}

# acl_remove <path|type|ugid|role>
acl_remove() {
    local -a p
    IFS='|' read -r -a p <<< "$1"
    [[ -n ${p[0]-} ]] || return 0
    Tf "Remove permission '%s' of '%s' on '%s'?" "${p[3]}" "${p[2]}" "${p[0]}"
    confirm "$REPLY" || return 0
    local opt=--users
    case ${p[1]} in group) opt=--groups ;; token) opt=--tokens ;; esac
    api_exec_sync "Remove permission" set /access/acl --path "${p[0]}" --roles "${p[3]}" "$opt" "${p[2]}" --delete 1
    content_load 1
    return 0
}

# Key handler for ACL panels: acl_keys <fixed path> <KEY> <row key>
acl_keys() {
    case $2 in
        a|INS) acl_add "$1" ;;
        d|DEL) acl_remove "$3" ;;
        *) return 1 ;;
    esac
    return 0
}

v_dc_permissions() { acl_table; }
v_dc_permissions__key() { acl_keys "" "$@"; }
VIEW_HINT[v_dc_permissions]="a:Add d:Remove"

# ---------------------------------------------------------------------------
v_dc_users() {
    view_table /access/users "" "userid:User name:24|realm-type:Realm:8|enable:Enabled:8:bool|expire:Expire:12:d|firstname:First Name:12|lastname:Last Name:12|email:E-Mail:*|comment:Comment:*"
}
crud v_dc_users label="User" add=/access/users edit="/access/users/{1}" del="/access/users/{1}" \
    first="userid password groups expire enable firstname lastname email comment keys" \
    choices="groups:choice_groups" extra="p:Password u:Unlock_TFA"
# Add a user like the web UI: realm, then the name, then the other fields
# (the API wants the full "name@realm" user ID). The password is set for
# the "pve" and "pam" realms (for pam it is the Linux password); LDAP / AD /
# OpenID users authenticate on their server.
_users_add() {
    local realm name type="" row
    local -a f items=()
    api_get rows /access/domains "" "realm,type,comment" || { dlg_msg "Add: User" "$API_ERR"; return; }
    for row in "${API_ROWS[@]}"; do
        tsv_split f "$row"
        [[ ${f[0]} == pve ]] && items=("${f[0]}" "${f[1]}${f[2]:+ - ${f[2]}}" "${items[@]}") \
                             || items+=("${f[0]}" "${f[1]}${f[2]:+ - ${f[2]}}")
    done
    if [[ -n ${CRUD_ANSWER[realm]-} ]]; then realm=${CRUD_ANSWER[realm]}
    else dlg_menu "Add: User" "Realm:" "${items[@]}" || return; realm=$REPLY
    fi
    for row in "${API_ROWS[@]}"; do tsv_split f "$row"; [[ ${f[0]} == "$realm" ]] && type=${f[1]}; done
    while :; do
        if [[ -n ${CRUD_ANSWER[name]-} ]]; then name=${CRUD_ANSWER[name]}
        else
            Tf "User name (without @%s):" "$realm"
            dlg_input "Add: User" "$REPLY" "" || return
            name=$REPLY
        fi
        name=${name%@"$realm"}
        [[ $name =~ ^[^[:space:]@:/]+$ ]] && break
        [[ -n ${CRUD_ANSWER[name]-} ]] && return
        dlg_msg "Add: User" "Invalid user name: no spaces, '@', ':' or '/'."
    done
    if [[ $type == pam ]] && ! id "$name" >/dev/null 2>&1; then
        _users_pam_account "$name" || return
    fi
    form_reset
    FORM_FIX[userid]="$name@$realm"
    FORM_FIRST=${CRUD[v_dc_users|first]-}
    # Password: pve realm, and pam (Proxmox VE then sets the Linux password).
    [[ $type == pve || $type == pam ]] || FORM_HIDE="password"
    _crud_choices v_dc_users
    Tf "Add: User %s" "$name@$realm"
    form_run "$REPLY" POST /access/users && content_load 1
}

# Linux account of a new PAM user, created only when the user pvetty runs as
# may create Linux accounts itself: a PAM user whose Linux account is root
# or may run useradd through sudo. The account is created through that
# account (runuser + sudo: its sudo rules apply, sudo may ask its password
# and logs the action), never with pvetty's own root rights. rc 1: cancel.
_users_pam_account() {
    local name=$1 me=${PVE_USER%@pam} how=""
    if [[ $PVE_USER == *@pam ]] && id "$me" >/dev/null 2>&1; then
        if [[ $(id -u "$me") == 0 ]]; then how=root
        elif command -v sudo >/dev/null && sudo -l -U "$me" "$(command -v useradd)" >/dev/null 2>&1; then how=sudo
        fi
    fi
    if [[ -z $how ]]; then
        Tf "No Linux account '%s' on node %s, and %s may not create Linux accounts (it must be a PAM user that is root or may run useradd with sudo). Create the account first: useradd -m %s" "$name" "$LOCAL_NODE" "$PVE_USER" "$name"
        dlg_msg "Add: User" "$REPLY"
        return 1
    fi
    # Proxmox VE side first: may this user add users to the pam realm?
    perm_need /access/realm/pam Realm.AllocateUser || return 1
    if [[ -z ${CRUD_ANSWER[create_account]-} ]]; then
        Tf "No Linux account '%s' on node %s. Create it now as %s (useradd -m -s /bin/bash %s)?" "$name" "$LOCAL_NODE" "$PVE_USER" "$name"
        DLG_DEFAULT_YES=1 dlg_yesno "Add: User" "$REPLY" || return 1
    fi
    local useradd; useradd=$(command -v useradd)
    if [[ $how == root ]]; then
        "$useradd" -m -s /bin/bash "$name" > "$RUN_DIR/useradd.log" 2>&1
    else
        # Interactive: sudo may ask the password of $me.
        Tf "Creating the Linux account '%s' as %s with sudo (sudo may ask the password of %s)." "$name" "$me" "$me"
        term_run bash -c 'clear; printf "%s\n\n" "$1"; runuser -u "$2" -- sudo "$3" -m -s /bin/bash "$4"; rc=$?
            (( rc )) && read -rp "[Enter] " _; exit $rc' sh "$REPLY" "$me" "$useradd" "$name"
    fi
    if ! id "$name" >/dev/null 2>&1; then
        Tf "The Linux account '%s' was not created: %s" "$name" "$(tail -n 1 "$RUN_DIR/useradd.log" 2>/dev/null)"
        dlg_msg "Add: User" "$REPLY"
        return 1
    fi
    Tf "Linux account '%s' created on %s (the password set below is its Linux password)" "$name" "$LOCAL_NODE"
    status_msg ok "$REPLY"
    return 0
}

v_dc_users__key() {
    local u=$2
    case $1 in a|INS) _users_add; return 0 ;; esac
    [[ -n $u ]] || return 1
    case $1 in
        p)
            form_reset
            FORM_FIX[userid]=$u
            Tf "Password for %s" "$u"
            FORM_TEXT=$REPLY
            form_run "Change Password" PUT /access/password ;;
        u) api_exec_sync "Unlock TFA $u" set "/access/users/$u/unlock-tfa" ;;
        *) return 1 ;;
    esac
    return 0
}

# ---------------------------------------------------------------------------
# API tokens. Row keys: "userid|tokenid".
v_dc_tokens() {
    local u row n=0
    local -a users f
    table_spec "user:User name:24|tokenid:Token Name:16|expire:Expire:12|privsep:Privilege Separation:22|comment:Comment:*"
    api_get rows /access/users "" "userid" || { c_api_error; return; }
    users=("${API_ROWS[@]}")
    table_header
    for u in "${users[@]}"; do
        api_get rows "/access/users/$u/token" "" "tokenid,expire,privsep,comment" || continue
        for row in "${API_ROWS[@]}"; do
            tsv_split f "$row"
            local ex="never"; [[ -n ${f[1]} && ${f[1]} != 0 ]] && { fmt_time "${f[1]}" '%Y-%m-%d'; ex=$REPLY; }
            fmtv bool "${f[2]}"
            table_row "$u"$'\t'"${f[0]}"$'\t'"$ex"$'\t'"$REPLY"$'\t'"${f[3]}"
            c_sel "$REPLY" "$u|${f[0]}"; (( n++ ))
        done
    done
    (( n )) || c_msg dim "No items"
}
crud v_dc_tokens label="API Token" add="/access/users/{?userid:User:choice_users}/token/{?tokenid:Token ID}" \
    edit="/access/users/{1}/token/{2}" del="/access/users/{1}/token/{2}" first="comment expire privsep" result=1

# ---------------------------------------------------------------------------
# Two factor entries. Row keys: "userid|id".
v_dc_tfa() {
    local u row n=0
    local -a users f
    table_spec "user:User:24|type:Type:10|desc:Description:*|created:Created:19:t|enable:Enabled:8:bool"
    api_get rows /access/tfa "" "userid" || { c_api_error; return; }
    users=("${API_ROWS[@]}")
    table_header
    for u in "${users[@]}"; do
        api_get rows "/access/tfa/$u" "" "id,type,description,created,enable" || continue
        for row in "${API_ROWS[@]}"; do
            tsv_split f "$row"
            table_row "$u"$'\t'"${f[1]}"$'\t'"${f[2]}"$'\t'"${f[3]}"$'\t'"${f[4]:-1}"
            c_sel "$REPLY" "$u|${f[0]}"; (( n++ ))
        done
    done
    (( n )) || c_msg dim "No items"
}
crud v_dc_tfa label="Second Factor" add="/access/tfa/{?userid:User:choice_users}" edit="/access/tfa/{1}/{2}" \
    del="/access/tfa/{1}/{2}" first="type description totp value password" result=1

# ---------------------------------------------------------------------------
v_dc_groups() { view_table /access/groups "" "groupid:Group name:24|comment:Comment:*|users:Users:*"; }
crud v_dc_groups label="Group" add=/access/groups edit="/access/groups/{1}" del="/access/groups/{1}" first="groupid comment"

v_dc_pools() { view_table /pools "" "poolid:Name:24|comment:Comment:*"; }
crud v_dc_pools label="Pool" add=/pools edit="/pools/{1}" del="/pools/{1}" first="poolid comment" hide="allow-move"

v_dc_roles() { view_table /access/roles "" "roleid:Name:24|special:Built-In:10:bool|privs:Privileges:*" 0 0; }
crud v_dc_roles label="Role" add=/access/roles edit="/access/roles/{1}" del="/access/roles/{1}" first="roleid privs" hide="append"

v_dc_realms() { view_table /access/domains "" "realm:Realm:16|type:Type:8|comment:Comment:*|tfa:TFA:12"; }
crud v_dc_realms label="Realm" add=/access/domains edit="/access/domains/{1}" del="/access/domains/{1}" \
    plugin=realm types="ad,ldap,openid" first="realm server1 server2 port base_dn domain user_attr bind_dn password issuer-url client-id client-key default comment" \
    extra="s:Sync"
v_dc_realms__key() {
    [[ $1 == s && -n $2 ]] || return 1
    form_reset
    FORM_FIRST="scope remove-vanished enable-new dry-run"
    form_run "Realm Sync: $2" POST "/access/domains/$2/sync"
    return 0
}
