# -*- Mode: perl -*-
use strict;
use warnings;
use Test::More;
use Net::EmptyPort qw(check_port);
use t::Util;

plan skip_all => "nc not found"
    unless prog_exists("nc");

# ns
# client 10.10.1.2
# server 10.10.2.2

my ($srvip, $srvport) = ("10.10.2.2", 8888);
my $unreachable_ip = "10.10.2.100";
my $cltport = 7777;

sub spawn_test_server {
    my ($ip, $port) = @_;
    my $server = spawn_server_with_ns("server",
				      argv => [ qw(nc -kl), $port ],
				      is_ready =>  sub {
					  check_port {
					      host => $ip,
					      port => $port,
					      proto => "tcp",
					  };
				      },
	);
}
sub spawn_udp_server {
    my ($ip, $port) = @_;
    my $server = spawn_server_with_ns("server",
				      argv => [ qw(perl t/udp_server.pl), $port ],
				      is_ready =>  sub {
					  check_port {
					      host => $ip,
					      port => $port,
					      proto => "udp",
					  };
				      },
	);
}

sub test_timeout {
    my ($arg, $desc) = @_;
    local $@;
    my $gotsig = 0;
    local $SIG{ALRM} = sub {
        $gotsig = 1;
        die "gotsig";
    };
    alarm(1);
    eval { `$arg` };
    alarm(0);
    ok $gotsig, $desc;
}

subtest 'ICMP' => sub {
    my $resp;
    my $x = "ip netns exec client";

    $resp = `$x ping -c 1 $srvip 2>&1`;
    is $?, 0, "should ping";
    $resp = `$x ping -c 1 -W 1 $unreachable_ip 2>&1`;
    isnt $?, 0, "shouldn't ping";

    $x = "ip netns exec ";
    is(system($x . "client ping -c 1 -W 1 10.10.2.2 > /dev/null"), 0);
    is(system($x . "client ping -c 1 -W 1 10.10.2.3 > /dev/null"), 0);
    is(system($x . "client ping -c 1 -W 1 10.10.2.4 > /dev/null"), 0);
    is(system($x . "server ping -c 1 -W 1 10.10.1.2 > /dev/null"), 0);
};

subtest 'TCP' => sub {
    my $guard = spawn_test_server $srvip, $srvport;
    
    my $resp;
    my $x = "ip netns exec client";

    $resp = `$x nc -N $srvip $srvport < /dev/null 2>&1`;
    is $?, 0, "should connect";

    $resp = `$x nc -N $srvip ${\( $srvport+1 )} < /dev/null 2>&1`;
    isnt $?, 0, "cannot connect";

    test_timeout "nc -N $unreachable_ip $srvport < /dev/null 2>&1", "should be timed-out";
};

subtest 'UDP' => sub {
    my $guard = spawn_udp_server $srvip, $srvport;
    
    my $resp;
    my $x = "ip netns exec client";

    $resp = `$x perl t/udp_client.pl $srvip $srvport hi`;
    like $resp, qr{^hi$}is, "echo back";

    $resp = `$x perl t/udp_client.pl $srvip ${\( $srvport+1 )} hi`;
    is $resp, "", "no echo back";

    test_timeout "$x perl t/udp_client.pl $unreachable_ip $srvport hi", "should be timed-out";
};

done_testing;
