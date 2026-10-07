#!/usr/bin/env bash
# make-deb.sh - build a Debian package of proxhawk-tui.
#   tools/make-deb.sh [output directory]   (default: ../releases)
# Installs the program in /usr/share/proxhawk-tui, the command /usr/bin/proxhawk-tui,
# the example configuration in /etc/proxhawk-tui.conf (conffile, all commented)
# and the documentation in /usr/share/doc/proxhawk-tui. Development files
# (tests, tools, .git) are left out.
set -euo pipefail
src=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
ver=$(< "$src/VERSION")
out=${1:-$(dirname "$src")/releases}
command -v dpkg-deb >/dev/null || { echo "dpkg-deb not found" >&2; exit 1; }
mkdir -p "$out"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pkg=$tmp/pkg
share=$pkg/usr/share/proxhawk-tui
mkdir -p "$share" "$pkg/usr/bin" "$pkg/etc" "$pkg/usr/share/doc/proxhawk-tui" "$pkg/DEBIAN"
cp -a "$src/proxhawk-tui" "$src/VERSION" "$src/lib" "$src/views" "$src/themes" "$src/lang" "$src/plugins" "$share/"
# The help screen opens the user guide from $PROXHAWK_TUI_HOME/docs.
mkdir -p "$share/docs"
for f in "$src"/docs/*.md; do
    case ${f##*/} in DEVELOPMENT.md|TEST-RESULTS.md|COMPARISON-*) continue ;; esac
    cp "$f" "$share/docs/"
done
cp "$src/README.md" "$src/CHANGELOG.md" "$pkg/usr/share/doc/proxhawk-tui/"
cat > "$pkg/usr/share/doc/proxhawk-tui/copyright" <<CPY
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: proxhawk-tui

Files: *
Copyright: 2026 francois <5002201+Mrdindon@users.noreply.github.com>
License: AGPL-3.0+
 On Debian systems, the full text of the GNU Affero General Public License
 version 3 can be found in /usr/share/common-licenses/AGPL-3.0.
CPY
ln -s ../../proxhawk-tui/docs "$pkg/usr/share/doc/proxhawk-tui/docs"
# Every setting commented out: the defaults stay in effect until edited.
sed 's/^\([a-z]\)/# \1/' "$src/conf/proxhawk-tui.conf.example" > "$pkg/etc/proxhawk-tui.conf"
ln -s ../share/proxhawk-tui/proxhawk-tui "$pkg/usr/bin/proxhawk-tui"
find "$pkg" -name '*~' -delete
chmod 755 "$share/proxhawk-tui" "$share/lib/broker.pl"
size=$(du -sk "$pkg/usr" | cut -f1)
cat > "$pkg/DEBIAN/control" <<CTL
Package: proxhawk-tui
Version: $ver
Section: admin
Priority: optional
Architecture: all
Depends: bash (>= 4.3), pve-manager
Recommends: dialog | whiptail
Suggests: tmux
Installed-Size: $size
Maintainer: francois <5002201+Mrdindon@users.noreply.github.com>
Replaces: pvetty, pvetui
Breaks: pvetty, pvetui
Description: text console for Proxmox VE
 Terminal user interface that mirrors the Proxmox VE web interface
 (resource tree, panels, forms, tasks), running on a Proxmox VE node
 with the local API. Also provides non-interactive subcommands
 (proxhawk-tui nodes|guests|tasks|storage|api) with JSON or table output.
CTL
echo /etc/proxhawk-tui.conf > "$pkg/DEBIAN/conffiles"
deb="$out/proxhawk-tui_${ver}_all.deb"
dpkg-deb --root-owner-group --build "$pkg" "$deb" >/dev/null
( cd "$out" && sha256sum "${deb##*/}" > "${deb##*/}.sha256" )
echo "$deb"
