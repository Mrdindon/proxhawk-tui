# shellcheck shell=bash
# dialog.sh - modal dialogs through `dialog` or `whiptail` (whichever is
# installed, whiptail ships with Proxmox VE), with a plain prompt fallback.
#
#   dlg_yesno  <title> <text>                 rc 0 = yes
#   dlg_input  <title> <text> [default]       REPLY, rc 0 = ok
#   dlg_password <title> <text>               REPLY, rc 0 = ok
#   dlg_menu   <title> <text> tag label ...   REPLY = tag, rc 0 = ok
#   dlg_msg    <title> <text>
#   dlg_textbox <title> <file>

DLG=""
DLG_NOTAGS=0   # 1 = hide the tags of the next menus (forms)

dlg_init() {
    case ${CFG[dialog]} in
        dialog|whiptail) command -v "${CFG[dialog]}" >/dev/null && DLG=${CFG[dialog]} ;;
        builtin) DLG=builtin ;;
    esac
    if [[ -z $DLG ]]; then
        if command -v dialog >/dev/null; then DLG=dialog
        elif command -v whiptail >/dev/null; then DLG=whiptail
        else DLG=builtin
        fi
    fi
}

# Run the dialog tool outside of the TUI; the answer is captured in REPLY.
_dlg_run() {
    local rc out="$RUN_DIR/dlg.out"
    term_leave
    if [[ $DLG == dialog ]]; then
        dialog --colors --backtitle "pvetty - Proxmox VE" "$@" 2> "$out"
    else
        whiptail --backtitle "pvetty - Proxmox VE" "$@" 2> "$out"
    fi
    rc=$?
    REPLY=$(< "$out")
    term_enter
    NEED_REDRAW=1
    return $rc
}

_dlg_size() {
    DH=$(( ROWS - 4 )); DW=$(( COLS - 10 ))
    (( DH > ${1:-12} )) && DH=${1:-12}
    (( DW > ${2:-70} )) && DW=${2:-70}
}

dlg_yesno() {
    T "$1"; local title=$REPLY; T "$2"; local text=$REPLY
    if [[ $DLG == builtin ]]; then
        term_leave
        printf '\n%s\n%s [y/N] ' "$title" "$text"
        local a; read -r a
        term_enter; NEED_REDRAW=1
        [[ $a == [yYoO]* ]]
        return
    fi
    _dlg_size 12 70
    local -a dflt=(--defaultno)
    (( ${DLG_DEFAULT_YES:-0} )) && dflt=()
    _dlg_run --title " $title " "${dflt[@]}" --yesno "$text" "$DH" "$DW"
}

dlg_input() {
    T "$1"; local title=$REPLY; T "$2"; local text=$REPLY
    if [[ $DLG == builtin ]]; then
        term_leave
        printf '\n%s\n%s [%s]: ' "$title" "$text" "${3:-}"
        local a rc; read -r a; rc=$?
        REPLY=${a:-${3:-}}
        term_enter; NEED_REDRAW=1
        return $rc
    fi
    _dlg_size 10 70
    _dlg_run --title " $title " --inputbox "$text" "$DH" "$DW" "${3:-}"
}

dlg_menu() {
    T "$1"; local title=$REPLY; T "$2"; local text=$REPLY
    shift 2
    if [[ $DLG == builtin ]]; then
        term_leave
        printf '\n%s - %s\n' "$title" "$text"
        local -a tags=()
        while (( $# >= 2 )); do tags+=("$1"); printf '  %d) %s\n' "${#tags[@]}" "$2"; shift 2; done
        local a; read -r -p '> ' a
        term_enter; NEED_REDRAW=1
        [[ $a =~ ^[0-9]+$ ]] && (( a >= 1 && a <= ${#tags[@]} )) || return 1
        REPLY=${tags[a - 1]}
        return 0
    fi
    # whiptail hides the text when the list height leaves no room for it.
    local n=$(( $# / 2 )) tl
    # Room for the text: one line per 70 characters (and per newline).
    tl=$(( (${#text} + 69) / 70 )); (( tl < 1 )) && tl=1
    tl=$(( tl + $(printf '%s' "$text" | grep -c '') - 1 ))
    # Width: the longest "tag  item" line (at least 76 columns), within the
    # terminal; longer items are cut, otherwise whiptail breaks the frame.
    local -a args=("$@")
    local i tw=0 iw=0 w
    for (( i = 0; i + 1 < ${#args[@]}; i += 2 )); do
        (( ${#args[i]} > tw )) && tw=${#args[i]}
        (( ${#args[i+1]} > iw )) && iw=${#args[i+1]}
    done
    (( DLG_NOTAGS )) && tw=0
    w=$(( tw + iw + 12 )); (( w < 76 )) && w=76
    _dlg_size $(( n + 7 + tl )) "$w"
    local room=$(( DW - tw - 12 ))
    if (( iw > room && room > 8 )); then
        for (( i = 1; i < ${#args[@]}; i += 2 )); do
            (( ${#args[i]} > room )) && args[i]="${args[i]:0:room-1}…"
        done
    fi
    set -- "${args[@]}"
    local mh=$(( DH - 7 - tl )); (( mh > n )) && mh=$n; (( mh < 1 )) && mh=1
    local -a extra=()
    if (( DLG_NOTAGS )); then [[ $DLG == dialog ]] && extra=(--no-tags) || extra=(--notags); fi
    _dlg_run --title " $title " "${extra[@]}" --menu "$text" "$DH" "$DW" "$mh" "$@"
}

dlg_msg() {
    T "$1"; local title=$REPLY; T "$2"; local text=$REPLY
    if [[ $DLG == builtin ]]; then
        term_leave
        printf '\n%s\n%s\n[Enter] ' "$title" "$text"
        read -r
        term_enter; NEED_REDRAW=1
        return 0
    fi
    _dlg_size 14 72
    _dlg_run --title " $title " --msgbox "$text" "$DH" "$DW"
}

dlg_textbox() {
    T "$1"; local title=$REPLY
    if [[ $DLG == builtin ]]; then
        term_run sh -c 'cat "$1"; printf "\n[Enter] "; read -r _' sh "$2"
        return 0
    fi
    _dlg_size 999 999
    local -a extra=()
    [[ $DLG == whiptail ]] && extra=(--scrolltext)
    _dlg_run --title " $title " "${extra[@]}" --textbox "$2" "$DH" "$DW"
}

dlg_password() {
    T "$1"; local title=$REPLY; T "$2"; local text=$REPLY
    if [[ $DLG == builtin ]]; then
        term_leave
        printf '\n%s\n%s: ' "$title" "$text"
        local a rc; read -rs a; rc=$?
        REPLY=$a
        term_enter; NEED_REDRAW=1
        return $rc
    fi
    _dlg_size 10 70
    _dlg_run --title " $title " --passwordbox "$text" "$DH" "$DW"
}
