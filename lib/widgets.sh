# shellcheck shell=bash
# widgets.sh - formatting helpers and text widgets (progress bars, braille
# charts, tables, key/value lists, spinner). All functions return their
# result in REPLY (or in an array) to avoid sub-shells.

shopt -s extglob

# ---------------------------------------------------------------------------
# Value formatting
# ---------------------------------------------------------------------------
_UNITS=(B KiB MiB GiB TiB PiB EiB)

# fmt_bytes <bytes> -> "1.23 GiB"
fmt_bytes() {
    local b=${1%%.*} u=0 v
    [[ $b =~ ^[0-9]+$ ]] || { REPLY=""; return; }
    if (( b < 1024 )); then REPLY="$b B"; return; fi
    v=$(( b * 100 / 1024 )); u=1
    while (( v >= 102400 && u < 6 )); do v=$(( v / 1024 )); (( u++ )); done
    printf -v REPLY '%d.%02d %s' $(( v / 100 )) $(( v % 100 )) "${_UNITS[u]}"
}

# fmt_rate <bytes/s> -> "1.23 KiB/s"
fmt_rate() { fmt_bytes "$1"; [[ -n $REPLY ]] && REPLY+="/s"; }

# fmt_pct <value * 10000> -> "12.34%"
fmt_pct() {
    local v=${1:-0}
    [[ $v =~ ^-?[0-9]+$ ]] || { REPLY=""; return; }
    printf -v REPLY '%d.%02d%%' $(( v / 100 )) $(( v % 100 ))
}

# fmt_uptime <seconds> -> "3 days 04:05:06"
fmt_uptime() {
    local s=${1%%.*} d
    [[ $s =~ ^[0-9]+$ ]] && (( s > 0 )) || { REPLY="-"; return; }
    d=$(( s / 86400 )); s=$(( s % 86400 ))
    printf -v REPLY '%02d:%02d:%02d' $(( s / 3600 )) $(( s % 3600 / 60 )) $(( s % 60 ))
    if (( d == 1 )); then Tf "%d day %s" "$d" "$REPLY"
    elif (( d > 1 )); then Tf "%d days %s" "$d" "$REPLY"
    fi
}

# fmt_time <epoch> -> localized date/time
fmt_time() {
    local e=${1%%.*}
    [[ $e =~ ^[0-9]+$ ]] && (( e > 0 )) || { REPLY=""; return; }
    printf -v REPLY "%(${2:-$DATE_FMT})T" "$e"
}

# fmtv <format> <value> -> formatted (possibly coloured) value
#   s string | b bytes | t datetime | ts short datetime | d date | u uptime
#   pct (x10000) | bool | nbool (negated) | status | task | int | ml (multi-line, first line)
fmtv() {
    local f=$1 v=$2
    case $f in
        b) fmt_bytes "$v" ;;
        t) fmt_time "$v" ;;
        ts) fmt_time "$v" "$DATE_SHORT" ;;
        d) fmt_time "$v" '%Y-%m-%d' ;;
        u) fmt_uptime "$v" ;;
        pct) fmt_pct "$v" ;;
        bool) if [[ $v == 1 ]]; then T Yes; else T No; fi ;;
        nbool) if [[ $v == 1 ]]; then T No; else T Yes; fi ;;
        status) status_color "$v"; T "$v"; REPLY="${STATUS_C}${REPLY}${C[norm]}" ;;
        task)
            if [[ -z $v ]]; then T running; REPLY="${C[info]}${SPIN_MARK} $REPLY${C[norm]}"
            elif [[ $v == OK ]]; then REPLY="${C[ok]}OK${C[norm]}"
            elif [[ $v == WARNINGS* ]]; then REPLY="${C[warn]}$v${C[norm]}"
            else REPLY="${C[err]}$v${C[norm]}"
            fi ;;
        ml) REPLY=${v%%$'\x1f'*} ;;
        *) REPLY=$v ;;
    esac
}

