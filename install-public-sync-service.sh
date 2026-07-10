#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="local-knowledge-base-public-sync.service"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this installer as root: sudo ./install-public-sync-service.sh"
  exit 1
fi

cat >"${SERVICE_PATH}" <<EOF
[Unit]
Description=Local knowledge base public content sync
After=docker.service network-online.target
Wants=docker.service network-online.target

[Service]
Type=simple
WorkingDirectory=${SCRIPT_DIR}
ExecStart=${SCRIPT_DIR}/auto-sync-public.sh
Restart=always
RestartSec=15
Environment=AUTO_SYNC_INTERVAL_SECONDS=60

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}"
systemctl --no-pager --full status "${SERVICE_NAME}"
