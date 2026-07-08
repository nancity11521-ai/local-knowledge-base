#!/usr/bin/env bash
set -euo pipefail
# Diagnostic script for public Open WebUI "Model not found" issues
# Run from the project directory on the Ubuntu server.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
source "${SCRIPT_DIR}/docker-bin.sh"

DOCKER_BIN="$(find_docker_bin)" || {
  echo "❌ Docker CLI not found."
  exit 1
}

PUBLIC_CONTAINER="${PUBLIC_CONTAINER:-local-knowledge-base-public}"
PROXY_CONTAINER="${PROXY_CONTAINER:-local-knowledge-base-token-cache}"

echo "=== Open WebUI Public Instance Diagnostics ==="
echo ""

# 1. Container status
echo "--- 1. Container status ---"
"${DOCKER_BIN}" ps --filter name="${PUBLIC_CONTAINER}" --filter name="${PROXY_CONTAINER}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""

# 2. Proxy /v1/models check
echo "--- 2. Proxy model list ---"
"${DOCKER_BIN}" exec -i "${PUBLIC_CONTAINER}" python3 -c "
import urllib.request, json
try:
    req = urllib.request.Request('http://token-cache-proxy:8000/v1/models')
    req.add_header('Authorization', 'Bearer unused')
    resp = urllib.request.urlopen(req, timeout=5)
    data = json.loads(resp.read())
    models = [m.get('id') for m in data.get('data', [])]
    print('Available base models from proxy:', models)
except Exception as e:
    print('ERROR contacting proxy:', e)
"
echo ""

# 3. Database model record
echo "--- 3. Database model record ---"
"${DOCKER_BIN}" exec -i "${PUBLIC_CONTAINER}" python3 -c "
import sqlite3, json
con = sqlite3.connect('/app/backend/data/webui.db')
con.row_factory = sqlite3.Row
row = con.execute('select id, base_model_id, name, is_active from model').fetchone()
if row:
    print(f'  id:             {row[\"id\"]}')
    print(f'  base_model_id:  {row[\"base_model_id\"]}')
    print(f'  name:           {row[\"name\"]}')
    print(f'  is_active:      {row[\"is_active\"]}')
else:
    print('  No model records found!')
"
echo ""

# 4. Config entries relevant to model resolution
echo "--- 4. Key config entries ---"
"${DOCKER_BIN}" exec -i "${PUBLIC_CONTAINER}" python3 -c "
import sqlite3
con = sqlite3.connect('/app/backend/data/webui.db')
keys = [
    'openai.api_base_urls', 'openai.api_keys', 'openai.enable',
    'enable_ollama_api', 'ui.default_models', 'ui.default_pinned_models'
]
for key in keys:
    row = con.execute('select value from config where key = ?', (key,)).fetchone()
    print(f'  {key}: {row[0] if row else \"(not in db)\"}')
"
echo ""

# 5. Environment variables
echo "--- 5. Environment variables ---"
"${DOCKER_BIN}" exec -i "${PUBLIC_CONTAINER}" python3 -c "
import os
for key in ['ENABLE_OPENAI_API', 'OPENAI_API_BASE_URL', 'OPENAI_API_KEY',
            'ENABLE_OLLAMA_API', 'OLLAMA_BASE_URL', 'USE_OLLAMA_DOCKER',
            'DEFAULT_MODELS', 'ENABLE_CUSTOM_MODEL_FALLBACK', 'BYPASS_MODEL_ACCESS_CONTROL',
            'WEBUI_AUTH', 'RESET_CONFIG_ON_START']:
    val = os.environ.get(key, '(not set)')
    if 'KEY' in key and val and val != '(not set)':
        val = val[:8] + '...'
    print(f'  {key}={val}')
"
echo ""

# 6. Match check: is base_model_id in the proxy model list?
echo "--- 6. Model chain validation ---"
"${DOCKER_BIN}" exec -i "${PUBLIC_CONTAINER}" python3 -c "
import sqlite3, urllib.request, json

con = sqlite3.connect('/app/backend/data/webui.db')
row = con.execute('select base_model_id from model limit 1').fetchone()
base_model_id = row[0] if row else None
print(f'  base_model_id in database: {base_model_id}')

try:
    req = urllib.request.Request('http://token-cache-proxy:8000/v1/models')
    req.add_header('Authorization', 'Bearer unused')
    resp = urllib.request.urlopen(req, timeout=5)
    data = json.loads(resp.read())
    available = [m.get('id') for m in data.get('data', [])]
    print(f'  Available from proxy:      {available}')
    
    if base_model_id in available:
        print('  ✅ base_model_id matches an available model — chain should work')
    else:
        print(f'  ❌ MISMATCH! base_model_id \"{base_model_id}\" is NOT in proxy model list')
        print(f'     This is the root cause of \"Model not found\"')
        print(f'     Fix: run ./sync-public-requirement-model.sh to re-sync with correct mapping')
except Exception as e:
    print(f'  ❌ Cannot reach proxy: {e}')
"
echo ""

# 7. Check the fallback path
echo "--- 7. Fallback path check ---"
"${DOCKER_BIN}" exec -i "${PUBLIC_CONTAINER}" python3 -c "
import sqlite3, urllib.request, json, os

con = sqlite3.connect('/app/backend/data/webui.db')

# Get ui.default_models from config  
dm_row = con.execute(\"select value from config where key = 'ui.default_models'\").fetchone()
default_models_raw = dm_row[0].strip('\"') if dm_row else ''
print(f'  ui.default_models (from db config): \"{default_models_raw}\"')

# Get available models from proxy
try:
    req = urllib.request.Request('http://token-cache-proxy:8000/v1/models')
    req.add_header('Authorization', 'Bearer unused')
    resp = urllib.request.urlopen(req, timeout=5)
    data = json.loads(resp.read())
    available = set(m.get('id') for m in data.get('data', []))
except Exception:
    available = set()

# The fallback logic in chat_completion:
# default_models = (Config.get('ui.default_models') or '').split(',')
# fallback_model_id = default_models[0].strip()
# if fallback_model_id in request.app.state.MODELS: use it
# else: raise 'Model not found'
# 
# MODELS includes both base models (from proxy) and custom models (from db)
# So if ui.default_models = 'requirement-docs-kb', the fallback tries requirement-docs-kb
# But requirement-docs-kb is a CUSTOM model, not a base model, so the fallback re-enters 
# the same check and causes an infinite issue or just fails.

fallback = default_models_raw.split(',')[0].strip() if default_models_raw else ''
print(f'  Fallback model ID:                  \"{fallback}\"')

if fallback in available:
    print(f'  ✅ Fallback \"{fallback}\" is a base model — fallback would work')
elif fallback:
    # Check if it's a custom model
    row = con.execute('select base_model_id from model where id = ?', (fallback,)).fetchone()
    if row:
        print(f'  ⚠️  Fallback \"{fallback}\" is a CUSTOM model (base={row[0]})')
        print(f'     When base_model_id fails, fallback to another custom model may cause a loop')
        print(f'     This could be contributing to Model not found!')
    else:
        print(f'  ❌ Fallback \"{fallback}\" is not found anywhere')
else:
    print(f'  ⚠️  No fallback configured')

print()
enable_fallback = os.environ.get('ENABLE_CUSTOM_MODEL_FALLBACK', '(not set)')
print(f'  ENABLE_CUSTOM_MODEL_FALLBACK: {enable_fallback}')
"
echo ""
echo "=== Diagnostics complete ==="
