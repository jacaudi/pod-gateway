#!/bin/sh
set -euo pipefail

# --- Utility functions ---
require_var() {
  VAR_NAME="$1"
  if [ -z "${!VAR_NAME:-}" ]; then
    echo "ERROR: Required variable $VAR_NAME is not set." >&2
    exit 1
  fi
}

# --- Load main settings ---
if [ -f /default_config/settings.sh ]; then
  . /default_config/settings.sh
fi
if [ -f /config/settings.sh ]; then
  . /config/settings.sh
fi

# --- Check for required variables ---
require_var VXLAN_ID
require_var VXLAN_IP_NETWORK
require_var VPN_INTERFACE
require_var VPN_LOCAL_CIDRS
require_var VXLAN_STATIC_IP

# --- Switch to nftables if requested ---
if [ "${IPTABLES_NFT:-no}" = "yes" ]; then
  rm -f /sbin/iptables
  ln -s /sbin/iptables-translate /sbin/iptables
fi

# --- Remove existing vxlan0 interface if present ---
if ip addr | grep -q vxlan0; then
  ip link del vxlan0
fi

# --- Enable IP forwarding if not already enabled ---
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" -ne 1 ]; then
  echo "ip_forward is not enabled; enabling."
  sysctl -w net.ipv4.ip_forward=1
fi

# --- Create VXLAN NIC for gateway pod ---
VXLAN_GATEWAY_IP=$(echo "$VXLAN_IP_NETWORK" | awk -F'[./]' '{print $1 "." $2 "." $3 ".1"}')
ip link add vxlan0 type vxlan id "$VXLAN_ID" dev eth0 dstport "${VXLAN_PORT:-0}" || true
ip addr add "$VXLAN_GATEWAY_IP/24" dev vxlan0 || true
ip link set up dev vxlan0

# --- Set VXLAN MTU if specified ---
if [ -n "${VPN_INTERFACE_MTU:-}" ]; then
  ETH0_INTERFACE_MTU=$(cat /sys/class/net/eth0/mtu)
  VXLAN0_INTERFACE_MAX_MTU=$((ETH0_INTERFACE_MTU - 50))
  if [ "$VPN_INTERFACE_MTU" -ge "$VXLAN0_INTERFACE_MAX_MTU" ]; then
    ip link set mtu "$VXLAN0_INTERFACE_MAX_MTU" dev vxlan0
  else
    ip link set mtu "$VPN_INTERFACE_MTU" dev vxlan0
  fi
fi

# --- Add routing rule to suppress main table for policy routing ---
if ! ip rule | grep -q "from all lookup main suppress_prefixlength 0"; then
  ip rule add from all lookup main suppress_prefixlength 0 preference 50
fi

# --- Enable outbound NAT or masquerading ---
if [ -n "${SNAT_IP:-}" ]; then
  echo "Enable SNAT"
  iptables -t nat -A POSTROUTING -o "$VPN_INTERFACE" -j SNAT --to "$SNAT_IP"
else
  echo "Enable Masquerading"
  iptables -t nat -A POSTROUTING -j MASQUERADE
fi

