#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

INTERVAL_SECONDS="${AUTO_SYNC_INTERVAL_SECONDS:-60}"

echo "Auto public sync started."
echo "Interval: ${INTERVAL_SECONDS}s"
echo "Main: ${MAIN_CONTAINER:-local-knowledge-base}"
echo "Public: ${PUBLIC_CONTAINER:-local-knowledge-base-public}"
echo "Knowledge: ${KNOWLEDGE_NAME:-g3问题库}"
echo

while true; do
  "${SCRIPT_DIR}/sync-public-once-if-needed.sh" || true
  sleep "${INTERVAL_SECONDS}"
done
