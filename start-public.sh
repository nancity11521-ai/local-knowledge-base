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

if [ ! -f .env.public ]; then
  cp .env.public.example .env.public
  if [ -f .env ]; then
    awk -F= '
      /^OPENAI_API_KEY=/ { key=$0 }
      /^OPENAI_API_BASE_URL=/ { base=$0 }
      /^OPENAI_MODEL=/ { model=$0 }
      END {
        if (base) print base
        if (key) print key
        if (model) print model
      }
    ' .env > .env.public.model.tmp
    while IFS= read -r line; do
      key_name="${line%%=*}"
      value="${line#*=}"
      awk -v k="${key_name}" -v v="${value}" 'BEGIN{FS=OFS="="} $1==k {$0=k OFS v} {print}' .env.public > .env.public.tmp
      mv .env.public.tmp .env.public
    done < .env.public.model.tmp
    rm .env.public.model.tmp
  fi
  echo "Created .env.public from .env.public.example."
fi

PUBLIC_WEBUI_PORT_VALUE="$(grep -E '^PUBLIC_WEBUI_PORT=' .env.public | tail -n 1 | cut -d '=' -f 2- || true)"
PUBLIC_WEBUI_PORT_VALUE="${PUBLIC_WEBUI_PORT_VALUE:-3001}"

"${DOCKER_BIN}" compose --env-file .env.public -f docker-compose.public.yml up -d

"${SCRIPT_DIR}/cleanup-public-chats.sh" || true

echo
echo "Public guest knowledge base is starting:"
echo "  http://localhost:${PUBLIC_WEBUI_PORT_VALUE}"
echo
echo "This instance has WEBUI_AUTH=False. Only put public-safe documents here."
