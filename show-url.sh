#!/usr/bin/env bash
set -euo pipefail

WEBUI_PORT_VALUE="3000"
if [ -f .env ]; then
  WEBUI_PORT_VALUE="$(grep -E '^WEBUI_PORT=' .env | tail -n 1 | cut -d '=' -f 2- || true)"
  WEBUI_PORT_VALUE="${WEBUI_PORT_VALUE:-3000}"
fi

LAN_IP="$(ifconfig en0 2>/dev/null | awk '/inet / {print $2; exit}')"

echo "Local:"
echo "  http://localhost:${WEBUI_PORT_VALUE}"

if [ -n "${LAN_IP}" ]; then
  echo
  echo "LAN:"
  echo "  http://${LAN_IP}:${WEBUI_PORT_VALUE}"
else
  echo
  echo "LAN IP not found on en0. Run ifconfig and look for an active inet address."
fi
