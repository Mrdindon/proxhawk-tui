#!/usr/bin/env bash
# make-release.sh - build the release archive of pvetty.
#   tools/make-release.sh [output directory]   (default: ../releases)
# Produces pvetty-<version>.tar.gz, its SHA-256 and a manifest of the files.
set -euo pipefail
src=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
ver=$(< "$src/VERSION")
out=${1:-$(dirname "$src")/releases}
mkdir -p "$out"
name="pvetty-$ver"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/$name"
tar -C "$src" --exclude=.git -cf - . | tar -C "$tmp/$name" -xf -
find "$tmp/$name" -name '*~' -delete
( cd "$tmp/$name" && find . -type f ! -name MANIFEST.sha256 | sort | xargs sha256sum ) > "$tmp/MANIFEST.sha256"
mv "$tmp/MANIFEST.sha256" "$tmp/$name/MANIFEST.sha256"
tar -C "$tmp" --owner=0 --group=0 -czf "$out/$name.tar.gz" "$name"
( cd "$out" && sha256sum "$name.tar.gz" > "$name.tar.gz.sha256" )
echo "$out/$name.tar.gz"
cat "$out/$name.tar.gz.sha256"
