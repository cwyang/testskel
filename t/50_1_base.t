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

plan skip_all => "nc not found"
    unless prog_exists("nc");

my ($vpp, $vppctl) = ($ENV{VPP}, $ENV{VPPCTL});
my $tempdir = tempdir(CLEANUP => 1);
my $accesslog_name="access.log";

# ns
# client 10.10.1.2
# server 10.10.2.2

my ($allow_ip, $allowport) = ("10.10.2.2", 8888);
my ($deny_ip, $deny_port) = ("10.10.2.3", 8888);

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
show inter
EOT

# deny to 10.10.2.3:8888 (TCP 6)
# allow to 10.10.2.2/31 (ALL)
# allow to port 8888 (TCP 6 / UDP 17)
# deny all
my $acl_rule = <<"EOT";
set acl-plugin acl deny proto 6 dst 10.10.2.3/32 dport 8888 desc deny-host-port
set acl-plugin acl permit+reflect dst 10.10.2.2/31 desc allow-host
set acl-plugin acl permit+reflect proto 6 dport 8888, permit+reflect proto 17 dport 8888 desc allow-port
set acl-plugin acl deny desc deny-all
set acl-plugin interface host-client-veth0 input acl 0
set acl-plugin interface host-client-veth0 input acl 1
set acl-plugin interface host-client-veth0 input acl 2
set acl-plugin interface host-client-veth0 input acl 3
set acl-plugin interface host-client-veth0 output acl 3
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
    my ($conffh, $conffn) = tempfile(UNLINK => 0);
    print $conffh $conf or confess("failed to write to $conffn: $!");
    $conffh->flush or confess("failed to write to $conffn: $!");
    system("$vppctl exec $conffn");
    Test::More::diag($conf) if $ENV{TEST_DEBUG};
    if ($? >> 8 != 0) {
	confess("vppctl($conffn) returns $? error: $!");
    }
}

sub spawn_vpp {
    my ($conf) = @_;
    my @opts;
    my $logname;
    
    if (ref $conf eq 'HASH') {
        @opts = @{$conf->{opts}} if $conf->{opts};
        $logname = $conf->{logname};
        $conf = $conf->{conf};
	$conf = "" unless defined $conf;
    }
    $conf = <<"EOT";
unix {
	nodaemon
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
    Test::More::diag($conf) if $ENV{TEST_DEBUG};
    
    my ($guard, $pid) = spawn_server_with_ns "router", (
        argv => [ $vpp, "-c", $conffn, @{@opts || []} ],
        is_ready => sub {
	    system("nc -Uz /run/vpp/cli.sock > /dev/null 2>&1") ? 0 : 1;
        },
    );
    run_vpp_rule($interface_rule);
    run_vpp_rule($acl_rule);

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

    my $server = spawn_vpp({logfn => $logfn});

    $cmd->($server);
    
    undef $server->{guard}; # log will be emitted before the server exits

    my @log = do {
        open my $fh, "<", $logfn
            or die "failed to open access_log $logfn:$!";
        map { my $l = $_; chomp $l; $l } <$fh>;
    };

    local $Test::Builder::Level = $Test::Builder::Level + 1;
    for (my $i = 0; $i != @$expected; ++$i) {
        if (ref $expected->[$i] eq 'CODE') {
            $expected->[$i]->($log[$i], $server);
        } else {
            like $log[$i], $expected->[$i];
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
	    $resp = `$x ping -c 1 -W 1 $deny_ip 2>&1`;
	    is $?, 0, "shouldn't ping";
        },
        '%h %l %u %t "%r" %s %b "%{Referer}i" "%{User-agent}i"',
	#        [ qr{^127\.0\.0\.1 - - \[[0-9]{2}/[A-Z][a-z]{2}/20[0-9]{2}:[0-9]{2}:[0-9]{2}:[0-9]{2} [+\-][0-9]{4}\] "GET / HTTP/1\.1" 200 6 "http://example.com/" "curl/.*"$} ],
	[ qr{^11} ],
    );
};

done_testing;
