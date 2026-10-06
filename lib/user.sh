# shellcheck shell=bash
# user.sh - the Proxmox VE user pvetty runs as.
#
# pvetty runs as root on the node; by default it acts as root@pam. Another
# user can be chosen at start-up (prompt), with --user or "user = ...": the
# API requests then run as that user and are checked with its permissions,
# like in the web UI (lib/broker.pl for reads, lib/pvesh-as.pl for writes,
# put first in PATH as "pvesh"). No password is asked: pvetty already runs
# as root, which can do anything on the node; the user only limits what
# pvetty does.
#
#   user_select      prompt (setting ask_user), then user_apply
#   user_apply USER  run the API requests as USER (rc 1: unknown user)
#   perm_ok PATH PRIV   does the user have PRIV on PATH (rc 0 / 1)
#   perm_need PATH PRIV  same, with an error message when not

PVE_USER=root@pam

# Enabled users of /etc/pve/user.cfg: USERS (ids) and USER_DESC (id -> text).
user_list() {
    local line id en first last comment
    USERS=() ; declare -gA USER_DESC=()
    [[ -r /etc/pve/user.cfg ]] || return 0
    while IFS=: read -r kind id en _ first last _ comment _; do
        [[ $kind == user && $en != 0 ]] || continue
        USERS+=("$id")
        line="$first $last"; line=${line# }; line=${line% }
        [[ -n $comment ]] && line+="${line:+ - }$comment"
        USER_DESC[$id]=$line
    done < /etc/pve/user.cfg
}

# The user pvetty was launched by: SUDO_USER@pam when that PVE user exists.
user_default() {
    REPLY=root@pam
    [[ -n ${SUDO_USER-} && $SUDO_USER != root && " ${USERS[*]} " == *" $SUDO_USER@pam "* ]] && REPLY="$SUDO_USER@pam"
}

user_select() {
    local u def
    user_list
    if [[ -n ${CFG[user]} ]]; then user_apply "${CFG[user]}" || die "unknown or disabled Proxmox VE user: ${CFG[user]}"; return; fi
    user_default; def=$REPLY
    [[ ${CFG[ask_user]} == 1 ]] || { user_apply "$def"; return; }
    local -a items=()
    Tf "%s (launching user)" "$def"; items+=("$def" "$REPLY")
    for u in "${USERS[@]}"; do
        [[ $u == "$def" ]] || { printf -v REPLY '%-24s %s' "$u" "${USER_DESC[$u]-}"; items+=("$u" "$REPLY"); }
    done
    T "Other user (name@realm)..."; items+=(_other "$REPLY")
    while :; do
        DLG_NOTAGS=1 DLG_OK_LABEL="Run" DLG_CANCEL_LABEL="Quit" \
            dlg_menu "pvetty" "Run pvetty as which Proxmox VE user? Its permissions apply. (ask_user = 0 in the settings: always the launching user)" "${items[@]}" \
            || exit 0
        u=$REPLY
        if [[ $u == _other ]]; then
            dlg_input "pvetty" "Proxmox VE user ID (name@realm):" "" || continue
            u=$REPLY
        fi
        user_apply "$u" && return
        Tf "Unknown or disabled Proxmox VE user: %s" "$u"
        dlg_msg "pvetty" "$REPLY"
    done
}

user_apply() {
    local u=$1 d p=""
    [[ $u == *@* ]] || u="$u@pam"
    # Drop the "pvesh" wrapper of an earlier choice (or of the pvetty that
    # restarted this one) from PATH.
    local IFS=:
    for d in $PATH; do [[ $d == */pvetty.*/bin ]] || p+="${p:+:}$d"; done
    unset IFS
    PATH=$p
    if [[ $u != root@pam ]]; then
        user_list
        [[ " ${USERS[*]} " == *" $u "* ]] || return 1
        # Writes: a "pvesh" that runs as the user, first in PATH (also for
        # the background jobs and the API helper started later).
        mkdir -p "$RUN_DIR/bin"
        printf '#!/bin/sh\nexec perl %q "$@"\n' "$PVETTY_HOME/lib/pvesh-as.pl" > "$RUN_DIR/bin/pvesh"
        chmod +x "$RUN_DIR/bin/pvesh"
        PATH="$RUN_DIR/bin:$PATH"
    fi
    export PATH PVETTY_USER=$u
    PVE_USER=$u
    return 0
}

perm_ok() {
    [[ $PVE_USER == root@pam ]] && return 0
    api_get perm "$1" "priv=$2" "" && [[ ${API_ROWS[0]-} == 1 ]]
}

perm_need() {
    perm_ok "$1" "$2" && return 0
    Tf "Permission check failed (%s, %s) for %s" "$1" "$2" "$PVE_USER"
    status_msg err "$REPLY"
    return 1
}
