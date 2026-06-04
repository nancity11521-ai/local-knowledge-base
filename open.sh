#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

WEBUI_PORT_VALUE="3000"
if [ -f .env ]; then
  WEBUI_PORT_VALUE="$(grep -E '^WEBUI_PORT=' .env | tail -n 1 | cut -d '=' -f 2- || true)"
  WEBUI_PORT_VALUE="${WEBUI_PORT_VALUE:-3000}"
fi

URL="http://localhost:${WEBUI_PORT_VALUE}"
echo "Opening ${URL}"
open "${URL}"
