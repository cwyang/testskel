# -*- Mode: perl -*-
#
# base test
#
use strict;
use warnings;
use File::Temp qw(tempdir tempfile);
use Test::More;
use Net::EmptyPort qw(check_port);
use t::Util;
use Carp;
use Time::HiRes qw(sleep);

plan skip_all => "nc not found"
    unless prog_exists("nc");

my $debug = $ENV{TEST_DEBUG};

my ($vpp, $vppctl) = ($ENV{VPP}, $ENV{VPPCTL});
my $tempdir = tempdir(CLEANUP => $debug ? 0 : 1);
my $accesslog_name="access.log";

my $client_ip = "10.10.1.2";
my $allow_ip = "10.10.2.2";
my $deny_ip  = "10.10.2.3";
my $nolog_ip = "10.10.2.4";
my $unreachable_ip = "10.10.2.5";
my $server_port = 8888;

my $interface_rule = <<"EOT";
create host-interface name client-veth0
set interface ip address host-client-veth0 10.10.1.1/24
set interface state host-client-veth0 up
ip route add 10.10.1.0/24 via 10.10.1.2
create host-interface name server-veth0
set interface ip address host-server-veth0 10.10.2.1/24
set interface state host-server-veth0 up
ip route add 10.10.2.0/24 via 10.10.2.2
ip route add 10.10.2.3/32 via 10.10.2.2
ip route add 10.10.2.4/32 via 10.10.2.2
EOT

# deny to 10.10.2.3:8888 (TCP 6)
# allow to 10.10.2.2/31 (ALL)
# allow to port 8888 (TCP 6 / UDP 17)
# deny all
my $acl_rule = <<"EOT";
set acl-plugin acl permit+reflect dst 10.10.2.4/32 desc allow-nolog nolog
set acl-plugin acl deny proto 6 dst 10.10.2.3/32 dport 8888 desc deny-host-port
set acl-plugin acl permit+reflect dst 10.10.2.2/31 desc allow-host
set acl-plugin acl permit+reflect proto 6 dport 8888 desc allow-tcp-port , permit+reflect proto 17 dport 8888 desc allow-udp-port
set acl-plugin acl deny desc deny-all
set acl-plugin interface host-client-veth0 input acl 0
set acl-plugin interface host-client-veth0 input acl 1
set acl-plugin interface host-client-veth0 input acl 2
set acl-plugin interface host-client-veth0 input acl 3
set acl-plugin interface host-client-veth0 input acl 4
set acl-plugin interface host-client-veth0 output acl 4
show acl-plugin interface sw_if_index 1 acl
EOT

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

sub run_vpp_rule {
    my ($conf) = @_;
    my ($conffh, $conffn) = tempfile(UNLINK => $debug ? 0 : 1);
    print $conffh $conf or confess("failed to write to $conffn: $!");
    $conffh->flush or confess("failed to write to $conffn: $!");
    system("$vppctl exec $conffn");
    Test::More::diag($conf) if $debug;
    if ($? >> 8 != 0) {
	confess("vppctl($conffn) returns $? error: $!");
    }
}

sub spawn_vpp {
    my ($conf) = @_;
    my @opts;
    my $logname;
    my $rule;
    
    if (ref $conf eq 'HASH') {
        @opts = @{$conf->{opts}} if $conf->{opts};
        $logname = $conf->{logname};
	$rule = $conf->{rule};
        $conf = $conf->{conf} || "";
    }
    $conf = <<"EOT";
unix {
	nodaemon
	coredump-size unlimited
	cli-listen /run/vpp/cli.sock
	log /var/log/vpp/vpp.log
}
logging {
	default-log-level info
	default-syslog-log-level info
}
plugins {
	plugin dpdk_plugin.so { disable }
}
$conf
EOT

    my ($conffh, $conffn) = tempfile(UNLINK => 1);
    print $conffh $conf or confess("failed to write to $conffn: $!");
    $conffh->flush or confess("failed to write to $conffn: $!");
    Test::More::diag($conf) if $debug;
    
    my ($guard, $pid) = spawn_server_with_ns "router", (
        argv => [ $vpp, "-c", $conffn, @{@opts || []} ],
	close_stdout => 1,
        is_ready => sub {
	    system("nc -Uz /run/vpp/cli.sock > /dev/null 2>&1") ? 0 : 1;
        },
    );
    run_vpp_rule($interface_rule);
    run_vpp_rule($acl_rule);
    if (defined($rule)) {
	run_vpp_rule($rule);
    }

    return +{
        guard => $guard,
        pid => $pid,
        conf_file => $conffn,
    };
}