# --- Configure NAT and firewall rules for VPN traffic ---
if [ -n "$VPN_INTERFACE" ]; then
  # Open inbound NAT ports as defined in nat.conf
  while read -r line; do
    case "$line" in 
      \#*) continue;; # Skip comment lines
      "") continue;; # Skip empty lines
    esac
    echo "Processing line: $line"
    NAME=$(echo "$line" | cut -d' ' -f1)
    IP=$(echo "$line" | cut -d' ' -f2)
    PORTS=$(echo "$line" | cut -d' ' -f3)
    for port_string in $(echo "$PORTS" | tr ',' ' '); do
      PORT_TYPE=$(echo "$port_string" | cut -d':' -f1)
      PORT_NUMBER=$(echo "$port_string" | cut -d':' -f2)
      echo "IP: $IP , NAME: $NAME , PORT: $PORT_NUMBER , TYPE: $PORT_TYPE"
      # DNAT incoming VPN traffic to the correct VXLAN static IP
      iptables -t nat -A PREROUTING -p "$PORT_TYPE" -i "$VPN_INTERFACE" \
        --dport "$PORT_NUMBER" -j DNAT \
        --to-destination "$VXLAN_STATIC_IP:$PORT_NUMBER"
      # Allow forwarding of the port to the VXLAN static IP
      iptables -A FORWARD -p "$PORT_TYPE" -d "$VXLAN_STATIC_IP" \
        --dport "$PORT_NUMBER" -m state --state NEW,ESTABLISHED,RELATED \
        -j ACCEPT
    done
  done </config/nat.conf

  # Allow VXLAN UDP traffic on eth0 if VXLAN_PORT is set
  if [ -n "${VXLAN_PORT:-}" ]; then
    echo "Allow VXLAN traffic from eth0"
    iptables -A INPUT -i eth0 -p udp --dport="$VXLAN_PORT" -j ACCEPT
    iptables -A OUTPUT -o eth0 -p udp --dport="$VXLAN_PORT" -j ACCEPT
  fi

  # Allow DHCP traffic from vxlan0
  echo "Allow DHCP traffic from vxlan"
  iptables -A INPUT -i vxlan0 -p udp --sport=68 --dport=67 -j ACCEPT

  # Set up VPN firewall rules
  echo "Setting iptables for VPN with NIC $VPN_INTERFACE"
  iptables -A FORWARD -i "$VPN_INTERFACE" -m state --state ESTABLISHED,RELATED -j ACCEPT
  iptables -A FORWARD -i "$VPN_INTERFACE" -j REJECT

  # Block all non-VPN traffic if requested
  if [ "${VPN_BLOCK_OTHER_TRAFFIC:-false}" = "true" ]; then
    iptables --policy FORWARD DROP
    iptables -I FORWARD -o "$VPN_INTERFACE" -j ACCEPT
    iptables --policy OUTPUT DROP
    iptables -A OUTPUT -p udp --dport "$VPN_TRAFFIC_PORT" -j ACCEPT
    iptables -A OUTPUT -p tcp --dport "$VPN_TRAFFIC_PORT" -j ACCEPT
    for local_cidr in $VPN_LOCAL_CIDRS; do
      iptables -A OUTPUT -d "$local_cidr" -j ACCEPT
    done
    iptables -A OUTPUT -o "$VPN_INTERFACE" -j ACCEPT
    iptables -A OUTPUT -o vxlan0 -j ACCEPT
  fi

  # Add routes for local networks via the K8S gateway
  K8S_GW_IP=$(/sbin/ip route | awk '/default/ { print $3 }')
  for local_cidr in $VPN_LOCAL_CIDRS; do
    ip route add "$local_cidr" via "$K8S_GW_IP" || true
  done
fi

# --- Print routing table and iptables rules for sanity check ---
echo "==== ROUTING TABLE ===="
ip route
ip -6 route || true

echo "==== IPTABLES (filter) ===="
iptables -L -v -n

echo "==== IPTABLES (nat) ===="
iptables -t nat -L -v -n

# --- Output external IP after VPN is up ---
if [ -n "${VPN_INTERFACE:-}" ]; then
  echo "Waiting for VPN interface $VPN_INTERFACE to be up..."
  for i in $(seq 1 10); do
    if ip link show "$VPN_INTERFACE" | grep -q 'state UP'; then
      break
    fi
    sleep 1
  done
  echo "VPN interface $VPN_INTERFACE is up. Checking external IP..."
  # Use curl or wget to get external IP via VPN interface
  if command -v curl >/dev/null 2>&1; then
    EXT_IP=$(curl --interface "$VPN_INTERFACE" -s https://api.ipify.org || true)
  elif command -v wget >/dev/null 2>&1; then
    EXT_IP=$(wget -qO- --bind-address=$(ip -4 -o addr show "$VPN_INTERFACE" | awk '{print $4}' | cut -d/ -f1 | head -n1) https://api.ipify.org || true)
  else
    EXT_IP="(curl/wget not found)"
  fi
  echo "==== EXTERNAL IP (via $VPN_INTERFACE) ===="
  echo "$EXT_IP"
fi
