# shellcheck shell=bash
# core.sh - global state, configuration loading, logging and cleanup.

# ---------------------------------------------------------------------------
# Default configuration (overridable by config files and environment).
# ---------------------------------------------------------------------------
declare -gA CFG=(
    [language]=auto        # auto | en | fr | ...
    [glyphs]=auto          # auto | nerd | unicode | ascii
    [theme]=auto           # auto | default | dark | light | basic
    [backend]=auto         # auto | broker | pvesh | replay (PVETTY_REPLAY=dir)
    [dialog]=auto          # auto | dialog | whiptail | builtin
    [refresh]=5            # seconds between automatic refreshes (0 = off)
    [mouse]=1              # 1 = enable mouse support
    [tree_width]=0         # 0 = automatic
    [task_rows]=5          # visible rows in the bottom task panel (0 = hidden)
    [graph_timeframe]=hour # hour | day | week | month | year
    [show_tags]=1          # display guest tags in the resource tree
    [confirm]=1            # ask before power actions
    [editor]=""            # editor for notes (default: $VISUAL, $EDITOR, nano, vi)
    [pager]=""             # pager for logs (default: $PAGER, less)
    [icons]=1              # 0 = no icons in the tree, menus and buttons (glyphs "none")
    [startup]=root         # initial selection: root | last | a tree id (qemu/100, node/pve1...)
    [confirm_quit]=1       # ask before quitting while tasks started by pvetty are running
    [ip_column]=1          # IP addresses of the guests in the search grids
    [ssh_user]=root        # default user of the SSH console of VMs
    [ssh_key]=""           # private key file for the SSH console (-i)
    [ssh_jump]=""          # jump host for the SSH console (-J user@host:port)
    [ssh_options]=""       # extra ssh options (e.g. "-o StrictHostKeyChecking=no")
    [console_host]=""      # host name used in browser console URLs (default: node IP)
    [plugins]=""           # enabled plugins (space separated names, see plugins/)
    [onboarding]=1         # 1 = show the first run wizard when no user config exists
    [queue_parallel]=2     # actions of the queue / batch actions running at once
    [cli_output]=json      # default output of the subcommands: json | table
    [user]=""              # Proxmox VE user to run as (empty = launching user, see ask_user)
    [ask_user]=1           # 1 = ask at start-up which user to run as
)

# Free form settings of the configuration file:
#   key.<action> = <key>      key bindings (see lib/keys.sh)
#   color.<token> = <value>   colour overrides (#rrggbb, SGR parameters or "default")
declare -gA CFGX=()

PVETTY_VERSION="1.3.0"
RUN_DIR=""
LOCAL_NODE="${HOSTNAME%%.*}"

# The project was called "pvetui" before 1.2.0: move its user files (settings,
# plugins, state) to the new names once, and keep reading /etc/pvetui.conf
# while /etc/pvetty.conf does not exist.
core_migrate_legacy() {
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}" st="${XDG_STATE_HOME:-$HOME/.local/state}"
    if [[ -d $cfg/pvetui && ! -e $cfg/pvetty ]]; then
        mkdir -p "$cfg/pvetty" &&
        cp -a "$cfg/pvetui/." "$cfg/pvetty/" &&
        { [[ -e $cfg/pvetty/pvetui.conf ]] && mv "$cfg/pvetty/pvetui.conf" "$cfg/pvetty/pvetty.conf"; true; } &&
        rm -rf "$cfg/pvetui"
    fi
    if [[ -d $st/pvetui && ! -e $st/pvetty ]]; then mv "$st/pvetui" "$st/pvetty"; fi
    return 0
}

# Load "key = value" style configuration files. Unknown keys are ignored.
core_load_config() {
    local f key val etc=/etc/pvetty.conf
    core_migrate_legacy 2>/dev/null
    [[ ! -e $etc && -e /etc/pvetui.conf ]] && etc=/etc/pvetui.conf
    for f in "$etc" "${XDG_CONFIG_HOME:-$HOME/.config}/pvetty/pvetty.conf" "$@"; do
        [[ -r $f ]] || continue
        while IFS= read -r key || [[ -n $key ]]; do
            key="${key%%#*}"
            [[ $key == *=* ]] || continue
            val="${key#*=}"; key="${key%%=*}"
            key="${key//[[:space:]]/}"
            val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"
            val="${val#[\"\']}"; val="${val%[\"\']}"
            if [[ -v CFG[$key] ]]; then CFG[$key]="$val"
            elif [[ $key == key.* || $key == color.* ]]; then CFGX[$key]="$val"
            fi
        done < "$f"
    done
    # Environment overrides: PVETTY_<KEY>=value
    local k v
    for k in "${!CFG[@]}"; do
        v="PVETTY_${k^^}"
        [[ -n ${!v-} ]] && CFG[$k]="${!v}"
    done
}

# Persist a single configuration key into the user configuration file.
core_save_config() {
    local key=$1 val=$2 dir="${XDG_CONFIG_HOME:-$HOME/.config}/pvetty"
    local f="$dir/pvetty.conf" tmp
    mkdir -p "$dir" || return 1
    touch "$f"
    tmp="$f.tmp"
    local re=${key//./\\.}
    grep -v "^[[:space:]]*${re}[[:space:]]*=" "$f" > "$tmp"
    printf '%s = %s\n' "$key" "$val" >> "$tmp"
    mv "$tmp" "$f"
    if [[ $key == key.* || $key == color.* ]]; then CFGX[$key]="$val"; else CFG[$key]="$val"; fi
}

# Small state kept between sessions (last selection...): ~/.local/state/pvetty/state
STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/pvetty/state"
declare -gA STATE=()
core_state_load() {
    local k v
    [[ -r $STATE_FILE ]] || return 0
    while IFS='=' read -r k v; do [[ -n $k ]] && STATE[$k]=$v; done < "$STATE_FILE"
}
core_state_save() {
    local k
    mkdir -p "${STATE_FILE%/*}" 2>/dev/null || return 0
    for k in "${!STATE[@]}"; do printf '%s=%s\n' "$k" "${STATE[$k]}"; done > "$STATE_FILE"
}

# First run: no user configuration file yet.
core_first_run() { [[ ! -e "${XDG_CONFIG_HOME:-$HOME/.config}/pvetty/pvetty.conf" ]]; }

core_init_rundir() {
    RUN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/pvetty.XXXXXX") || { echo "pvetty: cannot create temp dir" >&2; exit 1; }
}

# Debug log, enabled with PVETTY_DEBUG=1 (file: $PVETTY_LOG or /tmp/pvetty-debug.log).
log() { [[ ${PVETTY_DEBUG:-0} == 1 ]] && printf '%(%T)T %s\n' -1 "$*" >> "${PVETTY_LOG:-/tmp/pvetty-debug.log}"; return 0; }

die() {
    term_restore 2>/dev/null
    printf 'pvetty: %s\n' "$*" >&2
    exit 1
}

# Registered cleanup hooks run on exit (modules append function names).
declare -ga CLEANUP_HOOKS=()
core_cleanup() {
    local h
    for h in "${CLEANUP_HOOKS[@]}"; do "$h" 2>/dev/null; done
    [[ -n $RUN_DIR && -d $RUN_DIR ]] && rm -rf "$RUN_DIR"
}

now() { if [[ -n ${PVETTY_NOW-} ]]; then NOW=$PVETTY_NOW; else printf -v NOW '%(%s)T' -1; fi; }   # PVETTY_NOW: frozen clock (screen tests)
