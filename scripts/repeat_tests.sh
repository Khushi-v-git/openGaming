#!/usr/bin/env bash
# Runs the whole suite N times in a row (default 5) and reports each run, to catch flaky
# tests. Needs GODOT_BIN. Usage: scripts/repeat_tests.sh [N] [extra GUT args]
# Exit code is non-zero if any run failed. Failing test names are printed per run.
set -uo pipefail
if [ -z "${GODOT_BIN:-}" ]; then
  echo "GODOT_BIN is not set (see docs/running-tests.md)." >&2
  exit 2
fi
runs="${1:-5}"
shift || true
cd "$(dirname "$0")/.."
"$GODOT_BIN" --headless --import --path . >/dev/null 2>&1 || true
failed_runs=0
for i in $(seq 1 "$runs"); do
  out="$(mktemp)"
  "$GODOT_BIN" --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json "$@" >"$out" 2>&1
  code=$?
  tests="$(grep -E '^Tests ' "$out" | awk '{print $2}')"
  passing="$(grep -E '^Passing Tests' "$out" | awk '{print $3}')"
  secs="$(grep -E '^Time ' "$out" | awk '{print $2}')"
  if [ "$code" -eq 0 ] && grep -q "All tests passed" "$out"; then
    echo "run $i/$runs: PASS  tests=$tests passing=$passing time=$secs"
  else
    failed_runs=$((failed_runs + 1))
    echo "run $i/$runs: FAIL  tests=${tests:-?} passing=${passing:-?} exit=$code time=${secs:-?}"
    grep -E '^- test_|^res://.*\.gd$' "$out" | grep -B1 -E '^- test_' | sed 's/^/    /' | head -40
    cp "$out" "${TMPDIR:-/tmp}/gut_failed_run_$i.log" 2>/dev/null && echo "    full log: ${TMPDIR:-/tmp}/gut_failed_run_$i.log"
  fi
  rm -f "$out"
done
echo "$((runs - failed_runs))/$runs runs passed"
[ "$failed_runs" -eq 0 ]
