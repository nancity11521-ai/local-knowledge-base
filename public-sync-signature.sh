#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
source "${SCRIPT_DIR}/docker-bin.sh"
source "${SCRIPT_DIR}/public-container.sh"

DOCKER_BIN="$(find_docker_bin)" || {
  echo "Docker CLI was not found." >&2
  echo "Open Docker Desktop first, then run this script again." >&2
  exit 1
}

TARGET="${1:-main}"
KNOWLEDGE_NAME="${KNOWLEDGE_NAME:-g3问题库}"
MODEL_ID="${MODEL_ID:-requirement-docs-kb}"
# Bump when the synchronization implementation changes in a way that requires
# one fresh public-model import even if no document changed.
PUBLIC_SYNC_FORMAT_VERSION="${PUBLIC_SYNC_FORMAT_VERSION:-20260726-knowledge-json-files-1}"

case "${TARGET}" in
  main)
    CONTAINER="${MAIN_CONTAINER:-local-knowledge-base}"
    ;;
  public)
    CONTAINER="$(resolve_public_container)" || {
      echo "Public container is not available." >&2
      exit 1
    }
    ;;
  *)
    echo "Usage: $0 main|public" >&2
    exit 2
    ;;
esac

"${DOCKER_BIN}" exec -i "${CONTAINER}" python - "${TARGET}" "${PUBLIC_SYNC_FORMAT_VERSION}" "${KNOWLEDGE_NAME}" "${MODEL_ID}" <<'PY'
import hashlib
import json
import sqlite3
import sys

target, expected_format_version, knowledge_name, model_id = sys.argv[1:5]
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

FILE_CONTAINER_KEYS = {"file_ids", "fileids", "files", "documents", "document_ids", "docs"}

def parse_json(value):
    if not value:
        return None
    if isinstance(value, (dict, list)):
        return value
    if not isinstance(value, str):
        return None
    try:
        return json.loads(value)
    except (TypeError, ValueError):
        return None

def add_ordered(target, seen, value):
    if value and value not in seen:
        seen.add(value)
        target.append(value)

def collect_file_id_candidates(value, out, in_file_context=False):
    parsed = parse_json(value)
    if parsed is not None:
        value = parsed
    if isinstance(value, dict):
        for key, item in value.items():
            key_l = str(key).lower()
            if key_l in {"file_id", "fileid"} and isinstance(item, str):
                out.add(item)
            elif key_l == "id" and in_file_context and isinstance(item, str):
                out.add(item)
            elif key_l in FILE_CONTAINER_KEYS:
                collect_file_id_candidates(item, out, True)
            else:
                collect_file_id_candidates(item, out, in_file_context)
    elif isinstance(value, list):
        for item in value:
            collect_file_id_candidates(item, out, in_file_context)
    elif isinstance(value, str) and in_file_context:
        out.add(value)

def valid_file_ids(cur, candidates):
    if not candidates:
        return set()
    ids = sorted(candidates)
    valid = set()
    for idx in range(0, len(ids), 500):
        chunk = ids[idx:idx + 500]
        marks = ",".join("?" for _ in chunk)
        for row in cur.execute(f"select id from file where id in ({marks})", chunk).fetchall():
            valid.add(row["id"])
    return valid

def knowledge_file_ids(cur, knowledge):
    if knowledge is None:
        return []
    ids = []
    seen = set()
    for row in cur.execute(
        "select file_id from knowledge_file where knowledge_id = ? order by created_at, file_id",
        (knowledge["id"],),
    ).fetchall():
        add_ordered(ids, seen, row["file_id"])
    candidates = set()
    collect_file_id_candidates(knowledge["data"], candidates)
    collect_file_id_candidates(knowledge["meta"], candidates)
    for fid in sorted(valid_file_ids(cur, candidates)):
        add_ordered(ids, seen, fid)
    return ids

file_ids = knowledge_file_ids(cur, knowledge)
rows = []
for idx in range(0, len(file_ids), 500):
    chunk = file_ids[idx:idx + 500]
    marks = ",".join("?" for _ in chunk)
    row_map = {
        row["id"]: row
        for row in cur.execute(
            f"""
            select id, coalesce(hash, '') as hash, filename, coalesce(path, '') as path,
                   coalesce(meta, '') as meta, coalesce(data, '') as data,
                   coalesce(created_at, '') as created_at
            from file
            where id in ({marks})
            """,
            chunk,
        ).fetchall()
    }
    rows.extend(row_map[fid] for fid in chunk if fid in row_map)

config_columns = {row[1] for row in cur.execute("pragma table_info(config)")}
if {"key", "value"}.issubset(config_columns):
    rag_config = [
        {"key": row["key"], "value": row["value"]}
        for row in cur.execute(
            "select key, value from config where key = 'rag' or key like 'rag.%' order by key"
        ).fetchall()
    ]
else:
    rag_config = None

if {"key", "value"}.issubset(config_columns):
    row = cur.execute(
        "select value from config where key = 'public.sync_format_version'"
    ).fetchone()
    public_format_version = row["value"] if row else ""
else:
    public_format_version = ""

def normalized_json(value):
    """Compare JSON-backed database fields by content, not serialized formatting."""
    if not isinstance(value, str):
        return value
    try:
        return json.loads(value)
    except (TypeError, ValueError):
        return value

def normalize_fields(record, fields):
    if record is None:
        return None
    result = dict(record)
    for field in fields:
        result[field] = normalized_json(result.get(field))
    return result

normalized_rag_config = None
if rag_config is not None:
    normalized_rag_config = [
        {"key": item["key"], "value": normalized_json(item["value"])}
        for item in rag_config
    ]

payload_obj = {
    # The sync script deserializes and reserializes these JSON columns. Their
    # whitespace/key order can therefore differ while the actual configuration
    # is identical. Hash their parsed value to prevent an endless re-sync loop.
    "model": normalize_fields(model, ("params",)),
    "knowledge": normalize_fields(knowledge, ("meta", "data")),
    "files": [normalize_fields(row, ("meta", "data")) for row in rows],
    "rag_config": normalized_rag_config,
    # Main carries the format expected by this checkout; public carries the
    # format that was last imported. A code-only retrieval fix therefore
    # triggers exactly one safe sync on the next automatic cycle.
    "sync_format_version": expected_format_version if target == "main" else public_format_version,
}
payload = json.dumps(payload_obj, ensure_ascii=False, sort_keys=True)
print(hashlib.sha256(payload.encode("utf-8")).hexdigest())
print(len(rows))
PY
