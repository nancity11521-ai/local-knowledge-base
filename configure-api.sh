#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

if [ ! -f .env ]; then
  cp .env.example .env
  echo "Created .env from .env.example."
fi

PROVIDER=""
BASE_URL=""
API_KEY=""
MODEL=""

if [ "$#" -eq 3 ]; then
  PROVIDER="custom"
  BASE_URL="${1}"
  API_KEY="${2}"
  MODEL="${3}"
elif [ "$#" -ge 4 ]; then
  PROVIDER="${1}"
  BASE_URL="${2}"
  API_KEY="${3}"
  MODEL="${4}"
fi

if [ -z "${PROVIDER}" ]; then
  read -r -p "Provider name [custom]: " PROVIDER
  PROVIDER="${PROVIDER:-custom}"
fi

if [ -z "${BASE_URL}" ]; then
  read -r -p "API base URL: " BASE_URL
fi

if [ -z "${API_KEY}" ]; then
  read -r -s -p "API key: " API_KEY
  echo
fi

if [ -z "${MODEL}" ]; then
  read -r -p "Model name: " MODEL
fi

if [ -z "${BASE_URL}" ] || [ -z "${API_KEY}" ] || [ -z "${MODEL}" ]; then
  echo "Base URL, API key, and model name are required."
  echo
  echo "Usage:"
  echo "  ./configure-api.sh https://api.example.com/v1 sk-your-api-key model_name"
  echo "  ./configure-api.sh provider_name https://api.example.com/v1 sk-your-api-key model_name"
  exit 1
fi

tmp_file="$(mktemp)"
awk -v provider="${PROVIDER}" \
  -v base_url="${BASE_URL}" \
  -v api_key="${API_KEY}" \
  -v model="${MODEL}" '
  BEGIN {
    seen_provider = 0
    seen_base_url = 0
    seen_api_key = 0
    seen_model = 0
  }
  /^MODEL_PROVIDER_NAME=/ {
    print "MODEL_PROVIDER_NAME=" provider
    seen_provider = 1
    next
  }
  /^OPENAI_API_BASE_URL=/ {
    print "OPENAI_API_BASE_URL=" base_url
    seen_base_url = 1
    next
  }
  /^OPENAI_API_KEY=/ {
    print "OPENAI_API_KEY=" api_key
    seen_api_key = 1
    next
  }
  /^OPENAI_MODEL=/ {
    print "OPENAI_MODEL=" model
    seen_model = 1
    next
  }
  { print }
  END {
    if (!seen_provider) print "MODEL_PROVIDER_NAME=" provider
    if (!seen_base_url) print "OPENAI_API_BASE_URL=" base_url
    if (!seen_api_key) print "OPENAI_API_KEY=" api_key
    if (!seen_model) print "OPENAI_MODEL=" model
  }
' .env > "${tmp_file}"

mv "${tmp_file}" .env

echo "Updated .env model API config:"
echo "  MODEL_PROVIDER_NAME=${PROVIDER}"
echo "  OPENAI_API_BASE_URL=${BASE_URL}"
echo "  OPENAI_MODEL=${MODEL}"
echo "  OPENAI_API_KEY=(hidden)"
echo
echo "Run ./stop.sh and ./start.sh to apply changes if Open WebUI is already running."
