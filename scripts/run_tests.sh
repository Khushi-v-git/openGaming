#!/usr/bin/env bash
# Run the GUT test suite headless. Needs GODOT_BIN (path to the Godot console binary).
# Usage: scripts/run_tests.sh [extra GUT args, e.g. -gselect=test_envelope.gd]
set -euo pipefail
if [ -z "${GODOT_BIN:-}" ]; then
  echo "GODOT_BIN is not set. Point it at your Godot console executable (see docs/running-tests.md)." >&2
  exit 2
fi
cd "$(dirname "$0")/.."
"$GODOT_BIN" --headless --import --path . >/dev/null 2>&1 || true
"$GODOT_BIN" --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json "$@"
