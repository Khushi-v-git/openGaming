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
