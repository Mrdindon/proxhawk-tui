# shellcheck shell=bash
# overlay.sh - scrollable text window drawn over the interface (help, command
# output...). The lines may contain colours.
#
#   overlay_show <title> <line>...        Esc / q / Enter / F1 close it
#   OVERLAY_KEYS="d:Documentation"        extra keys returned in OVERLAY_KEY

OVERLAY_KEY="" OVERLAY_KEYS=""

overlay_show() {
    local title=$1; shift
    local -a lines=("$@")
    local scroll=0 n=${#lines[@]} bw bh top left body r i line extra="" e
    OVERLAY_KEY=""
    draw
    while :; do
        bw=$(( COLS - 8 )); (( bw > 110 )) && bw=110
        bh=$(( ROWS - 4 )); (( bh > n + 4 )) && bh=$(( n + 4 )); (( bh < 8 )) && bh=8
        top=$(( (ROWS - bh) / 2 + 1 )); left=$(( (COLS - bw) / 2 + 1 ))
        body=$(( bh - 4 ))
        (( scroll > n - body )) && scroll=$(( n - body ))
        (( scroll < 0 )) && scroll=0
        FRAME=""
        _hline "$top" "$left" "$bw" "${G[tl]}" "${G[tr]}" "$title" "${C[accent]}"
        for (( r = 0; r < body; r++ )); do
            i=$(( scroll + r ))
            fit "${lines[i]-}" $(( bw - 4 ))
            _put $(( top + 1 + r )) "$left" "${C[border]}${G[v]}${C[norm]} ${REPLY}${C[norm]} ${C[border]}${G[v]}${C[norm]}"
        done
        repeat "${G[h]}" $(( bw - 2 ))
        _put $(( top + 1 + body )) "$left" "${C[border]}${G[tee_l]}${REPLY}${G[tee_r]}${C[norm]}"
        extra=""
        for e in $OVERLAY_KEYS; do T "${e#*:}"; extra+="${C[btn]} ${REPLY//_/ } ${C[btn_key]}${e%%:*}${C[btn]} ${C[norm]} "; done
        T "Close"; line="$extra${C[btn]} $REPLY ${C[btn_key]}Esc${C[btn]} ${C[norm]}"
        if (( n > body )); then Tf "%d-%d of %d" $(( scroll + 1 )) $(( scroll + body )) "$n"; line="${C[dim]}$REPLY${C[norm]}  $line"; fi
        fit " $line" $(( bw - 3 ))
        _put $(( top + 2 + body )) "$left" "${C[border]}${G[v]}${C[norm]}${REPLY}${C[border]}${G[v]}${C[norm]}"
        _hline $(( top + 3 + body )) "$left" "$bw" "${G[bl]}" "${G[br]}"
        printf '%s' "$FRAME"
        read_key 1 || continue
        case $KEY in
            ESC|q|ENTER|F1) break ;;
            UP|k) (( scroll-- )) ;;
            DOWN|j) (( scroll++ )) ;;
            PGUP) (( scroll -= body - 1 )) ;;
            PGDN|SPACE) (( scroll += body - 1 )) ;;
            HOME|g) scroll=0 ;;
            END|G) scroll=$n ;;
            MOUSE) (( MOUSE_B == 64 )) && (( scroll -= 3 )); (( MOUSE_B == 65 )) && (( scroll += 3 )) ;;
            *)
                for e in $OVERLAY_KEYS; do
                    [[ $KEY == "${e%%:*}" ]] && { OVERLAY_KEY=$KEY; break 2; }
                done ;;
        esac
        (( NEED_RESIZE )) && { NEED_RESIZE=0; layout_compute; draw; }
    done
    OVERLAY_KEYS=""
    NEED_REDRAW=1
}

# Help window: the keys of the current context.
help_overlay() {
    local -a out=()
    local a k i lab
    _hk() { local txt=$2; fit "$1" 12; out+=("  ${C[btn_key]}${REPLY}${C[norm]} $txt"); }
    _hs() { T "$1"; out+=("" "${C[group]}$REPLY${C[norm]}"); }
    # Current panel.
    ctx_title
    out+=("${C[title]}${REPLY}${C[norm]}")
    if (( ${#TB_KEY[@]} )); then
        _hs "Toolbar"
        for i in "${!TB_KEY[@]}"; do T "${TB_LABEL[i]}"; lab=$REPLY; [[ ${TB_ON[i]} == 1 ]] || lab+=" ${C[dim]}(not available now)${C[norm]}"; _hk "${TB_KEY[i]}" "$lab"; done
    fi
    if (( ${#PB_KEYS[@]} )); then
        _hs "Panel (when the content has the focus)"
        for i in "${!PB_KEYS[@]}"; do T "${PB_LABELS[i]//_/ }"; _hk "${PB_KEYS[i]}" "$REPLY"; done
    fi
    _hs "Global"
    for a in "${KEY_ACTIONS[@]}"; do T "${KEY_LABELS[$a]}"; _hk "${KEYMAP[$a]}" "$REPLY"; done
    _hs "Navigation"
    _hk "Tab S-Tab" "$(T "Next / previous panel (tree, menu, content, tasks)"; printf '%s' "$REPLY")"
    _hk "↑ ↓ j k" "$(T "Move"; printf '%s' "$REPLY")"
    _hk "PgUp PgDn" "$(T "Page up / down"; printf '%s' "$REPLY")"
    _hk "← →" "$(T "Collapse / expand (tree), previous / next panel"; printf '%s' "$REPLY")"
    _hk "Space" "$(T "Collapse / expand (tree), mark a guest (search grids)"; printf '%s' "$REPLY")"
    _hk "Enter" "$(T "Open / edit the selected row"; printf '%s' "$REPLY")"
    _hk "Esc" "$(T "Back to the tree"; printf '%s' "$REPLY")"
    _hs "Mouse"
    T "Click: select, double click: open, wheel: scroll, buttons and tabs are clickable"; out+=("  $REPLY")
    out+=("" "${C[dim]}$(T "Key bindings can be changed in the configuration file: key.<action> = <keys>"; printf '%s' "$REPLY")${C[norm]}")
    key_of docs; OVERLAY_KEYS="d:Documentation"
    T "Help"
    overlay_show "$REPLY" "${out[@]}"
    [[ $OVERLAY_KEY == d ]] && act_help
}
