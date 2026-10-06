# shellcheck shell=bash
# onboarding.sh - first run wizard (no user configuration file yet): icon
# set (with a preview), theme, mouse. The answers are saved in
# ~/.config/pvetty/pvetty.conf, so the wizard is shown only once.

onboarding_run() {
    [[ ${CFG[onboarding]} == 1 ]] && core_first_run || return 0
    local pn pu th f
    local DLG_DEFAULT_YES=1
    T "Welcome to pvetty, the text console of Proxmox VE. A few questions to adapt it to your terminal (they can be changed later with F4)."
    dlg_yesno "pvetty" "$REPLY"$'\n\n'"$(T "Configure now? (No = keep the defaults)"; printf '%s' "$REPLY")" || { core_save_config onboarding 0; return 0; }
    printf -v pn '       '
    pu="▦ ▣ ▭ ◈ ◫ ◇ ◉ ›"
    if dlg_menu "Icons" "Which line shows icons and not squares? (the icons are drawn by the font of your terminal)" \
        unicode "Unicode     $pu" nerd "Nerd Font   $pn" ascii "ASCII       D N V C S P o \$" none "$(T "No icons"; printf '%s' "$REPLY")"; then
        if [[ $REPLY == none ]]; then core_save_config icons 0; else core_save_config glyphs "$REPLY"; fi
    fi
    local -a items=()
    for f in "$PVETTY_HOME"/themes/*.sh; do f=${f##*/}; items+=("${f%.sh}" ""); done
    if dlg_menu "Theme" "Colour theme (default and basic keep the colours of your terminal):" "${items[@]}"; then
        core_save_config theme "$REPLY"
    fi
    if dlg_yesno "Mouse" "Enable the mouse? (click, double click, wheel; hold Shift to select text)"; then
        core_save_config mouse 1
    else
        core_save_config mouse 0
    fi
    core_save_config onboarding 0
    glyphs_load; theme_load; chart_init
}
