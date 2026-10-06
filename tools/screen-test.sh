#!/usr/bin/env bash
# screen-test.sh - golden screen tests: runs pvetty in a detached tmux
# session on recorded API answers (backend "replay"), sends the keys of each
# scenario and compares the screen with tests/screens/golden/<name>.txt.
#
#   tools/screen-test.sh [run] [name...]   compare (default)
#   tools/screen-test.sh update [name...]  rewrite the golden files
#   tools/screen-test.sh record            record the API answers on this node
#                                          (read only), then update the goldens
#
# Scenarios: tests/screens/scenarios, one per line:
#   <name> <key> <key>...       keys as accepted by "tmux send-keys"
#                               (Down, Enter, Tab, F1, Escape, q, ...)
# Lines starting with # are comments. The fixture (tests/screens/fixture)
# is a snapshot of a real node: re-record it when the API usage changes
# (a missing answer shows as "not recorded: ..." on the screen).
set -u
cd "$(dirname "$0")/.." || exit 1
ROOT=$PWD
DIR=$ROOT/tests/screens
FIX=$DIR/fixture GOLD=$DIR/golden
W=120 H=36
MODE=run
case ${1-} in run|update|record) MODE=$1; shift ;; esac
WANT=("$@")

TMP=$(mktemp -d)
SESSION=pvetty-screen-$$
trap 'tmux kill-session -t "$SESSION" 2>/dev/null; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/config/pvetty" "$TMP/state"
cat > "$TMP/config/pvetty/pvetty.conf" <<'EOF'
glyphs = unicode
theme = default
dialog = builtin
language = en
onboarding = 0
refresh = 0
ip_column = 0
EOF

# Screen content once it stopped changing (pvetty loads asynchronously).
capture() {
    local prev="" cur i
    for (( i = 0; i < 50; i++ )); do
        sleep 0.2
        cur=$(tmux capture-pane -p -t "$SESSION")
        [[ $cur == "$prev" && -n $cur ]] && break
        prev=$cur
    done
    printf '%s\n' "$cur"
}

# run_scenario <name> <keys...>  -> screen on stdout
run_scenario() {
    local name=$1 k; shift
    local -a env=(env XDG_CONFIG_HOME="$TMP/config" XDG_STATE_HOME="$TMP/state"
                  TZ=UTC LANG=C.UTF-8 LC_ALL=C.UTF-8 TERM=xterm-256color COLORTERM=)
    if [[ $MODE == record ]]; then
        env+=(PVETTY_RECORD="$FIX")
    else
        env+=(PVETTY_REPLAY="$FIX" PVETTY_NOW="$(< "$FIX/now")")
    fi
    local -a cmd=("${env[@]}" "$ROOT/pvetty")
    [[ $MODE == record ]] || cmd+=(--backend replay)
    tmux new-session -d -s "$SESSION" -x "$W" -y "$H" "$(printf '%q ' "${cmd[@]}")"
    capture > /dev/null
    for k in "$@"; do
        tmux send-keys -t "$SESSION" "$k"
        capture > /dev/null
    done
    capture
    tmux kill-session -t "$SESSION" 2>/dev/null
}

mapfile -t LINES < <(grep -v '^[[:space:]]*\(#\|$\)' "$DIR/scenarios")

if [[ $MODE == record ]]; then
    rm -rf "$FIX"; mkdir -p "$FIX"
    printf '%(%s)T' -1 > "$FIX/now"
    for line in "${LINES[@]}"; do
        read -r -a a <<< "$line"
        printf 'record %s\n' "${a[0]}"
        run_scenario "${a[@]}" > /dev/null
    done
    sort -u -o "$FIX/index" "$FIX/index"
    MODE=update
fi

mkdir -p "$GOLD"
pass=0 fail=0
for line in "${LINES[@]}"; do
    read -r -a a <<< "$line"
    name=${a[0]}
    if (( ${#WANT[@]} )) && [[ " ${WANT[*]} " != *" $name "* ]]; then continue; fi
    run_scenario "${a[@]}" > "$TMP/$name.txt"
    if [[ $MODE == update ]]; then
        cp "$TMP/$name.txt" "$GOLD/$name.txt"; printf 'updated %s\n' "$name"
    elif diff -u "$GOLD/$name.txt" "$TMP/$name.txt" > "$TMP/$name.diff"; then
        (( pass++ )); printf 'ok   %s\n' "$name"
    else
        (( fail++ )); printf 'FAIL %s\n' "$name"; sed 's/^/     /' "$TMP/$name.diff"
    fi
done
[[ $MODE == update ]] && exit 0
printf '%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
