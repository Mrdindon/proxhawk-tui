# shellcheck shell=bash
# theme.sh - loads a colour theme (themes/<name>.sh) and compiles it into
# ready-to-print escape sequences stored in the associative array C.
#
# A theme file only fills the TH array with colour specifications: SGR
# parameters (TH[ok]="38;5;71") or words ("#50fa7b bold", "bg=#282a36", see
# theme_sgr). TH_BG, when set, is appended to every token that does not
# define its own background, which allows "painted" themes. The configuration
# file can override any token: color.<token> = <specification>.

declare -gA TH=() C=()
TH_BG=""

theme_load() {
    local name=${CFG[theme]} k sgr
    if [[ $name == auto ]]; then
        (( ${TCAP[colors]:-8} >= 256 )) && name=default || name=basic
    fi
    [[ -r $PROXHAWK_TUI_HOME/themes/$name.sh ]] || name=default
    # shellcheck source=/dev/null
    source "$PROXHAWK_TUI_HOME/themes/default.sh"
    [[ $name != default ]] && source "$PROXHAWK_TUI_HOME/themes/$name.sh"
    THEME_NAME=$name
    # Overrides of the configuration file: color.<token> = <colour>
    for k in "${!CFGX[@]}"; do
        [[ $k == color.* ]] && TH[${k#color.}]=${CFGX[$k]}
    done
    local bg=""
    [[ -n $TH_BG ]] && { theme_sgr "$TH_BG"; bg=$REPLY; }
    for k in "${!TH[@]}"; do
        theme_sgr "${TH[$k]}"; sgr=$REPLY
        if [[ -n $bg ]] && ! _sgr_has_bg "$sgr"; then
            sgr+=";$bg"
        fi
        C[$k]=$'\e[0;'"${sgr}m"
    done
    C[reset]=$'\e[0m'
}

# Does an SGR parameter list set a background colour? (38/48;5;n and
# 38/48;2;r;g;b sub-parameters are skipped.)
_sgr_has_bg() {
    local -a p
    local i=0
    IFS=';' read -r -a p <<< "$1"
    while (( i < ${#p[@]} )); do
        case ${p[i]} in
            38) [[ ${p[i+1]-} == 5 ]] && (( i += 2 )) || (( i += 4 )) ;;
            48|49|4[0-7]|10[0-7]) return 0 ;;
        esac
        (( i++ ))
    done
    return 1
}

# Colour specification -> SGR parameters (REPLY). Accepted words (space
# separated, combinable): raw SGR ("38;5;71"), "#rrggbb" (foreground),
# "bg=#rrggbb" (background), "default" / "bg=default" (terminal colours),
# ANSI names (red, green... "bright-red", "bg=blue"), bold, dim, italic,
# underline, reverse. Hex colours use 24-bit colour when the terminal
# announces it (COLORTERM=truecolor|24bit), the nearest of the 256 colours
# otherwise.
declare -gA _ANSI=([black]=0 [red]=1 [green]=2 [yellow]=3 [blue]=4 [magenta]=5 [cyan]=6 [white]=7)
theme_sgr() {
    local spec=$1 w out="" target code
    if [[ $spec =~ ^[0-9\;]+$ ]]; then REPLY=$spec; return; fi
    for w in $spec; do
        target=38
        [[ $w == bg=* ]] && { target=48; w=${w#bg=}; }
        case $w in
            bold) code=1 ;; dim) code=2 ;; italic) code=3 ;; underline) code=4 ;; reverse) code=7 ;;
            default) code=$(( target + 1 )) ;;
            \#??????) _hex_sgr "$target" "$w"; code=$REPLY ;;
            bright-*) code=$(( target - 38 + 90 + _ANSI[${w#bright-}] )); (( target == 48 )) && code=$(( 100 + _ANSI[${w#bright-}] )) ;;
            *)
                if [[ -v _ANSI[$w] ]]; then code=$(( target - 8 + _ANSI[$w] ))
                elif [[ $w =~ ^[0-9\;]+$ ]]; then code=$w
                else continue
                fi ;;
        esac
        out+="${out:+;}$code"
    done
    REPLY=${out:-39}
}

_hex_sgr() {
    local t=$1 h=${2#\#} r g b
    r=$(( 16#${h:0:2} )) g=$(( 16#${h:2:2} )) b=$(( 16#${h:4:2} ))
    if [[ ${COLORTERM-} == truecolor || ${COLORTERM-} == 24bit ]]; then
        REPLY="$t;2;$r;$g;$b"
    else
        # Nearest colour of the 6x6x6 cube of the 256 colour palette.
        local q=(0 95 135 175 215 255) i best=0 d bd
        _c6() { local v=$1; best=0 bd=999; for i in 0 1 2 3 4 5; do d=$(( v > q[i] ? v - q[i] : q[i] - v )); (( d < bd )) && { bd=$d; best=$i; }; done; REPLY=$best; }
        _c6 "$r"; local ri=$REPLY; _c6 "$g"; local gi=$REPLY; _c6 "$b"; local bi=$REPLY
        REPLY="$t;5;$(( 16 + 36 * ri + 6 * gi + bi ))"
    fi
}
