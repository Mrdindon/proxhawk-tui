# shellcheck shell=bash
# plugins.sh - optional extensions, disabled by default.
#
# A plugin is a bash file loaded after the views, from
#   $PVETTY_HOME/plugins/<name>.sh   or   ~/.config/pvetty/plugins/<name>.sh
# when <name> is listed in the "plugins" setting (F4 > Plugins). Its first
# lines describe it:
#   # plugin: <name>
#   # description: <one line>
# A plugin uses the same API as the views (view_menu, crud, v_<type>_<id>,
# VIEW_HINT...) plus:
#   menu_extend <type> "id|Label|icon|level"   add an entry to a menu
#   toolbar_extend <type> <function>           function adding toolbar buttons

declare -gA PLUGIN_FILES=() PLUGIN_DESC=()

plugins_scan() {
    local f n d
    PLUGIN_FILES=() PLUGIN_DESC=()
    for f in "$PVETTY_HOME"/plugins/*.sh "${XDG_CONFIG_HOME:-$HOME/.config}"/pvetty/plugins/*.sh; do
        [[ -r $f ]] || continue
        n=$(sed -n 's/^# plugin: *//p' "$f" | head -1); [[ -n $n ]] || n=$(basename "$f" .sh)
        d=$(sed -n 's/^# description: *//p' "$f" | head -1)
        PLUGIN_FILES[$n]=$f PLUGIN_DESC[$n]=$d
    done
}

plugins_load() {
    local n
    plugins_scan
    for n in ${CFG[plugins]}; do
        if [[ -n ${PLUGIN_FILES[$n]-} ]]; then
            # shellcheck source=/dev/null
            source "${PLUGIN_FILES[$n]}"
            log "plugin loaded: $n"
        else
            log "plugin not found: $n"
        fi
    done
}

plugins_dialog() {
    local n on
    plugins_scan
    while :; do
        local -a items=()
        for n in $(printf '%s\n' "${!PLUGIN_FILES[@]}" | sort); do
            [[ " ${CFG[plugins]} " == *" $n "* ]] && on="[x]" || on="[ ]"
            items+=("$n" "$on ${PLUGIN_DESC[$n]}")
        done
        (( ${#items[@]} )) || { dlg_msg "Plugins" "No plugin found."; return; }
        T "Plugins"
        dlg_menu "$REPLY" "$(T "Enter toggles a plugin. Changes apply after restarting pvetty."; printf '%s' "$REPLY")" "${items[@]}" || break
        n=$REPLY
        if [[ " ${CFG[plugins]} " == *" $n "* ]]; then
            on=" ${CFG[plugins]} "; on=${on/ $n / }
        else
            on="${CFG[plugins]} $n"
        fi
        on=${on#"${on%%[! ]*}"}; on=${on%"${on##*[! ]}"}
        core_save_config plugins "$on"
    done
}
