#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
source "${SCRIPT_DIR}/docker-bin.sh"

MODEL_ID="${MODEL_ID:-requirement-docs-kb}"
PUBLIC_CONTAINER="${PUBLIC_CONTAINER:-local-knowledge-base-public}"

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

echo "Public Knowledge Base Doctor"
echo

if [ ! -f .env.public ]; then
  fail ".env.public is missing. Run: cp .env.public.example .env.public"
fi
ok ".env.public exists."

PUBLIC_WEBUI_PORT_VALUE="$(grep -E '^PUBLIC_WEBUI_PORT=' .env.public | tail -n 1 | cut -d '=' -f 2- || true)"
PUBLIC_WEBUI_PORT_VALUE="${PUBLIC_WEBUI_PORT_VALUE:-3001}"

PUBLIC_API_KEY_VALUE="$(grep -E '^OPENAI_API_KEY=' .env.public | tail -n 1 | cut -d '=' -f 2- || true)"
if [ -z "${PUBLIC_API_KEY_VALUE}" ] || [[ "${PUBLIC_API_KEY_VALUE}" == sk-your-* ]]; then
  warn "Public API key is not configured."
else
  ok "Public API key is configured."
fi

if grep -Eq '^OPENAI_API_BASE_URL=' .env.public; then
  ok "Public API base URL is configured."
else
  warn "Public API base URL is missing."
fi

"${DOCKER_BIN}" compose --env-file .env.public -f docker-compose.public.yml config >/dev/null || fail "docker-compose.public.yml is invalid."
ok "Public compose config is valid."

if "${DOCKER_BIN}" ps --format '{{.Names}}' | grep -qx "${PUBLIC_CONTAINER}"; then
  ok "Public container is running."
else
  warn "Public container is not running. Run: ./start-public.sh"
fi

if curl -fsS "http://127.0.0.1:${PUBLIC_WEBUI_PORT_VALUE}/api/config" >/dev/null; then
  ok "Public web endpoint responds on port ${PUBLIC_WEBUI_PORT_VALUE}."
else
  warn "Public web endpoint is not responding on port ${PUBLIC_WEBUI_PORT_VALUE}."
fi

if curl -fsS "http://127.0.0.1:${PUBLIC_WEBUI_PORT_VALUE}/static/loader.js" | grep -q "PUBLIC_STYLE_VERSION"; then
  ok "Public loader is available."
else
  warn "Public loader was not found or is stale."
fi

if curl -fsS "http://127.0.0.1:${PUBLIC_WEBUI_PORT_VALUE}/" | grep -q "/static/loader.js"; then
  ok "Public index loads the custom loader."
else
  warn "Public index does not load the custom loader. Run: ./inject-public-assets.sh"
fi

if "${DOCKER_BIN}" ps --format '{{.Names}}' | grep -qx "${PUBLIC_CONTAINER}"; then
  "${DOCKER_BIN}" exec -i "${PUBLIC_CONTAINER}" python3 - "${MODEL_ID}" <<'PY'
import json
import sqlite3
import sys

model_id = sys.argv[1]
con = sqlite3.connect("/app/backend/data/webui.db")
con.row_factory = sqlite3.Row
cur = con.cursor()

model = cur.execute("select id, name, base_model_id, meta, is_active from model where id = ?", (model_id,)).fetchone()
if not model:
    print(f"[WARN] Public model not found: {model_id}")
    raise SystemExit(0)

meta = json.loads(model["meta"] or "{}")
knowledge = meta.get("knowledge") or []
print(f"[OK] Public model exists: {model['id']} / {model['name']} / base={model['base_model_id']} / active={model['is_active']}")
print(f"[OK] Public model knowledge bindings: {len(knowledge)}")

files = cur.execute("select count(*) from file").fetchone()[0]
knowledge_rows = cur.execute("select count(*) from knowledge").fetchone()[0]
print(f"[OK] Public DB files: {files}; collections: {knowledge_rows}")
PY
fi

echo
echo "If public answers differ from admin, run:"
echo "  ./sync-public-requirement-model.sh"
echo "  ./start-public.sh"
