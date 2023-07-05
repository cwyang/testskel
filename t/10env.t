use strict;
use warnings;
use Test::More;
use t::Util;

my $resp = `ip netns identify`;
like $resp, qr/^client$/, "must be in netns 'client'";

$PROGNAME = '<NOT DEFINED>' unless defined $PROGNAME;

my $fn = bindir() . "/$PROGNAME";
ok -x $fn, "$PROGNAME is ready";
is system("$fn -v > /dev/null"), 0, "$PROGNAME can run";

plan skip_all => "$PROGNAME not found" unless -x $fn;

done_testing