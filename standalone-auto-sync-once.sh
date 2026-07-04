#!/usr/bin/env bash
set -euo pipefail

DOCKER_DESKTOP_BIN="/Applications/Docker.app/Contents/Resources/bin"
export PATH="${DOCKER_DESKTOP_BIN}:${PATH}"

DOCKER_BIN="$(command -v docker || true)"
if [ -z "${DOCKER_BIN}" ]; then
  echo "Docker CLI was not found."
  exit 1
fi

MAIN_CONTAINER="${MAIN_CONTAINER:-local-knowledge-base}"
PUBLIC_CONTAINER="${PUBLIC_CONTAINER:-local-knowledge-base-public}"
KNOWLEDGE_NAME="${KNOWLEDGE_NAME:-需求文档}"
MODEL_ID="${MODEL_ID:-requirement-docs-kb}"

timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
echo "[${timestamp}] Checking uploads..."
echo "[${timestamp}] Safe mode: only files already linked to the public knowledge are synced."

cleanup_public_chats() {
  local retention_seconds="${PUBLIC_CHAT_RETENTION_SECONDS:-60}"
  "${DOCKER_BIN}" exec -i "${PUBLIC_CONTAINER}" python - "${retention_seconds}" <<'PY'
import json
import sqlite3
import sys
import time

retention_seconds = int(sys.argv[1])
cutoff = int(time.time()) - retention_seconds

con = sqlite3.connect("/app/backend/data/webui.db")
con.row_factory = sqlite3.Row
cur = con.cursor()

cur.execute(
    """
    create table if not exists public_question_log (
        message_id text primary key,
        chat_id text,
        title text,
        question text,
        model_id text,
        created_at integer
    )
    """
)

old_chats = cur.execute(
    "select id, title, updated_at from chat where coalesce(updated_at, created_at, 0) < ?",
    (cutoff,),
).fetchall()
chat_ids = [row["id"] for row in old_chats]

if chat_ids:
    placeholders = ",".join("?" for _ in chat_ids)
    messages = cur.execute(
        f"""
        select cm.id, cm.chat_id, cm.content, cm.model_id, cm.created_at, c.title
        from chat_message cm
        left join chat c on c.id = cm.chat_id
        where cm.role = 'user' and cm.chat_id in ({placeholders})
        """,
        chat_ids,
    ).fetchall()
    for message in messages:
        cur.execute(
            """
            insert or ignore into public_question_log
            (message_id, chat_id, title, question, model_id, created_at)
            values (?, ?, ?, ?, ?, ?)
            """,
            (
                message["id"],
                message["chat_id"],
                message["title"],
                message["content"],
                message["model_id"],
                message["created_at"],
            ),
        )
    cur.execute(f"delete from chat_message where chat_id in ({placeholders})", chat_ids)
    cur.execute(f"delete from chat where id in ({placeholders})", chat_ids)
    con.commit()

print(json.dumps({
    "retention_seconds": retention_seconds,
    "removed_count": len(chat_ids),
}, ensure_ascii=False))
PY
}

signature() {
  local container="$1"
  "${DOCKER_BIN}" exec -i "${container}" python - "${KNOWLEDGE_NAME}" "${MODEL_ID}" <<'PY'
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
}

main_signature="$(signature "${MAIN_CONTAINER}" | tr '\n' ' ')"
public_signature="$(signature "${PUBLIC_CONTAINER}" | tr '\n' ' ')"

if [ "${main_signature}" = "${public_signature}" ]; then
  echo "[${timestamp}] No changes."
  cleanup_public_chats
  exit 0
fi

echo "[${timestamp}] Public instance is out of date. Syncing..."

TMP_DIR="$(mktemp -d /private/tmp/local-kb-sync.XXXXXX)"
trap 'rm -rf "${TMP_DIR}"' EXIT
mkdir -p "${TMP_DIR}/uploads"

echo "Checkpointing main instance database..."
"${DOCKER_BIN}" exec -i "${MAIN_CONTAINER}" python - <<'PY'
import sqlite3

con = sqlite3.connect("/app/backend/data/webui.db")
con.execute("pragma wal_checkpoint(full)")
con.close()
PY

echo "Exporting main instance database snapshot..."
"${DOCKER_BIN}" cp "${MAIN_CONTAINER}:/app/backend/data/webui.db" "${TMP_DIR}/main-webui.db"

echo "Copying referenced upload files..."
python3 - "${TMP_DIR}/main-webui.db" "${TMP_DIR}/uploads-list.txt" "${KNOWLEDGE_NAME}" "${MODEL_ID}" <<'PY'
import sqlite3
import sys

