# shellcheck shell=bash
# content.sh - content panel model and generic content builders.
#
# A view handler fills C_LINES (pre-formatted lines). Lines registered with
# c_sel are selectable: C_SELL holds their line index and C_SELK the key
# passed to the view's "enter" / "key" callbacks.

declare -ga C_LINES=() C_SELL=() C_SELK=()
C_CUR=0        # index into C_SELL
C_SCROLL=0     # first visible line
CONTENT_W=60   # width available to views (set by the layout)
CONTENT_H=20

c_reset() { C_LINES=(); C_SELL=(); C_SELK=(); }
c_add() { C_LINES+=("${1//$'\x1e'/, }"); }
c_blank() { C_LINES+=(""); }
c_sel() { C_SELL+=("${#C_LINES[@]}"); C_SELK+=("$2"); C_LINES+=("${1//$'\x1e'/, }"); }

# Section heading followed by a thin rule.
c_section() {
    T "$1"
    c_add "${C[group]}${REPLY}${C[norm]}"
    repeat "${G[h]}" "$CONTENT_W"
    c_add "${C[border]}${REPLY}${C[norm]}"
}

# Key/value line. c_kv <key> <value> [key width]
c_kv() {
    T "$1"; fit "$REPLY" "${3:-22}"
    c_add "${C[dim]}${REPLY}${C[norm]} $2"
}

# Selectable key/value line. c_kv_sel <key> <value> <selection key> [key width]
c_kv_sel() {
    T "$1"; fit "$REPLY" "${4:-22}"
    c_sel "${C[dim]}${REPLY}${C[norm]} $2" "$3"
}

# Informational / error message.
c_msg() {
    local level=$1; T "$2"
    c_add ""
    c_add "  ${C[$level]}${REPLY}${C[norm]}"
}

c_api_error() { c_msg err "${API_ERR:-unknown error}"; }

# Multi-line text (the broker encodes newlines as \x1f).
c_text() {
    local text=$1 l
    local -a lines
    IFS=$'\x1f' read -r -d '' -a lines <<< "${text}"$'\x1f'
    for l in "${lines[@]}"; do
        l=${l%$'\n'}
        c_add "$l"
    done
}

# ---------------------------------------------------------------------------
# Tables
#   spec: "field:Header:width[:fmt[:align]]|..."  width "*" = flexible
# ---------------------------------------------------------------------------
declare -ga TS_F=() TS_H=() TS_W=() TS_FMT=() TS_A=()
TS_FIELDS=""

table_spec() {
    local spec=$1 col f h w fm a fixed=0 flex=0 i
    local -a cols parts
    TS_F=() TS_H=() TS_W=() TS_FMT=() TS_A=()
    IFS='|' read -r -a cols <<< "$spec"
    for col in "${cols[@]}"; do
        IFS=':' read -r -a parts <<< "$col"
        f=${parts[0]} h=${parts[1]-} w=${parts[2]:-10} fm=${parts[3]:-s} a=${parts[4]:-l}
        TS_F+=("$f"); TS_H+=("$h"); TS_W+=("$w"); TS_FMT+=("$fm"); TS_A+=("$a")
        if [[ $w == \** ]]; then (( flex += ${#w}, fixed += 2 )); else (( fixed += w + 2 )); fi
    done
    # Distribute the remaining width between flexible columns
    # ("*" = one share, "**" = two shares...).
    local remain=$(( CONTENT_W - fixed - 1 ))
    for i in "${!TS_W[@]}"; do
        if [[ ${TS_W[i]} == \** ]]; then
            w=$(( flex ? remain * ${#TS_W[i]} / flex : 10 ))
            (( w < 8 )) && w=8
            TS_W[i]=$w
        fi
    done
    local IFS=,
    TS_FIELDS="${TS_F[*]}"
}

table_header() {
    local i line=" "
    for i in "${!TS_H[@]}"; do
        T "${TS_H[i]}"
        fit "$REPLY" "${TS_W[i]}"
        line+="$REPLY  "
    done
    c_add "${C[th]}${line}${C[norm]}"
    repeat "${G[h]}" "$CONTENT_W"
    c_add "${C[border]}${REPLY}${C[norm]}"
}

# table_row <tsv row> -> formatted line in REPLY
table_row() {
    local -a v
    local i line=" " cell n
    tsv_split v "$1"
    for i in "${!TS_F[@]}"; do
        fmtv "${TS_FMT[i]}" "${v[i]-}"; cell=$REPLY
        if [[ ${TS_A[i]} == r ]]; then
            vlen "$cell"; n=$REPLY
            (( n < TS_W[i] )) && printf -v cell '%*s%s' $(( TS_W[i] - n )) "" "$cell"
        fi
        fit "$cell" "${TS_W[i]}"
        line+="$REPLY  "
    done
    REPLY=$line
}

# table_add [key column index]: append API_ROWS as selectable rows.
table_add() {
    local kc=${1:-0} row
    local -a v
    if (( ${#API_ROWS[@]} == 0 )); then
        c_msg dim "No items"
        return
    fi
    for row in "${API_ROWS[@]}"; do
        tsv_split v "$row"
        table_row "$row"
        if [[ $kc == -1 ]]; then c_add "$REPLY"        # read-only rows
        else c_sel "$REPLY" "${TABLE_KEY_PREFIX}${v[kc]-}"
        fi
    done
}
TABLE_KEY_PREFIX=""   # prefix added to row keys (multi-table panels: "pci|")

# Sort API_ROWS by a column: table_sort <col index> [n|r|nr]
table_sort() {
    local k=$(( $1 + 1 )) o=${2:-}
    (( ${#API_ROWS[@]} > 1 )) || return 0
    mapfile -t API_ROWS < <(printf '%s\n' "${API_ROWS[@]}" | sort -t $'\t' -k "$k,$k$o")
}

# view_table <path> <query> <spec> [key column|-1] [sort column] [sort opts]
# One-line generic table view used by most menu entries.
# Row keys get the prefix TABLE_KEY_PREFIX (reset after the call).
view_table() {
    local path=$1 query=$2 spec=$3 kc=${4:-0}
    table_spec "$spec"
    if ! api_get rows "$path" "$query" "$TS_FIELDS"; then
        c_api_error
        TABLE_KEY_PREFIX=""
        return 1
    fi
    [[ -n ${5:-} ]] && table_sort "$5" "${6:-}"
    table_header
    table_add "$kc"
    TABLE_KEY_PREFIX=""
}

# view_kv <path> [query] [key width]: generic key/value view (flattened).
view_kv() {
    local r
    if ! api_get kv "$1" "${2:-}"; then c_api_error; return 1; fi
    (( ${#API_ROWS[@]} )) || { c_msg dim "No items"; return 0; }
    for r in "${API_ROWS[@]}"; do
        c_kv_sel "${r%%$'\t'*}" "${r#*$'\t'}" "${r%%$'\t'*}" "${3:-24}"
    done
}
