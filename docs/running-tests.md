# Running tests

Tests use [GUT](https://github.com/bitwes/Gut) 9.7.1 (MIT), installed in `addons/gut/`.
GUT 9.7.x targets Godot 4.7.

## Setup (once per machine)

Set `GODOT_BIN` to your Godot **console** executable. Do not commit the path.

- Windows (PowerShell, persistent): `setx GODOT_BIN "D:\path\to\Godot_v4.7.x-stable_win64_console.exe"` then open a new terminal.
- Git Bash / Linux / macOS: `export GODOT_BIN=/path/to/godot` in your shell profile.

## Run

```
scripts/run_tests.ps1                       # Windows PowerShell
scripts/run_tests.sh                        # bash
scripts/run_tests.sh -gselect=test_envelope.gd   # one file
```

Both scripts first run `godot --headless --import` (so `class_name` scripts are registered),
then run GUT headless using `.gutconfig.json`. The exit code is non-zero on failure.

Direct-WebSocket tests bind to localhost on an OS-assigned port, so they need no setup
beyond allowing Godot through the firewall if Windows asks.

## Integration tier: the real relay

The shared transport, session and lobby contract suites also run, unchanged, over `RelayTransport`
against a real relay (`relay/cloudflare`, run locally with `wrangler dev`). They live outside
`tests/` in `tests_integration/` (config: `.gutconfig.integration.json`), so the normal run never
picks them up.

```
scripts/run_integration_tests.sh                              # all three suites
scripts/run_integration_tests.sh -gselect=test_session_relay.gd
```

The script starts `wrangler dev` on port 8787 (`RELAY_PORT` to change), waits for `/health`, sets
`RELAY_URL`, runs GUT, and stops the relay. It prints `SKIPPED: ...` and exits 0 if Node or
`relay/cloudflare/node_modules` is missing. Without `RELAY_URL` the suites skip themselves.
Needs Node 22+ and `npm install` once in `relay/cloudflare`.

## Relay Node tests

```
cd relay/cloudflare
npm install
npm test            # 41 tests in the Workers runtime (@cloudflare/vitest-plugin)
npm run typecheck
```

`vitest` is pinned to **4.1.11**: 5.0.x fails to start the Workers pool on Windows ("File path
must be a file: URL"). `relay/cloudflare/.npmrc` sets `legacy-peer-deps=true` because npm 10 crashes
resolving vitest's optional peers; all versions are pinned, so nothing is lost.

`relay/cloudflare/tools/hibernation_check.mjs` is a manual check against `wrangler dev`; see
`docs/relay.md`.
