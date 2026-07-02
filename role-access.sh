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
COMMAND="${1:-}"
shift || true

usage() {
  cat <<'EOF'
Usage:
  ./role-access.sh list-users
  ./role-access.sh list-roles
  ./role-access.sh list-models
  ./role-access.sh list-knowledge
  ./role-access.sh list-access

  ./role-access.sh create-role ROLE_NAME [DESCRIPTION]
  ./role-access.sh delete-role ROLE_NAME

  ./role-access.sh add-user ROLE_NAME USER_EMAIL
  ./role-access.sh remove-user ROLE_NAME USER_EMAIL

  ./role-access.sh grant-model ROLE_NAME MODEL_ID_OR_NAME
  ./role-access.sh revoke-model ROLE_NAME MODEL_ID_OR_NAME

  ./role-access.sh grant-knowledge ROLE_NAME KNOWLEDGE_ID_OR_NAME
  ./role-access.sh revoke-knowledge ROLE_NAME KNOWLEDGE_ID_OR_NAME

Examples:
  ./role-access.sh create-role 内部员工 "内部敏感资料访问"
  ./role-access.sh add-user 内部员工 111@qq.com
  ./role-access.sh grant-model 内部员工 internal-docs-kb
  ./role-access.sh grant-knowledge 内部员工 内部资料
EOF
}

if [ -z "${COMMAND}" ]; then
  usage
  exit 2
fi

"${DOCKER_BIN}" exec -i "${CONTAINER}" python - "${COMMAND}" "$@" <<'PY'
import json
import sqlite3
import sys
import time
import uuid

command = sys.argv[1]
args = sys.argv[2:]

con = sqlite3.connect("/app/backend/data/webui.db")
con.row_factory = sqlite3.Row
cur = con.cursor()

def now():
    return int(time.time())

def out(data):
    print(json.dumps(data, ensure_ascii=False, indent=2, default=str))

def first_admin_id():
    row = cur.execute("select id from user where role = 'admin' order by created_at limit 1").fetchone()
    if row:
        return row["id"]
    row = cur.execute("select id from user order by created_at limit 1").fetchone()
    if not row:
        raise SystemExit("No users found")
    return row["id"]

def get_role(name):
    return cur.execute('select * from "group" where name = ?', (name,)).fetchone()

def require_role(name):
    row = get_role(name)
    if not row:
        raise SystemExit(f"Role/group not found: {name}")
    return row

def find_user(email):
    return cur.execute("select * from user where email = ?", (email,)).fetchone()

def require_user(email):
    row = find_user(email)
    if not row:
        raise SystemExit(f"User not found: {email}")
    return row

def find_model(value):
    row = cur.execute("select * from model where id = ?", (value,)).fetchone()
    if row:
        return row
    return cur.execute("select * from model where name = ?", (value,)).fetchone()

def require_model(value):
    row = find_model(value)
    if not row:
        raise SystemExit(f"Model not found: {value}")
    return row

def find_knowledge(value):
    row = cur.execute("select * from knowledge where id = ?", (value,)).fetchone()
    if row:
        return row
    return cur.execute("select * from knowledge where name = ?", (value,)).fetchone()

def require_knowledge(value):
    row = find_knowledge(value)
    if not row:
        raise SystemExit(f"Knowledge not found: {value}")
    return row

def grant(resource_type, resource_id, group_id):
    existing = cur.execute(
        """
        select id from access_grant
        where resource_type = ?
          and resource_id = ?
          and principal_type = 'group'
          and principal_id = ?
          and permission = 'read'
        """,
        (resource_type, resource_id, group_id),
    ).fetchone()
    if existing:
        return existing["id"], False
    grant_id = str(uuid.uuid4())
    cur.execute(
        """
        insert into access_grant
        (id, resource_type, resource_id, principal_type, principal_id, permission, created_at)
        values (?, ?, ?, 'group', ?, 'read', ?)
        """,
        (grant_id, resource_type, resource_id, group_id, now()),
    )
    return grant_id, True

def revoke(resource_type, resource_id, group_id):
    cur.execute(
        """
        delete from access_grant
        where resource_type = ?
          and resource_id = ?
          and principal_type = 'group'
          and principal_id = ?
          and permission = 'read'
        """,
        (resource_type, resource_id, group_id),
    )
    return cur.rowcount

if command == "list-users":
    rows = cur.execute("select id, name, email, role, created_at from user order by created_at").fetchall()
    out([dict(r) for r in rows])

elif command == "list-roles":
    rows = cur.execute(
        """
        select g.id, g.name, g.description, count(gm.user_id) as members
        from "group" g
        left join group_member gm on gm.group_id = g.id
        group by g.id
        order by g.created_at
        """
    ).fetchall()
    out([dict(r) for r in rows])

