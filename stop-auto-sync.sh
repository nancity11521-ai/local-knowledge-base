#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${SCRIPT_DIR}/.auto-sync"
PID_FILE="${STATE_DIR}/auto-sync.pid"

if [ "$(uname -s)" = "Darwin" ] && command -v launchctl >/dev/null 2>&1; then
  "${SCRIPT_DIR}/uninstall-auto-sync-launch-agent.sh"
fi

if [ ! -f "${PID_FILE}" ]; then
  exit 0
fi

pid="$(cat "${PID_FILE}")"
if kill -0 "${pid}" >/dev/null 2>&1; then
  kill "${pid}"
  echo "Auto sync stopped. PID: ${pid}"
else
  echo "Auto sync process was not running. PID: ${pid}"
fi

rm -f "${PID_FILE}"
