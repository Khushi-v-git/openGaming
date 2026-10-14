# Run the GUT test suite headless. Needs GODOT_BIN (path to the Godot console binary).
# Usage: scripts/run_tests.ps1 [extra GUT args, e.g. -gselect=test_envelope.gd]
if (-not $env:GODOT_BIN) {
    Write-Error "GODOT_BIN is not set. Point it at your Godot console executable (see docs/running-tests.md)."
    exit 2
}
Set-Location (Join-Path $PSScriptRoot "..")
& $env:GODOT_BIN --headless --import --path . *> $null
& $env:GODOT_BIN --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json @args
exit $LASTEXITCODE
