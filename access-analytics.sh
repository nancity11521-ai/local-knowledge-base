#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
source "${SCRIPT_DIR}/docker-bin.sh"

DOCKER_BIN="$(find_docker_bin)" || {
  echo "Docker CLI was not found." >&2
  exit 1
}

CONTAINER="${ANALYTICS_CONTAINER:-local-knowledge-base-token-cache}"
OUT_DIR="${SCRIPT_DIR}/analytics"
OUT_FILE="${OUT_DIR}/access-analytics.json"
TMP_FILE="${OUT_FILE}.tmp"
mkdir -p "${OUT_DIR}"

"${DOCKER_BIN}" exec -i "${CONTAINER}" python3 - <<'PY' >"${TMP_FILE}"
import json
import sqlite3
import time

con = sqlite3.connect("/cache/token-cache.sqlite3")
con.execute(
    """
    create table if not exists access_log (
        id integer primary key autoincrement,
        event text not null,
        session_id text,
        language text,
        created_at integer not null
    )
    """
)

days = con.execute(
    """
    select date(created_at, 'unixepoch', 'localtime') as day,
           sum(case when event = 'visit' then 1 else 0 end) as visits,
           count(distinct case when event = 'visit' then session_id end) as visitors,
           sum(case when event = 'consultation' then 1 else 0 end) as consultations
    from access_log
    group by day
    order by day desc
    limit 366
    """
).fetchall()
languages = con.execute(
    """
    select coalesce(nullif(language, ''), '其他') as language, count(*) as count
    from access_log
    where event = 'consultation'
    group by language
    order by count desc, language
    """
).fetchall()

print(json.dumps({
    "generated_at": int(time.time()),
    "days": [
        {"day": row[0], "visits": row[1] or 0, "visitors": row[2] or 0, "consultations": row[3] or 0}
        for row in days
    ],
    "languages": [{"language": row[0], "count": row[1]} for row in languages],
}, ensure_ascii=False, indent=2))
PY

mv "${TMP_FILE}" "${OUT_FILE}"
