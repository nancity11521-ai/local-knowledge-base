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

PUBLIC_CONTAINER="${PUBLIC_CONTAINER:-local-knowledge-base-public}"
PUBLIC_ASSET_VERSION="${PUBLIC_ASSET_VERSION:-20260707-2}"

if ! "${DOCKER_BIN}" ps --format '{{.Names}}' | grep -qx "${PUBLIC_CONTAINER}"; then
  echo "Public container is not running: ${PUBLIC_CONTAINER}"
  exit 1
fi

"${DOCKER_BIN}" exec -i "${PUBLIC_CONTAINER}" python3 - "${PUBLIC_ASSET_VERSION}" <<'PY'
import re
import sys
from pathlib import Path

version = sys.argv[1]
targets = [
    Path("/app/build/index.html"),
    Path("/app/backend/open_webui/frontend/index.html"),
]

loader = f'<script src="/static/loader.js?v={version}" defer crossorigin="use-credentials"></script>'
style = f'<link rel="stylesheet" href="/static/custom.css?v={version}" crossorigin="use-credentials" />'
block = f"\n\t\t{loader}\n\t\t{style}\n"

patched = []
for path in targets:
    if not path.exists():
        continue
    text = path.read_text(encoding="utf-8")
    text = re.sub(r'\s*<script[^>]+src="/static/loader\.js(?:\?v=[^"]*)?"[^>]*></script>', "", text)
    text = re.sub(r'\s*<link[^>]+href="/static/custom\.css(?:\?v=[^"]*)?"[^>]*>', "", text)
    if "</head>" not in text:
        continue
    text = text.replace("</head>", f"{block}\t</head>", 1)
    path.write_text(text, encoding="utf-8")
    patched.append(str(path))

if not patched:
    raise SystemExit("No public index.html file was patched.")

print("Injected public assets into:")
for item in patched:
    print("-", item)
PY
