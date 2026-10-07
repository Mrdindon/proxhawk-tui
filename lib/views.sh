# shellcheck shell=bash
# views.sh - view registry: context of the selected tree entry, the
# per-type navigation menu (middle column) and content loading.
#
# A view module (views/*.sh) declares:
#   view_menu <type> "id|Label|icon|level" ...   static menu of a type
#   menu_<type>()                                 optional dynamic menu builder
#   title_<type>()                                content title (REPLY)
#   toolbar_<type>()                              toolbar buttons (tb_add ...)
#   v_<type>_<id>()                               content handler of a menu entry
#   v_<type>_<id>__enter <key>                    optional: Enter on a row
#   v_<type>_<id>__key <KEY> <key>                optional: extra keys (rc 0 = handled)
#   VIEW_LIVE[v_<type>_<id>]=1                     auto-refresh with the timer
#   VIEW_HINT[v_<type>_<id>]="k:Label ..."         footer key hints

declare -gA MENU_DEF=() MENU_LAST=() VIEW_LIVE=() VIEW_HINT=()
declare -ga M_ID=() M_LABEL=() M_ICON=() M_LVL=()
MENU_CUR=0 MENU_SCROLL=0
CTX_ID="" CTX_TYPE="" CTX_NODE="" CTX_VMID="" CTX_STORAGE="" CTX_POOL="" CTX_NAME="" CTX_NET=""
VIEW_FN="" VIEW_PREV=""

view_menu() {
    local t=$1; shift
    local IFS=$'\n'
    MENU_DEF[$t]="$*"
}

