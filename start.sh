#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/docker-bin.sh"

DOCKER_BIN="$(find_docker_bin)" || {
  echo "Docker CLI was not found."
  echo "Open Docker Desktop first, then run this script again."
  exit 1
}

if [ ! -f .env ]; then
  cp .env.example .env
  echo "Created .env from .env.example."
  echo "Edit .env and set your model API details before using chat and summarization."
fi

WEBUI_PORT_VALUE="$(grep -E '^WEBUI_PORT=' .env | tail -n 1 | cut -d '=' -f 2-)"
WEBUI_PORT_VALUE="${WEBUI_PORT_VALUE:-3000}"

if grep -Eq "sk-your-(deepseek|model)-api-key|your-provider.example.com|your-model-name" .env; then
  echo "Warning: .env still contains placeholder model API config."
  echo "The web app can start, but model calls will fail until OPENAI_API_BASE_URL, OPENAI_API_KEY, and OPENAI_MODEL are updated."
fi

"${DOCKER_BIN}" compose up -d

echo
echo "Local knowledge base is starting:"
echo "  http://localhost:${WEBUI_PORT_VALUE}"
echo
echo "First registered user becomes the admin."