db, out, knowledge_name, model_id = sys.argv[1:5]
con = sqlite3.connect(db)
con.row_factory = sqlite3.Row
cur = con.cursor()

model = cur.execute("select * from model where id = ?", (model_id,)).fetchone()
if not model:
    raise SystemExit(f"Model not found: {model_id}")

rows = cur.execute(
    """
    select f.id, f.filename, f.path
    from file f
    join knowledge_file kf on kf.file_id = f.id
    join knowledge k on k.id = kf.knowledge_id
    where k.name = ?
    order by f.created_at
    """,
    (knowledge_name,),
).fetchall()
if not rows:
    raise SystemExit(f"No files found for knowledge: {knowledge_name}")

with open(out, "w", encoding="utf-8") as file:
    for row in rows:
        file.write(row["path"] + "\n")

print(f"Files linked to {knowledge_name}:")
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

echo "Syncing vector database (embeddings)..."
"${DOCKER_BIN}" exec "${PUBLIC_CONTAINER}" rm -rf /app/backend/data/vector_db
"${DOCKER_BIN}" exec -i "${MAIN_CONTAINER}" tar -cf - -C /app/backend/data vector_db | "${DOCKER_BIN}" exec -i "${PUBLIC_CONTAINER}" tar -xf - -C /app/backend/data

echo "Importing model, knowledge, and file records into public instance..."
"${DOCKER_BIN}" exec -i "${PUBLIC_CONTAINER}" python - "${MODEL_ID}" "${KNOWLEDGE_NAME}" <<'PY'
import json
import sqlite3
import sys
import time
import uuid

model_id, knowledge_name = sys.argv[1:3]

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

model = src_cur.execute("select * from model where id = ?", (model_id,)).fetchone()
if not model:
    raise SystemExit(f"Source model not found: {model_id}")

knowledge = src_cur.execute("select * from knowledge where name = ?", (knowledge_name,)).fetchone()
if not knowledge:
    raise SystemExit(f"Source knowledge not found: {knowledge_name}")

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

for file in files:
    dst_cur.execute(
        """
        insert or replace into file
        (id, user_id, filename, meta, created_at, hash, data, updated_at, path)
        values (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            file["id"],
            public_user_id,
            file["filename"],
            file["meta"],
            file["created_at"],
            file["hash"],
            file["data"],
            now,
            file["path"],
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

for resource_type, resource_id in (("knowledge", knowledge_id), ("model", model_id)):
    dst_cur.execute(
        """
        insert or replace into access_grant
        (id, resource_type, resource_id, principal_type, principal_id, permission, created_at)
        values (?, ?, ?, 'user', '*', 'read', ?)
        """,
        (str(uuid.uuid4()), resource_type, resource_id, now),
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
    "citations": False,
    "status_updates": True,
    "builtin_tools": False,
}
for knowledge_item in meta.get("knowledge", []):
    knowledge_item["user_id"] = public_user_id
    knowledge_item["write_access"] = False
    knowledge_item["user"] = {
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
print("Imported public model:", model_id)
print("Imported knowledge:", knowledge_name)
print("Imported files:", len(files))
PY

echo "Updating Chroma metadata owner to match public guest user ID..."
"${DOCKER_BIN}" exec -i "${PUBLIC_CONTAINER}" python3 - <<'CHROMA_PY'
import sys
sys.path.append("/app/backend")
import chromadb
import sqlite3

con = sqlite3.connect("/app/backend/data/webui.db")
cur = con.cursor()
public_user_row = cur.execute("select id from user where email = 'admin@localhost' or role = 'admin' limit 1;").fetchone()
if public_user_row:
    public_user_id = public_user_row[0]
    client = chromadb.PersistentClient(path="/app/backend/data/vector_db")
    for col in client.list_collections():
        try:
            results = col.get()
            metadatas = results.get("metadatas")
            ids = results.get("ids")
            if metadatas and ids:
                new_metadatas = []
                changed = False
                for m in metadatas:
                    if m:
                        nm = dict(m)
                        if nm.get("created_by") != public_user_id:
                            nm["created_by"] = public_user_id
                            changed = True
                        new_metadatas.append(nm)
                    else:
                        new_metadatas.append(m)
                if changed:
                    col.update(ids=ids, metadatas=new_metadatas)
                    print(f"Updated Chroma collection owner: {col.name}")
        except Exception as e:
            print(f"Skipped updating collection {col.name}: {e}")
CHROMA_PY

echo "Restarting public instance..."
"${DOCKER_BIN}" restart "${PUBLIC_CONTAINER}" >/dev/null

cleanup_public_chats

echo "[${timestamp}] Sync complete."
