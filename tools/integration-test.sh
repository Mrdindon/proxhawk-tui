#!/usr/bin/env bash
# integration-test.sh - read/write tests of every panel, run against the
# local Proxmox VE node through the real pvetty functions.
#
#   tools/integration-test.sh [section ...]      (default: all sections)
#   sections: access cluster firewall sdn acme node disks vm ct features storage ceph
#
# Dialogs are simulated (queued answers, forms submitted with FORM_PRESET),
# every write is verified by reading the API back, and every test object is
# removed afterwards. Objects are named "pvetty-test*" / "pvt*", guests use
# the VMIDs 9901-9919. THIS MODIFIES THE NODE: run it on a test system.
#
# Results: one line per check, summary at the end, full log in $LOG.
set -o pipefail
shopt -s extglob
PVETTY_HOME=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
for _m in core term theme glyphs i18n widgets api user content resources views rrd tasks dialog form crud choices taskviewer keys overlay queue plugins actions layout; do
    # shellcheck source=/dev/null
    source "$PVETTY_HOME/lib/$_m.sh"
done
core_load_config
core_init_rundir
LOG=${LOG:-/tmp/pvetty-integration.log}
: > "$LOG"
trap 'core_cleanup' EXIT
TCAP[colors]=256
i18n_load; glyphs_load; theme_load; chart_init; views_load
plugins_load
ROWS=50 COLS=160 CONTENT_W=100 CONTENT_H=40 TASK_H=8
CFG[confirm]=1
spinner_start() { :; }; spinner_stop() { :; }
layout_compute() { :; }
api_start
res_load
NODE=$LOCAL_NODE
TEST_VM=9901 TEST_CT=9911

