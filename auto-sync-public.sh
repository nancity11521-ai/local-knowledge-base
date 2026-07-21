#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
source "${SCRIPT_DIR}/docker-bin.sh"

DOCKER_BIN="$(find_docker_bin)" || {
  echo "Docker CLI was not found; API configuration sync will retry on the next cycle." >&2
  exit 1
}

INTERVAL_SECONDS="${AUTO_SYNC_INTERVAL_SECONDS:-60}"

echo "Auto public sync started."
echo "Interval: ${INTERVAL_SECONDS}s"
echo "Main: ${MAIN_CONTAINER:-local-knowledge-base}"
echo "Public: ${PUBLIC_CONTAINER:-local-knowledge-base-public}"
echo "Knowledge: ${KNOWLEDGE_NAME:-g3问题库}"
echo

while true; do
  # The public model/data signature does not include API credentials. Check the
  # administrator connection independently so a backend key rotation reaches
  # the public proxy automatically, without recreating the public web UI.
  if api_sync_output="$("${SCRIPT_DIR}/sync-public-api-config.sh" 2>&1)"; then
    if grep -q '^PUBLIC_API_CONFIG_CHANGED=1$' <<<"${api_sync_output}"; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] Public API connection changed; restarting token cache proxy..."
      "${DOCKER_BIN}" compose --env-file .env.public -f docker-compose.public.yml \
        up -d --force-recreate token-cache-proxy
    fi
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Public API configuration check failed; will retry on the next cycle." >&2
  fi
  "${SCRIPT_DIR}/sync-public-once-if-needed.sh" || true
  "${SCRIPT_DIR}/analytics-dashboard.sh" || echo "Analytics refresh failed; will retry on the next cycle." >&2
  sleep "${INTERVAL_SECONDS}"
done
