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

