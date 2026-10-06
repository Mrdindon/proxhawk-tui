# shellcheck shell=bash
# keys.sh - configurable key bindings of the global actions.
#
# Each action has one or more keys (space separated). They can be changed in
# the configuration file:   key.<action> = <keys>      e.g.  key.help = F1 ?
# Key names: letters / symbols as typed, F1..F12, C-x (Ctrl+x), M-x (Alt+x),
# ENTER, ESC, TAB, SPACE, DEL, INS. Navigation keys (arrows, Tab, PgUp...)
# and panel keys (toolbars, panel buttons) are not remapped.

declare -gA KEYMAP=(
    [help]="F1 ?"           [search]="/"            [refresh]="r F5"
    [quit]="q F10"          [view]="v"              [tasklog]="l"
    [create_vm]="F2 V"      [create_ct]="F3 C"      [user_menu]="F4 U"
    [auto_refresh]="F6"     [docs]="F7"
)
# Order and labels used by the help window.
KEY_ACTIONS=(help docs search refresh auto_refresh view tasklog create_vm create_ct user_menu quit)
declare -gA KEY_LABELS=(
    [help]="Help (keys of the current panel)" [docs]="Documentation (user guide)"
    [search]="Search / filter resources" [refresh]="Refresh now"
    [auto_refresh]="Pause / resume the automatic refresh" [view]="Cycle the tree view"
    [tasklog]="Switch Tasks / Cluster log" [create_vm]="Create VM" [create_ct]="Create CT"
    [user_menu]="User menu and settings" [quit]="Quit"
)
declare -gA KEY_TO_ACTION=()

keys_load() {
    local k a
    for k in "${!CFGX[@]}"; do
        [[ $k == key.* ]] || continue
        a=${k#key.}
        [[ -v KEYMAP[$a] ]] && KEYMAP[$a]=${CFGX[$k]}
    done
    KEY_TO_ACTION=()
    for a in "${!KEYMAP[@]}"; do
        for k in ${KEYMAP[$a]}; do KEY_TO_ACTION[$k]=$a; done
    done
}

# Global action of a key (REPLY, rc 1 if none).
key_action() {
    REPLY=${KEY_TO_ACTION[$1]-}
    [[ -n $REPLY ]]
}

# First key of an action, for display ("F1").
key_of() { REPLY=${KEYMAP[$1]%% *}; }
