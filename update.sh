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

echo "Creating a backup before updating..."
./backup.sh

echo
echo "Pulling the latest Open WebUI image..."
"${DOCKER_BIN}" compose pull open-webui

echo
echo "Restarting with the latest image..."
"${DOCKER_BIN}" compose up -d open-webui

echo
echo "Update complete."
./status.sh
