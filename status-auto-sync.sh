#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${SCRIPT_DIR}/.auto-sync"
PID_FILE="${STATE_DIR}/auto-sync.pid"
LOG_FILE="${STATE_DIR}/auto-sync.log"
LAUNCHD_LOG_FILE="/private/tmp/local-knowledge-base-auto-sync.launchd.log"
LABEL="com.local-knowledge-base.auto-sync"

if [ "$(uname -s)" = "Darwin" ] && command -v launchctl >/dev/null 2>&1; then
  if launchctl print "gui/$(id -u)/${LABEL}" >/dev/null 2>&1; then
    echo "Auto sync: running via LaunchAgent"
    echo "Label: ${LABEL}"
  else
    echo "Auto sync: stopped"
  fi
  echo "Log: ${LAUNCHD_LOG_FILE}"
  if [ -f "${LAUNCHD_LOG_FILE}" ]; then
    echo
    echo "Recent log:"
    tail -60 "${LAUNCHD_LOG_FILE}"
  fi
  exit 0
fi

if [ -f "${PID_FILE}" ]; then
  pid="$(cat "${PID_FILE}")"
  if kill -0 "${pid}" >/dev/null 2>&1; then
    echo "Auto sync: running"
    echo "PID: ${pid}"
  else
    echo "Auto sync: stopped, stale PID file"
    echo "PID: ${pid}"
  fi
else
  echo "Auto sync: stopped"
fi

echo "Log: ${LOG_FILE}"
if [ -f "${LOG_FILE}" ]; then
  echo
  echo "Recent log:"
  tail -40 "${LOG_FILE}"
fi