elif command == "list-models":
    rows = cur.execute("select id, name, base_model_id, is_active from model order by created_at").fetchall()
    out([dict(r) for r in rows])

elif command == "list-knowledge":
    rows = cur.execute("select id, name, description, created_at, updated_at from knowledge order by created_at").fetchall()
    out([dict(r) for r in rows])

elif command == "list-access":
    roles = {r["id"]: r["name"] for r in cur.execute('select id, name from "group"')}
    models = {r["id"]: r["name"] for r in cur.execute("select id, name from model")}
    knowledge = {r["id"]: r["name"] for r in cur.execute("select id, name from knowledge")}
    grants = []
    for r in cur.execute("select * from access_grant order by created_at"):
        item = dict(r)
        item["principal_name"] = roles.get(item["principal_id"], item["principal_id"])
        if item["resource_type"] == "model":
            item["resource_name"] = models.get(item["resource_id"], item["resource_id"])
        elif item["resource_type"] == "knowledge":
            item["resource_name"] = knowledge.get(item["resource_id"], item["resource_id"])
        else:
            item["resource_name"] = item["resource_id"]
        grants.append(item)
    out(grants)

elif command == "create-role":
    if len(args) < 1:
        raise SystemExit("create-role requires ROLE_NAME")
    name = args[0]
    description = args[1] if len(args) > 1 else ""
    existing = get_role(name)
    if existing:
        out({"created": False, "role": dict(existing)})
    else:
        role_id = str(uuid.uuid4())
        cur.execute(
            """
            insert into "group"
            (id, user_id, name, description, data, meta, permissions, created_at, updated_at)
            values (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (role_id, first_admin_id(), name, description, "{}", "{}", "{}", now(), now()),
        )
        con.commit()
        out({"created": True, "role": dict(require_role(name))})

elif command == "delete-role":
    if len(args) < 1:
        raise SystemExit("delete-role requires ROLE_NAME")
    role = require_role(args[0])
    cur.execute("delete from group_member where group_id = ?", (role["id"],))
    cur.execute("delete from access_grant where principal_type = 'group' and principal_id = ?", (role["id"],))
    cur.execute('delete from "group" where id = ?', (role["id"],))
    con.commit()
    out({"deleted": True, "role": role["name"]})

elif command in ("add-user", "remove-user"):
    if len(args) < 2:
        raise SystemExit(f"{command} requires ROLE_NAME USER_EMAIL")
    role = require_role(args[0])
    user = require_user(args[1])
    if command == "add-user":
        existing = cur.execute(
            "select id from group_member where group_id = ? and user_id = ?",
            (role["id"], user["id"]),
        ).fetchone()
        if existing:
            out({"added": False, "role": role["name"], "user": user["email"]})
        else:
            cur.execute(
                "insert into group_member (id, group_id, user_id, created_at, updated_at) values (?, ?, ?, ?, ?)",
                (str(uuid.uuid4()), role["id"], user["id"], now(), now()),
            )
            con.commit()
            out({"added": True, "role": role["name"], "user": user["email"]})
    else:
        cur.execute("delete from group_member where group_id = ? and user_id = ?", (role["id"], user["id"]))
        con.commit()
        out({"removed": cur.rowcount, "role": role["name"], "user": user["email"]})

elif command in ("grant-model", "revoke-model"):
    if len(args) < 2:
        raise SystemExit(f"{command} requires ROLE_NAME MODEL_ID_OR_NAME")
    role = require_role(args[0])
    model = require_model(args[1])
    if command == "grant-model":
        grant_id, created = grant("model", model["id"], role["id"])
        con.commit()
        out({"granted": created, "grant_id": grant_id, "role": role["name"], "model_id": model["id"], "model_name": model["name"]})
    else:
        removed = revoke("model", model["id"], role["id"])
        con.commit()
        out({"revoked": removed, "role": role["name"], "model_id": model["id"], "model_name": model["name"]})

elif command in ("grant-knowledge", "revoke-knowledge"):
    if len(args) < 2:
        raise SystemExit(f"{command} requires ROLE_NAME KNOWLEDGE_ID_OR_NAME")
    role = require_role(args[0])
    knowledge = require_knowledge(args[1])
    if command == "grant-knowledge":
        grant_id, created = grant("knowledge", knowledge["id"], role["id"])
        con.commit()
        out({"granted": created, "grant_id": grant_id, "role": role["name"], "knowledge_id": knowledge["id"], "knowledge_name": knowledge["name"]})
    else:
        removed = revoke("knowledge", knowledge["id"], role["id"])
        con.commit()
        out({"revoked": removed, "role": role["name"], "knowledge_id": knowledge["id"], "knowledge_name": knowledge["name"]})

else:
    raise SystemExit(f"Unknown command: {command}")
PY
