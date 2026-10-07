# shellcheck shell=bash
# upgrade.sh - "proxhawk-tui upgrade": update proxhawk-tui from GitHub,
# according to how it was installed.
#
#   proxhawk-tui upgrade [--check] [--version X.Y.Z] [--yes]
#
#   package (.deb, one-line install)  latest release: download the .deb,
#                                     check its SHA-256, apt-get install
#   git clone                         git fetch, then git pull --ff-only of
#                                     the current branch
#   other (archive unpacked by hand)  shows the available version
# --check only reports whether an update is available (exit code 10 when
# there is one, 0 when up to date).

UPGRADE_REPO=Mrdindon/proxhawk-tui

_up_say() { printf '%s\n' "$*"; }
_up_die() { printf 'proxhawk-tui upgrade: %s\n' "$*" >&2; exit 1; }

# Version of the latest GitHub release (the "latest" page redirects to the
# tag) -> REPLY.
_up_latest() {
    local url
    url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$UPGRADE_REPO/releases/latest" 2>/dev/null) \
        || _up_die "cannot reach GitHub"
    REPLY=${url##*/v}
    [[ $REPLY =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || _up_die "no release found ($url)"
}

# _up_newer A B: is version A newer than B?
_up_newer() { [[ $1 != "$2" && $(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1) == "$1" ]]; }

_up_confirm() {
    (( UP_YES )) && return 0
    [[ -t 0 ]] || _up_die "not a terminal: use --yes to confirm"
    local a
    read -r -p "$1 [y/N] " a
    [[ $a == [yYoO]* ]]
}

upgrade_main() {
    local check=0 want="" cur=$PROXHAWK_TUI_VERSION method latest
    UP_YES=0
    while (( $# )); do
        case $1 in
            --check) check=1 ;;
            --version) want=${2#v}; shift ;;
            -y|--yes) UP_YES=1 ;;
            -h|--help) sed -n '2,13p' "$PROXHAWK_TUI_HOME/lib/upgrade.sh" | sed 's/^# \{0,1\}//'; return 0 ;;
            *) _up_die "unknown option: $1" ;;
        esac
        shift
    done
    # How it was installed.
    if [[ -d $PROXHAWK_TUI_HOME/.git ]]; then method=git
    elif [[ $PROXHAWK_TUI_HOME == /usr/share/proxhawk-tui ]] && dpkg -s proxhawk-tui >/dev/null 2>&1; then method=package
    else method=archive
    fi
    case $method in
        git) _upgrade_git "$check" ;;
        *)
            if [[ -n $want ]]; then latest=$want; else _up_latest; latest=$REPLY; fi
            _up_say "Installed: $cur ($method)   Latest release: $latest"
            if ! _up_newer "$latest" "$cur" && [[ -z $want ]]; then _up_say "proxhawk-tui is up to date."; return 0; fi
            (( check )) && { _up_say "An update is available: proxhawk-tui upgrade"; return 10; }
            if [[ $method == archive ]]; then
                _up_say "This copy was installed from an archive. Get the new version with:"
                _up_say "  bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/$UPGRADE_REPO/main/install.sh)\""
                _up_say "or download https://github.com/$UPGRADE_REPO/releases/tag/v$latest"
                return 0
            fi
            _upgrade_package "$latest" ;;
    esac
}

_upgrade_package() {
    local v=$1 deb tmp base
    (( EUID == 0 )) || _up_die "run it as root (or with sudo)"
    _up_confirm "Install proxhawk-tui $v?" || return 0
    deb="proxhawk-tui_${v}_all.deb"
    base="https://github.com/$UPGRADE_REPO/releases/download/v$v"
    tmp=$(mktemp -d)
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" RETURN
    _up_say "Downloading $deb..."
    curl -fsSL -o "$tmp/$deb" "$base/$deb" || _up_die "cannot download $base/$deb"
    curl -fsSL -o "$tmp/$deb.sha256" "$base/$deb.sha256" || _up_die "cannot download the checksum"
    ( cd "$tmp" && sha256sum -c --quiet "$deb.sha256" ) || _up_die "checksum mismatch: nothing installed"
    apt-get install -y "$tmp/$deb" || _up_die "apt-get failed"
    _up_say "proxhawk-tui $v installed."
}

_upgrade_git() {
    local check=$1 dir=$PROXHAWK_TUI_HOME branch up n newv
    branch=$(git -C "$dir" symbolic-ref --short -q HEAD) \
        || _up_die "the git copy is not on a branch (detached at $(git -C "$dir" describe --tags --always)): git checkout main"
    git -C "$dir" fetch --tags --quiet origin || _up_die "git fetch failed"
    up=$(git -C "$dir" rev-parse -q --verify "origin/$branch") || _up_die "no origin/$branch"
    n=$(git -C "$dir" rev-list --count "HEAD..$up")
    newv=$(git -C "$dir" show "$up:VERSION" 2>/dev/null)
    _up_say "Installed: $PROXHAWK_TUI_VERSION (git, branch $branch)   origin/$branch: ${newv:-?}, $n new commit(s)"
    (( n > 0 )) || { _up_say "proxhawk-tui is up to date."; return 0; }
    (( check )) && { _up_say "An update is available: proxhawk-tui upgrade"; return 10; }
    git -C "$dir" --no-pager log --oneline --no-decorate "HEAD..$up" | head -20
    [[ -z $(git -C "$dir" status --porcelain --untracked-files=no) ]] \
        || _up_die "local changes in $dir: commit or stash them first"
    _up_confirm "Update to ${newv:-origin/$branch}?" || return 0
    git -C "$dir" pull --ff-only --quiet origin "$branch" || _up_die "git pull --ff-only failed (the branch has diverged)"
    _up_say "proxhawk-tui updated to $(< "$dir/VERSION")."
}
