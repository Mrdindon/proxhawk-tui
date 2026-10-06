#!/usr/bin/env bash
# selftest.sh - render every view of every resource type without the UI and
# report errors and timings. Useful after modifying a view module.
#   tools/selftest.sh [resource id ...]     (default: one resource per type)
set -o pipefail
shopt -s extglob
PVETTY_HOME=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
for _m in core term theme glyphs i18n widgets api user content resources views rrd tasks dialog form crud choices taskviewer keys overlay queue plugins actions layout; do
    source "$PVETTY_HOME/lib/$_m.sh"
done
core_load_config
core_init_rundir
trap 'core_cleanup' EXIT
TCAP[colors]=256
i18n_load; glyphs_load; theme_load; chart_init; views_load
plugins_load
ROWS=50 COLS=160; CFG[task_rows]=5
layout_compute() { :; }
CONTENT_W=100 CONTENT_H=40 TASK_H=8
spinner_start() { :; }; spinner_stop() { :; }
api_start
res_load || { echo "res_load failed: $API_ERR"; exit 1; }
ids=("$@")
if (( ${#ids[@]} == 0 )); then
    ids=(root)
    declare -A seen=()
    for id in "${RES_IDS[@]}"; do
        t=${R_TYPE[$id]}
        [[ -n ${seen[$t]-} ]] && continue
        seen[$t]=1; ids+=("$id")
    done
fi
fail=0
for id in "${ids[@]}"; do
    ctx_set "$id"; menu_load
    for i in "${!M_ID[@]}"; do
        MENU_CUR=$i
        fn="v_${CTX_TYPE}_${M_ID[i]}"
        start=$EPOCHREALTIME
        err=$( { content_load >/dev/null; } 2>&1 )
        content_load >/dev/null 2>&1
        ms=$(( (${EPOCHREALTIME/./} - ${start/./}) / 1000 / 2 ))
        status=ok
        declare -F "$fn" >/dev/null || status="missing"
        [[ -n $err ]] && { status="STDERR"; fail=1; }
        printf '%-28s %-34s %6d ms %4d lines  %s\n' "$id" "$fn" "$ms" "${#C_LINES[@]}" "$status"
        [[ -n $err ]] && printf '    %s\n' "${err//$'\n'/$'\n'    }"
    done
done
exit $fail
