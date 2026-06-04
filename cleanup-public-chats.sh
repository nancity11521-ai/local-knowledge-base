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

PUBLIC_CONTAINER="${PUBLIC_CONTAINER:-local-knowledge-base-public}"
ENV_RETENTION_SECONDS="$(awk -F= '$1 == "PUBLIC_CHAT_RETENTION_SECONDS" {print $2}' .env.public 2>/dev/null | tail -n 1 || true)"
RETENTION_SECONDS="${PUBLIC_CHAT_RETENTION_SECONDS:-${ENV_RETENTION_SECONDS:-60}}"

"${DOCKER_BIN}" exec -i "${PUBLIC_CONTAINER}" python - "${RETENTION_SECONDS}" <<'PY'
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
    "removed_chats": [dict(row) for row in old_chats],
}, ensure_ascii=False, indent=2))
PY
