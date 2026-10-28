#!/usr/bin/env bash
# Reliability run: launch Matchsight on the iPhone with its console attached,
# save the console to a log, and print the report when you stop it (Ctrl-C).
#
#   DEVICE_ID=<udid> scripts/reliability-run.sh [logfile]
#
# Install the build first. `script` gives devicectl a TTY; without one the
# app's prints are buffered and never reach the log.
set -euo pipefail

: "${DEVICE_ID:?set DEVICE_ID to the iPhone UDID (xcrun devicectl list devices)}"
LOG="${1:-reliability-$(date +%Y%m%d-%H%M).log}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "Logging to $LOG. Stop with Ctrl-C after the run."
script -q "$LOG" xcrun devicectl device process launch --console --terminate-existing \
  --device "$DEVICE_ID" com.alienfader.CopaHUD || true

echo
swift run -q --package-path "$ROOT/CopaHUDCore" reliability-report "$LOG"
