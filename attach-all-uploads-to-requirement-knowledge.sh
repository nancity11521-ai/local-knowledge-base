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
KNOWLEDGE_NAME="${KNOWLEDGE_NAME:-需求文档}"

"${DOCKER_BIN}" exec -i "${MAIN_CONTAINER}" python - "${KNOWLEDGE_NAME}" <<'PY'
import json
import sqlite3
import sys
import time
import uuid

knowledge_name = sys.argv[1]

con = sqlite3.connect("/app/backend/data/webui.db")
con.row_factory = sqlite3.Row
cur = con.cursor()

knowledge = cur.execute("select * from knowledge where name = ?", (knowledge_name,)).fetchone()
if not knowledge:
    raise SystemExit(f"Knowledge not found: {knowledge_name}")

files = cur.execute(
    """
    select f.*
    from file f
    left join knowledge_file kf
      on kf.file_id = f.id
     and kf.knowledge_id = ?
    where kf.file_id is null
    order by f.created_at
    """,
    (knowledge["id"],),
).fetchall()

now = int(time.time())
added = []

for file in files:
    cur.execute(
        """
        insert into knowledge_file
        (id, user_id, knowledge_id, file_id, created_at, updated_at, directory_id)
        values (?, ?, ?, ?, ?, ?, ?)
        """,
        (
            str(uuid.uuid4()),
            knowledge["user_id"],
            knowledge["id"],
            file["id"],
            now,
            now,
            None,
        ),
    )
    added.append(file["filename"])

cur.execute("update knowledge set updated_at = ? where id = ?", (now, knowledge["id"]))
con.commit()

print(json.dumps({"knowledge": knowledge_name, "added_count": len(added), "added_files": added}, ensure_ascii=False, indent=2))
PY

echo
if [ "${SKIP_PUBLIC_SYNC:-0}" = "1" ]; then
  echo "Public visitor sync skipped."
else
  echo "Now syncing public visitor instance..."
  "${SCRIPT_DIR}/sync-public-requirement-model.sh"
fi
