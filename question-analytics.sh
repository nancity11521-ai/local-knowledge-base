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

CONTAINER="${ANALYTICS_CONTAINER:-local-knowledge-base-public}"
OUT_DIR="${SCRIPT_DIR}/analytics"
mkdir -p "${OUT_DIR}"

"${DOCKER_BIN}" exec -i "${CONTAINER}" python - <<'PY' > "${OUT_DIR}/question-analytics.json"
import collections
import json
import re
import sqlite3
import time

MODEL_PATTERNS = [
    r"\b[A-Z]\d{1,3}\s*(?:Pro|Max|Mini|Plus)?\b",
    r"\bG\d{1,3}\s*(?:Pro|Max|Mini|Plus)?\b",
    r"\bK\d{1,3}\s*(?:Pro|Max|Mini|Plus)?\b",
    r"\bi\d[- ]?\d{4,5}[A-Z]*\b",
    r"\bUltra\s*\d+\s*\d*[A-Z]?\b",
]

def text_from_json(value):
    if value is None:
        return ""
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
        except Exception:
            return value
    else:
        parsed = value
    if isinstance(parsed, str):
        return parsed
    if isinstance(parsed, dict):
        for key in ("content", "text", "value"):
            if isinstance(parsed.get(key), str):
                return parsed[key]
    return json.dumps(parsed, ensure_ascii=False)

def normalize_question(text):
    text = re.sub(r"\s+", "", text.strip().lower())
    text = re.sub(r"[？?。！!，,、：:；;\"'“”‘’（）()【】\\[\\]{}<>《》]", "", text)
    return text

def extract_models(text):
    found = []
    for pattern in MODEL_PATTERNS:
        found.extend(re.findall(pattern, text, flags=re.I))
    clean = []
    seen = set()
    for item in found:
        value = re.sub(r"\s+", " ", item.strip()).upper()
        if value and value not in seen:
            seen.add(value)
            clean.append(value)
    return clean

con = sqlite3.connect("/app/backend/data/webui.db")
con.row_factory = sqlite3.Row
cur = con.cursor()

messages = cur.execute(
    """
    select cm.chat_id, cm.content, cm.model_id, cm.created_at, c.title
    from chat_message cm
    left join chat c on c.id = cm.chat_id
    where cm.role = 'user'
    order by cm.created_at
    """
).fetchall()

questions = []
question_counter = collections.Counter()
model_counter = collections.Counter()
hour_counter = collections.Counter()

for row in messages:
    text = text_from_json(row["content"]).strip()
    if not text:
        continue
    normalized = normalize_question(text)
    question_counter[normalized] += 1
    dt = time.strftime("%Y-%m-%d %H:00", time.localtime(row["created_at"] or 0))
    hour_counter[dt] += 1
    models = extract_models(text)
    for model in models:
        model_counter[model] += 1
    questions.append({
        "chat_id": row["chat_id"],
        "title": row["title"],
        "question": text,
        "normalized": normalized,
        "models": models,
        "created_at": row["created_at"],
        "hour": dt,
    })

top_questions = []
example_by_norm = {}
for q in questions:
    example_by_norm.setdefault(q["normalized"], q["question"])
for normalized, count in question_counter.most_common(30):
    top_questions.append({
        "question": example_by_norm.get(normalized, normalized),
        "normalized": normalized,
        "count": count,
    })

result = {
    "generated_at": int(time.time()),
    "total_questions": len(questions),
    "top_questions": top_questions,
    "top_models": [{"model": k, "count": v} for k, v in model_counter.most_common(30)],
    "questions_by_hour": [{"hour": k, "count": v} for k, v in sorted(hour_counter.items())],
    "recent_questions": questions[-50:],
}
print(json.dumps(result, ensure_ascii=False, indent=2))
PY

python3 - "${OUT_DIR}/question-analytics.json" "${OUT_DIR}/question-analytics.md" <<'PY'
import json
import sys
from datetime import datetime

src, dst = sys.argv[1:3]
data = json.load(open(src, encoding="utf-8"))
with open(dst, "w", encoding="utf-8") as f:
    f.write("# 问题统计分析\n\n")
    f.write(f"生成时间：{datetime.fromtimestamp(data['generated_at']).strftime('%Y-%m-%d %H:%M:%S')}\n\n")
    f.write(f"总问题数：{data['total_questions']}\n\n")
    f.write("## 高频问题\n\n")
    for item in data["top_questions"][:20]:
        f.write(f"- {item['count']} 次：{item['question']}\n")
    f.write("\n## 高频型号\n\n")
    for item in data["top_models"][:20]:
        f.write(f"- {item['count']} 次：{item['model']}\n")
    f.write("\n## 最近问题\n\n")
    for item in data["recent_questions"][-20:]:
        f.write(f"- {item['question']}\n")
PY

echo "Analytics written:"
echo "  ${OUT_DIR}/question-analytics.json"
echo "  ${OUT_DIR}/question-analytics.md"
