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

CONTAINER="${CONTAINER:-local-knowledge-base}"
KNOWLEDGE_NAME="${1:-${KNOWLEDGE_NAME:-需求文档}}"

"${DOCKER_BIN}" exec -i "${CONTAINER}" python - "${KNOWLEDGE_NAME}" <<'PY'
import json
import sqlite3
import sys

knowledge_name = sys.argv[1]
con = sqlite3.connect("/app/backend/data/webui.db")
con.row_factory = sqlite3.Row
cur = con.cursor()

rows = cur.execute(
    """
    select k.name as knowledge, f.id, f.filename, f.path
    from file f
    join knowledge_file kf on kf.file_id = f.id
    join knowledge k on k.id = kf.knowledge_id
    where k.name = ?
    order by f.created_at
    """,
    (knowledge_name,),
).fetchall()

print(json.dumps([dict(row) for row in rows], ensure_ascii=False, indent=2))
PY