sub doit {
    my ($cmd, $args, $expected) = @_;
    $args = { format => $args }
        unless ref $args;
    my $logfn = "$tempdir/$accesslog_name";
    unlink $logfn;

    my $server = spawn_vpp({rule => <<"EOT", logfn => $logfn});
set acl-plugin log enable path $logfn
set acl-plugin timeout tcp 100 tcptrans 200 reset 1
EOT

    $cmd->($server);

    system("$vppctl show acl-plugin interface sw_if_index 1 acl");
    
    undef $server->{guard}; # log will be emitted before the server exits

    my @log = do {
        open my $fh, "<", $logfn
            or die "failed to open access_log $logfn:$!";
        map { my $l = $_; chomp $l; $l } <$fh>;
    };
    Test::More::diag(join("\n", @log)) if $debug;

    local $Test::Builder::Level = $Test::Builder::Level + 1;
    for (my $i = 0; $i != @$expected; ++$i) {
        if (ref $expected->[$i] eq 'CODE') {
            $expected->[$i]->($log[$i], $server);
        } else {
            like $log[$i], $expected->[$i], "match ${ \(split ' ', $expected->[$i])[0] }";
        }
    }
}

subtest "ICMP" => sub {
    doit(
        sub {
	    my $server = shift;
	    my $resp;
	    my $x = "ip netns exec client";

	    $resp = `$x ping -c 1 -W 1 $allow_ip 2>&1`;
	    is $?, 0, "should ping";
	    $resp = `$x ping -c 1 -W 1 $unreachable_ip 2>&1`;
	    isnt $?, 0, "shouldn't ping";
	    $resp = `$vppctl show acl-plugin interface sw_if_index 1 acl`;
	    is $?, 0, "vppctl";
	    print STDERR $resp;
        },
        "",
	# we should see icmp type 8 (echo request), code 0
	[ qr{ALLOW .+ ip4 - $client_ip 8 $allow_ip 0 proto 1},
	  qr{DENY .+ ip4 - $client_ip 8 $unreachable_ip 0 proto 1},
	],
    );
};

subtest "TCP" => sub {
    doit(
        sub {
	    my $server = shift;
	    my $guard = spawn_test_server $nolog_ip, $server_port;
    
	    my $resp;
	    my $x = "ip netns exec client";

	    $resp = `$x nc -N $allow_ip $server_port < /dev/null 2>&1`;
	    is $?, 0, "should connect";
	    $resp = `$x nc -N $allow_ip ${\($server_port+1 )} < /dev/null 2>&1`;
	    isnt $?, 0, "should connection refused";
	    $resp = `$x nc -N $deny_ip ${\($server_port+1 )} < /dev/null 2>&1`;
	    isnt $?, 0, "should connection refused";
	    test_timeout "nc -N $unreachable_ip $server_port < /dev/null 2>&1", "should be allowed but timed-out";
	    test_timeout "nc -N $deny_ip $server_port < /dev/null 2>&1", "should be denied and timed-out";
	    sleep 1;
        },
        "",
	[ qr{ALLOW .+ ip4 - $client_ip \d+ $allow_ip $server_port proto 6},
	  qr{FIN .+ ip4 - $client_ip \d+ $allow_ip $server_port proto 6},
	  qr{ALLOW .+ ip4 - $client_ip \d+ $allow_ip ${\( $server_port+1 )} proto 6},	  
	  qr{RST-SVR .+ ip4 - $allow_ip ${\( $server_port+1 )} $client_ip \d+ proto 6},
	  qr{ALLOW .+ ip4 - $client_ip \d+ $deny_ip ${\( $server_port+1 )} proto 6},	  
	  qr{RST-SVR .+ ip4 - $deny_ip ${\( $server_port+1 )} $client_ip \d+ proto 6},
	  qr{ALLOW .+ ip4 - $client_ip \d+ $unreachable_ip $server_port proto 6},
	  # ALLOW세션의 경우 retried packet이 추가 로깅되지 않음
	  qr{DENY .+ ip4 - $client_ip \d+ $deny_ip $server_port proto 6},
	  # DENY세션의 경우 세션이 유지되지 않으므로 retried packet이 추가 로깅됨
	],
    );
};

done_testing;
