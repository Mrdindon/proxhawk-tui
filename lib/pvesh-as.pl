#!/usr/bin/perl
# pvesh-as.pl - pvesh as another Proxmox VE user (PVETTY_USER).
#
# Same command line as pvesh. The call runs as that user (tasks are logged
# under its name) and is checked with its permissions first, exactly like
# the API server does (check_api2_permissions on the called method only, not
# on the internal calls it makes). pvetty puts a "pvesh" wrapper calling it
# first in PATH when it runs as a user other than root@pam.
use strict;
use warnings;

use PVE::CLI::pvesh;
use PVE::RPCEnvironment;
use PVE::RESTHandler;

my $user = $ENV{PVETTY_USER} or die "pvesh-as: PVETTY_USER is not set\n";

no warnings 'redefine';
*PVE::CLI::pvesh::setup_environment = sub {
    PVE::RPCEnvironment->setup_default_cli_env();
    PVE::RPCEnvironment->get()->set_user($user);
};
my $handle = \&PVE::RESTHandler::handle;
our $depth = 0;
*PVE::RESTHandler::handle = sub {
    my ($self, $info, $param) = @_;
    if ($depth == 0) {
        PVE::RPCEnvironment->get()->check_api2_permissions($info->{permissions}, $user, $param // {});
    }
    local $depth = $depth + 1;
    return $handle->(@_);
};

PVE::CLI::pvesh->run_cli_handler();
