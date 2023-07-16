import socket, sys, struct
IP_PKTINFO = 8

def unpack_cmsg(cmsgs):
    for level, type, data in cmsgs:
        _ifindex, _, _, src_addr = struct.unpack('IHH4s', data)
        return (level, type, data), socket.inet_ntoa(src_addr)

def udp_echo_server(port):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_IP, IP_PKTINFO, 1)
    sock.bind(('0.0.0.0', port))
    while True:
        data, cmsgs, _flags, addr = sock.recvmsg(1024, 1024)
        cmsg, local_addr = unpack_cmsg(cmsgs)
        sock.sendmsg([data], [cmsg], 0, addr)
        print(f"RECV: {addr[0]}:{addr[1]} -> {local_addr}:{port} - [{data.decode()}]")
    sock.close()
    
port = int(sys.argv[1])
udp_echo_server(port)
