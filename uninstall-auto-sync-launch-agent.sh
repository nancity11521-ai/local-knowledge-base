#!/usr/bin/env bash
set -euo pipefail

LABEL="com.local-knowledge-base.auto-sync"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
RUNNER="/private/tmp/local-knowledge-base-auto-sync-runner.sh"
STANDALONE="/private/tmp/local-knowledge-base-auto-sync-once.sh"
UID_VALUE="$(id -u)"

launchctl bootout "gui/${UID_VALUE}" "${PLIST}" >/dev/null 2>&1 || true
rm -f "${PLIST}"
rm -f "${RUNNER}"
rm -f "${STANDALONE}"

echo "LaunchAgent removed."
echo "Label: ${LABEL}"
