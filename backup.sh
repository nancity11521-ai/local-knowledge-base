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

BACKUP_DIR="${SCRIPT_DIR}/backups"
mkdir -p "${BACKUP_DIR}"

CONTAINER_ID="$("${DOCKER_BIN}" compose ps -q open-webui)"
if [ -z "${CONTAINER_ID}" ]; then
  echo "Open WebUI container was not found. Run ./start.sh first."
  exit 1
fi

FULL_VOLUME_NAME="$("${DOCKER_BIN}" inspect "${CONTAINER_ID}" --format '{{range .Mounts}}{{if eq .Destination "/app/backend/data"}}{{.Name}}{{end}}{{end}}')"
if [ -z "${FULL_VOLUME_NAME}" ]; then
  echo "Could not find /app/backend/data volume on the Open WebUI container."
  exit 1
fi
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_FILE="${BACKUP_DIR}/open-webui-data-${STAMP}.tar.gz"

echo "Creating backup:"
echo "  volume: ${FULL_VOLUME_NAME}"
echo "  file: ${BACKUP_FILE}"

"${DOCKER_BIN}" run --rm \
  -v "${FULL_VOLUME_NAME}:/data:ro" \
  -v "${BACKUP_DIR}:/backup" \
  alpine:3.20 \
  tar -czf "/backup/$(basename "${BACKUP_FILE}")" -C /data .

echo
echo "Backup complete:"
echo "  ${BACKUP_FILE}"
