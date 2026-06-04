#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

"${SCRIPT_DIR}/question-analytics.sh" >/dev/null

OUT_DIR="${SCRIPT_DIR}/analytics"
JSON_FILE="${OUT_DIR}/question-analytics.json"
HTML_FILE="${OUT_DIR}/question-analytics-dashboard.html"

python3 - "${JSON_FILE}" "${HTML_FILE}" <<'PY'
import html
import json
import math
import sys
from datetime import datetime

src, dst = sys.argv[1:3]
data = json.load(open(src, encoding="utf-8"))

generated_at = datetime.fromtimestamp(data.get("generated_at", 0)).strftime("%Y-%m-%d %H:%M:%S")
total = int(data.get("total_questions") or 0)
top_questions = data.get("top_questions") or []
top_models = data.get("top_models") or []
by_hour = data.get("questions_by_hour") or []
recent = data.get("recent_questions") or []

def esc(value):
    return html.escape(str(value or ""))

def percent(value, base):
    if not base:
        return 0
    return min(100, round(value / base * 100, 1))

max_question_count = max([item.get("count", 0) for item in top_questions] or [1])
max_model_count = max([item.get("count", 0) for item in top_models] or [1])
max_hour_count = max([item.get("count", 0) for item in by_hour] or [1])

top_question_rows = "\n".join(
    f"""
    <tr>
      <td class="rank">{index}</td>
      <td>{esc(item.get("question"))}</td>
      <td class="number">{item.get("count", 0)}</td>
      <td class="bar-cell"><span style="width:{percent(item.get("count", 0), max_question_count)}%"></span></td>
    </tr>
    """
    for index, item in enumerate(top_questions[:20], 1)
) or '<tr><td colspan="4" class="empty">暂无问题数据。访客提问后重新运行 ./analytics-dashboard.sh。</td></tr>'

model_rows = "\n".join(
    f"""
    <tr>
      <td>{esc(item.get("model"))}</td>
      <td class="number">{item.get("count", 0)}</td>
      <td class="bar-cell"><span style="width:{percent(item.get("count", 0), max_model_count)}%"></span></td>
    </tr>
    """
    for item in top_models[:20]
) or '<tr><td colspan="3" class="empty">暂未识别到型号关键词。</td></tr>'

hour_bars = "\n".join(
    f"""
    <div class="hour-item" title="{esc(item.get("hour"))}: {item.get("count", 0)}">
      <div class="hour-bar" style="height:{max(8, percent(item.get("count", 0), max_hour_count) * 1.2)}px"></div>
      <div class="hour-label">{esc(str(item.get("hour", ""))[-5:])}</div>
    </div>
    """
    for item in by_hour[-24:]
) or '<div class="empty trend-empty">暂无趋势数据</div>'

recent_rows = "\n".join(
    f"""
    <tr>
      <td>{esc(item.get("hour"))}</td>
      <td>{esc(item.get("question"))}</td>
      <td>{esc(", ".join(item.get("models") or [])) or "-"}</td>
    </tr>
    """
    for item in recent[-30:][::-1]
) or '<tr><td colspan="3" class="empty">暂无最近问题。</td></tr>'

