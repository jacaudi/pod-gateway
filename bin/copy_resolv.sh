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

require_var RESOLV_CONF_COPY

echo "Copying /etc/resolv.conf to ${RESOLV_CONF_COPY}"
cp /etc/resolv.conf "${RESOLV_CONF_COPY}"

exit 0