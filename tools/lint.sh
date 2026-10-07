#!/usr/bin/env bash
# lint.sh - static checks: bash syntax, shellcheck (warnings and errors,
# see .shellcheckrc), Perl syntax of the API helper.
#   tools/lint.sh            check every file
set -uo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." || exit 1
rc=0
mapfile -t files < <(printf '%s\n' proxhawk-tui install.sh lib/*.sh views/*.sh themes/*.sh lang/*.sh tools/*.sh tools/integration/*.sh plugins/*.sh 2>/dev/null | while read -r f; do [[ -f $f ]] && echo "$f"; done)
for f in "${files[@]}"; do bash -n "$f" || { echo "syntax error: $f"; rc=1; }; done
perl -c lib/broker.pl 2>&1 | grep -v 'syntax OK' && rc=1
if command -v shellcheck >/dev/null; then
    shellcheck -x -S warning "${files[@]}" || rc=1
else
    echo "shellcheck not installed - skipped"
fi
(( rc == 0 )) && echo "lint: OK"
exit $rc