# status_color <status> -> STATUS_C escape sequence
status_color() {
    case $1 in
        running|online|active|available|ok|OK|enabled|started|quorate|1) STATUS_C=${C[ok]} ;;
        stopped|inactive|dead|disabled|unknown|"") STATUS_C=${C[dim]} ;;
        paused|suspended|prelaunch|standby|warning) STATUS_C=${C[warn]} ;;
        *) STATUS_C=${C[err]} ;;
    esac
}

# Status glyph for a guest/node in STATUS_G (coloured).
status_glyph() {
    case $1 in
        running|online|available|ok) STATUS_G="${C[ok]}${G[st_running]}" ;;
        paused|suspended) STATUS_G="${C[warn]}${G[st_paused]}" ;;
        offline|error|unknown) STATUS_G="${C[err]}${G[st_offline]}" ;;
        *) STATUS_G="${C[dim]}${G[st_stopped]}" ;;
    esac
}

# ---------------------------------------------------------------------------
# String width helpers (ANSI aware). Wide (CJK/emoji) characters are not
# supported on purpose: glyph sets only use single-cell characters.
# ---------------------------------------------------------------------------
# strip <string> -> string without SGR escape sequences (ESC [ ... m).
# Segment based: much faster than an extglob substitution on long lines.
strip() {
    local s=$1 out=""
    while [[ $s == *$'\e['* ]]; do
        out+=${s%%$'\e['*}
        s=${s#*$'\e['}
        s=${s#*m}
    done
    REPLY=$out$s
}

# Double width characters (CJK, Hangul, full width forms): two cells each.
# Only handled when WIDE_TEXT=1 (set for the zh / ja / ko languages by
# i18n_load): the test costs time on every cell. The ranges are compared by
# code point (LC_COLLATE=C; other collations give wrong ranges).
WIDE_TEXT=0
_WR=$'\u1100-\u115f\u2e80-\u303e\u3041-\u33ff\u3400-\u4dbf\u4e00-\u9fff\ua000-\ua4cf\uac00-\ud7a3\uf900-\ufaff\ufe30-\ufe4f\uff00-\uff60\uffe0-\uffe6'
WIDE_ANY="*[$_WR]*" WIDE_ONE="[$_WR]" WIDE_NOT="[!$_WR]"
unset _WR

# vlen <string> -> visible width in REPLY
# shellcheck disable=SC2053  # WIDE_* are glob patterns on purpose
vlen() {
    strip "$1"
    if (( WIDE_TEXT )); then
        local LC_COLLATE=C w
        [[ $REPLY == $WIDE_ANY ]] && { w=${REPLY//$WIDE_NOT/}; REPLY=$(( ${#REPLY} + ${#w} )); return; }
    fi
    REPLY=${#REPLY}
}

# dwidth <string> -> display width in REPLY (no escape sequences inside).
# shellcheck disable=SC2053
dwidth() {
    REPLY=${#1}
    if (( WIDE_TEXT )); then
        local LC_COLLATE=C w
        [[ $1 == $WIDE_ANY ]] && { w=${1//$WIDE_NOT/}; REPLY=$(( ${#1} + ${#w} )); }
    fi
}

# fit for strings with double width characters (slow path of fit).
# shellcheck disable=SC2053  # WIDE_* are glob patterns on purpose
_fit_wide() {
    local s=$1 w=$2 LC_COLLATE=C out="" used=0 rem c seg
    vlen "$s"
    if (( REPLY <= w )); then printf -v REPLY '%s%*s' "$s" $(( w - REPLY )) ""; return; fi
    rem=$(( w > 1 ? w - 1 : w ))
    while [[ -n $s ]]; do
        if [[ $s == $'\e['* ]]; then seg=${s%%m*}m; out+=$seg; s=${s:${#seg}}; continue; fi
        c=${s:0:1}
        if [[ $c == $WIDE_ONE ]]; then (( used + 2 > rem )) && break; (( used += 2 ))
        else (( used + 1 > rem )) && break; (( used++ )); fi
        out+=$c; s=${s:1}
    done
    printf -v out '%s%*s' "$out" $(( rem - used )) ""
    (( w > 1 )) && out+=${G[ellipsis]}
    REPLY=$out
}

# fit <string> <width> -> string padded or truncated to exactly <width> cells
# shellcheck disable=SC2053  # WIDE_* are glob patterns on purpose
fit() {
    local s=$1 w=$2 n seg out="" rem
    if (( WIDE_TEXT )); then
        local LC_COLLATE=C
        [[ $s == $WIDE_ANY ]] && { _fit_wide "$s" "$w"; return; }
    fi
    if [[ $s != *$'\e'* ]]; then
        n=${#s}
        if (( n <= w )); then printf -v REPLY '%s%*s' "$s" $(( w - n )) ""
        elif (( w > 1 )); then REPLY="${s:0:w-1}${G[ellipsis]}"
        else REPLY=${s:0:w}
        fi
        return
    fi
    strip "$s"; n=${#REPLY}
    if (( n <= w )); then
        printf -v REPLY '%s%*s' "$s" $(( w - n )) ""
        return
    fi
    # Truncate: copy escape sequences, count only visible characters.
    rem=$(( w - 1 ))
    while (( rem > 0 )) && [[ -n $s ]]; do
        if [[ $s == $'\e['* ]]; then
            seg=${s%%m*}m
        else
            seg=${s%%$'\e['*}
            (( ${#seg} > rem )) && seg=${seg:0:rem}
            (( rem -= ${#seg} ))
        fi
        out+=$seg
        s=${s:${#seg}}
    done
    REPLY="${out}${G[ellipsis]}"
}

# center <string> <width>
center() {
    local s=$1 w=$2
    vlen "$s"
    local pad=$(( (w - REPLY) / 2 ))
    (( pad < 0 )) && pad=0
    printf -v REPLY '%*s%s' "$pad" "" "$s"
    fit "$REPLY" "$w"
}

# repeat <char> <count>
repeat() {
    local n=$2
    (( n > 0 )) || { REPLY=""; return; }
    printf -v REPLY '%*s' "$n" ""
    REPLY=${REPLY// /$1}
}

# ---------------------------------------------------------------------------
# Progress bar: bar <value> <max> <width> -> coloured bar in REPLY
# ---------------------------------------------------------------------------
bar() {
    local v=${1%%.*} m=${2%%.*} w=$3 eighths full part col pct
    [[ $v =~ ^[0-9]+$ ]] || v=0
    [[ $m =~ ^[0-9]+$ ]] && (( m > 0 )) || m=1
    (( v > m )) && v=$m
    eighths=$(( v * w * 8 / m ))
    full=$(( eighths / 8 )) part=$(( eighths % 8 ))
    pct=$(( v * 100 / m ))
    col=${C[bar_fill]}
    (( pct >= 80 )) && col=${C[bar_warn]}
    (( pct >= 90 )) && col=${C[bar_crit]}
    repeat "${G[bar_full]}" "$full"; local s=$REPLY
    if (( part > 0 )) && [[ -n ${BAR_PARTS[part]} ]]; then s+=${BAR_PARTS[part]}; (( full++ )); fi
    repeat "${G[bar_empty]}" $(( w - full ))
    REPLY="${col}${s}${C[bar_empty]}${REPLY}${C[norm]}"
}

# usage_line <label> <used> <total> <width> [unit: b|cpu]
#   "CPU usage   [████░░░░]  12.34% of 4 CPU(s)"
usage_line() {
    local label=$1 used=$2 total=$3 w=$4 unit=${5:-b} text lw=18
    # Same bar width for every line of a panel (like the web UI gauges).
    local bw=$(( (w - lw - 2) * 2 / 5 ))
    (( bw > 30 )) && bw=30
    (( bw < 5 )) && bw=5
    [[ $used =~ ^[0-9]+$ ]] || used=0
    [[ $total =~ ^[0-9]+$ ]] && (( total > 0 )) || total=0
    if [[ $unit == cpu ]]; then
        # used = cpu * 10000, total = number of cpus
        fmt_pct "$used"; text=$REPLY
        Tf "%s of %s CPU(s)" "$text" "$total"; text=$REPLY
        bar "$used" 10000 "$bw"
    else
        local p=0
        (( total > 0 )) && p=$(( used * 10000 / total ))
        fmt_pct "$p"; text="$REPLY ("
        fmt_bytes "$used"; text+="$REPLY "
        T "of"; text+="$REPLY "
        fmt_bytes "$total"; text+="$REPLY)"
        bar "$used" "$total" "$bw"
    fi
    local b=$REPLY
    T "$label"; fit "$REPLY" "$lw"
    REPLY="${C[dim]}${REPLY}${C[norm]} ${b} ${text}"
}

# ---------------------------------------------------------------------------
# Braille area chart
#   chart <title> <width> <height> <fmt> <series1 array> [series2 array]
#     fmt: pct | b | rate | num  (how to print max / last values)
#   Result lines in CHART[]. Empty values are gaps.
# ---------------------------------------------------------------------------
declare -ga BRAILLE=() CHART=()
_L_MASK=(0 64 68 70 71)      # left dot column, filled from the bottom
_R_MASK=(0 128 160 176 184)  # right dot column, filled from the bottom

chart_init() {
    local i
    (( UTF8 )) || return 0
    local hex
    for (( i = 0; i < 256; i++ )); do
        printf -v hex '%02x' "$i"
        printf -v "BRAILLE[i]" "\\u28$hex"
    done
}

_chart_fmt() {
    case $1 in
        pct) fmt_pct "$2" ;;
        b) fmt_bytes "$2" ;;
        rate) fmt_rate "$2" ;;
        load) printf -v REPLY "%d.%02d" $(( $2 / 100 )) $(( $2 % 100 )) ;;
        *) REPLY=$2 ;;
    esac
}

chart() {
    local title=$1 w=$2 h=$3 fmt=$4
    local -n _s1=$5
    local -a _empty=()
    if [[ -n ${6:-} ]]; then local -n _s2=$6; else local -n _s2=_empty; fi
    local n=${#_s1[@]} max=0 v i x r c dots=$(( w * 2 )) hd=$(( h * 4 ))
    local -a l1=() l2=()
    CHART=()

    for v in "${_s1[@]}" "${_s2[@]}"; do [[ -n $v ]] && (( v > max )) && max=$v; done
    (( max <= 0 )) && max=1

    # Resample each series onto the dot columns (keeping the peak value).
    _resample() {
        local -n src=$1 dst=$2
        local cnt=${#src[@]} a b j m val
        dst=()
        for (( x = 0; x < dots; x++ )); do
            if (( cnt == 0 )); then dst[x]=-1; continue; fi
            a=$(( x * cnt / dots )); b=$(( (x + 1) * cnt / dots )); (( b <= a )) && b=$(( a + 1 ))
            m=-1
            for (( j = a; j < b && j < cnt; j++ )); do
                val=${src[j]}
                [[ -n $val ]] && (( val > m )) && m=$val
            done
            if (( m < 0 )); then dst[x]=-1
            else
                val=$(( (m * hd + max - 1) / max ))
                (( m > 0 && val == 0 )) && val=1
                dst[x]=$val
            fi
        done
    }
    _resample _s1 l1
    (( ${#_s2[@]} )) && _resample _s2 l2

    # Title line with legend and current/max values.
    local last1="" last2="" line
    for (( i = n - 1; i >= 0; i-- )); do [[ -n ${_s1[i]} ]] && { last1=${_s1[i]}; break; }; done
    T "$title"; line="${C[title]}${REPLY}${C[norm]}"
    _chart_fmt "$fmt" "${last1:-0}"; line+="  ${C[graph1]}${G[bar_full]}${C[norm]} $REPLY"
    if (( ${#_s2[@]} )); then
        for (( i = ${#_s2[@]} - 1; i >= 0; i-- )); do [[ -n ${_s2[i]} ]] && { last2=${_s2[i]}; break; }; done
        _chart_fmt "$fmt" "${last2:-0}"; line+="  ${C[graph2]}${G[bar_full]}${C[norm]} $REPLY"
    fi
    T "max"; line+="  ${C[dim]}($REPLY "; _chart_fmt "$fmt" "$max"; line+="$REPLY)${C[norm]}"
    CHART+=("$line")

    local base f1 f2 bits1 bits2 cell col prev
    for (( r = 0; r < h; r++ )); do
        base=$(( (h - 1 - r) * 4 ))
        line="${C[axis]}${G[v]}" prev=axis
        for (( c = 0; c < w; c++ )); do
            bits1=0 bits2=0
            for x in $(( c * 2 )) $(( c * 2 + 1 )); do
                f1=$(( l1[x] - base )); (( f1 < 0 )) && f1=0; (( f1 > 4 )) && f1=4
                f2=0
                if (( ${#l2[@]} )); then f2=$(( l2[x] - base )); (( f2 < 0 )) && f2=0; (( f2 > 4 )) && f2=4; fi
                if (( x % 2 == 0 )); then
                    (( bits1 |= _L_MASK[f1], bits2 |= _L_MASK[f2] ))
                else
                    (( bits1 |= _R_MASK[f1], bits2 |= _R_MASK[f2] ))
                fi
            done
            if (( UTF8 && ${CHART_BRAILLE:-1} )); then
                cell=${BRAILLE[bits1 | bits2]}
            else
                local cnt=$(( (bits1 | bits2) ? ((bits1 | bits2) == 255 ? 2 : 1) : 0 ))
                case $cnt in 0) cell=" " ;; 1) cell="." ;; *) cell=":" ;; esac
            fi
            col=graph1
            (( bits2 & ~bits1 )) && col=graph2
            if [[ $col != "$prev" ]]; then line+=${C[$col]}; prev=$col; fi
            line+=$cell
        done
        CHART+=("${line}${C[norm]}")
    done
    # X axis with the time span.
    repeat "${G[h]}" "$w"
    CHART+=("${C[axis]}${G[bl]}${REPLY}${C[norm]}")
}

# ---------------------------------------------------------------------------
# Animated spinner in the screen: content producers write SPIN_MARK (one
# cell wide), draw() replaces it with the current frame. SPIN_ACTIVE tells the
# main loop to redraw often while something is running.
SPIN_MARK=$'\x01'
SPIN_FRAME=0

# ---------------------------------------------------------------------------
# Spinner shown in the footer while a slow operation runs.
# ---------------------------------------------------------------------------
SPIN_PID=""
spinner_start() {
    spinner_stop
    local msg=$1 row=${ROWS:-24}
    (
        trap 'exit 0' TERM
        sleep 0.2
        local i=0 n=${#SPINNER[@]} main=$$
        while kill -0 "$main" 2>/dev/null; do
            printf '\e[%d;1H%s %s %s \e[K%s' "$row" "${C[footer_key]}" "${SPINNER[i % n]}" "${C[footer]}$msg" "${C[reset]}" 2>/dev/null || exit 0
            (( i++ ))
            sleep 0.1
        done
    ) &
    SPIN_PID=$!
}

spinner_stop() {
    [[ -n $SPIN_PID ]] || return 0
    kill "$SPIN_PID" 2>/dev/null
    wait "$SPIN_PID" 2>/dev/null
    SPIN_PID=""
}
