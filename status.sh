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

echo "URLs:"
./show-url.sh

echo
echo "Container:"
"${DOCKER_BIN}" compose ps

echo
if grep -Eq "sk-your-(deepseek|model)-api-key|your-provider.example.com|your-model-name" .env 2>/dev/null; then
  echo "Model API: not configured"
else
  PROVIDER="$(grep -E '^MODEL_PROVIDER_NAME=' .env | tail -n 1 | cut -d '=' -f 2- || true)"
  MODEL="$(grep -E '^OPENAI_MODEL=' .env | tail -n 1 | cut -d '=' -f 2- || true)"
  echo "Model API: configured"
  echo "  provider: ${PROVIDER:-unknown}"
  echo "  model: ${MODEL:-unknown}"
fi
