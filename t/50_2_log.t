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

my $logname = "access.log";

sub spawn_dut {
    my ($conf) = @_;
    my @opts;
    my $logname;
    
    if (ref $conf eq 'HASH') {
        @opts = @{$conf->{opts}} if $conf->{opts};
        $conf = $conf->{conf};
        $logname = $conf->{logname};
    }
    $conf = <<"EOT";
$conf
This is postconf;
EOT

    my ($conffh, $conffn) = tempfile(UNLINK => 1);
    print $conffh $conf or confess("failed to write to $conffn: $!");
    $conffh->flush or confess("failed to write to $conffn: $!");
    Test::More::diag($conf) if $ENV{TEST_DEBUG};
    
    my ($guard, $pid) = spawn_server(
        argv => [ "foo", $conffn, @{@opts || []} ],
        is_ready => sub {
            1;
        },
    );
    return +{
        guard => $guard,
        pid => $pid,
        conf_file => $conffn,
    };
}

sub doit {
    my ($cmd, $logname, $expected) = @_;

    unlink "$tempdir/$logname";
    my $server = spawn_dut({conf => <<"EOT", logname => "$tempdir/$logname"});
#This is a test conf file
foo: bar
EOT
    $cmd->($server);

    # server should output logs here
    
    undef $server->{guard};

    my @log = do {
        open my $fh, "<", "$tempdir/access_log"
            or die "failed to open access_log:$!";
        map { my $l = $_; chomp $l; $l } <$fh>;   #chomping all lines
    };

    local $Test::Builder::Level = $Test::Builder::Level + 1;
    for (my $i = 0; $i != @$expected; ++$i) {
        if (ref $expected->[$i] eq 'CODE') {
            $expected->[$i]->($log[$i], $server);
        } else {
            like $log[i], $expected->[$i];
        }
    }
}

subtest "test" => sub {
    doit(
        sub {
            my $server = shift;
        },
        'sample arg',
        [ qr{^hello$} ],
    );
};

done_testing;
