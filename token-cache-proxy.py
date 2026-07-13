#!/usr/bin/env python3
import hashlib
import json
import os
import sqlite3
import threading
import time
import urllib.error
import urllib.request
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urljoin

CACHE_DB = os.environ.get("CACHE_DB", "/cache/token-cache.sqlite3")
UPSTREAM_BASE_URL = os.environ.get("UPSTREAM_BASE_URL", "https://api.deepseek.com/v1").rstrip("/")
UPSTREAM_API_KEY = os.environ.get("OPENAI_API_KEY") or os.environ.get("UPSTREAM_API_KEY", "")
CACHE_TTL_SECONDS = int(os.environ.get("CACHE_TTL_SECONDS", "604800"))
PORT = int(os.environ.get("CACHE_PROXY_PORT", "8000"))
DB_LOCK = threading.RLock()
LANGUAGE_RULES = {
    "zh-CN": "请只使用中文回答。最终回答的所有内容都必须是中文。",
    "en-US": "Respond only in English. Every part of the final answer must be in English.",
    "ja-JP": "日本語のみで回答してください。最終回答のすべてを日本語で書いてください。",
    "ko-KR": "한국어로만 답변하세요. 최종 답변의 모든 내용을 한국어로 작성하세요.",
    "es-ES": "Responde únicamente en español. Toda la respuesta final debe estar en español.",
    "fr-FR": "Répondez uniquement en français. Toute la réponse finale doit être en français.",
    "de-DE": "Antworten Sie ausschließlich auf Deutsch. Die gesamte endgültige Antwort muss auf Deutsch sein.",
    "ar-SA": "أجب باللغة العربية فقط. يجب أن تكون جميع أجزاء الإجابة النهائية باللغة العربية.",
}
LANGUAGE_MARKER = re.compile(r"\[PUBLIC_RESPONSE_LANGUAGE:([A-Za-z]{2}-[A-Za-z]{2})\]\s*")

os.makedirs(os.path.dirname(CACHE_DB), exist_ok=True)

