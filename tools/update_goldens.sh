#!/usr/bin/env bash
# Regenerates tests/golden/expected/*.json and tests/golden/conditions/expected/*.json.
# Never called from CI. Review the diff before committing it.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if ! command -v godot >/dev/null 2>&1; then
	echo "godot is not on PATH. Install the version in tools/pins.env." >&2
	exit 1
fi

godot --headless --path . --import
godot --headless --path . -s res://tests/golden/update_goldens.gd
