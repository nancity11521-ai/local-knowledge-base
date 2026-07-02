#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

if [ "$(uname -s)" = "Darwin" ] && command -v launchctl >/dev/null 2>&1; then
  "${SCRIPT_DIR}/install-auto-sync-launch-agent.sh"
  exit 0
fi

STATE_DIR="${SCRIPT_DIR}/.auto-sync"
PID_FILE="${STATE_DIR}/auto-sync.pid"
LOG_FILE="${STATE_DIR}/auto-sync.log"

mkdir -p "${STATE_DIR}"

if [ -f "${PID_FILE}" ]; then
  old_pid="$(cat "${PID_FILE}")"
  if kill -0 "${old_pid}" >/dev/null 2>&1; then
    echo "Auto sync is already running. PID: ${old_pid}"
    echo "Log: ${LOG_FILE}"
    exit 0
  fi
fi

nohup "${SCRIPT_DIR}/auto-sync-public.sh" >> "${LOG_FILE}" 2>&1 &
pid="$!"
echo "${pid}" > "${PID_FILE}"

echo "Auto sync started. PID: ${pid}"
echo "Log: ${LOG_FILE}"
echo "Interval: ${AUTO_SYNC_INTERVAL_SECONDS:-60}s"
