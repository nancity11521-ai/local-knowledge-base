#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 filename-keyword"
  echo "Example: $0 G3"
  exit 2
fi

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
KEYWORD="$1"

"${DOCKER_BIN}" exec -i "${MAIN_CONTAINER}" python - "${KNOWLEDGE_NAME}" "${KEYWORD}" <<'PY'
import json
import sqlite3
import sys
import time

knowledge_name, keyword = sys.argv[1:3]

con = sqlite3.connect("/app/backend/data/webui.db")
con.row_factory = sqlite3.Row
cur = con.cursor()

knowledge = cur.execute("select * from knowledge where name = ?", (knowledge_name,)).fetchone()
if not knowledge:
    raise SystemExit(f"Knowledge not found: {knowledge_name}")

matches = cur.execute(
    """
    select kf.id as link_id, f.filename
    from knowledge_file kf
    join file f on f.id = kf.file_id
    where kf.knowledge_id = ?
      and f.filename like ?
    order by f.created_at
    """,
    (knowledge["id"], f"%{keyword}%"),
).fetchall()

if not matches:
    print(json.dumps({"removed_count": 0, "removed_files": []}, ensure_ascii=False, indent=2))
    raise SystemExit(0)

for row in matches:
    cur.execute("delete from knowledge_file where id = ?", (row["link_id"],))

cur.execute("update knowledge set updated_at = ? where id = ?", (int(time.time()), knowledge["id"]))
con.commit()

print(json.dumps(
    {"removed_count": len(matches), "removed_files": [row["filename"] for row in matches]},
    ensure_ascii=False,
    indent=2,
))
PY

echo
echo "Syncing public visitor instance after unpublishing..."
"${SCRIPT_DIR}/sync-public-requirement-model.sh"
