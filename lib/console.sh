# shellcheck shell=bash
# console.sh - the Linux virtual console (TERM=linux: screen and keyboard of
# the node, IPMI / KVM).
#
# The kernel draws its text with a bitmap font of at most 512 glyphs: no
# TrueType / Nerd Font, and the fonts shipped by Debian lack most symbols of
# the interface and every braille pattern. On that console proxhawk-tui:
#
#   1. loads its own console font for the time it runs (fonts/proxhawk-256
#      or -512.psf.gz, built by tools/make-console-font.py: box drawing,
#      blocks, the symbols and braille patterns of the interface, letters of
#      the languages) and puts the previous font back when it quits;
#   2. reads the characters the console font really has, and replaces what
#      is missing: icons by the letters of the ascii set, graphs by dots,
#      other symbols by an ASCII character. This also covers the case where
#      the font cannot be loaded (console_font = off, no setfont, an error).
#
# Setting console_font: auto (default) | 256 | 512 | off.
# PROXHAWK_TUI_CONSOLE=1 forces the console mode in another terminal and
# PROXHAWK_TUI_CONSOLE_MAP=<unicode map file> gives its characters (tests).

CONSOLE=0                    # 1 on the Linux console
CONSOLE_FONT=""              # font file loaded by proxhawk-tui
CONSOLE_NOTE=""              # message shown once the interface is up
declare -gA CONSOLE_HAS=()   # characters of the console font
declare -ga CONSOLE_SUBST=() # "char=replacement" applied to every frame
CHART_BRAILLE=1

# Replacements of symbols written in the code when the font lacks them.
declare -gA _CONSOLE_FALLBACK=(
    ["⏎"]="<" ["↑"]="^" ["↓"]="v" ["←"]="<" ["→"]=">" ["↻"]="@" ["✔"]="*" ["✖"]="x"
    ["✓"]="*" ["✕"]="x" ["…"]="~" ["•"]="*" ["●"]="*" ["○"]="o" ["◐"]="o" ["▾"]="v"
    ["▸"]=">" ["›"]=">" ["▶"]=">" ["■"]="#" ["█"]="#" ["░"]="." ["▐"]="#" ["─"]="-"
    ["│"]="|" ["╭"]="+" ["╮"]="+" ["╰"]="+" ["╯"]="+" ["├"]="+" ["┤"]="+" ["┬"]="+"
    ["┴"]="+" ["┼"]="+" ["«"]="\"" ["»"]="\""
)

console_is_vt() {
    [[ ${TERM-} == linux ]] || return 1
    local t; t=$(tty 2>/dev/null)
    [[ $t =~ ^/dev/tty[0-9]+$ ]]
}

# Characters of a unicode map (output of setfont -ou / psfgettable).
_console_read_map() {
    local cp ch
    CONSOLE_HAS=()
    while read -r cp; do
        printf -v ch "\\U${cp#U+}"
        CONSOLE_HAS[$ch]=1
    done < <(grep -o 'U+[0-9a-fA-F]*' "$1" 2>/dev/null | sort -u)
    (( ${#CONSOLE_HAS[@]} ))
}

# Is every character of the string in the console font?
console_has() {
    local s=$1 i c
    for (( i = 0; i < ${#s}; i++ )); do
        c=${s:i:1}
        [[ $c == [[:ascii:]] || -n ${CONSOLE_HAS[$c]-} ]] || return 1
    done
    return 0
}

_console_load_font() {
    local size=$1 f="$PROXHAWK_TUI_HOME/fonts/proxhawk-$1.psf.gz"
    [[ -r $f ]] || return 1
    setfont "$f" 2>/dev/null || return 1
    CONSOLE_FONT=$f
    setfont -ou "$RUN_DIR/console.map" 2>/dev/null && _console_read_map "$RUN_DIR/console.map"
}

console_restore() {
    [[ -n $CONSOLE_FONT && -s $RUN_DIR/console-saved.psf ]] && setfont "$RUN_DIR/console-saved.psf" 2>/dev/null
    CONSOLE_FONT=""
}

# Called once at start-up, before the language and the glyphs are loaded.
console_setup() {
    CONSOLE=0 CONSOLE_FONT="" CONSOLE_SUBST=() CHART_BRAILLE=1
    if [[ ${PROXHAWK_TUI_CONSOLE-} == 1 ]]; then
        CONSOLE=1
        [[ -n ${PROXHAWK_TUI_CONSOLE_MAP-} ]] && _console_read_map "$PROXHAWK_TUI_CONSOLE_MAP"
        return 0
    fi
    console_is_vt || return 0
    CONSOLE=1
    command -v setfont >/dev/null || return 0
    local want=${CFG[console_font]:-auto}
    # The font of the user is saved first (with its unicode map) and put
    # back when proxhawk-tui quits.
    if [[ $want != off ]] && setfont -O "$RUN_DIR/console-saved.psf" 2>/dev/null; then
        CLEANUP_HOOKS+=(console_restore)
        [[ $want == 512 ]] && _console_load_font 512 || _console_load_font 256 || CONSOLE_FONT=""
    fi
    # Without our font: the characters of the current one.
    if [[ -z $CONSOLE_FONT ]]; then
        setfont -ou "$RUN_DIR/console.map" 2>/dev/null && _console_read_map "$RUN_DIR/console.map"
    fi
    return 0
}

# After i18n_load: a language whose letters the font lacks. Try the 512
# glyph font (Cyrillic, Greek, Latin Extended), else fall back to English.
console_language() {
    (( CONSOLE )) && (( ${#CONSOLE_HAS[@]} )) || return 0
    [[ $LANG_CODE == en ]] && return 0
    _console_lang_ok && return 0
    if [[ -n $CONSOLE_FONT && $CONSOLE_FONT != *-512.psf.gz && ${CFG[console_font]:-auto} == auto ]]; then
        _console_load_font 512 && _console_lang_ok && return 0
        _console_load_font 256
    fi
    printf -v CONSOLE_NOTE 'Language "%s" cannot be displayed on the Linux console: English is used here' "$LANG_CODE"
    CFG[language]=en
    i18n_load
}
_console_lang_ok() {
    local k
    for k in "${!L[@]}"; do console_has "${L[$k]}" || return 1; done
    return 0
}

# After glyphs_load: replace what the console font cannot draw.
console_glyphs() {
    (( CONSOLE )) || return 0
    local k c i ok=1
    for k in "${!G[@]}"; do
        console_has "${G[$k]}" || G[$k]=${_ASCII[$k]-}
    done
    for c in "${BAR_PARTS[@]}"; do console_has "$c" || ok=0; done
    (( ok )) || BAR_PARTS=("" "" "" "" "" "" "" "")
    ok=1
    for c in "${SPINNER[@]}"; do console_has "$c" || ok=0; done
    (( ok )) || SPINNER=('|' '/' '-' '\')
    # Graphs: the 25 braille patterns of two dot columns.
    CHART_BRAILLE=1
    for i in 64 68 70 71 128 160 176 184 255; do
        printf -v c "\\u28%02x" "$i"
        console_has "$c" || CHART_BRAILLE=0
    done
    CONSOLE_SUBST=()
    for c in "${!_CONSOLE_FALLBACK[@]}"; do
        console_has "$c" || CONSOLE_SUBST+=("$c=${_CONSOLE_FALLBACK[$c]}")
    done
}

# Last pass on a frame: symbols written in the code that the font lacks.
frame_fix() {
    local p
    for p in "${CONSOLE_SUBST[@]}"; do FRAME=${FRAME//"${p%%=*}"/"${p#*=}"}; done
}
