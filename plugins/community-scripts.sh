# shellcheck shell=bash
# plugin: community-scripts
# description: Install applications with the Proxmox VE Community Scripts (third-party, runs as root)
#
# Adds Node > "Community Scripts": lists the scripts of
# https://github.com/community-scripts/ProxmoxVE (ct/, vm/, tools/) and runs
# the selected one in a terminal on the node, exactly like the documented
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/<name>.sh)"
# These scripts are third-party code executed as root: read them first.

CS_REPO_API="https://api.github.com/repos/community-scripts/ProxmoxVE/contents"
CS_REPO_RAW="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main"
CS_CATEGORY=ct

menu_extend node "communityscripts|Community Scripts|m_import|0"

# Script names of a category, cached for the session.
_cs_list() {
    local cat=$1 f="$RUN_DIR/cs-$1.list"
    # Recorded API answers (tests, demo): the list is part of the recording.
    if [[ $API_BACKEND == replay ]]; then f="$PROXHAWK_TUI_REPLAY/cs-$cat.list"; [[ -r $f ]] || f=/dev/null; fi
    if [[ ! -s $f && $f != /dev/null ]]; then
        curl -fsSL --max-time 20 "$CS_REPO_API/$cat" 2>/dev/null \
            | perl -MJSON -e 'my $d = eval { decode_json(join("", <STDIN>)) } || []; print map { "$_->{name}\n" } grep { $_->{name} =~ /\.sh$/ } @$d' > "$f"
        [[ -n ${PROXHAWK_TUI_RECORD-} ]] && cp "$f" "$PROXHAWK_TUI_RECORD/cs-$cat.list"
    fi
    mapfile -t CS_LIST < "$f"
}

v_node_communityscripts() {
    local n row
    c_add " ${C[warn]}$(T "Third-party scripts executed as root on the node: read them before installing."; printf '%s' "$REPLY")${C[norm]}"
    c_add " ${C[dim]}https://github.com/community-scripts/ProxmoxVE  -  ${CS_CATEGORY}/  (c: change category)${C[norm]}"
    c_blank
    _cs_list "$CS_CATEGORY"
    (( ${#CS_LIST[@]} )) || { c_msg err "Cannot read the script list (network / GitHub API limit)."; return; }
    table_spec "name:Script:*|cat:Category:10"
    table_header
    for n in "${CS_LIST[@]}"; do
        [[ -n $SEARCH_TERM && ${n,,} != *"${SEARCH_TERM,,}"* ]] && continue
        table_row "${n%.sh}"$'\t'"$CS_CATEGORY"
        c_sel "$REPLY" "$CS_CATEGORY/$n"
    done
}
v_node_communityscripts__enter() {
    local s=$1 url
    [[ -n $s ]] || return
    url="$CS_REPO_RAW/$s"
    local -a items=()
    T "Install (run the script in a terminal)"; items+=(run "$REPLY")
    T "View the script"; items+=(view "$REPLY")
    dlg_menu "Community Scripts" "$url" "${items[@]}" || return
    case $REPLY in
        view)
            curl -fsSL --max-time 20 "$url" > "$RUN_DIR/cs-script.sh" 2>&1
            pager_show "$RUN_DIR/cs-script.sh" "$s" ;;
        run)
            # Scripts run as root on the node: root@pam only.
            [[ $PVE_USER == root@pam ]] || { dlg_msg "Community Scripts" "Installing scripts requires running proxhawk-tui as root@pam."; return; }
            Tf "Run %s as root on node %s? It is third-party code." "$s" "$CTX_NODE"
            dlg_yesno "Community Scripts" "$REPLY" || return
            node_cmd "$CTX_NODE" bash -c "bash -c \"\$(curl -fsSL '$url')\"; echo; read -rp '[Enter] to return to proxhawk-tui' _"
            NEED_REFRESH=1 ;;
    esac
}
v_node_communityscripts__key() {
    [[ $1 == c ]] || return 1
    dlg_menu "Community Scripts" "Category:" ct "Containers (LXC)" vm "Virtual machines" tools "Tools (node add-ons)" || return 0
    CS_CATEGORY=$REPLY
    content_load
    return 0
}
VIEW_HINT[v_node_communityscripts]="Enter:Install/View c:Category /:Search"
