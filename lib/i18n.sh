# shellcheck shell=bash
# i18n.sh - minimal gettext-like translation layer.
#
# Source strings are written in English directly in the code and used as
# lookup keys:  T "Start"        -> REPLY="Start" (or its translation)
#               Tf "VM %s" 100   -> REPLY="VM 100" (format string translated)
# A language file (lang/<code>.sh) fills the associative array L with
# "English" -> "Translation" pairs. Missing entries fall back to English.

declare -gA L=()
LANG_CODE=en
LANG_NAME=English
DATE_FMT='%Y-%m-%d %H:%M:%S'
DATE_SHORT='%b %d %H:%M:%S'

i18n_load() {
    local code=${CFG[language]}
    if [[ $code == auto ]]; then
        code=${LC_ALL:-${LC_MESSAGES:-${LANG:-en}}}
        code=${code%%[_.@]*}
        [[ -z $code || $code == C || $code == POSIX ]] && code=en
    fi
    # shellcheck source=/dev/null
    source "$PVETTY_HOME/lang/en.sh"
    if [[ $code != en && -r $PVETTY_HOME/lang/$code.sh ]]; then
        source "$PVETTY_HOME/lang/$code.sh"
    else
        code=en
    fi
    LANG_CODE=$code
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

# List available languages as "code name" lines.
i18n_list() {
    local f name
    for f in "$PVETTY_HOME"/lang/*.sh; do
        [[ $f == */TEMPLATE.sh ]] && continue
        name=$(sed -n 's/^LANG_NAME=["'\'']\{0,1\}\([^"'\'']*\).*/\1/p' "$f" | head -1)
        printf '%s %s\n' "$(basename "$f" .sh)" "${name:-?}"
    done
}
