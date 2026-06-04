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

CONTAINER="${CACHE_CONTAINER:-local-knowledge-base-token-cache}"

"${DOCKER_BIN}" exec -i "${CONTAINER}" python - <<'PY'
import json
import os
import sqlite3
import time

db_path = os.environ.get("CACHE_DB", "/cache/token-cache.sqlite3")
con = sqlite3.connect(db_path)
con.row_factory = sqlite3.Row
cur = con.cursor()

cur.execute(
    """
    create table if not exists cache (
        key text primary key,
        status integer not null,
        headers text not null,
        body blob not null,
        created_at integer not null,
        hits integer not null default 0
    )
    """
)
cur.execute(
    """
    create table if not exists stats (
        key text primary key,
        value integer not null
    )
    """
)

stats = {row["key"]: row["value"] for row in cur.execute("select key, value from stats")}
row = cur.execute(
    "select count(*) as entries, coalesce(sum(hits), 0) as reused_answers, min(created_at) as oldest, max(created_at) as newest from cache"
).fetchone()
top = cur.execute(
    "select key, hits, created_at from cache order by hits desc, created_at desc limit 10"
).fetchall()

def fmt(ts):
    if not ts:
        return None
    return time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(ts))

print(json.dumps({
    "cache_entries": row["entries"],
    "reused_answers": row["reused_answers"],
    "cache_hits": stats.get("cache_hits", 0),
    "cache_misses": stats.get("cache_misses", 0),
    "oldest_cache_at": fmt(row["oldest"]),
    "newest_cache_at": fmt(row["newest"]),
    "top_cached_requests": [
        {"cache_key": item["key"], "hits": item["hits"], "created_at": fmt(item["created_at"])}
        for item in top
    ],
}, ensure_ascii=False, indent=2))
PY
