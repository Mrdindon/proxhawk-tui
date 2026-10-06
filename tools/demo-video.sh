#!/usr/bin/env bash
# demo-video.sh - make the demo video of the README: plays a storyboard in
# pvetty (detached tmux session, recorded API answers) and renders the
# screens to an MP4 with tools/render-video.py.
#
#   tools/demo-video.sh [output.mp4|.gif]     (default: docs/demo.mp4)
#   tools/demo-video.sh --record DIR          record the API answers of the
#                                             storyboard on this node into DIR
#
# Storyboard (tests/demo/storyboard), one step per line:
#   <seconds> <key> [key...]     keys as "tmux send-keys" names; the screen
#                                after the last key is shown <seconds>
#   type:<text>                  as a key: types the text one letter at a time
# The fixture (tests/demo/fixture) holds demo data only: a recording made on
# a real node must be anonymised before it is copied there.
# Rendering needs Python with Pillow and imageio-ffmpeg (development only):
#   python3 -m venv /tmp/v && /tmp/v/bin/pip install pillow imageio-ffmpeg
#   PYTHON=/tmp/v/bin/python tools/demo-video.sh
set -u
cd "$(dirname "$0")/.." || exit 1
ROOT=$PWD
W=${DEMO_COLS:-120} H=${DEMO_ROWS:-38}
FIX=$ROOT/tests/demo/fixture
OUT=$ROOT/docs/demo.mp4
RECORD=""
case ${1-} in
    --record) RECORD=$2 ;;
    ?*) OUT=$1 ;;
esac
PYTHON=${PYTHON:-python3}

TMP=$(mktemp -d)
SESSION=pvetty-demo-$$
trap 'tmux kill-session -t "$SESSION" 2>/dev/null; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/config/pvetty" "$TMP/state" "$TMP/frames"
cat > "$TMP/config/pvetty/pvetty.conf" <<'EOF'
glyphs = nerd
theme = default
dialog = builtin
language = en
onboarding = 0
refresh = 0
ip_column = 0
EOF

# Screen once it stopped changing.
# (unchanged during 0.6 s: the menu selection is applied after 150 ms)
settle() {
    local prev="" cur i same=0
    for (( i = 0; i < 80; i++ )); do
        sleep 0.15
        cur=$(tmux capture-pane -p -e -t "$SESSION")
        if [[ $cur == "$prev" && -n $cur ]]; then (( ++same >= 4 )) && break; else same=0; fi
        prev=$cur
    done
}
N=0
frame() {   # frame <seconds>: current screen (with colours) shown <seconds>
    local f; printf -v f '%05d.ans' "$N"; (( N++ ))
    tmux capture-pane -p -e -t "$SESSION" > "$TMP/frames/$f"
    printf '%s %s\n' "$f" "$1" >> "$TMP/frames/list"
}

env=(env XDG_CONFIG_HOME="$TMP/config" XDG_STATE_HOME="$TMP/state" TZ=UTC
     LANG=C.UTF-8 LC_ALL=C.UTF-8 TERM=xterm-256color COLORTERM= NERD_FONT=1)
if [[ -n $RECORD ]]; then
    rm -rf "$RECORD"; mkdir -p "$RECORD"
    printf '%(%s)T' -1 > "$RECORD/now"
    env+=(PVETTY_RECORD="$RECORD")
    cmd=("${env[@]}" "$ROOT/pvetty")
else
    env+=(PVETTY_REPLAY="$FIX" PVETTY_NOW="$(< "$FIX/now")")
    cmd=("${env[@]}" "$ROOT/pvetty" --backend replay)
fi
tmux new-session -d -s "$SESSION" -x "$W" -y "$H" "$(printf '%q ' "${cmd[@]}")"
# Wait for the first complete screen (the API helper loads first).
for (( i = 0; i < 100; i++ )); do
    tmux capture-pane -p -t "$SESSION" | grep -q "Tasks" && break
    sleep 0.2
done
settle

while read -r hold keys; do
    [[ -z $hold || $hold == \#* ]] && continue
    for k in $keys; do
        if [[ $k == type:* ]]; then
            local_text=${k#type:}
            for (( i = 0; i < ${#local_text}; i++ )); do
                tmux send-keys -t "$SESSION" -l "${local_text:i:1}"; settle; frame 0.12
            done
        else
            tmux send-keys -t "$SESSION" "$k"; settle
            [[ -n $RECORD ]] || frame 0.35
        fi
    done
    [[ -n $RECORD ]] || frame "$hold"
done < "$ROOT/tests/demo/storyboard"

if [[ -n $RECORD ]]; then
    sort -u -o "$RECORD/index" "$RECORD/index"
    echo "recorded in $RECORD (anonymise it before copying it to tests/demo/fixture)"
    exit 0
fi
grep -l "not recorded" "$TMP"/frames/*.ans >/dev/null && echo "warning: some answers are not recorded" >&2
mkdir -p "$(dirname "$OUT")"
"$PYTHON" "$ROOT/tools/render-video.py" "$TMP/frames" "$OUT" "$W" "$H"
