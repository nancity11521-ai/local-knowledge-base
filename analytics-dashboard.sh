#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

"${SCRIPT_DIR}/question-analytics.sh" >/dev/null

OUT_DIR="${SCRIPT_DIR}/analytics"
JSON_FILE="${OUT_DIR}/question-analytics.json"
HTML_FILE="${OUT_DIR}/question-analytics-dashboard.html"

python3 - "${JSON_FILE}" "${HTML_FILE}" <<'PY'
import json
import sys
from datetime import datetime

src, dst = sys.argv[1:3]
data = json.load(open(src, encoding="utf-8"))
generated_at = datetime.fromtimestamp(data.get("generated_at", 0)).strftime("%Y-%m-%d %H:%M:%S")
payload = json.dumps(data, ensure_ascii=False).replace("</", "<\\/")

html = f"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta http-equiv="cache-control" content="no-store">
  <title>问题分析后台</title>
  <script>
    (async function () {
      try {
        const response = await fetch('/api/v1/auths/', { credentials: 'same-origin' });
        const user = response.ok ? await response.json() : null;
        if (user?.role !== 'admin') {
          location.replace('/auth?redirect=' + encodeURIComponent(location.pathname));
        }
      } catch (_) {
        location.replace('/auth?redirect=' + encodeURIComponent(location.pathname));
      }
    })();
  </script>
  <style>
    :root {{
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      --text:#172033; --muted:#6b7280; --line:#e5e7eb; --panel:#fff; --soft:#f7f8fb;
      --accent:#0f766e; --accent2:#2563eb; --bg:#f4f6f8;
    }}
    * {{ box-sizing:border-box; }}
    body {{ margin:0; background:var(--bg); color:var(--text); font-size:14px; }}
    header {{
      align-items:center; background:var(--panel); border-bottom:1px solid var(--line);
      display:flex; gap:20px; justify-content:space-between; padding:18px 28px; position:sticky; top:0; z-index:2;
    }}
    h1 {{ font-size:22px; margin:0 0 4px; letter-spacing:0; }}
    h2 {{ border-bottom:1px solid var(--line); font-size:16px; margin:0; padding:14px 16px; }}
    .subtitle {{ color:var(--muted); font-size:13px; }}
    .actions {{ display:flex; gap:10px; align-items:center; }}
    .button {{ background:#111827; border-radius:7px; color:white; font-weight:700; padding:9px 12px; text-decoration:none; white-space:nowrap; }}
    main {{ max-width:1220px; margin:0 auto; padding:22px 24px 28px; }}
    .filters {{
      background:var(--panel); border:1px solid var(--line); border-radius:8px; display:grid;
      gap:12px; grid-template-columns: repeat(7, minmax(0, 1fr)); margin-bottom:16px; padding:14px;
    }}
    label {{ color:#4b5563; display:block; font-size:12px; font-weight:700; margin-bottom:6px; }}
    select, input[type="date"] {{
      background:#fff; border:1px solid #d1d5db; border-radius:7px; color:var(--text);
      height:36px; padding:0 10px; width:100%;
    }}
    .custom-date {{ display:none; }}
    .custom-date.is-visible {{ display:block; }}
    .metrics {{ display:grid; gap:14px; grid-template-columns:repeat(4, minmax(0,1fr)); margin-bottom:18px; }}
    .metric {{ background:var(--panel); border:1px solid var(--line); border-radius:8px; padding:16px; }}
    .metric-label {{ color:var(--muted); font-size:13px; margin-bottom:8px; }}
    .metric-value {{ font-size:28px; font-weight:760; }}
    .grid {{ display:grid; gap:18px; grid-template-columns:minmax(0,1.45fr) minmax(320px,.9fr); }}
    section {{ background:var(--panel); border:1px solid var(--line); border-radius:8px; overflow:hidden; }}
    section + section {{ margin-top:18px; }}
    table {{ border-collapse:collapse; width:100%; }}
    th, td {{ border-bottom:1px solid var(--line); padding:11px 14px; text-align:left; vertical-align:middle; }}
    th {{ background:var(--soft); color:#4b5563; font-size:12px; font-weight:700; }}
    tr:last-child td {{ border-bottom:0; }}
    .rank {{ color:var(--muted); width:48px; }}
    .number {{ font-variant-numeric:tabular-nums; font-weight:700; text-align:right; width:72px; }}
    .bar-cell {{ width:150px; }}
    .bar-cell span {{ background:linear-gradient(90deg,var(--accent),var(--accent2)); border-radius:999px; display:block; height:8px; min-width:4px; }}
    .trend {{ align-items:end; display:flex; gap:8px; height:180px; padding:18px 16px 12px; }}
    .hour-item {{ align-items:center; display:flex; flex:1; flex-direction:column; gap:8px; justify-content:end; min-width:18px; }}
    .hour-bar {{ background:#0f766e; border-radius:4px 4px 0 0; min-height:8px; width:100%; }}
    .hour-label {{ color:var(--muted); font-size:11px; writing-mode:vertical-rl; }}
    .empty {{ color:var(--muted); padding:24px; text-align:center; }}
    .note {{ background:#fff7ed; border:1px solid #fed7aa; border-radius:8px; color:#7c2d12; margin-top:18px; padding:14px 16px; }}
    .pill {{ background:#eef2ff; border-radius:999px; color:#3730a3; display:inline-block; font-size:12px; font-weight:700; padding:3px 8px; }}
    @media (max-width:980px) {{ .filters,.metrics {{ grid-template-columns:repeat(2,minmax(0,1fr)); }} .grid {{ grid-template-columns:1fr; }} header {{ align-items:flex-start; flex-direction:column; }} }}
  </style>
</head>
<body>
  <header>
    <div>
      <h1>问题分析后台</h1>
      <div class="subtitle">生成时间：{generated_at} · 数据来源：外部访客端问题日志</div>
    </div>
    <div class="actions">
      <a class="button" href="/static/analytics/question-analytics.json">JSON 数据</a>
      <a class="button" href="/static/analytics/question-analytics.md">Markdown 报告</a>
    </div>
  </header>
  <main>
    <div class="filters">
      <div><label for="period">时间范围</label><select id="period"><option value="all">全部</option><option value="month">本月</option><option value="quarter">本季度</option><option value="year">本年</option><option value="custom">可选日期</option></select></div>
      <div class="custom-date" id="customStartWrap"><label for="startDate">开始日期</label><input id="startDate" type="date"></div>
      <div class="custom-date" id="customEndWrap"><label for="endDate">结束日期</label><input id="endDate" type="date"></div>
      <div><label for="modelFilter">机型</label><select id="modelFilter"><option value="all">全部机型</option></select></div>
      <div><label for="typeFilter">问题类型</label><select id="typeFilter"><option value="all">全部类型</option></select></div>
      <div><label for="languageFilter">语言</label><select id="languageFilter"><option value="all">全部语言</option></select></div>
      <div><label for="sortFilter">排序</label><select id="sortFilter"><option value="count">按次数</option><option value="recent">按最近</option></select></div>
    </div>
    <div class="metrics">
      <div class="metric"><div class="metric-label">筛选后问题数</div><div class="metric-value" id="metricTotal">0</div></div>
      <div class="metric"><div class="metric-label">高频问题种类</div><div class="metric-value" id="metricQuestionKinds">0</div></div>
      <div class="metric"><div class="metric-label">识别型号数</div><div class="metric-value" id="metricModels">0</div></div>
      <div class="metric"><div class="metric-label">问题类型数</div><div class="metric-value" id="metricTypes">0</div></div>
    </div>
    <div class="grid">
      <div>
        <section>
          <h2>高频问题</h2>
          <table>
            <thead><tr><th>#</th><th>问题</th><th>类型</th><th>语言</th><th>次数</th><th>占比</th></tr></thead>
            <tbody id="topQuestions"></tbody>
          </table>
        </section>
        <section>
          <h2>最近问题</h2>
          <table>
            <thead><tr><th>时间</th><th>问题</th><th>类型</th><th>语言</th><th>识别型号</th></tr></thead>
            <tbody id="recentQuestions"></tbody>
          </table>
        </section>
      </div>
      <div>
        <section>
          <h2>哪个型号被问得多</h2>
          <table>
            <thead><tr><th>型号</th><th>次数</th><th>热度</th></tr></thead>
            <tbody id="topModels"></tbody>
          </table>
        </section>
        <section>
          <h2>问题类型分布</h2>
          <table>
            <thead><tr><th>类型</th><th>次数</th><th>占比</th></tr></thead>
            <tbody id="topTypes"></tbody>
          </table>
        </section>
        <section>
          <h2>趋势</h2>
          <div class="trend" id="trend"></div>
        </section>
      </div>
    </div>
    <div class="note">提示：外部访客端会清理聊天记录，但在清理前会保留问题日志用于统计；敏感资料仍应放在登录访问的知识库中。</div>
  </main>
  <script>
    const DATA = {payload};
    const QUESTIONS = DATA.questions || DATA.recent_questions || [];
    const els = {{
      period: document.getElementById('period'),
      startDate: document.getElementById('startDate'),
      endDate: document.getElementById('endDate'),
      startWrap: document.getElementById('customStartWrap'),
      endWrap: document.getElementById('customEndWrap'),
      model: document.getElementById('modelFilter'),
      type: document.getElementById('typeFilter'),
      language: document.getElementById('languageFilter'),
      sort: document.getElementById('sortFilter')
    }};
    const fmtTime = (ts) => ts ? new Date(ts * 1000).toLocaleString('zh-CN', {{ hour12:false }}) : '-';
    const html = (v) => String(v ?? '').replace(/[&<>"']/g, s => ({{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}}[s]));
    const unique = (items) => [...new Set(items.filter(Boolean))].sort((a,b) => String(a).localeCompare(String(b), 'zh-CN'));
    const countBy = (items, getter) => {{
      const map = new Map();
      for (const item of items) {{
        const keys = getter(item);
        for (const key of Array.isArray(keys) ? keys : [keys]) {{
          if (!key) continue;
          map.set(key, (map.get(key) || 0) + 1);
        }}
      }}
      return [...map.entries()].map(([name, count]) => ({{ name, count }})).sort((a,b) => b.count - a.count || String(a.name).localeCompare(String(b.name), 'zh-CN'));
    }};
    function periodStart(period) {{
      const now = new Date();
      if (period === 'month') return new Date(now.getFullYear(), now.getMonth(), 1).getTime() / 1000;
      if (period === 'quarter') return new Date(now.getFullYear(), Math.floor(now.getMonth() / 3) * 3, 1).getTime() / 1000;
      if (period === 'year') return new Date(now.getFullYear(), 0, 1).getTime() / 1000;
      return 0;
    }}
    function customRange() {{
      if (els.period.value !== 'custom') return {{ start: 0, end: Infinity }};
      const start = els.startDate.value ? new Date(`${{els.startDate.value}}T00:00:00`).getTime() / 1000 : 0;
      const end = els.endDate.value ? new Date(`${{els.endDate.value}}T23:59:59`).getTime() / 1000 : Infinity;
      return {{ start, end }};
    }}
    function fillSelect(select, values, labelAll) {{
      const selected = select.value || 'all';
      select.innerHTML = `<option value="all">${{labelAll}}</option>` + values.map(v => `<option value="${{html(v)}}">${{html(v)}}</option>`).join('');
      select.value = values.includes(selected) ? selected : 'all';
    }}
    function setupFilters() {{
      fillSelect(els.model, unique(QUESTIONS.flatMap(q => q.models || [])), '全部机型');
      fillSelect(els.type, unique(QUESTIONS.map(q => q.type || '其他')), '全部类型');
      fillSelect(els.language, unique(QUESTIONS.map(q => q.language || '其他')), '全部语言');
      [els.period, els.startDate, els.endDate, els.model, els.type, els.language, els.sort].forEach(el => el.addEventListener('change', render));
    }}
    function filteredQuestions() {{
      const custom = customRange();
      const start = els.period.value === 'custom' ? custom.start : periodStart(els.period.value);
      const end = els.period.value === 'custom' ? custom.end : Infinity;
      els.startWrap.classList.toggle('is-visible', els.period.value === 'custom');
      els.endWrap.classList.toggle('is-visible', els.period.value === 'custom');
      return QUESTIONS.filter(q => {{
        if (start && (q.created_at || 0) < start) return false;
        if ((q.created_at || 0) > end) return false;
        if (els.model.value !== 'all' && !(q.models || []).includes(els.model.value)) return false;
        if (els.type.value !== 'all' && (q.type || '其他') !== els.type.value) return false;
        if (els.language.value !== 'all' && (q.language || '其他') !== els.language.value) return false;
        return true;
      }});
    }}
    function rowsForCounts(items, empty, labelKey='name') {{
      if (!items.length) return `<tr><td colspan="3" class="empty">${{empty}}</td></tr>`;
      const max = Math.max(...items.map(i => i.count), 1);
      return items.slice(0, 20).map(item => `
        <tr><td>${{html(item[labelKey] || item.name)}}</td><td class="number">${{item.count}}</td><td class="bar-cell"><span style="width:${{Math.max(4, item.count / max * 100)}}%"></span></td></tr>
      `).join('');
    }}
    function render() {{
      const rows = filteredQuestions();
      const questionCounts = countBy(rows, q => q.normalized || q.question).map(item => {{
        const sample = rows.find(q => (q.normalized || q.question) === item.name) || {{}};
        return {{ ...item, question: sample.question || item.name, type: sample.type || '其他', language: sample.language || '其他', latest: sample.created_at || 0 }};
      }});
      if (els.sort.value === 'recent') questionCounts.sort((a,b) => b.latest - a.latest);
      const modelCounts = countBy(rows, q => q.models || []);
      const typeCounts = countBy(rows, q => q.type || '其他');
      document.getElementById('metricTotal').textContent = rows.length;
      document.getElementById('metricQuestionKinds').textContent = questionCounts.length;
      document.getElementById('metricModels').textContent = modelCounts.length;
      document.getElementById('metricTypes').textContent = typeCounts.length;
      const maxQ = Math.max(...questionCounts.map(i => i.count), 1);
      document.getElementById('topQuestions').innerHTML = questionCounts.length ? questionCounts.slice(0, 20).map((item, idx) => `
        <tr><td class="rank">${{idx + 1}}</td><td>${{html(item.question)}}</td><td><span class="pill">${{html(item.type)}}</span></td><td>${{html(item.language)}}</td><td class="number">${{item.count}}</td><td class="bar-cell"><span style="width:${{Math.max(4, item.count / maxQ * 100)}}%"></span></td></tr>
      `).join('') : '<tr><td colspan="6" class="empty">暂无问题数据。</td></tr>';
      document.getElementById('topModels').innerHTML = rowsForCounts(modelCounts, '暂未识别到型号关键词。');
      document.getElementById('topTypes').innerHTML = rowsForCounts(typeCounts, '暂无类型数据。');
      document.getElementById('recentQuestions').innerHTML = rows.length ? [...rows].sort((a,b) => (b.created_at || 0) - (a.created_at || 0)).slice(0, 30).map(q => `
        <tr><td>${{fmtTime(q.created_at)}}</td><td>${{html(q.question)}}</td><td><span class="pill">${{html(q.type || '其他')}}</span></td><td>${{html(q.language || '其他')}}</td><td>${{html((q.models || []).join(', ') || '-')}}</td></tr>
      `).join('') : '<tr><td colspan="5" class="empty">暂无最近问题。</td></tr>';
      const hours = countBy(rows, q => q.hour || '-').sort((a,b) => String(a.name).localeCompare(String(b.name))).slice(-24);
      const maxH = Math.max(...hours.map(i => i.count), 1);
      document.getElementById('trend').innerHTML = hours.length ? hours.map(item => `
        <div class="hour-item" title="${{html(item.name)}}: ${{item.count}}"><div class="hour-bar" style="height:${{Math.max(8, item.count / maxH * 140)}}px"></div><div class="hour-label">${{html(String(item.name).slice(-5))}}</div></div>
      `).join('') : '<div class="empty" style="width:100%">暂无趋势数据</div>';
    }}
    setupFilters();
    render();
  </script>
</body>
</html>
"""

open(dst, "w", encoding="utf-8").write(html)
print(dst)
PY

echo "Analytics dashboard written:"
echo "  ${HTML_FILE}"
