#!/usr/bin/env bash
# Networked-game test on one PC: starts a host and up to three guest instances of the REAL game
# (the project's main scene) as separate windows. You press Start in the host's lobby yourself.
#
#   scripts/run_network_manual_test.sh [direct|relay] [--players=N]
#
#   direct (default)  the host listens on 127.0.0.1:24680, the guests join that address
#   relay             starts a local relay (wrangler dev, port 8787); the host gets a room code,
#                     writes it to a file, and the guests read it from there and join with it
#   --players=N       number of guests, 1 to 3 (default 3)
#
# Needs GODOT_BIN (see docs/running-tests.md); relay mode also needs Node 22+ and `npm install`
# run once in relay/cloudflare. Logs go to a temp folder that is printed. Press Enter (or Ctrl-C)
# to stop everything THIS SCRIPT started, and only that: it never kills anything by name.
set -uo pipefail
cd "$(dirname "$0")/.."

MODE="direct"
GUESTS=3
for arg in "$@"; do
  case "$arg" in
    direct|relay) MODE="$arg" ;;
    --players=*) GUESTS="${arg#--players=}" ;;
    -h|--help) sed -n 2,16p "$0"; exit 0 ;;
    *) echo "Unknown argument: $arg (see --help)" >&2; exit 2 ;;
  esac
done
case "$GUESTS" in 1|2|3) ;; *) echo "--players must be 1, 2 or 3." >&2; exit 2 ;; esac

PORT="${RELAY_PORT:-8787}"
DIRECT_PORT=24680
[ -n "${GODOT_BIN:-}" ] || { echo "GODOT_BIN is not set (see docs/running-tests.md)." >&2; exit 2; }
if [ "$MODE" = relay ]; then
  command -v node >/dev/null 2>&1 || { echo "Node is not installed." >&2; exit 2; }
  [ -f relay/cloudflare/node_modules/wrangler/bin/wrangler.js ] || { echo "Run 'npm install' in relay/cloudflare first." >&2; exit 2; }
fi

LOGDIR="$(mktemp -d -t network-manual.XXXXXX)"
PERSIST="$LOGDIR/state"
CODEFILE="$LOGDIR/code.txt"
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

if [ "$MODE" = relay ]; then
  (cd relay/cloudflare && exec node node_modules/wrangler/bin/wrangler.js dev --local --port "$PORT" --persist-to "$PERSIST" > "$LOGDIR/relay.log" 2>&1) &
  PIDS+=("$!")
  for _ in $(seq 1 60); do
    curl -fs "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && READY=1 && break
    kill -0 "${PIDS[0]}" 2>/dev/null || { cat "$LOGDIR/relay.log" >&2; echo "wrangler dev did not start." >&2; exit 1; }
    sleep 1
  done
  [ "${READY:-0}" = 1 ] || { cat "$LOGDIR/relay.log" >&2; echo "Relay not ready after 60 s." >&2; exit 1; }
  URL="ws://127.0.0.1:$PORT"
  HOST_ARGS=(--name=Host --auto=host --via=relay --relay_url="$URL" --share_file="$CODEFILE")
  GUEST_ARGS=(--auto=join --join_from_file="$CODEFILE" --relay_url="$URL" --auto_ready)
  WHERE="Relay at $URL (log: $LOGDIR/relay.log). The host's room code is written to $CODEFILE."
else
  HOST_ARGS=(--name=Host --auto=host --via=direct --port="$DIRECT_PORT")
  GUEST_ARGS=(--auto=join --join="127.0.0.1:$DIRECT_PORT" --auto_ready)
  WHERE="Direct: the host listens on 127.0.0.1:$DIRECT_PORT."
fi

"$GODOT_BIN" --path . -- "${HOST_ARGS[@]}" > "$LOGDIR/Host.log" 2>&1 &
PIDS+=("$!")
sleep 3  # give the host a head start; relay guests also wait for the code file by themselves
for i in $(seq 1 "$GUESTS"); do
  "$GODOT_BIN" --path . -- --name="Guest$i" "${GUEST_ARGS[@]}" > "$LOGDIR/Guest$i.log" 2>&1 &
  PIDS+=("$!")
done

cat <<MSG

$WHERE
Opened 1 host and $GUESTS guest window(s) (mode: $MODE). Logs: $LOGDIR
  1. The guests join and tick ready by themselves.
  2. In the Host window, check the lobby lists everyone ready, then press Start game.
  3. Play: take turns across the windows. Close a guest window to see the pause overlay on the
     host; start it again by hand with the same name (--name=Guest1 --auto=join --join=...);
     the host is asked to let it back in.
Press Enter here to stop the windows (and the relay, in relay mode).
MSG
read -r _
