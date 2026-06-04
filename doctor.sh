#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
source "${SCRIPT_DIR}/docker-bin.sh"

ok() {
  echo "[OK] $1"
}

warn() {
  echo "[WARN] $1"
}

fail() {
  echo "[FAIL] $1"
  exit 1
}

DOCKER_BIN="$(find_docker_bin)" || fail "Docker CLI was not found. Open Docker Desktop first."

echo "Local Knowledge Base Doctor"
echo

"${DOCKER_BIN}" --version >/dev/null || fail "Docker CLI is not working."
ok "Docker CLI is available."

"${DOCKER_BIN}" compose version >/dev/null || fail "Docker Compose is not working."
ok "Docker Compose is available."

if [ -f .env ]; then
  ok ".env exists."
else
  warn ".env is missing. Run: cp .env.example .env"
fi

"${DOCKER_BIN}" compose config >/dev/null || fail "docker-compose.yml is invalid."
ok "Compose config is valid."

if "${DOCKER_BIN}" compose ps --services --filter status=running 2>/dev/null | grep -q '^open-webui$'; then
  ok "Open WebUI container is running."
else
  warn "Open WebUI container is not running. Run: ./start.sh"
fi

HEALTH="$("${DOCKER_BIN}" inspect local-knowledge-base --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' 2>/dev/null || true)"
if [ "${HEALTH}" = "healthy" ]; then
  ok "Container health is healthy."
elif [ -n "${HEALTH}" ]; then
  warn "Container health/status: ${HEALTH}"
else
  warn "Container local-knowledge-base was not found."
fi

if [ -f .env ] && grep -Eq "sk-your-(deepseek|model)-api-key|your-provider.example.com|your-model-name" .env; then
  warn "Model API is not configured yet."
elif [ -f .env ]; then
  ok "Model API config is filled."
fi

echo
./show-url.sh

echo
if [ -d backups ] && find backups -name 'open-webui-data-*.tar.gz' -maxdepth 1 | grep -q .; then
  LATEST_BACKUP="$(find backups -name 'open-webui-data-*.tar.gz' -maxdepth 1 -print | sort | tail -n 1)"
  ok "Backup exists: ${LATEST_BACKUP}"
else
  warn "No backup file found yet. Run: ./backup.sh"
fi

echo
echo "Doctor check complete."
