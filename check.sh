#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/docker-bin.sh"

echo "Checking Docker..."
DOCKER_BIN="$(find_docker_bin)" || {
  echo "Docker CLI was not found. Open Docker Desktop, then try again."
  exit 1
}

"${DOCKER_BIN}" --version
"${DOCKER_BIN}" compose version

echo
echo "Checking config..."
if [ ! -f .env ]; then
  echo "Missing .env. Run: cp .env.example .env"
  exit 1
fi

if grep -Eq "sk-your-(deepseek|model)-api-key|your-provider.example.com|your-model-name" .env; then
  echo "Model API config still contains placeholders in .env."
  echo "Edit .env and set OPENAI_API_BASE_URL, OPENAI_API_KEY, and OPENAI_MODEL before testing model calls."
  exit 1
fi

echo
echo "Checking compose config..."
"${DOCKER_BIN}" compose config >/dev/null

echo
echo "OK. You can start with: ./start.sh"
