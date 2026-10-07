#!/usr/bin/perl
# proxhawk-tui API broker
# -----------------
# Long-running helper that loads the Proxmox VE API stack once and answers
# read-only (GET) requests over stdin/stdout. This avoids the ~1-2 s start-up
# cost of `pvesh` for every call. Requests that must be proxied to another
# cluster node fall back to `pvesh` (which tunnels through SSH).
#
# Request  (one line, tab separated):  MODE \t PATH \t QUERY \t FIELDS
#   MODE   rows | kv | json                       data (GET)
#          schema | propparse | propprint          API parameter definitions
#          pluginopts                               options of a plugin type
#          perm                                     PATH = ACL path, QUERY priv=X:
#                                                   "1" if the user has it, else "0"
#   PATH   API path, e.g. /nodes/pve1/status
#   QUERY  url-encoded parameters, e.g. timeframe=hour&cf=AVERAGE
#   FIELDS comma separated field specs (rows mode only):
#            name        plain value
#            a.b         nested hash value
#            name*N      numeric value multiplied by N and rounded to integer
#            name:i      numeric value rounded to integer
#            name#       number of elements of an array or hash
#          A leading "@a.*.b;" selects nested rows first ("*" = every element,
#          "**" = every element of the nested "children" lists).
# Response: zero or more data lines followed by a terminator line:
#   "\x04OK"  or  "\x04ERR\t<message>"
# Inside values, TAB becomes a space and NEWLINE becomes "\x1f".
#
# PROXHAWK_TUI_USER (default root@pam): the Proxmox VE user the requests run as.
# Like the API server, each request is checked with check_api2_permissions
# for that user, and the handlers filter their results for that user.
use strict;
use warnings;

use JSON;

$| = 1;
my $json = JSON->new->canonical->allow_nonref;
my $local = "";
my $as_user = $ENV{PROXHAWK_TUI_USER} || 'root@pam';

# Refresh the per-request state like pvedaemon (cluster file system, cached
# user configuration: pools, ACL...) and set the user of the request.
sub request_env {
    my $rpcenv = PVE::RPCEnvironment->get();
    $rpcenv->init_request();
    $rpcenv->set_user($as_user);
    return $rpcenv;
}

