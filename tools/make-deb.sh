#!/usr/bin/env bash
# make-deb.sh - build a Debian package of pvetty.
#   tools/make-deb.sh [output directory]   (default: ../releases)
# Installs the program in /usr/share/pvetty, the command /usr/bin/pvetty,
# the example configuration in /etc/pvetty.conf (conffile, all commented)
# and the documentation in /usr/share/doc/pvetty. Development files
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
share=$pkg/usr/share/pvetty
mkdir -p "$share" "$pkg/usr/bin" "$pkg/etc" "$pkg/usr/share/doc/pvetty" "$pkg/DEBIAN"
cp -a "$src/pvetty" "$src/VERSION" "$src/lib" "$src/views" "$src/themes" "$src/lang" "$src/plugins" "$share/"
# The help screen opens the user guide from $PVETTY_HOME/docs.
mkdir -p "$share/docs"
for f in "$src"/docs/*.md; do
    case ${f##*/} in DEVELOPMENT.md|TEST-RESULTS.md|COMPARISON-*) continue ;; esac
    cp "$f" "$share/docs/"
done
cp "$src/README.md" "$src/CHANGELOG.md" "$pkg/usr/share/doc/pvetty/"
cat > "$pkg/usr/share/doc/pvetty/copyright" <<CPY
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: pvetty

Files: *
Copyright: 2026 francois <5002201+Mrdindon@users.noreply.github.com>
License: AGPL-3.0+
 On Debian systems, the full text of the GNU Affero General Public License
 version 3 can be found in /usr/share/common-licenses/AGPL-3.0.
CPY
ln -s ../../pvetty/docs "$pkg/usr/share/doc/pvetty/docs"
# Every setting commented out: the defaults stay in effect until edited.
sed 's/^\([a-z]\)/# \1/' "$src/conf/pvetty.conf.example" > "$pkg/etc/pvetty.conf"
ln -s ../share/pvetty/pvetty "$pkg/usr/bin/pvetty"
find "$pkg" -name '*~' -delete
chmod 755 "$share/pvetty" "$share/lib/broker.pl"
size=$(du -sk "$pkg/usr" | cut -f1)
cat > "$pkg/DEBIAN/control" <<CTL
Package: pvetty
Version: $ver
Section: admin
Priority: optional
Architecture: all
Depends: bash (>= 4.3), pve-manager
Recommends: dialog | whiptail
Suggests: tmux
Installed-Size: $size
Maintainer: francois <5002201+Mrdindon@users.noreply.github.com>
Replaces: pvetui
Breaks: pvetui
Description: text console for Proxmox VE
 Terminal user interface that mirrors the Proxmox VE web interface
 (resource tree, panels, forms, tasks), running on a Proxmox VE node
 with the local API. Also provides non-interactive subcommands
 (pvetty nodes|guests|tasks|storage|api) with JSON or table output.
CTL
echo /etc/pvetty.conf > "$pkg/DEBIAN/conffiles"
deb="$out/pvetty_${ver}_all.deb"
dpkg-deb --root-owner-group --build "$pkg" "$deb" >/dev/null
( cd "$out" && sha256sum "${deb##*/}" > "${deb##*/}.sha256" )
echo "$deb"
