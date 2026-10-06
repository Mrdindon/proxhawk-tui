#!/usr/bin/env bash
# install.sh - install or remove the pvetty command.
#
#   ./install.sh                 symlink /usr/local/bin/pvetty -> this directory
#   ./install.sh --prefix DIR    symlink DIR/pvetty instead
#   ./install.sh --uninstall     remove the symlink (the source directory is kept)
#
# Nothing else is installed: pvetty only needs what Proxmox VE already ships.
set -euo pipefail
src=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
prefix=/usr/local/bin
action=install
while (( $# )); do
    case $1 in
        --prefix) prefix=$2; shift ;;
        --uninstall) action=uninstall ;;
        -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
link="$prefix/pvetty"
if [[ $action == uninstall ]]; then
    if [[ -L $link ]]; then rm -f "$link"; echo "removed $link"; else echo "$link is not a symlink - nothing done"; fi
    exit 0
fi
command -v pvesh >/dev/null || echo "warning: pvesh not found - pvetty must run on a Proxmox VE node" >&2
chmod +x "$src/pvetty" "$src/lib/broker.pl" "$src"/tools/*.sh
mkdir -p "$prefix"
ln -sfn "$src/pvetty" "$link"
echo "installed $link -> $src/pvetty"
