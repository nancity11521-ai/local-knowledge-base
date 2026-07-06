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
MODEL_ID="requirement-docs-kb"
KNOWLEDGE_NAME="${KNOWLEDGE_NAME:-g3问题库}"

TMP_DIR="${SCRIPT_DIR}/.sync-tmp"
rm -rf "${TMP_DIR}"
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

echo "Analyzing model links and upload files..."
python3 - "${TMP_DIR}/main-webui.db" "${TMP_DIR}/uploads-list.txt" "${MODEL_ID}" "${KNOWLEDGE_NAME}" <<'PY'
import sqlite3
import sys
import json

db, out, model_id, knowledge_name = sys.argv[1:5]
con = sqlite3.connect(db)
con.row_factory = sqlite3.Row
cur = con.cursor()

model = cur.execute("select * from model where id = ?", (model_id,)).fetchone()
if not model:
    raise SystemExit(f"Model not found: {model_id}")

meta = json.loads(model["meta"] or "{}")
knowledge_list = meta.get("knowledge", [])

collection_ids = []
file_ids = []
explicit_collection_ids = []
explicit_file_ids = []

for item in knowledge_list:
    if isinstance(item, dict):
        if item.get("type") == "collection":
            explicit_collection_ids.append(item.get("id"))
        elif item.get("type") == "file":
            explicit_file_ids.append(item.get("id"))

collection_ids = [item for item in explicit_collection_ids if item]
file_ids = [item for item in explicit_file_ids if item]

# Fallback only when the model has no explicit knowledge binding. This avoids
# leaking stale default collections while keeping an empty model usable.
if not collection_ids and not file_ids:
    named_knowledge = cur.execute("select id from knowledge where name = ?", (knowledge_name,)).fetchone()
    if named_knowledge:
        collection_ids.append(named_knowledge["id"])

# Include files from explicitly bound collections plus any direct file bindings.
for col_id in collection_ids:
    k_files = cur.execute("select file_id from knowledge_file where knowledge_id = ?", (col_id,)).fetchall()
    for kf in k_files:
        file_ids.append(kf["file_id"])

file_ids = list(set(file_ids))  # unique list

# Retrieve file paths from the file table
paths = []
filenames = []
for fid in file_ids:
    row = cur.execute("select filename, path from file where id = ?", (fid,)).fetchone()
    if row and row["path"]:
        paths.append(row["path"])
        filenames.append(row["filename"])

with open(out, "w", encoding="utf-8") as f:
    for p in paths:
        f.write(p + "\n")

print(f"Total files linked to model '{model_id}': {len(filenames)}")
for fname in filenames:
    print("-", fname)
PY

echo "Copying referenced upload files..."
while IFS= read -r path; do
  [ -n "${path}" ] || continue
  "${DOCKER_BIN}" cp "${MAIN_CONTAINER}:${path}" "${TMP_DIR}/uploads/"
done < "${TMP_DIR}/uploads-list.txt"

"${DOCKER_BIN}" cp "${TMP_DIR}/main-webui.db" "${PUBLIC_CONTAINER}:/tmp/main-webui.db"

# Ensure public uploads directory exists and copy files
"${DOCKER_BIN}" exec "${PUBLIC_CONTAINER}" mkdir -p /app/backend/data/uploads
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

# Ensure user permissions
dst_cur.execute("update user set role = 'user', updated_at = ?", (now,))
public_user = dst_cur.execute("select id, name, email, role from user limit 1").fetchone()
if not public_user:
    raise SystemExit("Public instance has no default user")
public_user_id = public_user["id"]

# Retrieve model record
model = src_cur.execute("select * from model where id = ?", (model_id,)).fetchone()
if not model:
    raise SystemExit(f"Source model '{model_id}' not found")

meta = json.loads(model["meta"] or "{}")
knowledge_list = meta.get("knowledge", [])

collection_ids = []
file_ids = []
explicit_collection_ids = []
explicit_file_ids = []

for item in knowledge_list:
    if isinstance(item, dict):
        if item.get("type") == "collection":
            explicit_collection_ids.append(item.get("id"))
        elif item.get("type") == "file":
            explicit_file_ids.append(item.get("id"))

collection_ids = [item for item in explicit_collection_ids if item]
file_ids = [item for item in explicit_file_ids if item]