# Permission check of an API call for the user (what the API server does).
sub check_perm {
    my ($info, $param) = @_;
    return if $as_user eq 'root@pam';
    # Methods open to everyone (realm list of the login box): the API server
    # does not check them.
    return if ($info->{permissions}{user} // '') eq 'world';
    PVE::RPCEnvironment->get()->check_api2_permissions($info->{permissions}, $as_user, $param);
}

sub uri_unescape { my $s = shift // ''; $s =~ tr/+/ /; $s =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge; return $s }

sub clean {
    my $v = shift;
    return '' if !defined $v;
    if (ref($v) eq 'ARRAY') { $v = join(',', map { ref($_) ? $json->encode($_) : ($_ // '') } @$v) }
    elsif (ref($v) eq 'HASH') { $v = $json->encode($v) }
    elsif (JSON::is_bool($v)) { $v = $v ? 1 : 0 }
    $v =~ s/\t/ /g; $v =~ s/\r?\n/\x1f/g;
    return $v;
}

sub field {
    my ($row, $spec) = @_;
    # "name#" returns the number of elements of an array (or keys of a hash)
    if ($spec =~ /^(.+)#$/) {
        my $v = $row;
        $v = ref($v) eq "HASH" ? $v->{$_} : undef for split /\./, $1;
        return ref($v) eq "ARRAY" ? scalar(@$v) : ref($v) eq "HASH" ? scalar(keys %$v) : (defined $v ? 1 : 0);
    }
    my ($name, $op, $arg) = $spec =~ /^([^*:]+)(?:([*:])(.+))?$/ or return '';
    my $v = $row;
    for my $k (split /\./, $name) {
        if (ref($v) eq 'HASH') { $v = $v->{$k} }
        elsif (ref($v) eq 'ARRAY' && $k =~ /^\d+$/) { $v = $v->[$k] }
        else { $v = undef; last }
    }
    return '' if !defined $v;
    if (defined $op && $v =~ /^-?[\d.eE+-]+$/) {
        $v = $op eq '*' ? $v * $arg : $v;
        return sprintf('%d', $v + ($v < 0 ? -0.5 : 0.5));
    }
    return clean($v);
}

# Flatten nested structures into "key<TAB>value" lines (dot separated keys).
sub flatten {
    my ($prefix, $v, $out) = @_;
    if (ref($v) eq 'HASH') {
        flatten($prefix eq '' ? $_ : "$prefix.$_", $v->{$_}, $out) for sort keys %$v;
    } elsif (ref($v) eq 'ARRAY' && grep { ref($_) } @$v) {
        flatten("$prefix.$_", $v->[$_], $out) for 0 .. $#$v;
    } elsif (ref($v) eq 'ARRAY') {
        # Arrays of scalars: elements separated by \x1e (values may contain commas).
        push @$out, "$prefix\t" . join("\x1e", map { clean($_) } @$v);
    } else {
        push @$out, "$prefix\t" . clean($v);
    }
}

sub call_get {
    my ($path, $param) = @_;
    my $uri_param = {};
    my ($handler, $info) = PVE::API2->find_handler('GET', $path, $uri_param);
    die "no handler for '$path'\n" if !$handler || !$info;
    my $all = { %$param, %$uri_param };
    check_perm($info, $all);
    if ($info->{proxyto} || $info->{proxyto_callback}) {
        my $rpcenv = PVE::RPCEnvironment->get();
        my $node = PVE::API2Tools::resolve_proxyto($rpcenv, $info->{proxyto_callback}, $info->{proxyto}, $all);
        if ($node ne 'localhost' && $node ne $local) {
            # Remote node: let pvesh handle the SSH tunnel.
            my @cmd = ('pvesh', 'get', $path, '--output-format', 'json');
            push @cmd, "--$_", $param->{$_} for sort keys %$param;
            open(my $fh, '-|', @cmd) or die "pvesh: $!\n";
            my $raw = do { local $/; <$fh> };
            close($fh) or die "pvesh failed for '$path'\n";
            return $raw eq '' ? undef : $json->decode($raw);
        }
    }
    my $data = $handler->handle($info, $all);
    # Streamed responses (e.g. journal) return a file handle or a path.
    if (ref($data) eq "HASH" && ref($data->{download}) eq "HASH") {
        my ($fh, $file, $enc, $type) = $data->{download}->@{qw(fh path content-encoding content-type)};
        if (defined $file) { open($fh, "<", $file) or die "open $file: $!\n" }
        my $raw = do { local $/; <$fh> };
        if (defined $enc && $enc eq "gzip") {
            require IO::Uncompress::Gunzip;
            my $out; IO::Uncompress::Gunzip::gunzip(\$raw => \$out); $raw = $out;
        }
        $data = (defined $type && $type eq "application/json") ? $json->decode($raw)->{data} : $raw;
    }
    return $data;
}

sub select_rows {
    my ($data, $path) = @_;
    my @cur = ($data);
    for my $k (split /\./, $path) {
        my @next;
        for my $c (@cur) {
            if ($k eq "**") {
                # Every element of the nested "children" lists (tree data).
                my @todo = ref($c) eq "ARRAY" ? @$c : ($c);
                while (my $e = shift @todo) {
                    next if ref($e) ne "HASH";
                    push @next, $e;
                    push @todo, @{ $e->{children} } if ref($e->{children}) eq "ARRAY";
                }
            }
            elsif ($k eq "*") { push @next, @$c if ref($c) eq "ARRAY" }
            elsif (ref($c) eq "ARRAY" && $k =~ /^\d+$/) { push @next, $c->[$k] if defined $c->[$k] }
            elsif (ref($c) eq "HASH" && defined $c->{$k}) { push @next, $c->{$k} }
        }
        @cur = @next;
    }
    return [ map { ref($_) eq "ARRAY" ? @$_ : $_ } @cur ];
}

sub format_data {
    my ($mode, $data, $fields) = @_;
    my @out;
    if ($mode eq 'json') {
        push @out, $json->encode($data);
    } elsif ($mode eq 'kv') {
        flatten('', $data, \@out) if defined $data;
    } else {
        # "@a.*.b;f1,f2" first selects nested rows ("*" walks every array element)
        if (($fields // '') =~ /^@([^;]*);(.*)$/) {
            $fields = $2;
            $data = select_rows($data, $1);
        }
        my @f = split /,/, ($fields // '');
        my $rows = ref($data) eq 'ARRAY' ? $data : defined($data) ? [$data] : [];
        for my $r (@$rows) {
            push @out, ref($r) ? join("\t", map { field($r, $_) } @f) : clean($r);
        }
    }
    return @out;
}

# Filter mode (pvesh backend): JSON on stdin, formatted lines on stdout.
#   broker.pl --filter MODE FIELDS
if (@ARGV && $ARGV[0] eq '--filter') {
    my (undef, $mode, $fields) = @ARGV;
    my $raw = do { local $/; <STDIN> } // '';
    my $data = $raw =~ /\S/ ? eval { $json->decode($raw) } : undef;
    print map { "$_\n" } format_data($mode // 'rows', $data, $fields);
    exit 0;
}

# ---------------------------------------------------------------------------
# Schema helpers (used to build forms from the official API definitions).
# ---------------------------------------------------------------------------
sub first_sentence {
    my $d = shift // '';
    $d =~ s/\s+/ /g;
    $d =~ s/^(.{0,240}?\.)\s.*$/$1/;
    return $d;
}

sub prop_row {
    my ($name, $p) = @_;
    my $fmt = $p->{format};
    my $kind = '';
    if ($p->{type} && $p->{type} eq 'array') {
        $kind = 'array';
        $fmt = $p->{items}{format} if ref($p->{items}) eq 'HASH';
    }
    my $fh = ref($fmt) eq 'HASH' ? $fmt : (defined($fmt) && !ref($fmt) ? eval { PVE::JSONSchema::get_format($fmt) } : undef);
    $kind ||= 'propstr' if ref($fh) eq 'HASH';
    $kind ||= 'list' if defined($fmt) && !ref($fmt) && $fmt =~ /-list$/;
    my $tt = eval { PVE::JSONSchema::schema_get_type_text($p) } // '';
    my $enum = ref($p->{enum}) eq 'ARRAY' ? join(',', @{ $p->{enum} }) : '';
    my $pw = ($name =~ /password|secret/ || ($p->{format} // '') eq 'pve-password') ? 1 : 0;
    return join("\t", map { clean($_) } $name, $p->{type} // 'string', $p->{optional} ? 1 : 0,
        $p->{default} // '', $enum, $tt, first_sentence($p->{description}), $kind,
        $p->{minimum} // '', $p->{maximum} // '', $pw, $p->{default_key} ? 1 : 0);
}

# schema: parameters of METHOD on PATH (uri parameters excluded).
#   rows: name type optional default enum typetext description kind min max password default_key
sub api_schema {
    my ($path, $param) = @_;
    my $method = $param->{method} // 'POST';
    my $uri = {};
    my ($h, $i) = PVE::API2->find_handler($method, $path, $uri);
    die "no '$method' handler for '$path'\n" if !$h || !$i;
    my $props = { %{ $i->{parameters}{properties} // {} } };
    # Newer schemas (e.g. HA rules) use allOf / oneOf variants selected by a
    # type property: merge all the variants.
    for my $part (@{ $i->{parameters}{allOf} // [] }) {
        $props->{$_} //= $part->{properties}{$_} for keys %{ $part->{properties} // {} };
        next if !$part->{oneOf};
        my $tp = $part->{'type-property'};
        $props->{$tp} //= $part->{'type-property-schema'} if $tp;
        for my $v (@{ $part->{oneOf} }) {
            $props->{$_} //= $v->{properties}{$_} for keys %{ $v->{properties} // {} };
        }
    }
    if (defined(my $pn = $param->{param})) {
        # Sub-fields of a property string parameter.
        my $p = $props->{$pn};
        if (!$p && $pn =~ /^([a-z]+)\d+$/) { $p = $props->{"${1}0"} }
        die "unknown parameter '$pn'\n" if !$p;
        my $fmt = $p->{type} eq 'array' ? $p->{items}{format} : $p->{format};
        $fmt = PVE::JSONSchema::get_format($fmt) if defined($fmt) && !ref($fmt);
        die "parameter '$pn' is not a property string\n" if ref($fmt) ne 'HASH';
        return [ map { prop_row($_, $fmt->{$_}) } grep { !$fmt->{$_}{alias} } sort keys %$fmt ];
    }
    my $ret = $i->{returns} // {};
    my @rows = map { prop_row($_, $props->{$_}) } grep { !exists $uri->{$_} } sort keys %$props;
    unshift @rows, "\x01returns\t" . ($ret->{type} // '') ;
    return \@rows;
}

# propparse: split a property string value into "key<TAB>value" lines.
sub api_propparse {
    my ($path, $param) = @_;
    my $method = $param->{method} // 'PUT';
    my $uri = {};
    my ($h, $i) = PVE::API2->find_handler($method, $path, $uri);
    die "no handler\n" if !$i;
    my $pn = $param->{param};
    my $props = $i->{parameters}{properties};
    my $p = $props->{$pn};
    if (!$p && $pn =~ /^([a-z]+)\d+$/) { $p = $props->{"${1}0"} }
    my $fmt = $p->{type} eq 'array' ? $p->{items}{format} : $p->{format};
    $fmt = PVE::JSONSchema::get_format($fmt) if !ref($fmt);
    my $h2 = PVE::JSONSchema::parse_property_string($fmt, $param->{value} // '');
    return [ map { "$_\t" . clean($h2->{$_}) } sort keys %$h2 ];
}

# propprint: build a property string from key=value parameters.
sub api_propprint {
    my ($path, $param) = @_;
    my $method = delete($param->{method}) // 'PUT';
    my $pn = delete $param->{param};
    my $uri = {};
    my ($h, $i) = PVE::API2->find_handler($method, $path, $uri);
    die "no handler\n" if !$i;
    my $props = $i->{parameters}{properties};
    my $p = $props->{$pn};
    if (!$p && $pn =~ /^([a-z]+)\d+$/) { $p = $props->{"${1}0"} }
    my $fmt = $p->{type} eq 'array' ? $p->{items}{format} : $p->{format};
    $fmt = PVE::JSONSchema::get_format($fmt) if !ref($fmt);
    my %v = map { $_ => $param->{$_} } grep { defined $param->{$_} && $param->{$_} ne '' } keys %$param;
    return [ PVE::JSONSchema::print_property_string(\%v, $fmt) ];
}

# pluginopts: options allowed for one type of a section config plugin family.
my %plugin_class = (
    storage => 'PVE::Storage::Plugin', realm => 'PVE::Auth::Plugin',
    sdnzone => 'PVE::Network::SDN::Zones::Plugin', sdncontroller => 'PVE::Network::SDN::Controllers::Plugin',
    sdnipam => 'PVE::Network::SDN::Ipams::Plugin', sdndns => 'PVE::Network::SDN::Dns::Plugin',
    metric => 'PVE::Status::Plugin', harule => 'PVE::HA::Rules',
);
sub api_pluginopts {
    my ($family, $param) = @_;
    my $class = $plugin_class{$family} // die "unknown plugin family '$family'\n";
    my $plugin = $class->lookup($param->{type} // die "missing type\n");
    my $opts = $plugin->options();
    my @rows = map { join("\t", $_, $opts->{$_}{optional} ? 1 : 0, $opts->{$_}{fixed} ? 1 : 0) } sort keys %$opts;
    push @rows, map { "$_\t1\t0" } grep { !$opts->{$_} } qw(type);
    if ($class->can('private')) {
        my $types = $class->private()->{plugins} // {};
        push @rows, "\x01types\t" . join(',', sort keys %$types);
    }
    return \@rows;
}

# write: execute a non-task POST/PUT/DELETE locally, with the parameters
# converted to the JSON types of the schema. Used as a fallback for calls
# that pvesh cannot perform (Rust backed endpoints refusing numeric strings).
sub api_write {
    my ($path, $param) = @_;
    my $method = delete($param->{method}) // 'POST';
    my $uri = {};
    my ($h, $i) = PVE::API2->find_handler($method, $path, $uri);
    die "no '$method' handler for '$path'\n" if !$h || !$i;
    my $props = $i->{parameters}{properties} // {};
    for my $k (keys %$param) {
        my $t = $props->{$k}{type} // '';
        $param->{$k} += 0 if ($t eq 'integer' || $t eq 'number') && $param->{$k} =~ /^-?[\d.]+$/;
        $param->{$k} = $param->{$k} ? 1 : 0 if $t eq 'boolean';
    }
    check_perm($i, { %$param, %$uri });
    my $res = $h->handle($i, { %$param, %$uri });
    return [ defined($res) ? (ref($res) ? $json->encode($res) : $res) : () ];
}

# Dispatch one request (shared by the broker loop and --once).
sub handle_request {
    my ($mode, $path, $param, $fields) = @_;
    return @{ api_schema($path, $param) } if $mode eq 'schema';
    return @{ api_propparse($path, $param) } if $mode eq 'propparse';
    return @{ api_propprint($path, $param) } if $mode eq 'propprint';
    return @{ api_pluginopts($path, $param) } if $mode eq 'pluginopts';
    if ($mode eq 'write') { request_env(); return @{ api_write($path, $param) } }
    if ($mode eq 'perm') {
        my $rpcenv = request_env();
        return ($rpcenv->check($as_user, $path, [ $param->{priv} ], 1) ? "1" : "0");
    }
    request_env();
    return format_data($mode, call_get($path, $param), $fields);
}

sub parse_query {
    my $param = {};
    for my $pair (split /&/, shift // '') {
        my ($k, $v) = split /=/, $pair, 2;
        $param->{uri_unescape($k)} = uri_unescape($v) if defined $k && $k ne '';
    }
    return $param;
}

# Broker mode: load the API stack once (this is the slow part, ~1-2 s).
require PVE::RPCEnvironment;
require PVE::API2;
require PVE::API2Tools;
require PVE::Cluster;
require PVE::INotify;
require PVE::JSONSchema;
PVE::RPCEnvironment->setup_default_cli_env();
$local = PVE::INotify::nodename();

# One-shot mode (pvesh backend): broker.pl --once MODE PATH QUERY FIELDS
if (@ARGV && $ARGV[0] eq '--once') {
    my (undef, $mode, $path, $query, $fields) = @ARGV;
    my @out = eval { handle_request($mode, $path, parse_query($query), $fields) };
    if (my $err = $@) { $err =~ s/\s+$//; print STDERR "$err\n"; exit 1 }
    print map { "$_\n" } @out;
    exit 0;
}

print "\x04READY\t$local\n";

while (my $line = <STDIN>) {
    chomp $line;
    my ($mode, $path, $query, $fields) = split /\t/, $line, 4;
    next if !defined $path;
    my @out;
    eval { @out = handle_request($mode, $path, parse_query($query), $fields) };
    if (my $err = $@) {
        $err =~ s/\s+$//; $err =~ s/[\t\n]/ /g;
        print "\x04ERR\t$err\n";
    } else {
        print map { "$_\n" } @out;
        print "\x04OK\n";
    }
}