# ---------------------------------------------------------------------------
# Simulated UI
# ---------------------------------------------------------------------------
declare -ga DLG_Q=()          # queued dialog answers ("__CANCEL" = cancel)
declare -ga TERM_CMDS=()      # commands run through term_run
_dq() { if (( ${#DLG_Q[@]} )); then REPLY=${DLG_Q[0]}; DLG_Q=("${DLG_Q[@]:1}"); return 0; fi; return 1; }
dlg_yesno() { echo "  [yesno] $1: $2" >> "$LOG"; if _dq; then [[ $REPLY == y* ]]; else return 0; fi; }
dlg_input() { echo "  [input] $1: $2" >> "$LOG"; _dq || REPLY=${3:-}; [[ $REPLY != __CANCEL ]]; }
dlg_password() { _dq || REPLY="Pvetty-Test-123"; [[ $REPLY != __CANCEL ]]; }
dlg_menu() {
    local t=$1 x=$2; shift 2
    echo "  [menu] $t: $x (${*:1:6}...)" >> "$LOG"
    if _dq; then [[ $REPLY != __CANCEL ]]; return; fi
    REPLY=$1
}
dlg_msg() { echo "  [msg] $1: $2" >> "$LOG"; LAST_MSG=$2; }
dlg_textbox() { echo "  [textbox] $1" >> "$LOG"; cat "$2" >> "$LOG" 2>/dev/null; LAST_TEXT=$(cat "$2" 2>/dev/null); }
pager_show() { echo "  [pager] $2" >> "$LOG"; LAST_TEXT=$(cat "$1" 2>/dev/null); }
term_run() { TERM_CMDS+=("$*"); echo "  [term] $*" >> "$LOG"; "$@" < /dev/null >> "$LOG" 2>&1; }
# Background jobs run synchronously so that results can be verified.
api_exec() { local d=$1; shift; api_exec_sync "$d" "$@"; }
# The task viewer is interactive: the tests wait for the task instead.
task_viewer() { echo "  [task viewer] $1" >> "$LOG"; task_wait "$1" "${2:-task}"; }
FORM_AUTO=1
API_WAIT_TASKS=1

# ---------------------------------------------------------------------------
# Test helpers
# ---------------------------------------------------------------------------
PASS=0 FAIL=0 SKIP=0 SECTION=""
declare -ga FAILS=()
section() { SECTION=$1; printf '\n== %s ==\n' "$1"; printf '\n== %s ==\n' "$1" >> "$LOG"; }
ok() { (( PASS++ )); printf '  PASS  %s\n' "$1"; echo "PASS $1" >> "$LOG"; }
ko() { (( FAIL++ )); FAILS+=("[$SECTION] $1: ${2-}"); printf '  FAIL  %s  -- %s\n' "$1" "${2-}"; echo "FAIL $1 -- ${2-}" >> "$LOG"; }
skip() { (( SKIP++ )); printf '  SKIP  %s  -- %s\n' "$1" "${2-}"; echo "SKIP $1 -- ${2-}" >> "$LOG"; }

# check <description> <command...>: PASS if the command succeeds.
check() { local d=$1; shift; if "$@" >> "$LOG" 2>&1; then ok "$d"; else ko "$d" "${API_ERR:-${STATUS_MSG:-command failed}}"; fi; }

# Prepare a step: context, form values and dialog answers.
ctx() { res_load >/dev/null 2>&1; select_ctx "$1"; }
select_ctx() { ctx_set "$1"; menu_load; }
preset() { FORM_PRESET=(); local kv; for kv; do FORM_PRESET[${kv%%=*}]=${kv#*=}; done; }
answers() { DLG_Q=("$@"); }
crud_answers() { CRUD_ANSWER=(); local kv; for kv; do CRUD_ANSWER[${kv%%=*}]=${kv#*=}; done; }
reset_step() { FORM_PRESET=(); DLG_Q=(); CRUD_ANSWER=(); STATUS_MSG=""; STATUS_LVL=none; API_ERR=""; }

# view <menu id>: render a panel of the current context (read test).
view() {
    local i
    for i in "${!M_ID[@]}"; do [[ ${M_ID[i]} == "$1" ]] && MENU_CUR=$i; done
    content_load > /dev/null 2> "$RUN_DIR/view.err"
    [[ ! -s $RUN_DIR/view.err && ${M_ID[MENU_CUR]} == "$1" ]]
}
# Row key of the content panel matching a pattern.
# shellcheck disable=SC2053  # $1 is a glob pattern on purpose
rowkey() { local k; for k in "${C_SELK[@]}"; do [[ $k == $1 ]] && { REPLY=$k; return 0; }; done; REPLY=""; return 1; }
# key <KEY> <row key>: press a key on a row like the main loop does.
# The step fails when the key is not handled or when an API call failed
# (status message "err" or API error of a form).
key() {
    local k=$1 rk=${2-} handled=1
    STATUS_LVL=none API_ERR=""
    if declare -F "${VIEW_FN}__key" >/dev/null && "${VIEW_FN}__key" "$k" "$rk"; then handled=0
    elif crud_has "$VIEW_FN" && crud_key "$VIEW_FN" "$k" "$rk"; then handled=0
    fi
    (( handled == 0 )) || { API_ERR="key '$k' not handled"; return 1; }
    [[ $STATUS_LVL != err ]]
}
enter() {
    STATUS_LVL=none API_ERR=""
    if declare -F "${VIEW_FN}__enter" >/dev/null; then "${VIEW_FN}__enter" "$1"
    else crud_enter "$VIEW_FN" "$1"
    fi
    [[ $STATUS_LVL != err ]]
}

# API assertions.
api_has() {     # api_has <path> <field> <value> [query]
    api_get rows "$1" "${4:-}" "$2" || return 1
    printf '%s\n' "${API_ROWS[@]}" | grep -qxF -- "$3"
}
api_lacks() { ! api_has "$@"; }
kv_is() {       # kv_is <path> <key> <value>   (trailing newlines ignored)
    api_kv "$1" || return 1
    local v=${API_KV[$2]-}; v=${v%%+($'\x1f')}
    [[ $v == "$3" ]] || { API_ERR="$2='${API_KV[$2]-}' (expected '$3')"; return 1; }
}
kv_like() {     # kv_like <path> <key> <glob>
    api_kv "$1" || return 1
    # shellcheck disable=SC2053
    [[ ${API_KV[$2]-} == $3 ]] || { API_ERR="$2='${API_KV[$2]-}' (expected $3)"; return 1; }
}
# Last task of the node with a given type/id finished OK.
task_ok() {
    api_get rows "/nodes/$NODE/tasks" "limit=20${2:+&vmid=$2}" "type,status" || return 1
    local row; for row in "${API_ROWS[@]}"; do
        [[ ${row%%$'\t'*} == "$1" ]] && { [[ ${row#*$'\t'} == OK ]] && return 0; API_ERR="task $1: ${row#*$'\t'}"; return 1; }
    done
    API_ERR="no task $1"; return 1
}
wait_for() {    # wait_for <seconds> <command...>
    local t=$1 i; shift
    for (( i = 0; i < t; i++ )); do "$@" >/dev/null 2>&1 && return 0; sleep 1; done
    return 1
}
EDITOR_SCRIPT="$RUN_DIR/editor.sh"
editor_writes() {  # the next "editor" run writes this text
    printf '%s' "$1" > "$RUN_DIR/editor.content"
    printf '#!/bin/sh\ncp "%s" "$1"\n' "$RUN_DIR/editor.content" > "$EDITOR_SCRIPT"; chmod +x "$EDITOR_SCRIPT"
    CFG[editor]=$EDITOR_SCRIPT
}

# Sections are defined in tools/integration/*.sh
for _f in "$PVETTY_HOME"/tools/integration/*.sh; do
    # shellcheck source=/dev/null
    source "$_f"
done

# Ad-hoc commands with the test environment: --eval 'commands'
if [[ ${1-} == --eval ]]; then eval "$2"; exit; fi

ALL_SECTIONS=(access cluster firewall sdn acme node disks vm ct features storage ceph)
sections=("$@")
(( ${#sections[@]} )) || sections=("${ALL_SECTIONS[@]}")
for s in "${sections[@]}"; do
    declare -F "test_$s" >/dev/null || { echo "unknown section: $s"; continue; }
    section "$s"
    reset_step
    "test_$s"
done

printf '\n== Summary ==\n  %d passed, %d failed, %d skipped (log: %s)\n' "$PASS" "$FAIL" "$SKIP" "$LOG"
for f in "${FAILS[@]}"; do printf '  - %s\n' "$f"; done
(( FAIL == 0 ))