if not collection_ids and not file_ids:
    named_knowledge = src_cur.execute("select id, name from knowledge where name = ?", (knowledge_name,)).fetchone()
    if named_knowledge:
        collection_ids.append(named_knowledge["id"])

# Include files from explicitly bound collections plus any direct file bindings.
for col_id in collection_ids:
    k_files = src_cur.execute("select file_id from knowledge_file where knowledge_id = ?", (col_id,)).fetchall()
    for kf in k_files:
        file_ids.append(kf["file_id"])

file_ids = list(set(file_ids))

# Clear old entries in public DB to avoid stale data
dst_cur.execute("delete from knowledge")
dst_cur.execute("delete from knowledge_file")
dst_cur.execute("delete from file")

# Copy knowledge collections
for col_id in collection_ids:
    knowledge = src_cur.execute("select * from knowledge where id = ?", (col_id,)).fetchone()
    if knowledge:
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

# Copy files
for fid in file_ids:
    file_row = src_cur.execute("select * from file where id = ?", (fid,)).fetchone()
    if file_row:
        dst_cur.execute(
            """
            insert or replace into file
            (id, user_id, filename, meta, created_at, hash, data, updated_at, path)
            values (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                file_row["id"],
                public_user_id,
                file_row["filename"],
                file_row["meta"],
                file_row["created_at"],
                file_row["hash"],
                file_row["data"],
                now,
                file_row["path"],
            ),
        )

# Copy only the file links that are part of the public model context.
for col_id in collection_ids:
    links = src_cur.execute("select * from knowledge_file where knowledge_id = ?", (col_id,)).fetchall()
    for link in links:
        if link["file_id"] not in file_ids:
            continue
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

# Create read access grants for everyone
for resource_type, resource_id in (("model", model_id),):
    dst_cur.execute(
        """
        insert or replace into access_grant
        (id, resource_type, resource_id, principal_type, principal_id, permission, created_at)
        values (?, ?, ?, 'user', '*', 'read', ?)
        """,
        (str(uuid.uuid4()), resource_type, resource_id, now),
    )

for col_id in collection_ids:
    dst_cur.execute(
        """
        insert or replace into access_grant
        (id, resource_type, resource_id, principal_type, principal_id, permission, created_at)
        values (?, 'knowledge', ?, 'user', '*', 'read', ?)
        """,
        (str(uuid.uuid4()), col_id, now),
    )

# Sync and customize the model
params = json.loads(model["params"] or "{}")
params["temperature"] = 0

model_meta = json.loads(model["meta"] or "{}")
model_meta["description"] = "公开访客专用：只根据当前绑定知识库回答"

# Rebuild knowledge bindings from the freshly imported public records. The
# public model intentionally uses direct file bindings instead of collection
# bindings so stale collection-level vectors cannot leak into visitor answers.
rebuilt_knowledge = []
for fid in file_ids:
    row = dst_cur.execute("select * from file where id = ?", (fid,)).fetchone()
    if not row:
        continue
    try:
        file_data = json.loads(row["data"] or "{}")
    except json.JSONDecodeError:
        file_data = {}
    try:
        file_meta = json.loads(row["meta"] or "{}")
    except json.JSONDecodeError:
        file_meta = {}
    file_record = {
        "id": row["id"],
        "user_id": public_user_id,
        "hash": row["hash"],
        "filename": row["filename"],
        "path": row["path"],
        "data": file_data,
        "meta": file_meta,
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
        "status": True,
    }
    rebuilt_knowledge.append({
        "type": "file",
        "file": file_record,
        "id": row["id"],
        "url": row["id"],
        "name": row["filename"],
        "status": "uploaded",
        "size": file_meta.get("size", 0),
        "error": "",
        "itemId": str(uuid.uuid4()),
    })
model_meta["knowledge"] = rebuilt_knowledge
model_meta["capabilities"] = {
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
for knowledge_item in model_meta.get("knowledge", []):
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
        json.dumps(model_meta, ensure_ascii=False),
        now,
        model["created_at"],
        1,
    ),
)

dst.commit()
print("Imported public model:", model_id)
print("Imported collections:", len(collection_ids))
print("Imported files:", len(file_ids))
PY

rm -rf "${TMP_DIR}"

echo
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

echo
echo "Restarting public instance..."
"${DOCKER_BIN}" compose --env-file .env.public -f docker-compose.public.yml restart open-webui-public

echo
echo "Public requirement model synced."
./status-public.sh
