use strict;
use warnings;
use Test::More;
use t::Util;

my $resp = `ip netns identify`;
like $resp, qr/^client$/, "must be in netns 'client'";

my @progs = split(/\s+/, $ENV{PROGS});

for my $i ( @progs ) {
    ok -x $i, "$i is ready";
}

done_testing