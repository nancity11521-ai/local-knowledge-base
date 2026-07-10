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

# The public UI always sends the custom knowledge-base model explicitly. Do not
# use that custom ID as Open WebUI's server-side fallback model: newer Open
# WebUI versions resolve the fallback as a base model and otherwise return
# "Model not found". The loader hides all base models from visitors instead.
set_public_env_value() {
  local key="$1"
  local value="$2"
  local tmp_file
  tmp_file="$(mktemp)"
  awk -v key="${key}" -v value="${value}" '
    $0 ~ "^" key "=" { print key "=" value; found = 1; next }
    { print }
    END { if (!found) print key "=" value }
  ' .env.public > "${tmp_file}"
  mv "${tmp_file}" .env.public
}

set_public_env_value "DEFAULT_MODELS" ""
set_public_env_value "DEFAULT_PINNED_MODELS" ""
set_public_env_value "MODEL_FILTER_LIST" ""
set_public_env_value "ENABLE_CUSTOM_MODEL_FALLBACK" "False"

API_SYNC_OUTPUT="$("${SCRIPT_DIR}/sync-public-api-config.sh")"
printf '%s\n' "${API_SYNC_OUTPUT}"
API_CONFIG_CHANGED="$(printf '%s\n' "${API_SYNC_OUTPUT}" | awk -F= '/^PUBLIC_API_CONFIG_CHANGED=/{print $2}' | tail -n1)"

PUBLIC_WEBUI_PORT_VALUE="$(grep -E '^PUBLIC_WEBUI_PORT=' .env.public | tail -n 1 | cut -d '=' -f 2- || true)"
PUBLIC_WEBUI_PORT_VALUE="${PUBLIC_WEBUI_PORT_VALUE:-3001}"

"${DOCKER_BIN}" compose --env-file .env.public -f docker-compose.public.yml up -d

echo
echo "Checking the public model and knowledge-base sync..."
if [ "${API_CONFIG_CHANGED}" = "1" ]; then
  echo "API settings changed; rebuilding the public model chain..."
  "${SCRIPT_DIR}/sync-public-requirement-model.sh"
else
  "${SCRIPT_DIR}/sync-public-once-if-needed.sh"
fi

"${SCRIPT_DIR}/inject-public-assets.sh"

echo
echo "Public guest knowledge base is starting:"
echo "  http://localhost:${PUBLIC_WEBUI_PORT_VALUE}"
echo
echo "This instance has WEBUI_AUTH=False. Only put public-safe documents here."
