#!/usr/bin/env bash
# Create and free a facade, then quit headless.
# Godot prints leftover instances and resources at process exit and still exits 0.
# This script fails when that report is present.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if ! command -v godot >/dev/null 2>&1 && [[ -x "${HOME}/.local/bin/godot" ]]; then
	export PATH="${HOME}/.local/bin:${PATH}"
fi
if ! command -v godot >/dev/null 2>&1; then
	echo "godot is not on PATH. Install the version in tools/pins.env." >&2
	exit 1
fi

godot --headless --path . --import

log="$(mktemp)"
trap 'rm -f "$log"' EXIT
set +e
godot --headless --path . -s res://tests/leak/facade_leak.gd >"$log" 2>&1
code=$?
set -e
cat "$log"
if [[ "$code" -ne 0 ]]; then
	echo "Leak check exited ${code}." >&2
	exit "$code"
fi
if grep -E -q 'SCRIPT ERROR|Parse Error' "$log"; then
	echo "Leak check hit a script error." >&2
	exit 1
fi
if grep -E -q 'ObjectDB (instance was|instances were) leaked at exit|resources still in use at exit' "$log"; then
	echo "Leak check failed: instances or resources were still alive at exit." >&2
	exit 1
fi
