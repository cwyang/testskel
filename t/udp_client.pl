use IO::Socket::INET;

my ($ip, $port, $msg) = @ARGV;

my $socket = IO::Socket::INET->new(
    PeerAddr => $ip,
    PeerPort => $port,
    Proto => 'udp'
) or die "Could not create socket: $!";

print STDERR "UDP echo client is connecting on $ip $port\n";

local $SIG{ALRM} = sub {
    $gotsig = 1;
    die "gotsig";
};

alarm(5);

$socket->send($msg);
my $data;
my $client_address = $socket->recv($data, 1024);
print $data;

$socket->close();
alarm(0);
