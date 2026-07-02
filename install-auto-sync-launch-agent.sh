#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${SCRIPT_DIR}/.auto-sync"
LABEL="com.local-knowledge-base.auto-sync"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
RUNNER="/private/tmp/local-knowledge-base-auto-sync-runner.sh"
STANDALONE="/private/tmp/local-knowledge-base-auto-sync-once.sh"
UID_VALUE="$(id -u)"

mkdir -p "${STATE_DIR}" "${HOME}/Library/LaunchAgents"

cp "${SCRIPT_DIR}/standalone-auto-sync-once.sh" "${STANDALONE}"
chmod +x "${STANDALONE}"

cat > "${RUNNER}" <<EOF
#!/bin/zsh
exec "${STANDALONE}"
EOF
chmod +x "${RUNNER}"

cat > "${PLIST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${RUNNER}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StartInterval</key>
  <integer>60</integer>
  <key>StandardOutPath</key>
  <string>/private/tmp/local-knowledge-base-auto-sync.launchd.log</string>
  <key>StandardErrorPath</key>
  <string>/private/tmp/local-knowledge-base-auto-sync.launchd.log</string>
</dict>
</plist>
EOF

launchctl bootout "gui/${UID_VALUE}" "${PLIST}" >/dev/null 2>&1 || true
launchctl bootstrap "gui/${UID_VALUE}" "${PLIST}"
launchctl enable "gui/${UID_VALUE}/${LABEL}"
launchctl kickstart -k "gui/${UID_VALUE}/${LABEL}" >/dev/null 2>&1 || true

echo "LaunchAgent installed."
echo "Label: ${LABEL}"
echo "Plist: ${PLIST}"
echo "Runner: ${RUNNER}"
echo "Standalone: ${STANDALONE}"
echo "Log: /private/tmp/local-knowledge-base-auto-sync.launchd.log"
