#!/usr/bin/env bash
# screen-test.sh - golden screen tests: runs proxhawk-tui in a detached tmux
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
#   <name>@<code> ...           the same in a language (fr, de, zh_CN...)
#   <name>%sys|%256|%512 ...    Linux console mode (font of Debian / ours)
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
SESSION=proxhawk-tui-screen-$$
trap 'tmux kill-session -t "$SESSION" 2>/dev/null; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/config/proxhawk-tui" "$TMP/state"
cat > "$TMP/config/proxhawk-tui/proxhawk-tui.conf" <<'EOF'
glyphs = unicode
theme = default
dialog = builtin
language = en
onboarding = 0
refresh = 0
ip_column = 0
ask_user = 0
EOF

# Screen content once it stopped changing (proxhawk-tui loads asynchronously).
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
    local name=$1 k lang=en; shift
    # name@code: the scenario in another language (the translations of the
    # Proxmox VE catalog installed on this node are used too).
    [[ $name == *@* ]] && lang=${name#*@}
    lang=${lang%%%*}
    local -a env=(env XDG_CONFIG_HOME="$TMP/config" XDG_STATE_HOME="$TMP/state"
                  TZ=UTC LANG=C.UTF-8 LC_ALL=C.UTF-8 TERM=xterm-256color COLORTERM=
                  PROXHAWK_TUI_LANGUAGE="$lang")
    # name%sys / name%256 / name%512: the Linux console mode, with the
    # characters of the default Debian console font or of our fonts.
    if [[ $name == *%* ]]; then
        local map="$DIR/console/debian-lat15-fixed16.map" f=${name##*%}
        if [[ $f != sys ]]; then
            map="$TMP/console-$f.map"
            zcat "$ROOT/fonts/proxhawk-$f.psf.gz" > "$TMP/console-$f.psf" && psfgettable "$TMP/console-$f.psf" "$map" > /dev/null 2>&1
        fi
        env+=(PROXHAWK_TUI_CONSOLE=1 PROXHAWK_TUI_CONSOLE_MAP="$map")
    fi
    if [[ $MODE == record ]]; then
        env+=(PROXHAWK_TUI_RECORD="$FIX")
    else
        env+=(PROXHAWK_TUI_REPLAY="$FIX" PROXHAWK_TUI_NOW="$(< "$FIX/now")")
    fi
    local -a cmd=("${env[@]}" "$ROOT/proxhawk-tui")
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
