#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
source "${SCRIPT_DIR}/docker-bin.sh"

DOCKER_BIN="$(find_docker_bin)" || {
  echo "Docker CLI was not found."
  exit 1
}

MAIN_CONTAINER="${MAIN_CONTAINER:-local-knowledge-base}"
export DOCKER_BIN MAIN_CONTAINER

python3 - <<'PY'
import json
import os
import sqlite3
import subprocess

docker = os.environ["DOCKER_BIN"]
container = os.environ["MAIN_CONTAINER"]

def read_env(path):
    values = {}
    if not os.path.exists(path):
        return values
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip().strip("'\"")
    return values

def usable(value):
    value = str(value or "").strip()
    return bool(value) and not value.startswith("sk-your-") and "your-deepseek" not in value

def admin_config():
    code = r'''
import json, sqlite3
con = sqlite3.connect("/app/backend/data/webui.db")
out = {}
for key in ("openai.api_base_urls", "openai.api_keys"):
    row = con.execute("select value from config where key = ?", (key,)).fetchone()
    out[key] = row[0] if row else ""
print(json.dumps(out))
'''
    result = subprocess.run(
        [docker, "exec", "-i", container, "python3", "-c", code],
        capture_output=True, text=True, timeout=15,
    )
    if result.returncode != 0:
        return {}, "container environment"
    try:
        raw = json.loads(result.stdout.strip())
        parsed = {}
        for key, value in raw.items():
            try:
                value = json.loads(value) if isinstance(value, str) else value
            except json.JSONDecodeError:
                pass
            if isinstance(value, list):
                value = next((item for item in value if usable(item)), "")
            parsed[key] = value
        return parsed, "Open WebUI admin database"
    except Exception:
        return {}, "container environment"

public = read_env(".env.public")
main = read_env(".env")
database, source = admin_config()

api_key = next((value for value in (
    database.get("openai.api_keys"),
    main.get("OPENAI_API_KEY"),
    public.get("OPENAI_API_KEY"),
) if usable(value)), "")
upstream_url = next((value for value in (
    database.get("openai.api_base_urls"),
    main.get("UPSTREAM_BASE_URL"),
    main.get("OPENAI_API_BASE_URL"),
    public.get("UPSTREAM_BASE_URL"),
) if usable(value)), "https://api.deepseek.com/v1")

forced = {
    "OPENAI_API_BASE_URL": "http://token-cache-proxy:8000/v1",
    "UPSTREAM_BASE_URL": upstream_url,
    "ENABLE_OLLAMA_API": "false",
    "USE_OLLAMA_DOCKER": "false",
    "BYPASS_MODEL_ACCESS_CONTROL": "True",
}
if api_key:
    forced["OPENAI_API_KEY"] = api_key

changed = False
lines = []
seen = set()
with open(".env.public", encoding="utf-8") as f:
    for line in f:
        stripped = line.strip()
        if "=" in stripped and not stripped.startswith("#"):
            key = stripped.split("=", 1)[0].strip()
            if key in forced:
                new_line = f"{key}={forced[key]}\n"
                changed = changed or line != new_line
                lines.append(new_line)
                seen.add(key)
                continue
        lines.append(line)

for key, value in forced.items():
    if key not in seen:
        lines.append(f"{key}={value}\n")
        changed = True

with open(".env.public", "w", encoding="utf-8") as f:
    f.writelines(lines)

if api_key:
    print(f"Public API settings synchronized from {source}." if database.get("openai.api_keys") else "Public API settings synchronized from environment file.")
else:
    print("WARNING: no usable API key was found in the admin database or environment files.")
print(f"PUBLIC_API_CONFIG_CHANGED={'1' if changed else '0'}")
PY
