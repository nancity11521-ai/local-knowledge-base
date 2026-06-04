#!/usr/bin/env python3
import hashlib
import json
import os
import sqlite3
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urljoin

CACHE_DB = os.environ.get("CACHE_DB", "/cache/token-cache.sqlite3")
UPSTREAM_BASE_URL = os.environ.get("UPSTREAM_BASE_URL", "https://api.deepseek.com/v1").rstrip("/")
UPSTREAM_API_KEY = os.environ.get("OPENAI_API_KEY") or os.environ.get("UPSTREAM_API_KEY", "")
CACHE_TTL_SECONDS = int(os.environ.get("CACHE_TTL_SECONDS", "604800"))
PORT = int(os.environ.get("CACHE_PROXY_PORT", "8000"))
DB_LOCK = threading.RLock()

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
    return con

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

def cache_key(path, raw):
    semantic = normalize_payload(raw)
    return hashlib.sha256(path.encode("utf-8") + b"\n" + semantic).hexdigest()

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        print("[%s] %s" % (time.strftime("%Y-%m-%d %H:%M:%S"), fmt % args), flush=True)

    def do_GET(self):
        if self.path == "/health":
            body = b"ok"
            self.send_response(200)
            self.send_header("content-length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.proxy(cacheable=False)

    def do_POST(self):
        self.proxy(cacheable=self.path.endswith("/chat/completions"))

    def proxy(self, cacheable=False):
        length = int(self.headers.get("content-length", "0") or "0")
        raw = self.rfile.read(length) if length else b""
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

        url = UPSTREAM_BASE_URL + self.path.replace("/v1", "", 1) if self.path.startswith("/v1") else urljoin(UPSTREAM_BASE_URL + "/", self.path.lstrip("/"))
        headers = {k: v for k, v in self.headers.items() if k.lower() not in {"host", "content-length", "connection"}}
        if UPSTREAM_API_KEY:
            headers["Authorization"] = "Bearer " + UPSTREAM_API_KEY
        request = urllib.request.Request(url, data=raw if self.command != "GET" else None, headers=headers, method=self.command)

        try:
            with urllib.request.urlopen(request, timeout=300) as response:
                body = response.read()
                status = response.status
                response_headers = dict(response.headers.items())
        except urllib.error.HTTPError as exc:
            body = exc.read()
            status = exc.code
            response_headers = dict(exc.headers.items())

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
