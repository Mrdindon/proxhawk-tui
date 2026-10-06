# shellcheck shell=bash
# rrd.sh - RRD statistics graphs (rrddata API) drawn with braille charts,
# laid out in one or two columns like the web UI summary panels.

RRD_TIMEFRAMES=(hour day week month year)
RRD_HEIGHT=5

rrd_tf_label() {
    case ${CFG[graph_timeframe]} in
        hour) T "Hour (average)" ;;
        day) T "Day (average)" ;;
        week) T "Week (average)" ;;
        month) T "Month (average)" ;;
        year) T "Year (average)" ;;
        *) REPLY=${CFG[graph_timeframe]} ;;
    esac
}

rrd_cycle_timeframe() {
    local i
    for i in "${!RRD_TIMEFRAMES[@]}"; do
        if [[ ${RRD_TIMEFRAMES[i]} == "${CFG[graph_timeframe]}" ]]; then
            CFG[graph_timeframe]=${RRD_TIMEFRAMES[(i + 1) % ${#RRD_TIMEFRAMES[@]}]}
            return
        fi
    done
    CFG[graph_timeframe]=hour
}

# rrd_graphs <rrddata path> "Title|fmt|field[|field2]" ...
#   fields use the broker syntax (e.g. cpu*10000, netin:i)
rrd_graphs() {
    local path=$1; shift
    local spec i j row
    local -a specs=("$@") fields=() parts
    local -A fidx=()
    for spec in "${specs[@]}"; do
        IFS='|' read -r -a parts <<< "$spec"
        for (( j = 2; j < ${#parts[@]}; j++ )); do
            [[ -v fidx[${parts[j]}] ]] || { fidx[${parts[j]}]=${#fields[@]}; fields+=("${parts[j]}"); }
        done
    done
    rrd_tf_label
    c_section "$REPLY"
    local IFS=,
    if ! api_get rows "$path" "timeframe=${CFG[graph_timeframe]}&cf=AVERAGE" "${fields[*]}"; then
        unset IFS
        c_api_error; return
    fi
    unset IFS
    # Column arrays: _RRD_0, _RRD_1, ...
    for i in "${!fields[@]}"; do declare -ga "_RRD_$i=()"; done
    local -a v
    for row in "${API_ROWS[@]}"; do
        tsv_split v "$row"
        for i in "${!fields[@]}"; do
            local -n _col="_RRD_$i"
            _col+=("${v[i]-}")
            unset -n _col
        done
    done

    # One or two charts per row depending on the available width.
    local cols=1 cw
    (( CONTENT_W >= 100 )) && cols=2
    if (( cols == 1 )); then cw=$(( CONTENT_W - 3 )); else cw=$(( (CONTENT_W - 4) / 2 - 2 )); fi
    local -a pending=()
    local n=0
    for spec in "${specs[@]}"; do
        IFS='|' read -r -a parts <<< "$spec"
        local a="_RRD_${fidx[${parts[2]}]}" b=""
        [[ -n ${parts[3]-} ]] && b="_RRD_${fidx[${parts[3]}]}"
        chart "${parts[0]}" "$cw" "$RRD_HEIGHT" "${parts[1]}" "$a" "$b"
        if (( cols == 1 )); then
            for row in "${CHART[@]}"; do c_add " $row"; done
            c_blank
        else
            if (( n % 2 == 0 )); then
                pending=("${CHART[@]}")
            else
                for i in "${!CHART[@]}"; do
                    fit "${pending[i]-}" $(( cw + 2 ))
                    c_add " ${REPLY}${C[norm]}  ${CHART[i]}"
                done
                c_blank
                pending=()
            fi
        fi
        (( n++ ))
    done
    if (( ${#pending[@]} )); then
        for row in "${pending[@]}"; do c_add " $row"; done
        c_blank
    fi
}

# Shared key handler for summary panels: "t" cycles the graph timeframe.
summary_key() {
    if [[ $1 == t ]]; then
        rrd_cycle_timeframe
        content_load 1
        return 0
    fi
    return 1
}
