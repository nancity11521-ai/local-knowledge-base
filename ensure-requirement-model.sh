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
MODEL_ID="${MODEL_ID:-requirement-docs-kb}"
KNOWLEDGE_NAME="${KNOWLEDGE_NAME:-g3问题库}"

"${DOCKER_BIN}" exec -i "${MAIN_CONTAINER}" python3 - "${MODEL_ID}" "${KNOWLEDGE_NAME}" <<'PY'
import json
import sqlite3
import sys
import time
import uuid

model_id, requested_knowledge_name = sys.argv[1:3]
con = sqlite3.connect("/app/backend/data/webui.db")
con.row_factory = sqlite3.Row
cur = con.cursor()

existing = cur.execute("select id, params from model where id = ?", (model_id,)).fetchone()
if existing:
    # Keep the source model deterministic. The public instance receives this
    # model record verbatim, so both entry points use the same sampling setting.
    try:
        params = json.loads(existing["params"] or "{}")
    except json.JSONDecodeError:
        params = {}
    if params.get("temperature") != 0:
        params["temperature"] = 0
        cur.execute(
            "update model set params = ?, updated_at = ? where id = ?",
            (json.dumps(params, ensure_ascii=False), int(time.time()), model_id),
        )
        con.commit()
        print(f"Updated source model temperature: {model_id}")
    print(f"Source model already exists: {model_id}")
    raise SystemExit(0)

# Keep the deployment resilient when older backups used the previous
# collection name. The explicitly requested collection remains the priority.
names = [requested_knowledge_name, "g3问题库", "需求文档"]
knowledge = None
for name in dict.fromkeys(names):
    knowledge = cur.execute("select * from knowledge where name = ?", (name,)).fetchone()
    if knowledge:
        break

if not knowledge:
    raise SystemExit(
        "Cannot create the public source model: no knowledge collection was found. "
        f"Checked: {', '.join(dict.fromkeys(names))}"
    )

owner = cur.execute("select id from user where role = 'admin' limit 1").fetchone()
if not owner:
    owner = cur.execute("select id from user limit 1").fetchone()
if not owner:
    raise SystemExit("Cannot create the public source model: no Open WebUI user exists")

now = int(time.time())
meta = {
    "description": "仅根据已绑定知识库回答的智能问答模型",
    "knowledge": [{
        "type": "collection",
        "id": knowledge["id"],
        "name": knowledge["name"],
        "description": knowledge["description"] or "",
        "status": True,
        "itemId": str(uuid.uuid4()),
    }],
    "capabilities": {
        "file_context": True,
        "file_upload": False,
        "web_search": False,
        "image_generation": False,
        "code_interpreter": False,
        "citations": False,
    },
}

# The public sync later detects the actual provider model dynamically. This
# source default only needs to be a normal DeepSeek-compatible base model.
params = {"temperature": 0}
cur.execute(
    """
    insert into model
    (id, user_id, base_model_id, name, params, meta, updated_at, created_at, is_active)
    values (?, ?, ?, ?, ?, ?, ?, ?, 1)
    """,
    (
        model_id,
        owner["id"],
        "deepseek-v4-flash",
        "智能问答",
        json.dumps(params, ensure_ascii=False),
        json.dumps(meta, ensure_ascii=False),
        now,
        now,
    ),
)
con.commit()
print(f"Created source model: {model_id}; knowledge: {knowledge['name']}")
PY
