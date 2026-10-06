# shellcheck shell=bash
# glyphs.sh - icon / box drawing sets. Three sets are available:
#   nerd     Nerd Font (Font Awesome code points, the same icons as the web UI)
#   unicode  plain Unicode (box drawing, geometric shapes, braille charts)
#   ascii    7-bit fallback for limited terminals
# Every set defines the same keys in the associative array G.

declare -gA G=()
GLYPH_SET=""
UTF8=0

# Nerd Font icons as hexadecimal code points (Font Awesome 4 range, as in PVE).
declare -gA _NERD=(
    [dc]=f233 [node]=f1ad [qemu]=f108 [lxc]=f1b2 [storage]=f1c0 [pool]=f02c
    [tmpl]=f016 [sdn]=f00a [folder]=f07b [tag]=f02b
    [lock]=f023 [ha]=f21e
    [btn_start]=f04b [btn_shutdown]=f011 [btn_stop]=f04d [btn_reboot]=f021
    [btn_console]=f120 [btn_shell]=f120 [btn_more]=f142 [btn_bulk]=f0ae
    [btn_pause]=f04c [btn_create]=f055 [btn_edit]=f040 [btn_remove]=f1f8
    [search]=f002 [docs]=f02d [user]=f007 [refresh]=f021 [help]=f059
    [m_search]=f002 [m_summary]=f02d [m_notes]=f249 [m_cluster]=f233
    [m_ceph]=f1c0 [m_options]=f013 [m_storage]=f1c0 [m_backup]=f0c7
    [m_replication]=f079 [m_permissions]=f09c [m_users]=f007 [m_tokens]=f2c1
    [m_tfa]=f084 [m_groups]=f0c0 [m_pools]=f02c [m_roles]=f183 [m_realms]=f2ba
    [m_ha]=f21e [m_sdn]=f00a [m_zones]=f009 [m_vnets]=f0e8 [m_acme]=f0a3
    [m_firewall]=f132 [m_metric]=f080 [m_mapping]=f277 [m_notify]=f0a2
    [m_support]=f1cd [m_shell]=f120 [m_system]=f085 [m_network]=f0ec
    [m_cert]=f0a3 [m_dns]=f0ac [m_hosts]=f0f6 [m_time]=f017 [m_syslog]=f022
    [m_services]=f085 [m_updates]=f021 [m_repos]=f0c5 [m_disks]=f0a0
    [m_lvm]=f0c8 [m_lvmthin]=f096 [m_dir]=f07b [m_zfs]=f009 [m_tasks]=f03a
    [m_subscription]=f1cd [m_console]=f120 [m_hardware]=f108 [m_cloudinit]=f0c2
    [m_monitor]=f06e [m_snapshot]=f1da [m_resources]=f1b2 [m_content]=f016
    [m_iso]=f192 [m_vztmpl]=f016 [m_images]=f0a0 [m_rootdir]=f0a0
    [m_snippets]=f1c9 [m_import]=f0ed [m_members]=f0c0 [m_backups]=f0c7
)

# Plain Unicode set: only narrow (single cell) characters.
declare -gA _UNICODE=(
    [dc]="▦" [node]="▣" [qemu]="▭" [lxc]="◈" [storage]="◫" [pool]="◇"
    [tmpl]="▯" [sdn]="⌗" [folder]="▪" [tag]="#"
    [lock]="⊘" [ha]="♥"
    [btn_start]="▶" [btn_shutdown]="◉" [btn_stop]="■" [btn_reboot]="↻"
    [btn_console]="›" [btn_shell]="›" [btn_more]="⋮" [btn_bulk]="≡"
    [btn_pause]="‖" [btn_create]="+" [btn_edit]="✎" [btn_remove]="✕"
    [search]="⌕" [docs]="?" [user]="@" [refresh]="↻" [help]="?"
    [m_search]="⌕" [m_summary]="≣" [m_notes]="✎" [m_cluster]="⁂" [m_ceph]="◎"
    [m_options]="≡" [m_storage]="◫" [m_backup]="⇩" [m_replication]="⇄"
    [m_permissions]="⊡" [m_users]="○" [m_tokens]="⊸" [m_tfa]="⊶" [m_groups]="∞"
    [m_pools]="◇" [m_roles]="◌" [m_realms]="⊞" [m_ha]="♥" [m_sdn]="⌗"
    [m_zones]="⊞" [m_vnets]="⋔" [m_acme]="✓" [m_firewall]="▥" [m_metric]="▁"
    [m_mapping]="↦" [m_notify]="◔" [m_support]="⊕" [m_shell]="›" [m_system]="⚙"
    [m_network]="⇄" [m_cert]="✓" [m_dns]="◍" [m_hosts]="≣" [m_time]="◷"
    [m_syslog]="≣" [m_services]="◎" [m_updates]="↻" [m_repos]="⊟" [m_disks]="▤"
    [m_lvm]="▢" [m_lvmthin]="▫" [m_dir]="▪" [m_zfs]="⊞" [m_tasks]="≣"
    [m_subscription]="⊕" [m_console]="›" [m_hardware]="▭" [m_cloudinit]="☁"
    [m_monitor]="◉" [m_snapshot]="◷" [m_resources]="◈" [m_content]="▯"
    [m_iso]="◎" [m_vztmpl]="▯" [m_images]="▤" [m_rootdir]="▤" [m_snippets]="✎"
    [m_import]="⇩" [m_members]="∞" [m_backups]="⇩"
)