# Set the context from a tree id.
ctx_set() {
    local id=$1
    CTX_ID=$id CTX_NODE="" CTX_VMID="" CTX_STORAGE="" CTX_POOL="" CTX_NAME="" CTX_NET=""
    case $id in
        root) CTX_TYPE=dc ;;
        node/*) CTX_TYPE=node CTX_NODE=${id#node/} ;;
        qemu/*|lxc/*) CTX_TYPE=${id%%/*} CTX_VMID=${id#*/} CTX_NODE=${R_NODE[$id]-} CTX_NAME=${R_NAME[$id]-} ;;
        storage/*) CTX_TYPE=storage CTX_NODE=${R_NODE[$id]-} CTX_STORAGE=${R_STORAGE[$id]:-${id##*/}} ;;
        pool/*) CTX_TYPE=pool CTX_POOL=${id#pool/} ;;
        network/*) CTX_TYPE=sdn CTX_NODE=${R_NODE[$id]-} CTX_NET=${R_NET[$id]:-${id##*/}} ;;
        folder/*) CTX_TYPE=folder ;;
        search) CTX_TYPE=search ;;
        *) CTX_TYPE=unknown ;;
    esac
}

# Load the menu of the current context type.
menu_load() {
    local item
    local -a parts
    M_ID=() M_LABEL=() M_ICON=() M_LVL=()
    if declare -F "menu_$CTX_TYPE" >/dev/null; then
        "menu_$CTX_TYPE"
    else
        while IFS= read -r item; do
            [[ -n $item ]] || continue
            IFS='|' read -r -a parts <<< "$item"
            menu_add "${parts[@]}"
        done <<< "${MENU_DEF[$CTX_TYPE]-}"
    fi
    # Entries added by plugins.
    while IFS= read -r item; do
        [[ -n $item ]] || continue
        IFS='|' read -r -a parts <<< "$item"
        menu_add "${parts[@]}"
    done <<< "${MENU_EXTRA[$CTX_TYPE]-}"
    (( ${#M_ID[@]} )) || menu_add info "Information" m_summary 0
    MENU_CUR=0
    local i
    for i in "${!M_ID[@]}"; do
        [[ ${M_ID[i]} == "${MENU_LAST[$CTX_TYPE]-}" ]] && MENU_CUR=$i
    done
    MENU_SCROLL=0
}

menu_add() { M_ID+=("$1"); M_LABEL+=("$2"); M_ICON+=("${3:-}"); M_LVL+=("${4:-0}"); }

# Plugins: extra menu entries and toolbar buttons of a type.
declare -gA MENU_EXTRA=() TOOLBAR_EXTRA=()
menu_extend() { local t=$1; shift; local e; for e; do MENU_EXTRA[$t]+="$e"$'\n'; done; }
toolbar_extend() { TOOLBAR_EXTRA[$1]+="$2 "; }

# Build the content of the selected menu entry.
content_load() {
    local keep=${1:-0}
    VIEW_FN="v_${CTX_TYPE}_${M_ID[MENU_CUR]-}"
    MENU_LAST[$CTX_TYPE]=${M_ID[MENU_CUR]-}
    local old_key="${C_SELK[C_CUR]-}" old_scroll=$C_SCROLL
    c_reset
    C_CUR=0 C_SCROLL=0
    if declare -F "$VIEW_FN" >/dev/null; then
        T "Loading..."; spinner_start "$REPLY"
        "$VIEW_FN"
        spinner_stop
    else
        c_msg dim "This panel is not available in the console version."
    fi
    if (( keep )) && [[ $VIEW_FN == "$VIEW_PREV" ]]; then
        # Try to keep the cursor on the same row after a refresh.
        local i
        for i in "${!C_SELK[@]}"; do [[ ${C_SELK[i]} == "$old_key" ]] && { C_CUR=$i; break; }; done
        (( C_CUR >= ${#C_SELL[@]} )) && C_CUR=$(( ${#C_SELL[@]} > 0 ? ${#C_SELL[@]} - 1 : 0 ))
        (( ${#C_SELL[@]} == 0 )) && C_SCROLL=$old_scroll
    fi
    VIEW_PREV=$VIEW_FN
    panel_buttons
    NEED_REDRAW=1
}

# Button bar of the panel (shown above the content, like the toolbars of the
# panels of the web UI): Add / Edit / Remove of CRUD panels and the keys of
# VIEW_HINT. Fills PB_KEYS / PB_LABELS.
declare -ga PB_KEYS=() PB_LABELS=()
panel_buttons() {
    local h="" e k
    PB_KEYS=() PB_LABELS=()
    if crud_has "$VIEW_FN"; then crud_buttons "$VIEW_FN"; crud_hints "$VIEW_FN"; h=$REPLY; fi
    h+=" ${VIEW_HINT[$VIEW_FN]-}"
    for e in $h; do
        k=${e%%:*}
        [[ " ${PB_KEYS[*]} " == *" $k "* ]] && continue
        PB_KEYS+=("$k"); PB_LABELS+=("${e#*:}")
    done
}

# Select a tree entry: update context, menu and content.
select_id() {
    SEL_ID=$1
    ctx_set "$1"
    menu_load
    content_load
}

# Selected row key of the content panel (empty if none).
content_key() { REPLY=${C_SELK[C_CUR]-}; }

# Default title.
ctx_title() {
    if declare -F "title_$CTX_TYPE" >/dev/null; then "title_$CTX_TYPE"; else REPLY=$CTX_ID; fi
}

# ---------------------------------------------------------------------------
# Toolbar (buttons at the right of the content title)
# ---------------------------------------------------------------------------
declare -ga TB_KEY=() TB_LABEL=() TB_ICON=() TB_ON=() TB_ACT=()

# tb_add <hotkey> <label> <icon> <enabled 0|1> <action function>
tb_add() { TB_KEY+=("$1"); TB_LABEL+=("$2"); TB_ICON+=("$3"); TB_ON+=("$4"); TB_ACT+=("$5"); }

toolbar_load() {
    TB_KEY=() TB_LABEL=() TB_ICON=() TB_ON=() TB_ACT=()
    declare -F "toolbar_$CTX_TYPE" >/dev/null && "toolbar_$CTX_TYPE"
    local f
    for f in ${TOOLBAR_EXTRA[$CTX_TYPE]-}; do "$f"; done
    return 0
}

# Run the toolbar action bound to a hot key; rc 1 if none.
toolbar_key() {
    local i
    for i in "${!TB_KEY[@]}"; do
        if [[ ${TB_KEY[i]} == "$1" ]]; then
            if [[ ${TB_ON[i]} == 1 ]]; then "${TB_ACT[i]}"
            else T "Action not available in the current state"; status_msg warn "$REPLY"
            fi
            return 0
        fi
    done
    return 1
}

# Load every view module.
views_load() {
    local f
    for f in "$PROXHAWK_TUI_HOME"/views/*.sh; do
        # shellcheck source=/dev/null
        source "$f"
    done
}
