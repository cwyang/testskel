# -*- Mode: perl -*-
#
# base test
#
use strict;
use warnings;
use File::Temp qw(tempdir);
use Test::More;
use Net::EmptyPort qw(check_port);
use t::Util;

plan skip_all => "nc not found"
    unless prog_exists("nc");

my $tempdir = tempdir(CLEANUP => 1);

my $logname = "access.log"

sub doit {
    my ($cmd, $args, $expected) = @_;

    unlink "$tempdir/$logname";
    my $server = spawn_dut({conf => <<"EOT"});
#This is a test conf file
foo: bar
EOT
    $cmd->($server);
