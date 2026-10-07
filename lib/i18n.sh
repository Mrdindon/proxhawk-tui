# shellcheck shell=bash
# i18n.sh - minimal gettext-like translation layer.
#
# Source strings are written in English directly in the code and used as
# lookup keys:  T "Start"        -> REPLY="Start" (or its translation)
#               Tf "VM %s" 100   -> REPLY="VM 100" (format string translated)
# Translations of a language <code>, by priority:
#   1. lang/<code>.sh                     strings of proxhawk-tui (array L)
#   2. /usr/share/pve-i18n/pve-lang-<code>.js
#                                         the official catalog of the Proxmox
#                                         VE web interface (same words as the
#                                         GUI, read by lib/i18n-pve.pl)
#   3. English
# Language: setting "language" (or --lang); with "auto", the locale
# (LC_ALL, LC_MESSAGES, LANG) when it is not English, else the language of
# the datacenter (Datacenter > Options > Language), else English.

declare -gA L=()
LANG_CODE=en
LANG_NAME=English
DATE_FMT='%Y-%m-%d %H:%M:%S'
DATE_SHORT='%b %d %H:%M:%S'
PVE_I18N_DIR=${PVE_I18N_DIR:-/usr/share/pve-i18n}

# Languages of the Proxmox VE web interface (code -> name for the menu).
# Right-to-left scripts show the English name: terminals do not lay them out.
declare -gA LANG_NAMES=(
    [ar]="Arabic" [bg]="Български - Bulgarian" [ca]="Català - Catalan" [cs]="Čeština - Czech"
    [da]="Dansk - Danish" [de]="Deutsch - German" [el_GR]="Ελληνικά - Greek" [en]="English"
    [es]="Español - Spanish" [eu]="Euskera - Basque" [fa]="Persian (Farsi)" [fr]="Français - French"
    [ga]="Gaeilge - Irish" [gl]="Galego - Galician" [he]="Hebrew" [hr]="Hrvatski - Croatian"
    [hu]="Magyar - Hungarian" [it]="Italiano - Italian" [ja]="日本語 - Japanese" [ka]="ქართული - Georgian"
    [ko]="한국어 - Korean" [lo]="ລາວ - Lao" [nb]="Bokmål - Norwegian (Bokmål)" [nl]="Nederlands - Dutch"
    [nn]="Nynorsk - Norwegian (Nynorsk)" [pl]="Polski - Polish" [pt_BR]="Português Brasileiro - Portuguese (Brazil)"
    [ru]="Русский - Russian" [sl]="Slovenščina - Slovenian" [sv]="Svenska - Swedish" [tr]="Türkçe - Turkish"
    [ukr]="Українська - Ukrainian" [zh_CN]="中文（简体）- Chinese (Simplified)" [zh_TW]="中文（繁體）- Chinese (Traditional)"
)

# Language code available for a locale or a code (fr_CA.UTF-8 -> fr,
# zh_CN.UTF-8 -> zh_CN): REPLY, rc 1 when nothing exists for it.
_i18n_resolve() {
    local v=${1%%[.@]*} c
    [[ $v == ko* ]] && v=ko
    for c in "$v" "${v%%_*}"; do
        [[ -n $c ]] || continue
        if [[ $c == en || -r $PROXHAWK_TUI_HOME/lang/$c.sh || -r $PVE_I18N_DIR/pve-lang-$c.js ]]; then
            REPLY=$c; return 0
        fi
    done
    [[ $v == ko ]] && [[ -r $PVE_I18N_DIR/pve-lang-kr.js ]] && { REPLY=kr; return 0; }
    return 1
}

i18n_code() {
    local want=${CFG[language]} loc dc
    if [[ $want != auto ]]; then _i18n_resolve "$want" || REPLY=en; return; fi
    loc=${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}
    if [[ -n $loc && $loc != C* && $loc != POSIX && $loc != en* ]] && _i18n_resolve "$loc"; then return; fi
    dc=$(sed -n 's/^language:[[:space:]]*//p' "${PVE_DATACENTER_CFG:-/etc/pve/datacenter.cfg}" 2>/dev/null | head -1)
    if [[ -n $dc && $dc != __default__ ]] && _i18n_resolve "$dc"; then return; fi
    REPLY=en
}

i18n_load() {
    local code k
    i18n_code; code=$REPLY
    L=()
    # shellcheck source=/dev/null
    source "$PROXHAWK_TUI_HOME/lang/en.sh"
    if [[ $code != en ]]; then
        if [[ -r $PROXHAWK_TUI_HOME/lang/$code.sh ]]; then
            # shellcheck source=/dev/null
            source "$PROXHAWK_TUI_HOME/lang/$code.sh"
        else
            LANG_NAME=${LANG_NAMES[$code]:-$code}
        fi
        # Official words of the web interface for what the file leaves empty.
        if [[ -r $PVE_I18N_DIR/pve-lang-$code.js ]]; then
            local -A P=()
            eval "$(perl "$PROXHAWK_TUI_HOME/lib/i18n-pve.pl" "$PVE_I18N_DIR/pve-lang-$code.js" "$PROXHAWK_TUI_HOME/lang/TEMPLATE.sh" 2>/dev/null | sed 's/^L\[/P[/')"
            for k in "${!P[@]}"; do [[ -n ${L[$k]-} ]] || L[$k]=${P[$k]}; done
        fi
    fi
    LANG_CODE=$code
    # Double width characters (lib/widgets.sh): languages written with them.
    case $code in zh*|ja|ko|kr) WIDE_TEXT=1 ;; *) WIDE_TEXT=0 ;; esac
}

# T <string>: translated string in REPLY.
T() { if [[ -n $1 ]]; then REPLY=${L[$1]:-$1}; else REPLY=""; fi; }

# Tf <format> [args...]: translated printf format in REPLY.
Tf() {
    local f=$1
    [[ -n $f ]] && f=${L[$f]:-$f}
    shift
    # shellcheck disable=SC2059
    printf -v REPLY "$f" "$@"
}

# Available languages as "code name" lines: the files of lang/ and the
# catalogs of the Proxmox VE web interface.
i18n_list() {
    local f c name
    local -A seen=()
    for f in "$PROXHAWK_TUI_HOME"/lang/*.sh "$PVE_I18N_DIR"/pve-lang-*.js; do
        [[ -r $f && $f != */TEMPLATE.sh ]] || continue
        c=${f##*/}; c=${c%.sh}; c=${c%.js}; c=${c#pve-lang-}
        [[ $c == kr && -n ${LANG_NAMES[ko]-} && -r $PVE_I18N_DIR/pve-lang-ko.js ]] && continue
        [[ -n ${seen[$c]-} ]] && continue
        seen[$c]=1
        name=""
        [[ $f == *.sh ]] && name=$(sed -n 's/^LANG_NAME=["'\'']\{0,1\}\([^"'\'']*\).*/\1/p' "$f" | head -1)
        printf '%s %s\n' "$c" "${name:-${LANG_NAMES[$c]:-$c}}"
    done | sort
}