def db():
    con = sqlite3.connect(CACHE_DB, timeout=30)
    con.execute("pragma journal_mode=wal")
    con.execute("pragma busy_timeout=30000")
    con.execute(
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
    con.execute(
        """
        create table if not exists stats (
            key text primary key,
            value integer not null
        )
        """
    )
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
    con.execute(
        """
        create table if not exists public_question_log (
            id integer primary key autoincrement,
            question text not null,
            language text,
            created_at integer not null
        )
        """
    )
    return con

def access_stats():
    with DB_LOCK:
        with db() as con:
            rows = con.execute(
                """
                select date(created_at, 'unixepoch', 'localtime') as day,
                       sum(case when event = 'visit' then 1 else 0 end) as visits,
                       count(distinct case when event = 'visit' then session_id end) as visitors,
                       sum(case when event = 'consultation' then 1 else 0 end) as consultations
                from access_log group by day order by day desc limit 366
                """
            ).fetchall()
            languages = con.execute(
                """
                select language, count(*) from access_log
                where event = 'consultation' and language is not null
                group by language order by count(*) desc
                """
            ).fetchall()
    return {
        "days": [
            {"day": row[0], "visits": row[1] or 0, "visitors": row[2] or 0, "consultations": row[3] or 0}
            for row in rows
        ],
        "languages": [{"language": row[0], "count": row[1]} for row in languages],
    }

def bump(name, amount=1):
    try:
        with DB_LOCK:
            with db() as con:
                con.execute(
                    "insert into stats (key, value) values (?, ?) on conflict(key) do update set value = value + ?",
                    (name, amount, amount),
                )
    except sqlite3.Error as exc:
        print(f"Stats write skipped: {exc}", flush=True)

def normalize_payload(raw):
    try:
        payload = json.loads(raw)
    except Exception:
        return raw
    payload.pop("stream_options", None)
    return json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")

def question_from_payload(raw):
    try:
        payload = json.loads(raw)
    except Exception:
        return ""

    questions = []

    def visit(value):
        if not isinstance(value, dict):
            return
        messages = value.get("messages")
        if isinstance(messages, list):
            for message in messages:
                if not isinstance(message, dict) or message.get("role") != "user":
                    continue
                content = message.get("content")
                if isinstance(content, str) and content.strip():
                    questions.append(content.strip())
        for key, child in value.items():
            if key != "messages" and isinstance(child, dict):
                visit(child)

    visit(payload)
    return questions[-1][:2000] if questions else ""

def cache_key(path, raw):
    semantic = normalize_payload(raw)
    return hashlib.sha256(path.encode("utf-8") + b"\n" + semantic).hexdigest()

def enforce_response_language(raw):
    try:
        payload = json.loads(raw)
    except Exception:
        return raw

    messages = payload.get("messages")
    if not isinstance(messages, list):
        return raw

    language = payload.get("public_response_language") or payload.get("language")
    last_user_index = max(
        (index for index, message in enumerate(messages)
         if isinstance(message, dict) and message.get("role") == "user"),
        default=None,
    )
    for index, message in enumerate(messages):
        content = message.get("content") if isinstance(message, dict) else None
        if not isinstance(content, str):
            continue
        matches = list(LANGUAGE_MARKER.finditer(content))
        # A marker belongs only to the most recent user question. Historical
        # markers must never alter a later Chinese request.
        if matches and index == last_user_index:
            language = matches[-1].group(1)
        message["content"] = LANGUAGE_MARKER.sub("", content)

    # The source custom model is synchronized from the administrator instance
    # and owns all knowledge-base rules. This proxy adds only the selected
    # response language; adding a second set of knowledge rules here would
    # make public and administrator answers use different prompts.
    messages[:] = [
        message for message in messages
        if not (
            isinstance(message, dict)
            and message.get("role") == "system"
            and "PUBLIC_LANGUAGE_ENFORCEMENT:" in str(message.get("content", ""))
        )
    ]

    # Chinese is the administrator model's source language. Keep its request
    # byte-for-byte free of public language instructions so both instances use
    # the same prompt and retrieval path.
    rule = LANGUAGE_RULES.get(language)
    if language in (None, "zh-CN") or not rule:
        payload.pop("public_response_language", None)
        payload["messages"] = messages
        return json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")

    has_language_rule = any(
        isinstance(message, dict)
        and message.get("role") == "system"
        and "RESPONSE_LANGUAGE:" in str(message.get("content", ""))
        for message in messages
    )
    if not has_language_rule:
        messages.insert(0, {
            "role": "system",
            "content": f"PUBLIC_LANGUAGE_ENFORCEMENT:{language}\n{rule}",
        })
    payload["messages"] = messages
    payload["public_response_language"] = language
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        print("[%s] %s" % (time.strftime("%Y-%m-%d %H:%M:%S"), fmt % args), flush=True)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("access-control-allow-origin", "*")
        self.send_header("access-control-allow-methods", "GET, POST, OPTIONS")
        self.send_header("access-control-allow-headers", "content-type")
        self.send_header("content-length", "0")
        self.end_headers()

    def do_GET(self):
        if self.path == "/health":
            body = b"ok"
            self.send_response(200)
            self.send_header("content-length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if self.path.startswith("/analytics/stats"):
            body = json.dumps(access_stats(), ensure_ascii=False).encode("utf-8")
            self.send_response(200)
            self.send_header("access-control-allow-origin", "*")
            self.send_header("content-type", "application/json; charset=utf-8")
            self.send_header("content-length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.proxy(cacheable=False)

    def do_POST(self):
        if self.path == "/analytics/visit":
            length = int(self.headers.get("content-length", "0") or "0")
            try:
                payload = json.loads(self.rfile.read(length) or b"{}")
                with DB_LOCK:
                    with db() as con:
                        con.execute(
                            "insert into access_log(event, session_id, language, created_at) values ('visit', ?, ?, ?)",
                            (str(payload.get("session_id", ""))[:128], str(payload.get("language", ""))[:32], int(time.time())),
                        )
                body = b'{"ok":true}'
                self.send_response(200)
            except Exception:
                body = b'{"ok":false}'
                self.send_response(400)
            self.send_header("access-control-allow-origin", "*")
            self.send_header("content-type", "application/json")
            self.send_header("content-length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.proxy(cacheable=self.path.endswith("/chat/completions"))

    def proxy(self, cacheable=False):
        length = int(self.headers.get("content-length", "0") or "0")
        raw = self.rfile.read(length) if length else b""
        if self.path.endswith("/chat/completions"):
            raw = enforce_response_language(raw)
            try:
                payload = json.loads(raw)
                language = payload.get("public_response_language")
                question = question_from_payload(raw)
                with DB_LOCK:
                    with db() as con:
                        con.execute(
                            "insert into access_log(event, language, created_at) values ('consultation', ?, ?)",
                            (str(language or "其他")[:32], int(time.time())),
                        )
                        if question:
                            con.execute(
                                "insert into public_question_log(question, language, created_at) values (?, ?, ?)",
                                (question, str(language or "其他")[:32], int(time.time())),
                            )
            except Exception:
                pass
        key = cache_key(self.path, raw)
        now = int(time.time())

        if cacheable:
            try:
                with DB_LOCK:
                    with db() as con:
                        row = con.execute("select status, headers, body, created_at from cache where key = ?", (key,)).fetchone()
                        if row and now - row[3] <= CACHE_TTL_SECONDS:
                            con.execute("update cache set hits = hits + 1 where key = ?", (key,))
                            con.execute(
                                "insert into stats (key, value) values ('cache_hits', 1) on conflict(key) do update set value = value + 1"
                            )
                            self.send_response(row[0])
                            for h, v in json.loads(row[1]).items():
                                if h.lower() not in {"transfer-encoding", "connection", "content-encoding"}:
                                    self.send_header(h, v)
                            self.send_header("x-token-cache", "hit")
                            self.send_header("content-length", str(len(row[2])))
                            self.end_headers()
                            self.wfile.write(row[2])
                            return
            except sqlite3.Error as exc:
                print(f"Cache read skipped: {exc}", flush=True)

        import ssl
        ssl_context = ssl._create_unverified_context()
        url = UPSTREAM_BASE_URL + self.path.replace("/v1", "", 1) if self.path.startswith("/v1") else urljoin(UPSTREAM_BASE_URL + "/", self.path.lstrip("/"))
        headers = {k: v for k, v in self.headers.items() if k.lower() not in {"host", "content-length", "connection"}}
        headers["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        if UPSTREAM_API_KEY:
            headers["Authorization"] = "Bearer " + UPSTREAM_API_KEY
        request = urllib.request.Request(url, data=raw if self.command != "GET" else None, headers=headers, method=self.command)

        try:
            with urllib.request.urlopen(request, timeout=300, context=ssl_context) as response:
                body = response.read()
                status = response.status
                response_headers = dict(response.headers.items())
        except urllib.error.HTTPError as exc:
            body = exc.read()
            status = exc.code
            response_headers = dict(exc.headers.items())
        except Exception as exc:
            body = f'{{"error": {{"message": "Proxy connection to upstream failed: {exc}", "type": "proxy_error"}}}}'.encode('utf-8')
            status = 502
            response_headers = {"content-type": "application/json"}

        if cacheable and status == 200:
            try:
                with DB_LOCK:
                    with db() as con:
                        con.execute(
                            "insert or replace into cache (key, status, headers, body, created_at, hits) values (?, ?, ?, ?, ?, coalesce((select hits from cache where key = ?), 0))",
                            (key, status, json.dumps(response_headers), body, now, key),
                        )
                        con.execute(
                            "insert into stats (key, value) values ('cache_misses', 1) on conflict(key) do update set value = value + 1"
                        )
            except sqlite3.Error as exc:
                print(f"Cache write skipped: {exc}", flush=True)

        self.send_response(status)
        for h, v in response_headers.items():
            if h.lower() not in {"transfer-encoding", "connection", "content-encoding", "content-length"}:
                self.send_header(h, v)
        self.send_header("x-token-cache", "miss")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

if __name__ == "__main__":
    print(f"Token cache proxy listening on :{PORT}, upstream={UPSTREAM_BASE_URL}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
