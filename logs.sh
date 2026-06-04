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

TAIL_LINES="${TAIL_LINES:-200}"

if [ "${1:-}" = "--follow" ] || [ "${1:-}" = "-f" ]; then
  "${DOCKER_BIN}" compose logs --tail "${TAIL_LINES}" --follow open-webui
else
  "${DOCKER_BIN}" compose logs --tail "${TAIL_LINES}" open-webui
fi
