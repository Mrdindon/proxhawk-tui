# shellcheck shell=bash
# term.sh - terminal control (tput with ANSI fallbacks) and keyboard/mouse input.

ROWS=24 COLS=80
TERM_ACTIVE=0
TERM_STTY=""
declare -gA TCAP=()

# Query a terminal capability once through tput, fall back to a raw sequence.
_tcap() {
    local name=$1 fallback=$2 v
    v=$(tput "$name" 2>/dev/null) || v=$fallback
    TCAP[$name]=$v
}

term_size() {
    local s
    s=$(stty size 2>/dev/null) || s="$(tput lines 2>/dev/null) $(tput cols 2>/dev/null)"
    read -r ROWS COLS <<< "$s"
    [[ $ROWS =~ ^[0-9]+$ ]] || ROWS=24
    [[ $COLS =~ ^[0-9]+$ ]] || COLS=80
}

term_init() {
    _tcap smcup $'\e[?1049h'
    _tcap rmcup $'\e[?1049l'
    _tcap civis $'\e[?25l'
    _tcap cnorm $'\e[?25h'
    _tcap colors 8
    TERM_STTY=$(stty -g 2>/dev/null)
    term_enter
    term_size
}

# Enter the full-screen mode (alternate screen, hidden cursor, no echo).
term_enter() {
    stty -echo -icanon 2>/dev/null
    printf '%s%s\e[?7l\e[2J' "${TCAP[smcup]}" "${TCAP[civis]}"
    [[ ${CFG[mouse]} == 1 ]] && printf '\e[?1000h\e[?1006h'
    TERM_ACTIVE=1
}

# Leave the full-screen mode (used before running dialogs or shells).
term_leave() {
    (( TERM_ACTIVE )) || return 0
    [[ ${CFG[mouse]} == 1 ]] && printf '\e[?1000l\e[?1006l'
    printf '\e[0m\e[?7h%s%s' "${TCAP[cnorm]}" "${TCAP[rmcup]}"
    [[ -n $TERM_STTY ]] && stty "$TERM_STTY" 2>/dev/null
    TERM_ACTIVE=0
}

term_restore() { term_leave; }

# Run a command outside of the TUI (shell, console, editor, pager...).
term_run() {
    term_leave
    "$@"
    local rc=$?
    term_enter
    NEED_REDRAW=1
    return $rc
}

# ---------------------------------------------------------------------------
# Input: read_key [timeout] -> KEY (symbolic name or literal char)
# Mouse events set KEY=MOUSE and MOUSE_B / MOUSE_X / MOUSE_Y / MOUSE_REL.
# ---------------------------------------------------------------------------
KEY="" MOUSE_B=0 MOUSE_X=0 MOUSE_Y=0 MOUSE_REL=0

read_key() {
    local k="" rest="" c
    KEY=""
    IFS= read -rsn1 -t "${1:-0.5}" k || { [[ -z $k ]] && return 1; }
    if [[ $k == $'\e' ]]; then
        IFS= read -rsn2 -t 0.01 rest
        if [[ $rest == '[<' ]]; then
            # SGR mouse report: ESC [ < b ; x ; y (M|m)
            while IFS= read -rsn1 -t 0.05 c; do
                rest+=$c
                [[ $c == [Mm] ]] && break
            done
            if [[ $rest =~ ^\[\<([0-9]+)\;([0-9]+)\;([0-9]+)([Mm])$ ]]; then
                MOUSE_B=${BASH_REMATCH[1]} MOUSE_X=${BASH_REMATCH[2]} MOUSE_Y=${BASH_REMATCH[3]}
                [[ ${BASH_REMATCH[4]} == m ]] && MOUSE_REL=1 || MOUSE_REL=0
                KEY=MOUSE
            fi
            return 0
        fi
        if [[ $rest == \[[0-9] ]]; then
            # Read the rest of a CSI sequence ending in ~ or a letter.
            while IFS= read -rsn1 -t 0.01 c; do
                rest+=$c
                [[ $c == [~A-Za-z] ]] && break
            done
        fi
        k+=$rest
        case $k in
            $'\e[A'|$'\eOA') KEY=UP ;;
            $'\e[B'|$'\eOB') KEY=DOWN ;;
            $'\e[C'|$'\eOC') KEY=RIGHT ;;
            $'\e[D'|$'\eOD') KEY=LEFT ;;
            $'\e[5~') KEY=PGUP ;;
            $'\e[6~') KEY=PGDN ;;
            $'\e[H'|$'\e[1~'|$'\eOH') KEY=HOME ;;
            $'\e[F'|$'\e[4~'|$'\eOF') KEY=END ;;
            $'\e[Z') KEY=BTAB ;;
            $'\eOP'|$'\e[11~'|$'\e[[A') KEY=F1 ;;
            $'\eOQ'|$'\e[12~'|$'\e[[B') KEY=F2 ;;
            $'\eOR'|$'\e[13~'|$'\e[[C') KEY=F3 ;;
            $'\eOS'|$'\e[14~'|$'\e[[D') KEY=F4 ;;
            $'\e[15~'|$'\e[[E') KEY=F5 ;;
            $'\e[17~') KEY=F6 ;;
            $'\e[18~') KEY=F7 ;;
            $'\e[19~') KEY=F8 ;;
            $'\e[20~') KEY=F9 ;;
            $'\e[21~') KEY=F10 ;;
            $'\e[23~') KEY=F11 ;;
            $'\e[24~') KEY=F12 ;;
            $'\e[3~') KEY=DEL ;;
            $'\e[2~') KEY=INS ;;
            $'\e') KEY=ESC ;;
            *)
                # Alt+key: ESC followed by one printable character.
                if [[ ${#rest} == 1 && $rest == [[:print:]] ]]; then KEY="M-$rest"; else KEY=UNKNOWN; fi ;;
        esac
        return 0
    fi
    case $k in
        '') KEY=ENTER ;;
        $'\t') KEY=TAB ;;
        ' ') KEY=SPACE ;;
        $'\x7f'|$'\b') KEY=BACKSPACE ;;
        [$'\x01'-$'\x1a'])
            # Ctrl+letter.
            local code; printf -v code '%d' "'$k"
            printf -v KEY 'C-%b' "\\x$(printf '%x' $(( code + 96 )))" ;;
        *) KEY=$k ;;
    esac
    return 0
}
