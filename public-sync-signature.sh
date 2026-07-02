#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
source "${SCRIPT_DIR}/docker-bin.sh"

DOCKER_BIN="$(find_docker_bin)" || {
  echo "Docker CLI was not found." >&2
  echo "Open Docker Desktop first, then run this script again." >&2
  exit 1
}

TARGET="${1:-main}"
KNOWLEDGE_NAME="${KNOWLEDGE_NAME:-需求文档}"
MODEL_ID="${MODEL_ID:-requirement-docs-kb}"

case "${TARGET}" in
  main)
    CONTAINER="${MAIN_CONTAINER:-local-knowledge-base}"
    ;;
  public)
    CONTAINER="${PUBLIC_CONTAINER:-local-knowledge-base-public}"
    ;;
  *)
    echo "Usage: $0 main|public" >&2
    exit 2
    ;;
esac

"${DOCKER_BIN}" exec -i "${CONTAINER}" python - "${KNOWLEDGE_NAME}" "${MODEL_ID}" <<'PY'
import hashlib
import json
import sqlite3
import sys

knowledge_name, model_id = sys.argv[1:3]
con = sqlite3.connect("/app/backend/data/webui.db")
con.row_factory = sqlite3.Row
cur = con.cursor()

model = cur.execute(
    "select id, base_model_id, name, params, created_at, is_active from model where id = ?",
    (model_id,),
).fetchone()
knowledge = cur.execute(
    "select id, name, description, meta, created_at, data from knowledge where name = ?",
    (knowledge_name,),
).fetchone()
rows = cur.execute(
    """
    select f.id, coalesce(f.hash, '') as hash, f.filename, coalesce(f.path, '') as path,
           coalesce(f.meta, '') as meta, coalesce(f.data, '') as data,
           coalesce(f.created_at, '') as created_at
    from file f
    join knowledge_file kf on kf.file_id = f.id
    join knowledge k on k.id = kf.knowledge_id
    where k.name = ?
    order by f.id
    """,
    (knowledge_name,),
).fetchall()

payload_obj = {
    "model": dict(model) if model else None,
    "knowledge": dict(knowledge) if knowledge else None,
    "files": [dict(row) for row in rows],
}
if payload_obj["model"] and payload_obj["model"].get("params"):
    try:
        params = json.loads(payload_obj["model"]["params"])
        params.pop("temperature", None)
        payload_obj["model"]["params"] = json.dumps(params, ensure_ascii=False, sort_keys=True)
    except Exception:
        pass
payload = json.dumps(payload_obj, ensure_ascii=False, sort_keys=True)
print(hashlib.sha256(payload.encode("utf-8")).hexdigest())
print(len(rows))
PY
