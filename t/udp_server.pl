use IO::Socket::INET;

my $port = $ARGV[0];

# Create a UDP socket
my $socket = IO::Socket::INET->new(
    LocalPort => $port,
    Proto => 'udp'
) or die "Could not create socket: $!";

print "UDP echo server is listening on port $port\n";

# Receive and echo UDP packets
while (1) {
    my $data;
    my $client_address = $socket->recv($data, 1024);
    print "Received packet from $client_address: $data\n";
    $socket->send($data);
}

# Close the socket
$socket->close();
