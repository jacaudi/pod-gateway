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
require_var GATEWAY_NAME
require_var CONNECTION_RETRY_COUNT

VXLAN_GATEWAY_IP=$(echo "$VXLAN_IP_NETWORK" | awk -F'[./]' '{print $1 "." $2 "." $3 ".1"}')

while true; do
  echo "Monitor connection to $VXLAN_GATEWAY_IP"

  # Ping the gateway vxlan IP -> this only works when vxlan is up
  while ping -c "${CONNECTION_RETRY_COUNT}" "$VXLAN_GATEWAY_IP" > /dev/null; do
    sleep 10 &
    wait $!
  done

  echo
  echo "Lost connection to ${GATEWAY_NAME}, reconnecting..."

  # reconnect
  if ! client_init.sh; then
    echo "client_init.sh failed, will retry in 5 seconds..." >&2
    sleep 5
  fi

done
