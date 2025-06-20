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

print_debug_info() {
  echo "==== Debug Info ===="
  ip addr
  ip route
  echo "===================="
}

# --- Load main settings ---
if [ -f /default_config/settings.sh ]; then
  . /default_config/settings.sh
fi
if [ -f /config/settings.sh ]; then
  . /config/settings.sh
fi

# --- Check for required variables ---
require_var GATEWAY_NAME
require_var K8S_DNS_IPS
require_var VXLAN_ID
require_var VXLAN_IP_NETWORK

# --- Remove vxlan0 if it exists, else set routing rule to K8S DNS server ---
if ip addr | grep -q vxlan0; then
  ip link del vxlan0
else
  K8S_GW_IP=$(/sbin/ip route | awk '/default/ { print $3 }')
  for local_cidr in $NOT_ROUTED_TO_GATEWAY_CIDRS; do
    ip route add "$local_cidr" via "$K8S_GW_IP" || true
  done
fi

# --- Delete default GWs to prevent outgoing traffic ---
echo "Deleting existing default GWs"
ip route del 0/0 || true

echo "Deleting existing default IPv6 route to prevent leakage"
ip -6 route del default || true

# --- Check isolation ---
if ping -c 1 -W 1 8.8.8.8; then
  echo "WE SHOULD NOT BE ABLE TO PING -> EXIT" >&2
  exit 255
fi

# --- Print debug info ---
print_debug_info

# --- Determine real hostname ---
if [ -n "${KUBERNETES_SERVICE_HOST:-}" ]; then
  HOSTNAME_REAL=$(hostname | cut -d'-' -f1)
else
  HOSTNAME_REAL=$(hostname)
fi
echo "$HOSTNAME_REAL"

# --- Derived settings ---
K8S_DNS_IP="$(echo "$K8S_DNS_IPS" | awk '{print $1}')"
GATEWAY_IP="$(dig +short "$GATEWAY_NAME" "@${K8S_DNS_IP}")"
if [ -z "$GATEWAY_IP" ]; then
  echo "ERROR: Could not resolve gateway IP for $GATEWAY_NAME" >&2
  exit 1
fi
NAT_ENTRY="$(grep "^$HOSTNAME_REAL " /config/nat.conf || true)"
VXLAN_GATEWAY_IP=$(echo "$VXLAN_IP_NETWORK" | awk -F'[./]' '{print $1 "." $2 "." $3 ".1"}')

# --- Ensure VXLAN_STATIC_IP for static NAT entry ---
if [ -n "$NAT_ENTRY" ] && [ -z "${VXLAN_STATIC_IP:-}" ]; then
  echo "ERROR: VXLAN_STATIC_IP is required for static NAT entry" >&2
  exit 1
fi

# --- Ensure route for gateway ---
if [ -n "${K8S_GW_IP:-}" ]; then
  ip route add "$GATEWAY_IP" via "$K8S_GW_IP" || true
fi

# --- Print debug info ---
print_debug_info

# --- Check connectivity to gateway IP ---
ping -c "${CONNECTION_RETRY_COUNT}" "$GATEWAY_IP"

# --- Create VXLAN tunnel NIC ---
if ! ip link add vxlan0 type vxlan id "$VXLAN_ID" dev eth0 dstport "${VXLAN_PORT:-0}" 2>/dev/null; then
  echo "vxlan0 already exists or failed to create, continuing..."
fi
bridge fdb append to 00:00:00:00:00:00 dst "$GATEWAY_IP" dev vxlan0
ip link set up dev vxlan0

# --- VXLAN MTU Setup ---
if [ -n "${VPN_INTERFACE_MTU:-}" ]; then
  ETH0_INTERFACE_MTU=$(cat /sys/class/net/eth0/mtu)
  VXLAN0_INTERFACE_MAX_MTU=$((ETH0_INTERFACE_MTU - 50))
  if [ "$VPN_INTERFACE_MTU" -ge "$VXLAN0_INTERFACE_MAX_MTU" ]; then
    ip link set mtu "$VXLAN0_INTERFACE_MAX_MTU" dev vxlan0
  else
    ip link set mtu "$VPN_INTERFACE_MTU" dev vxlan0
  fi
fi

# --- Configure IP and default GW ---
if [ -z "$NAT_ENTRY" ]; then
  echo "Get dynamic IP"
  killall -q udhcpc || true
  udhcpc --now --interface=vxlan0
else
  IP=$(echo "$NAT_ENTRY" | awk '{print $2}')
  VXLAN_IP="${VXLAN_STATIC_IP:-}"
  echo "Use fixed IP $VXLAN_IP"
  ip addr add "$VXLAN_IP/24" dev vxlan0
  route add default gw "$VXLAN_GATEWAY_IP"
fi

# --- Print debug info ---
print_debug_info

# --- Check connectivity to gateway via vxlan0 ---
ping -c "${CONNECTION_RETRY_COUNT}" "$VXLAN_GATEWAY_IP"

echo "Gateway ready and reachable"
