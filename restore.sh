#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
source "${SCRIPT_DIR}/docker-bin.sh"

usage() {
  cat <<'USAGE'
Usage:
  ./restore.sh backups/open-webui-data-YYYYMMDD-HHMMSS.tar.gz
  ./restore.sh --yes backups/open-webui-data-YYYYMMDD-HHMMSS.tar.gz

Restore replaces the current Open WebUI data volume with the selected backup.
Run ./backup.sh first if you want a fresh safety copy before restoring.
USAGE
}

ASSUME_YES="false"
BACKUP_FILE=""

for arg in "$@"; do
  case "${arg}" in
    --help|-h)
      usage
      exit 0
      ;;
    --yes|-y)
      ASSUME_YES="true"
      ;;
    *)
      BACKUP_FILE="${arg}"
      ;;
  esac
done

if [ -z "${BACKUP_FILE}" ]; then
  usage
  exit 1
fi

if [ ! -f "${BACKUP_FILE}" ]; then
  echo "Backup file not found: ${BACKUP_FILE}"
  exit 1
fi

DOCKER_BIN="$(find_docker_bin)" || {
  echo "Docker CLI was not found."
  echo "Open Docker Desktop first, then run this script again."
  exit 1
}

CONTAINER_ID="$("${DOCKER_BIN}" compose ps -q open-webui)"
if [ -z "${CONTAINER_ID}" ]; then
  echo "Open WebUI container was not found. Run ./start.sh once before restoring."
  exit 1
fi

FULL_VOLUME_NAME="$("${DOCKER_BIN}" inspect "${CONTAINER_ID}" --format '{{range .Mounts}}{{if eq .Destination "/app/backend/data"}}{{.Name}}{{end}}{{end}}')"
if [ -z "${FULL_VOLUME_NAME}" ]; then
  echo "Could not find /app/backend/data volume on the Open WebUI container."
  exit 1
fi

echo "Restore target:"
echo "  volume: ${FULL_VOLUME_NAME}"
echo "  backup: ${BACKUP_FILE}"
echo
echo "This will replace the current Open WebUI accounts, knowledge base, uploads, and settings."

if [ "${ASSUME_YES}" != "true" ]; then
  read -r -p "Type RESTORE to continue: " CONFIRM
  if [ "${CONFIRM}" != "RESTORE" ]; then
    echo "Restore cancelled."
    exit 1
  fi
fi

BACKUP_ABS="$(cd "$(dirname "${BACKUP_FILE}")" && pwd)/$(basename "${BACKUP_FILE}")"
BACKUP_DIR="$(dirname "${BACKUP_ABS}")"
BACKUP_NAME="$(basename "${BACKUP_ABS}")"

echo
echo "Stopping Open WebUI..."
"${DOCKER_BIN}" compose stop open-webui

echo "Restoring backup..."
"${DOCKER_BIN}" run --rm \
  -v "${FULL_VOLUME_NAME}:/data" \
  -v "${BACKUP_DIR}:/backup:ro" \
  -e BACKUP_NAME="${BACKUP_NAME}" \
  alpine:3.20 \
  sh -c 'rm -rf /data/* /data/.[!.]* /data/..?* 2>/dev/null || true; tar -xzf "/backup/${BACKUP_NAME}" -C /data'

echo "Starting Open WebUI..."
"${DOCKER_BIN}" compose up -d open-webui

echo
echo "Restore complete."
./status.sh
