#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
source "${SCRIPT_DIR}/docker-bin.sh"

DOCKER_BIN="$(find_docker_bin)" || {
  echo "Docker CLI was not found."
  echo "Open Docker Desktop first, then run this script again."
  exit 1
}

PUBLIC_WEBUI_PORT_VALUE="3001"
if [ -f .env.public ]; then
  PUBLIC_WEBUI_PORT_VALUE="$(grep -E '^PUBLIC_WEBUI_PORT=' .env.public | tail -n 1 | cut -d '=' -f 2- || true)"
  PUBLIC_WEBUI_PORT_VALUE="${PUBLIC_WEBUI_PORT_VALUE:-3001}"
fi

LAN_IP="$(ifconfig en0 2>/dev/null | awk '/inet / {print $2; exit}')"

echo "Public URLs:"
echo "  http://localhost:${PUBLIC_WEBUI_PORT_VALUE}"
if [ -n "${LAN_IP}" ]; then
  echo "  http://${LAN_IP}:${PUBLIC_WEBUI_PORT_VALUE}"
fi

echo
"${DOCKER_BIN}" compose --env-file .env.public -f docker-compose.public.yml ps
