#!/bin/bash

# Enable error handling
set -eE

# Function to execute ip netns exec command
ip_ns() {
    local netns=$1
    shift
    ip netns exec "$netns" "$@"
}

# Delete router namespace if it exists
ip netns del router &>/dev/null || true

# Create router namespace
ip netns add router

# Create veth pairs
ip link add client-veth0 type veth peer name router-veth0
ip link add server-veth0 type veth peer name router-veth1

# Move veth interfaces to router namespace
ip link set router-veth0 netns router
ip link set router-veth1 netns router

# Configure IP addresses in namespaces
ip addr add 10.10.1.2/24 dev client-veth0
ip addr add 10.10.2.2/24 dev server-veth0
ip addr add 10.10.2.3/24 dev server-veth0
ip_ns router ip addr add 10.10.1.1/24 dev router-veth0
ip_ns router ip addr add 10.10.2.1/24 dev router-veth1

# Bring up interfaces
ip link set client-veth0 up
ip link set server-veth0 up
ip_ns router ip link set dev router-veth0 up
ip_ns router ip link set dev router-veth1 up

echo "Network namespaces, veth pairs, and IP addresses have been set up."
