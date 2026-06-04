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

MAIN_CONTAINER="${MAIN_CONTAINER:-local-knowledge-base}"
PUBLIC_CONTAINER="${PUBLIC_CONTAINER:-local-knowledge-base-public}"
MODEL_ID="${MODEL_ID:-requirement-docs-kb}"

TMP_DIR="${SCRIPT_DIR}/.sync-tmp"
rm -rf "${TMP_DIR}"
mkdir -p "${TMP_DIR}/uploads"

echo "Exporting main instance database snapshot..."
"${DOCKER_BIN}" cp "${MAIN_CONTAINER}:/app/backend/data/webui.db" "${TMP_DIR}/main-webui.db"

echo "Copying referenced upload files..."
python3 - "${TMP_DIR}/main-webui.db" "${TMP_DIR}/uploads-list.txt" <<'PY'
import sqlite3, sys
db, out = sys.argv[1], sys.argv[2]
con = sqlite3.connect(db)
con.row_factory = sqlite3.Row
cur = con.cursor()
model_id = "requirement-docs-kb"
model = cur.execute("select * from model where id = ?", (model_id,)).fetchone()
if not model:
    raise SystemExit(f"Model not found: {model_id}")
knowledge_id = cur.execute(
    "select knowledge_id from knowledge_file limit 1"
).fetchone()
rows = cur.execute(
    """
    select f.id, f.filename, f.path
    from file f
    join knowledge_file kf on kf.file_id = f.id
    join knowledge k on k.id = kf.knowledge_id
    where k.name = '需求文档'
    """
).fetchall()
if not rows:
    raise SystemExit("No files found for knowledge: 需求文档")
with open(out, "w", encoding="utf-8") as f:
    for row in rows:
        f.write(row["path"] + "\n")
print("Files linked to 需求文档:")
for row in rows:
    print("-", row["filename"])
PY

while IFS= read -r path; do
  [ -n "${path}" ] || continue
  "${DOCKER_BIN}" cp "${MAIN_CONTAINER}:${path}" "${TMP_DIR}/uploads/"
done < "${TMP_DIR}/uploads-list.txt"

"${DOCKER_BIN}" cp "${TMP_DIR}/main-webui.db" "${PUBLIC_CONTAINER}:/tmp/main-webui.db"

for file in "${TMP_DIR}/uploads/"*; do
  [ -f "${file}" ] || continue
  "${DOCKER_BIN}" cp "${file}" "${PUBLIC_CONTAINER}:/app/backend/data/uploads/"
done

echo "Importing model, knowledge, and file records into public instance..."
"${DOCKER_BIN}" exec -i "${PUBLIC_CONTAINER}" python - <<'PY'
import json
import sqlite3
import time
import uuid

src = sqlite3.connect("/tmp/main-webui.db")
src.row_factory = sqlite3.Row
dst = sqlite3.connect("/app/backend/data/webui.db")
dst.row_factory = sqlite3.Row

src_cur = src.cursor()
dst_cur = dst.cursor()
now = int(time.time())

dst_cur.execute("update user set role = 'user', updated_at = ?", (now,))

public_user = dst_cur.execute("select id, name, email, role from user limit 1").fetchone()
if not public_user:
    raise SystemExit("Public instance has no default user")
public_user_id = public_user["id"]

model = src_cur.execute("select * from model where id = ?", ("requirement-docs-kb",)).fetchone()
if not model:
    raise SystemExit("Source model requirement-docs-kb not found")

knowledge = src_cur.execute("select * from knowledge where name = ?", ("需求文档",)).fetchone()
if not knowledge:
    raise SystemExit("Source knowledge 需求文档 not found")

knowledge_id = knowledge["id"]

dst_cur.execute(
    """
    insert or replace into knowledge
    (id, user_id, name, description, meta, created_at, updated_at, data)
    values (?, ?, ?, ?, ?, ?, ?, ?)
    """,
    (
        knowledge["id"],
        public_user_id,
        knowledge["name"],
        knowledge["description"],
        knowledge["meta"],
        knowledge["created_at"],
        now,
        knowledge["data"],
    ),
)

files = src_cur.execute(
    """
    select f.*
    from file f
    join knowledge_file kf on kf.file_id = f.id
    where kf.knowledge_id = ?
    """,
    (knowledge_id,),
).fetchall()

for f in files:
    dst_cur.execute(
        """
        insert or replace into file
        (id, user_id, filename, meta, created_at, hash, data, updated_at, path)
        values (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            f["id"],
            public_user_id,
            f["filename"],
            f["meta"],
            f["created_at"],
            f["hash"],
            f["data"],
            now,
            f["path"],
        ),
    )

links = src_cur.execute("select * from knowledge_file where knowledge_id = ?", (knowledge_id,)).fetchall()
for link in links:
    dst_cur.execute(
        """
        insert or replace into knowledge_file
        (id, user_id, knowledge_id, file_id, created_at, updated_at, directory_id)
        values (?, ?, ?, ?, ?, ?, ?)
        """,
        (
            link["id"],
            public_user_id,
            link["knowledge_id"],
            link["file_id"],
            link["created_at"],
            now,
            link["directory_id"],
        ),
    )

dst_cur.execute(
    """
    insert or replace into access_grant
    (id, resource_type, resource_id, principal_type, principal_id, permission, created_at)
    values (?, 'knowledge', ?, 'user', '*', 'read', ?)
    """,
    (str(uuid.uuid4()), knowledge_id, now),
)

dst_cur.execute(
    """
    insert or replace into access_grant
    (id, resource_type, resource_id, principal_type, principal_id, permission, created_at)
    values (?, 'model', 'requirement-docs-kb', 'user', '*', 'read', ?)
    """,
    (str(uuid.uuid4()), now),
)

params = json.loads(model["params"] or "{}")
params["temperature"] = 0

meta = json.loads(model["meta"] or "{}")
meta["description"] = "公开访客专用：只根据需求文档知识库回答"
meta["capabilities"] = {
    "file_context": True,
    "vision": False,
    "file_upload": False,
    "web_search": False,
    "image_generation": False,
    "code_interpreter": False,
    "terminal": False,
    "citations": True,
    "status_updates": True,
    "builtin_tools": False,
}
for k in meta.get("knowledge", []):
    k["user_id"] = public_user_id
    k["write_access"] = False
    k["user"] = {
        "id": public_user_id,
        "name": public_user["name"],
        "role": public_user["role"],
        "email": public_user["email"],
    }

dst_cur.execute(
    """
    insert or replace into model
    (id, user_id, base_model_id, name, params, meta, updated_at, created_at, is_active)
    values (?, ?, ?, ?, ?, ?, ?, ?, ?)
    """,
    (
        model["id"],
        public_user_id,
        model["base_model_id"],
        model["name"],
        json.dumps(params, ensure_ascii=False),
        json.dumps(meta, ensure_ascii=False),
        now,
        model["created_at"],
        1,
    ),
)

dst.commit()
print("Imported public model: requirement-docs-kb")
print("Imported knowledge:", knowledge["name"])
print("Imported files:", len(files))
PY

rm -rf "${TMP_DIR}"

echo
echo "Restarting public instance..."
"${DOCKER_BIN}" compose --env-file .env.public -f docker-compose.public.yml restart open-webui-public

echo
echo "Public requirement model synced."
./status-public.sh
