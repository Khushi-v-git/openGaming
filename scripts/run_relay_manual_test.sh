#!/usr/bin/env bash
# Local relay test on one PC: starts the relay (wrangler dev) and four lobby_demo instances
# (one host, three guests). The host presses Host and reads the room code; each guest types it
# in the join box. Press Enter (or Ctrl-C) to stop everything THIS SCRIPT started, and only that.
#
# Needs GODOT_BIN, Node 22+, and `npm install` run once in relay/cloudflare. Logs: $LOGDIR.
set -uo pipefail
cd "$(dirname "$0")/.."
PORT="${RELAY_PORT:-8787}"
[ -n "${GODOT_BIN:-}" ] || { echo "GODOT_BIN is not set (see docs/running-tests.md)." >&2; exit 2; }
command -v node >/dev/null 2>&1 || { echo "Node is not installed." >&2; exit 2; }
[ -f relay/cloudflare/node_modules/wrangler/bin/wrangler.js ] || { echo "Run 'npm install' in relay/cloudflare first." >&2; exit 2; }

LOGDIR="$(mktemp -d -t relay-manual.XXXXXX)"
PERSIST="$LOGDIR/state"
PIDS=()

stop_all() {
  trap - EXIT INT TERM
  echo "Stopping what this script started..."
  for pid in "${PIDS[@]}"; do
    kill "$pid" 2>/dev/null
    case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) taskkill //F //T //PID "$pid" >/dev/null 2>&1 ;; esac
  done
  rm -rf "$PERSIST"
  echo "Logs are in $LOGDIR"
  exit 0
}
trap stop_all EXIT INT TERM

(cd relay/cloudflare && exec node node_modules/wrangler/bin/wrangler.js dev --local --port "$PORT" --persist-to "$PERSIST" > "$LOGDIR/relay.log" 2>&1) &
PIDS+=("$!")
for _ in $(seq 1 60); do
  curl -fs "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && READY=1 && break
  kill -0 "${PIDS[0]}" 2>/dev/null || { cat "$LOGDIR/relay.log" >&2; echo "wrangler dev did not start." >&2; exit 1; }
  sleep 1
done
[ "${READY:-0}" = 1 ] || { cat "$LOGDIR/relay.log" >&2; echo "Relay not ready after 60 s." >&2; exit 1; }

URL="ws://127.0.0.1:$PORT"
for name in Host Guest1 Guest2 Guest3; do
  "$GODOT_BIN" --path . res://tests/manual/lobby_demo.tscn -- --name="$name" --relay_url="$URL" > "$LOGDIR/$name.log" 2>&1 &
  PIDS+=("$!")
done

cat <<MSG

Relay running at $URL (log: $LOGDIR/relay.log). Four windows opened.
  1. In the "Host" window press Host and read the room code it shows.
  2. In each Guest window type that code in the join box and press Join.
  3. Check all four lobbies list four players; try ready, Start, Remove, Leave.
Press Enter here to stop the relay and the four windows.
MSG
read -r _
