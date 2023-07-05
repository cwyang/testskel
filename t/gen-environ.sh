#!/bin/bash

# Enable error handling
set -eE

# Function to execute ip netns exec command
ip_ns() {
    local netns=$1
    shift
    ip netns exec "$netns" "$@"
}

# Delete network namespaces if they exist
ip netns del client &>/dev/null || true
ip netns del router &>/dev/null || true
ip netns del server &>/dev/null || true

# Create network namespaces
ip netns add client
ip netns add router
ip netns add server

# Create veth pairs
ip link add veth0 type veth peer name client-veth0
ip link add server-veth0 type veth peer name router-veth0

# Move veth interfaces to corresponding namespaces
ip link set veth0 netns client
ip link set client-veth0 netns router
ip link set server-veth0 netns router
ip link set router-veth0 netns server

# Configure IP addresses in namespaces
ip_ns client ip addr add 10.10.1.2/24 dev veth0
ip_ns router ip addr add 10.10.1.1/24 dev client-veth0
ip_ns router ip addr add 10.10.2.1/24 dev server-veth0
ip_ns server ip addr add 10.10.2.2/24 dev router-veth0
ip_ns server ip addr add 10.10.2.3/24 dev router-veth0

# Bring up interfaces
ip_ns client ip link set dev veth0 up
ip_ns router ip link set dev client-veth0 up
ip_ns router ip link set dev server-veth0 up
ip_ns server ip link set dev router-veth0 up

# Set default route in other namespaces
ip_ns client ip route add default via 10.10.1.1
ip_ns router ip route add default via 10.10.1.1
ip_ns server ip route add default via 10.10.2.1

echo "Network namespaces, veth pairs, IP addresses, and routes have been set up."
