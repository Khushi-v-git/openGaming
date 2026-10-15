#!/usr/bin/env bash
# Integration tier: the shared transport, session and lobby contract suites over RelayTransport
# against a REAL relay (relay/cloudflare, run locally with `wrangler dev`). Skips cleanly (exit 0,
# says why) when Node or the relay's dependencies are missing.
#
# Usage: scripts/run_integration_tests.sh [extra GUT args, e.g. -gselect=test_session_relay.gd]
# Needs GODOT_BIN, Node 22+, and `npm install` run once in relay/cloudflare.
set -uo pipefail
cd "$(dirname "$0")/.."
PORT="${RELAY_PORT:-8787}"

skip() { echo "SKIPPED: integration tests: $1"; exit 0; }
[ -n "${GODOT_BIN:-}" ] || { echo "GODOT_BIN is not set (see docs/running-tests.md)." >&2; exit 2; }
command -v node >/dev/null 2>&1 || skip "Node is not installed"
[ -f relay/cloudflare/node_modules/wrangler/bin/wrangler.js ] || skip "run 'npm install' in relay/cloudflare first"

LOG="$(mktemp -t relay-dev.XXXXXX)"
PERSIST="$(mktemp -d -t relay-state.XXXXXX)"
(cd relay/cloudflare && exec node node_modules/wrangler/bin/wrangler.js dev --local --port "$PORT" --persist-to "$PERSIST" > "$LOG" 2>&1) &
RELAY_PID=$!
cleanup() {
  kill "$RELAY_PID" 2>/dev/null
  case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) taskkill //F //T //PID "$RELAY_PID" >/dev/null 2>&1 ;; esac
  rm -rf "$PERSIST"
}
trap cleanup EXIT

for _ in $(seq 1 60); do
  if curl -fs "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then READY=1; break; fi
  kill -0 "$RELAY_PID" 2>/dev/null || { cat "$LOG" >&2; skip "wrangler dev did not start (see its output above)"; }
  sleep 1
done
[ "${READY:-0}" = 1 ] || { cat "$LOG" >&2; skip "wrangler dev did not become ready in 60 s"; }

export RELAY_URL="ws://127.0.0.1:$PORT"
"$GODOT_BIN" --headless --import --path . >/dev/null 2>&1 || true
"$GODOT_BIN" --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.integration.json "$@"
STATUS=$?
echo "relay log: $LOG"
exit $STATUS
