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

require_var VXLAN_IP_NETWORK
require_var VXLAN_GATEWAY_FIRST_DYNAMIC_IP
require_var RESOLV_CONF_COPY

# --- Make a copy of the original resolv.conf (for K8S DNS recovery) ---
if [ ! -f /etc/resolv.conf.org ]; then
  cp /etc/resolv.conf /etc/resolv.conf.org
  echo "/etc/resolv.conf.org written"
fi

# --- Get K8S DNS if not set (only IPv4 addresses) ---
if [ -z "${DNS_LOCAL_SERVER:-}" ]; then
  DNS_LOCAL_SERVER=$(grep nameserver /etc/resolv.conf.org | awk '/nameserver [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ {print $2}')
fi

# --- Generate dnsmasq config for DHCP and DNS ---
VXLAN_IP_NETWORK_PREFIX=$(echo "$VXLAN_IP_NETWORK" | awk -F'[./]' '{print $1 "." $2 "." $3}')
cat << EOF > /etc/dnsmasq.d/pod-gateway.conf
# DHCP server settings
interface=vxlan0
bind-interfaces

# Dynamic IPs assigned to PODs - we keep a range for static IPs
dhcp-range=${VXLAN_IP_NETWORK_PREFIX}.${VXLAN_GATEWAY_FIRST_DYNAMIC_IP},${VXLAN_IP_NETWORK_PREFIX}.255,12h

# For debugging purposes, log each DNS query as it passes through
dnsmasq.
log-queries

# Log lots of extra information about DHCP transactions.
log-dhcp

# Log to stdout
log-facility=-

# Clear DNS cache on reload
clear-on-reload

# /etc/resolv.conf cannot be monitored by dnsmasq since it is in a different file system
# and dnsmasq monitors directories only
# copy_resolv.sh is used to copy the file on changes
resolv-file=${RESOLV_CONF_COPY}
EOF

# --- Optionally enable DNSSEC if requested ---
if [ "${GATEWAY_ENABLE_DNSSEC:-false}" = "true" ]; then
cat << EOF >> /etc/dnsmasq.d/pod-gateway.conf
  # Enable DNSSEC validation and caching
  conf-file=/usr/share/dnsmasq/trust-anchors.conf
  dnssec
EOF
fi

# --- Forward local DNS queries to K8S DNS server ---
for local_cidr in $DNS_LOCAL_CIDRS; do
  cat << EOF >> /etc/dnsmasq.d/pod-gateway.conf
  # Send ${local_cidr} DNS queries to the K8S DNS server
  server=/${local_cidr}/${DNS_LOCAL_SERVER}
EOF
done

# --- Make a copy of /etc/resolv.conf for dnsmasq ---
/bin/copy_resolv.sh

# --- Start dnsmasq and inotifyd, handle shutdown ---
dnsmasq -k &
dnsmasq=$!

# Monitor /etc/resolv.conf for changes and keep the copy in sync
inotifyd /bin/copy_resolv.sh /etc/resolv.conf:ce &
inotifyd=$!

_kill_procs() {
  echo "Signal received -> killing processes"
  kill -TERM $dnsmasq || true
  wait $dnsmasq
  rc=$?
  kill -TERM $inotifyd || true
  wait $inotifyd
  rc=$(( $rc || $? ))
  echo "Terminated with RC: $rc"
  exit $rc
}

# Setup a trap to catch SIGTERM and relay it to child processes
trap _kill_procs SIGTERM

# Wait for any children to terminate
wait -n

echo "TERMINATING"

# Kill remaining processes
_kill_procs
