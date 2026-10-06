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
    local n sel old new=""
    local -a items=()
    plugins_scan
    for n in $(printf '%s\n' "${!PLUGIN_FILES[@]}" | sort); do
        [[ " ${CFG[plugins]} " == *" $n "* ]] && sel=on || sel=off
        items+=("$n" "${PLUGIN_DESC[$n]}" "$sel")
    done
    (( ${#items[@]} )) || { dlg_msg "Plugins" "No plugin found."; return; }
    dlg_checklist "Plugins" "Space: enable / disable a plugin. Enter: validate." "${items[@]}" || return
    for n in $REPLY; do new+="$n "; done
    new=${new% }
    old=$(printf '%s\n' ${CFG[plugins]} | sort | xargs)
    [[ $(printf '%s\n' $new | sort | xargs) == "$old" ]] && return
    core_save_config plugins "$new"
    # Plugins are loaded at start-up (they define panels and menus).
    if DLG_DEFAULT_YES=1 dlg_yesno "Plugins" "Restart pvetty now to apply the change? (the current selection is kept)"; then
        RESTART=1 RUNNING=0
    else
        T "The plugin change applies at the next start of pvetty"; status_msg info "$REPLY"
    fi
}
