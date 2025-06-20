#!/bin/sh
# entry.sh placeholder for container image build sanity.
# This script is only used if the container is run directly (not via Helm chart).
# It will print available scripts and exit with code 0.

set -e

echo "[entry.sh] This is a placeholder entrypoint."
echo "Available scripts in /bin:"
ls -1 /bin | grep -E '\.sh$' || true

echo "To use this image, run with the appropriate script (e.g. /bin/gateway_init.sh, /bin/gateway_sidecar.sh, etc)."
exit 0
