#!/usr/bin/perl
# i18n-pve.pl - translations of pvetty strings taken from the official
# message catalog of the Proxmox VE web interface (package pve-i18n,
# /usr/share/pve-i18n/pve-lang-<code>.js), so that pvetty uses the same
# words as the GUI.
#
#   i18n-pve.pl <catalog.js> <TEMPLATE.sh>   prints bash: L['English']='Translation'
#
# The catalog keys are the FNV-31a hashes of the English strings (the GUI
# gettext). Only the strings of TEMPLATE.sh are looked up; translations that
# would change printf placeholders are skipped.
use strict;
use warnings;
use JSON;

# FNV-31a of the UTF-8 bytes, as PVE::Tools::fnv31a (not loaded: slow).
sub fnv31a {
    my $h = 0x811c9dc5;
    for my $c (unpack('C*', shift)) {
        $h ^= $c;
        $h = ($h + ($h << 1) + ($h << 4) + ($h << 7) + ($h << 8) + ($h << 24)) & 0xffffffff;
    }
    return $h & 0x7fffffff;
}

my ($catalog, $template) = @ARGV;
open(my $fh, '<:raw', $catalog) or exit 0;
my $js = do { local $/; <$fh> };
my $i = index($js, '__proxmox_i18n_msgcat__ = ');
exit 0 if $i < 0;
my ($cat) = JSON->new->utf8->decode_prefix(substr($js, $i + 26));

open(my $th, '<:encoding(UTF-8)', $template) or exit 0;
binmode(STDOUT, ':encoding(UTF-8)');
sub sq { my $s = shift; $s =~ s/'/'\\''/g; return "'$s'" }
while (my $line = <$th>) {
    next unless $line =~ /^\s*\["(.*)"\]=""\s*$/;
    my $s = $1;
    $s =~ s/\\(["\\\$`])/$1/g;
    utf8::encode(my $bytes = $s);
    my $tr = $cat->{fnv31a($bytes)} or next;
    my $t = $tr->[0] // next;
    next if $t eq '' || $t =~ /[<>{}]/;
    my @a = $s =~ /%[-0-9.]*[sdif%]/g;
    my @b = $t =~ /%[-0-9.]*[sdif%]/g;
    next if "@a" ne "@b";
    print 'L[', sq($s), ']=', sq($t), "\n";
}
