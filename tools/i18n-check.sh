#!/usr/bin/env bash
# i18n-check.sh - translation coverage of the languages.
#
#   tools/i18n-check.sh              every language (lang/*.sh and the Proxmox
#                                    VE catalogs installed on this node)
#   tools/i18n-check.sh fr de        some languages
#   tools/i18n-check.sh -v fr        also list the strings still in English
#
# For each language: strings translated by lang/<code>.sh, by the Proxmox VE
# web interface catalog (/usr/share/pve-i18n), and left in English. Checks
# that the translations of lang/<code>.sh keep the printf placeholders (%s,
# %d) in the same order. Exit code 1 when a check fails.
set -u
PVETTY_HOME=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
PVE_I18N_DIR=${PVE_I18N_DIR:-/usr/share/pve-i18n}
verbose=0
[[ ${1-} == -v ]] && { verbose=1; shift; }
langs=("$@")
if (( ! ${#langs[@]} )); then
    for f in "$PVETTY_HOME"/lang/*.sh "$PVE_I18N_DIR"/pve-lang-*.js; do
        [[ -r $f && $f != */TEMPLATE.sh && $f != */en.sh && $f != *pve-lang-kr.js ]] || continue
        c=${f##*/}; c=${c%.sh}; c=${c%.js}; langs+=("${c#pve-lang-}")
    done
    mapfile -t langs < <(printf '%s\n' "${langs[@]}" | sort -u)
fi
rc=0
printf '%-7s %7s %8s %8s %8s\n' "lang" "pvetty" "Proxmox" "English" "coverage"
for code in "${langs[@]}"; do
    out=$(perl - "$PVETTY_HOME" "$code" "$PVE_I18N_DIR" "$verbose" <<'PERL'
use strict; use warnings;
my ($home, $code, $dir, $verbose) = @ARGV;
binmode(STDOUT, ':encoding(UTF-8)');
sub unesc { my $s = shift; $s =~ s/\\(["\\\$`])/$1/g; return $s }
my @keys;
open(my $t, '<:encoding(UTF-8)', "$home/lang/TEMPLATE.sh") or die;
while (<$t>) { push @keys, unesc($1) if /^\s*\["(.*)"\]=""\s*$/ }
my %file;
my $bad = 0;
if (open(my $f, '<:encoding(UTF-8)', "$home/lang/$code.sh")) {
    while (<$f>) {
        next unless /^\s*\["((?:[^"\\]|\\.)*)"\]="((?:[^"\\]|\\.)*)"/;
        my ($k, $v) = (unesc($1), unesc($2));
        next if $v eq '';
        my @a = $k =~ /%[-0-9.]*[sdif]/g; my @b = $v =~ /%[-0-9.]*[sdif]/g;
        if ("@a" ne "@b" || $v =~ /%\d+\$/) { print "BAD\t$k\t$v\n"; $bad++ }
        $file{$k} = 1;
    }
}
my %pve;
if (-r "$dir/pve-lang-$code.js") {
    open(my $p, '-|', 'perl', "$home/lib/i18n-pve.pl", "$dir/pve-lang-$code.js", "$home/lang/TEMPLATE.sh") or die;
    binmode($p, ':encoding(UTF-8)');
    while (<$p>) { if (/^L\['(.*?)'\]=/) { my $k = $1; $k =~ s/'\\''/'/g; $pve{$k} = 1 } }
}
my ($nf, $np, $ne) = (0, 0, 0);
for my $k (@keys) {
    if ($file{$k}) { $nf++ } elsif ($pve{$k}) { $np++ } else { $ne++; print "EN\t$k\n" if $verbose }
}
printf "SUM\t%d\t%d\t%d\t%d\t%d\n", $nf, $np, $ne, scalar(@keys) ? int(100 * ($nf + $np) / @keys) : 0, $bad;
PERL
)
    while IFS=$'\t' read -r kind a b c d e; do
        case $kind in
            SUM) printf '%-7s %7s %8s %8s %7s%%\n' "$code" "$a" "$b" "$c" "$d"; (( e )) && rc=1 ;;
            BAD) printf '  placeholders differ: %s  ->  %s\n' "$a" "$b" ;;
            EN) printf '  english: %s\n' "$a" ;;
        esac
    done <<< "$out"
done
exit $rc