glyphs_load() {
    local set=${CFG[glyphs]} k
    [[ ${LC_ALL:-${LC_CTYPE:-${LANG:-}}} =~ [Uu][Tt][Ff]-?8 ]] && UTF8=1
    if [[ $set == auto ]]; then
        if (( ! UTF8 )); then set=ascii
        elif [[ -n ${NERD_FONT:-} && ${NERD_FONT} != 0 ]]; then set=nerd
        else set=unicode
        fi
    fi
    (( UTF8 )) || set=ascii
    GLYPH_SET=$set

    if [[ $set == ascii ]]; then
        G=(
            [h]="-" [v]="|" [tl]="+" [tr]="+" [bl]="+" [br]="+"
            [tee_l]="+" [tee_r]="+" [tee_t]="+" [tee_b]="+" [cross]="+" [vsep]="|"
            [exp_open]="v" [exp_closed]=">" [caret]="v" [bullet]="*" [ellipsis]="~"
            [st_running]="+" [st_stopped]="-" [st_paused]="=" [st_unknown]="?"
            [st_online]="+" [st_offline]="x" [st_ok]="+" [st_err]="!"
            [bar_full]="#" [bar_empty]="." [scroll]="#"
            [dc]="D" [node]="N" [qemu]="V" [lxc]="C" [storage]="S" [pool]="P"
            [tmpl]="T" [sdn]="Z" [folder]="F" [tag]="#" [lock]="L" [ha]="H"
            [btn_start]=">" [btn_shutdown]="o" [btn_stop]="#" [btn_reboot]="@"
            [btn_console]="$" [btn_shell]="$" [btn_more]=":" [btn_bulk]="=" [btn_pause]="|"
            [btn_create]="+" [btn_edit]="e" [btn_remove]="x"
            [search]="/" [docs]="?" [user]="@" [refresh]="@" [help]="?"
        )
        BAR_PARTS=("" "" "" "" "" "" "" "")
        SPINNER=('|' '/' '-' '\')
        glyphs_icons_off
        return
    fi

    # Common Unicode drawing characters (also used by the nerd set).
    G=(
        [h]="─" [v]="│" [tl]="╭" [tr]="╮" [bl]="╰" [br]="╯"
        [tee_l]="├" [tee_r]="┤" [tee_t]="┬" [tee_b]="┴" [cross]="┼" [vsep]="│"
        [exp_open]="▾" [exp_closed]="▸" [caret]="▾" [bullet]="•" [ellipsis]="…"
        [st_running]="●" [st_stopped]="○" [st_paused]="◐" [st_unknown]="?"
        [st_online]="●" [st_offline]="✕" [st_ok]="✔" [st_err]="✖"
        [bar_full]="█" [bar_empty]="░" [scroll]="▐"
    )
    # Eighths of a block, used for smooth progress bars.
    BAR_PARTS=("" "▏" "▎" "▍" "▌" "▋" "▊" "▉")
    # Braille spinner.
    SPINNER=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

    for k in "${!_UNICODE[@]}"; do G[$k]=${_UNICODE[$k]}; done
    if [[ $set == nerd ]]; then
        for k in "${!_NERD[@]}"; do printf -v "G[$k]" "\\u${_NERD[$k]}"; done
    fi
    glyphs_icons_off
}

# icons = 0: no decorative icons (menus, buttons, header); the objects of the
# tree keep a coloured bullet so that their status stays visible.
glyphs_icons_off() {
    [[ ${CFG[icons]:-1} == 0 ]] || return 0
    local k
    for k in "${!G[@]}"; do
        case $k in
            m_*|btn_*|search|docs|user|refresh|help|tag) G[$k]="" ;;
            dc|node|qemu|lxc|storage|pool|tmpl|sdn|folder) G[$k]=${G[bullet]} ;;
        esac
    done
}
