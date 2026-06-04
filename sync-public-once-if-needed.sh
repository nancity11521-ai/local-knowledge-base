#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
echo "[${timestamp}] Checking uploads..."
echo "[${timestamp}] Safe mode: only files already linked to the public knowledge are synced."

main_signature="$("${SCRIPT_DIR}/public-sync-signature.sh" main | tr '\n' ' ')"
public_signature="$("${SCRIPT_DIR}/public-sync-signature.sh" public | tr '\n' ' ')"

if [ "${main_signature}" != "${public_signature}" ]; then
  echo "[${timestamp}] Public instance is out of date. Syncing..."
  "${SCRIPT_DIR}/sync-public-requirement-model.sh"
  echo "[${timestamp}] Sync complete."
else
  echo "[${timestamp}] No changes."
fi

"${SCRIPT_DIR}/cleanup-public-chats.sh"
