#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 EMAIL NAME PASSWORD [role]"
  echo "Example: $0 user@example.com 张三 'Temp@123456' user"
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

EMAIL="$1"
NAME="$2"
PASSWORD="$3"
ROLE="${4:-user}"
CONTAINER="${CONTAINER:-local-knowledge-base}"

"${DOCKER_BIN}" exec -i "${CONTAINER}" python - "${EMAIL}" "${NAME}" "${PASSWORD}" "${ROLE}" <<'PY'
import json
import sqlite3
import sys
import time
import uuid

email, name, password, role = sys.argv[1:5]
if role not in {"admin", "user", "pending"}:
    raise SystemExit("role must be admin, user, or pending")

try:
    from passlib.context import CryptContext
    pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
    password_hash = pwd_context.hash(password)
except Exception:
    import bcrypt
    password_hash = bcrypt.hashpw(password.encode(), bcrypt.gensalt(rounds=12)).decode()

con = sqlite3.connect("/app/backend/data/webui.db")
con.row_factory = sqlite3.Row
cur = con.cursor()

existing = cur.execute("select * from user where email = ?", (email,)).fetchone()
now = int(time.time())

if existing:
    user_id = existing["id"]
    cur.execute(
        "update user set name = ?, role = ?, updated_at = ? where id = ?",
        (name, role, now, user_id),
    )
    cur.execute(
        "insert or replace into auth (id, email, password, active) values (?, ?, ?, 1)",
        (user_id, email, password_hash),
    )
    created = False
else:
    user_id = str(uuid.uuid4())
    cur.execute(
        """
        insert into user
        (id, name, email, role, profile_image_url, last_active_at, updated_at, created_at, settings, oauth, info, scim)
        values (?, ?, ?, ?, '', ?, ?, ?, 'null', 'null', 'null', 'null')
        """,
        (user_id, name, email, role, now, now, now),
    )
    cur.execute(
        "insert into auth (id, email, password, active) values (?, ?, ?, 1)",
        (user_id, email, password_hash),
    )
    created = True

con.commit()
print(json.dumps({"created": created, "id": user_id, "email": email, "name": name, "role": role}, ensure_ascii=False, indent=2))
PY
