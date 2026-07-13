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

CONTAINER="${ANALYTICS_CONTAINER:-local-knowledge-base-token-cache}"
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

TYPE_RULES = [
    ("开机/系统故障", ["开机", "logo", "蓝屏", "死机", "无法进入", "黑屏", "卡住", "重启", "故障"]),
    ("风扇/噪音", ["风扇", "异响", "噪音", "响", "嗡", "吵"]),
    ("配置/参数", ["配置", "参数", "规格", "cpu", "内存", "硬盘", "接口", "分辨率"]),
    ("价格/购买", ["价格", "多少钱", "报价", "购买", "下单", "优惠"]),
    ("售后/保修", ["售后", "保修", "维修", "退换", "客服", "质保"]),
    ("使用/操作", ["怎么用", "如何", "操作", "设置", "安装", "连接", "升级"]),
]

LANGUAGE_RULES = [
    ("中文", re.compile(r"[\u4e00-\u9fff]")),
    ("日本語", re.compile(r"[\u3040-\u30ff]")),
    ("한국어", re.compile(r"[\uac00-\ud7af]")),
    ("العربية", re.compile(r"[\u0600-\u06ff]")),
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

def classify_type(text):
    low = text.lower()
    for label, keywords in TYPE_RULES:
        if any(keyword.lower() in low for keyword in keywords):
            return label
    if len(text.strip()) <= 8:
        return "寒暄/泛问"
    return "其他"

def detect_language(text):
    for label, pattern in LANGUAGE_RULES:
        if pattern.search(text):
            return label
    if re.search(r"\b(the|what|how|why|please|help|can|does|is|are)\b", text, flags=re.I):
        return "English"
    return "其他"

con = sqlite3.connect("/cache/token-cache.sqlite3")
con.row_factory = sqlite3.Row
cur = con.cursor()

cur.execute(
    """
    create table if not exists public_question_log (
        question text,
        language text,
        created_at integer not null
    )
    """
)

messages = cur.execute(
    """
    select '' as message_id, '' as chat_id, question as content, '' as model_id,
           created_at, '公开访客' as title, language
    from public_question_log
    order by created_at
    """
).fetchall()

questions = []
question_counter = collections.Counter()
model_counter = collections.Counter()
hour_counter = collections.Counter()
type_counter = collections.Counter()
language_counter = collections.Counter()

for row in messages:
    text = text_from_json(row["content"]).strip()
    if not text:
        continue
    normalized = normalize_question(text)
    question_counter[normalized] += 1
    dt = time.strftime("%Y-%m-%d %H:00", time.localtime(row["created_at"] or 0))
    hour_counter[dt] += 1
    models = extract_models(text)
    question_type = classify_type(text)
    language = row["language"] or detect_language(text)
    type_counter[question_type] += 1
    language_counter[language] += 1
    for model in models:
        model_counter[model] += 1
    questions.append({
        "chat_id": row["chat_id"],
        "title": row["title"],
        "question": text,
        "normalized": normalized,
        "models": models,
        "type": question_type,
        "language": language,
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
    "top_types": [{"type": k, "count": v} for k, v in type_counter.most_common(30)],
    "top_languages": [{"language": k, "count": v} for k, v in language_counter.most_common(30)],
    "questions_by_hour": [{"hour": k, "count": v} for k, v in sorted(hour_counter.items())],
    "questions": questions,
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
        f.write(f"- [{item.get('type', '其他')}/{item.get('language', '其他')}] {item['question']}\n")
PY

echo "Analytics written:"
echo "  ${OUT_DIR}/question-analytics.json"
echo "  ${OUT_DIR}/question-analytics.md"
