#!/usr/bin/env bash
# install.sh - install, update or remove proxhawk-tui on a Proxmox VE node.
#
# One line, from GitHub (installs the .deb of the latest release, checked
# with its SHA-256):
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/Mrdindon/proxhawk-tui/main/install.sh)"
#   ... install.sh)" -- --version 1.2.1      a given release
#   ... install.sh)" -- --uninstall          remove the package
#
# From a source directory (git clone or release archive):
#   ./install.sh                 symlink /usr/local/bin/proxhawk-tui -> this directory
#   ./install.sh --prefix DIR    symlink DIR/proxhawk-tui instead
#   ./install.sh --uninstall     remove the symlink (the source directory is kept)
set -euo pipefail
REPO=Mrdindon/proxhawk-tui
prefix=/usr/local/bin
action=install
version=""
while (( $# )); do
    case $1 in
        --prefix) prefix=$2; shift ;;
        --version) version=${2#v}; shift ;;
        --uninstall) action=uninstall ;;
        -h|--help) sed -n '2,14p' "${BASH_SOURCE[0]:-/dev/null}" 2>/dev/null || echo "see https://github.com/$REPO"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

die() { echo "install.sh: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# From GitHub: the script was not read from a file (bash -c "$(curl ...)").
# ---------------------------------------------------------------------------
if [[ -z ${BASH_SOURCE[0]:-} || ! -f ${BASH_SOURCE[0]} ]]; then
    (( EUID == 0 )) || die "run it as root"
    command -v pveversion >/dev/null || die "this is not a Proxmox VE node (pveversion not found)"
    if [[ $action == uninstall ]]; then
        apt-get remove -y proxhawk-tui
        exit 0
    fi
    if [[ -z $version ]]; then
        # The "latest" page redirects to .../releases/tag/vX.Y.Z
        url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest") \
            || die "cannot reach GitHub"
        version=${url##*/v}
        [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "no release found ($url)"
    fi
    deb="proxhawk-tui_${version}_all.deb"
    base="https://github.com/$REPO/releases/download/v$version"
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    echo "Downloading proxhawk-tui $version..."
    curl -fsSL -o "$tmp/$deb" "$base/$deb" || die "cannot download $base/$deb"
    curl -fsSL -o "$tmp/$deb.sha256" "$base/$deb.sha256" || die "cannot download the checksum"
    ( cd "$tmp" && sha256sum -c --quiet "$deb.sha256" ) || die "checksum mismatch: the package was not installed"
    apt-get install -y "$tmp/$deb"
    echo
    echo "proxhawk-tui $version installed: run 'proxhawk-tui' (documentation: /usr/share/doc/proxhawk-tui, https://github.com/$REPO)"
    exit 0
fi

# ---------------------------------------------------------------------------
# From a source directory.
# ---------------------------------------------------------------------------
src=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
link="$prefix/proxhawk-tui"
if [[ $action == uninstall ]]; then
    if [[ -L $link ]]; then rm -f "$link"; echo "removed $link"; else echo "$link is not a symlink - nothing done"; fi
    exit 0
fi
command -v pvesh >/dev/null || echo "warning: pvesh not found - proxhawk-tui must run on a Proxmox VE node" >&2
chmod +x "$src/proxhawk-tui" "$src/lib/broker.pl" "$src"/tools/*.sh
mkdir -p "$prefix"
ln -sfn "$src/proxhawk-tui" "$link"
echo "installed $link -> $src/proxhawk-tui"