html_doc = f"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>问题分析后台</title>
  <style>
    :root {{
      color-scheme: light;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      --text: #172033;
      --muted: #6b7280;
      --line: #e5e7eb;
      --panel: #ffffff;
      --soft: #f7f8fb;
      --accent: #0f766e;
      --accent-2: #2563eb;
      --warn: #b45309;
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      background: #f4f6f8;
      color: var(--text);
      font-size: 14px;
    }}
    header {{
      align-items: center;
      background: var(--panel);
      border-bottom: 1px solid var(--line);
      display: flex;
      gap: 20px;
      justify-content: space-between;
      padding: 18px 28px;
      position: sticky;
      top: 0;
      z-index: 3;
    }}
    h1 {{
      font-size: 22px;
      letter-spacing: 0;
      margin: 0 0 4px;
    }}
    .subtitle {{
      color: var(--muted);
      font-size: 13px;
    }}
    .actions {{
      align-items: center;
      display: flex;
      gap: 10px;
    }}
    .button {{
      background: #111827;
      border-radius: 7px;
      color: white;
      font-weight: 650;
      padding: 9px 12px;
      text-decoration: none;
      white-space: nowrap;
    }}
    main {{
      margin: 0 auto;
      max-width: 1180px;
      padding: 24px;
    }}
    .metrics {{
      display: grid;
      gap: 14px;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      margin-bottom: 18px;
    }}
    .metric {{
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 16px;
    }}
    .metric-label {{
      color: var(--muted);
      font-size: 13px;
      margin-bottom: 8px;
    }}
    .metric-value {{
      font-size: 28px;
      font-weight: 760;
    }}
    .grid {{
      display: grid;
      gap: 18px;
      grid-template-columns: minmax(0, 1.4fr) minmax(320px, 0.9fr);
    }}
    section {{
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      overflow: hidden;
    }}
    section + section {{ margin-top: 18px; }}
    h2 {{
      border-bottom: 1px solid var(--line);
      font-size: 16px;
      margin: 0;
      padding: 14px 16px;
    }}
    table {{
      border-collapse: collapse;
      width: 100%;
    }}
    th, td {{
      border-bottom: 1px solid var(--line);
      padding: 11px 14px;
      text-align: left;
      vertical-align: middle;
    }}
    th {{
      background: var(--soft);
      color: #4b5563;
      font-size: 12px;
      font-weight: 700;
    }}
    tr:last-child td {{ border-bottom: 0; }}
    .rank {{
      color: var(--muted);
      font-variant-numeric: tabular-nums;
      width: 48px;
    }}
    .number {{
      font-variant-numeric: tabular-nums;
      font-weight: 700;
      text-align: right;
      width: 72px;
    }}
    .bar-cell {{
      width: 150px;
    }}
    .bar-cell span {{
      background: linear-gradient(90deg, var(--accent), var(--accent-2));
      border-radius: 999px;
      display: block;
      height: 8px;
      min-width: 4px;
    }}
    .trend {{
      align-items: end;
      display: flex;
      gap: 8px;
      height: 170px;
      padding: 18px 16px 12px;
    }}
    .hour-item {{
      align-items: center;
      display: flex;
      flex: 1;
      flex-direction: column;
      gap: 8px;
      justify-content: end;
      min-width: 18px;
    }}
    .hour-bar {{
      background: #0f766e;
      border-radius: 4px 4px 0 0;
      min-height: 8px;
      width: 100%;
    }}
    .hour-label {{
      color: var(--muted);
      font-size: 11px;
      writing-mode: vertical-rl;
    }}
    .empty {{
      color: var(--muted);
      padding: 24px;
      text-align: center;
    }}
    .trend-empty {{
      align-self: center;
      width: 100%;
    }}
    .note {{
      background: #fff7ed;
      border: 1px solid #fed7aa;
      border-radius: 8px;
      color: #7c2d12;
      margin-top: 18px;
      padding: 14px 16px;
    }}
    @media (max-width: 900px) {{
      header {{ align-items: flex-start; flex-direction: column; }}
      .metrics {{ grid-template-columns: repeat(2, minmax(0, 1fr)); }}
      .grid {{ grid-template-columns: 1fr; }}
    }}
  </style>
</head>
<body>
  <header>
    <div>
      <h1>问题分析后台</h1>
      <div class="subtitle">生成时间：{esc(generated_at)} · 数据来源：外部访客端问题日志</div>
    </div>
    <div class="actions">
      <a class="button" href="question-analytics.json">JSON 数据</a>
      <a class="button" href="question-analytics.md">Markdown 报告</a>
    </div>
  </header>
  <main>
    <div class="metrics">
      <div class="metric"><div class="metric-label">总问题数</div><div class="metric-value">{total}</div></div>
      <div class="metric"><div class="metric-label">高频问题种类</div><div class="metric-value">{len(top_questions)}</div></div>
      <div class="metric"><div class="metric-label">识别型号数</div><div class="metric-value">{len(top_models)}</div></div>
      <div class="metric"><div class="metric-label">最近问题</div><div class="metric-value">{len(recent)}</div></div>
    </div>
    <div class="grid">
      <div>
        <section>
          <h2>高频问题</h2>
          <table>
            <thead><tr><th>#</th><th>问题</th><th>次数</th><th>占比</th></tr></thead>
            <tbody>{top_question_rows}</tbody>
          </table>
        </section>
        <section>
          <h2>最近问题</h2>
          <table>
            <thead><tr><th>时间</th><th>问题</th><th>识别型号</th></tr></thead>
            <tbody>{recent_rows}</tbody>
          </table>
        </section>
      </div>
      <div>
        <section>
          <h2>哪个型号被问得多</h2>
          <table>
            <thead><tr><th>型号</th><th>次数</th><th>热度</th></tr></thead>
            <tbody>{model_rows}</tbody>
          </table>
        </section>
        <section>
          <h2>最近 24 小时趋势</h2>
          <div class="trend">{hour_bars}</div>
        </section>
      </div>
    </div>
    <div class="note">提示：外部访客端会清理聊天记录，但在清理前会保留问题日志用于统计；敏感资料仍应放在登录访问的知识库中。</div>
  </main>
</body>
</html>
"""

open(dst, "w", encoding="utf-8").write(html_doc)
print(dst)
PY

echo "Analytics dashboard written:"
echo "  ${HTML_FILE}"
