#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

"${SCRIPT_DIR}/analytics-dashboard.sh"
open "http://localhost:3000/static/analytics/question-analytics-dashboard.html"
