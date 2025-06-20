#!/bin/sh

# hostname of the gateway - it must accept vxlan and DHCP traffic
# clients get it as env variable
export GATEWAY_NAME="${GATEWAY_NAME:-gateway}"

# K8S DNS IP address
# clients get it as env variable
export K8S_DNS_IPS="${K8S_DNS_IPS:-172.16.0.1 172.16.0.2}"

# Blank sepated IPs not sent to the POD gateway but to the default K8S
# This is needed, for example, in case your CNI does
# not add a non-default rule for the K8S addresses (Flannel does)
export NOT_ROUTED_TO_GATEWAY_CIDRS="${NOT_ROUTED_TO_GATEWAY_CIDRS:-}"

# Vxlan ID to use
export VXLAN_ID="${VXLAN_ID:-42}"
# Vxlan Port to use, change it to 4789 (preferably) when using Cillium
export VXLAN_PORT="${VXLAN_PORT:-4789}"
# VXLAN need an /24 IP range not conflicting with K8S and local IP ranges
export VXLAN_IP_NETWORK="${VXLAN_IP_NETWORK:-172.16.0.0/24}"
# Keep a range of IPs for static assignment in nat.conf
export VXLAN_GATEWAY_FIRST_DYNAMIC_IP="${VXLAN_GATEWAY_FIRST_DYNAMIC_IP:-20}"

# If using a VPN, interface name created by it
export VPN_INTERFACE="${VPN_INTERFACE:-tun0}"
# Prevent non VPN traffic to leave the gateway
export VPN_BLOCK_OTHER_TRAFFIC="${VPN_BLOCK_OTHER_TRAFFIC:-true}"
# If VPN_BLOCK_OTHER_TRAFFIC is true, allow VPN traffic over this port
export VPN_TRAFFIC_PORT="${VPN_TRAFFIC_PORT:-443}"
# Traffic to these IPs will be send through the K8S gateway
export VPN_LOCAL_CIDRS="${VPN_LOCAL_CIDRS:-10.0.0.0/8 192.168.0.0/16}"

# DNS queries to these domains will be resolved by K8S DNS instead of
# the default (typcally the VPN client changes it)
export DNS_LOCAL_CIDRS="${DNS_LOCAL_CIDRS:-local}"
# Dns to use for local resolution, if unset, will use default resolv.conf
export DNS_LOCAL_SERVER="${DNS_LOCAL_SERVER:-}"

# dnsmasq monitors directories. /etc/resolv.conf in a container is in another
# file system so it does not work. To circumvent this a copy is made using
# inotifyd
export RESOLV_CONF_COPY="${RESOLV_CONF_COPY:-/etc/resolv_copy.conf}"

# ICMP heartbeats are used to ensure the pod-gateway is connectable from the clients.
# The following value can be used to to provide more stability in an unreliable network connection.
export CONNECTION_RETRY_COUNT="${CONNECTION_RETRY_COUNT:-1}"

# you want to disable DNSSEC with the gateway then set this to false
export GATEWAY_ENABLE_DNSSEC="${GATEWAY_ENABLE_DNSSEC:-true}"

# If you use nftables for iptables you need to set this to yes
export IPTABLES_NFT="${IPTABLES_NFT:-no}"

# Set to WAN/VPN IP to enable SNAT instead of Masquerading
export SNAT_IP="${SNAT_IP:-}"

# Set the VPN MTU. It also adjust the VXLAN MTU to avoid fragmenting the package in the gateway (VXLAN-> MTU)
export VPN_INTERFACE_MTU="${VPN_INTERFACE_MTU:-}"
