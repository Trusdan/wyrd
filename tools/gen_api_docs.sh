#!/usr/bin/env bash
# Import the project, run Godot's doctool on addons/wyrd, and write docs/api.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if ! command -v godot >/dev/null 2>&1; then
	echo "godot is not on PATH. Install the version in tools/pins.env." >&2
	exit 1
fi

tmp="$(mktemp -d)"
log="$(mktemp)"
cleanup() {
	rm -rf "$tmp"
	rm -f "$log"
}
trap cleanup EXIT

godot --headless --path . --import

set +e
godot --headless --path . --doctool "$tmp" --gdscript-docs res://addons/wyrd >"$log" 2>&1
code=$?
set -e
cat "$log"
if [[ "$code" -ne 0 ]]; then
	echo "doctool exited ${code}." >&2
	exit "$code"
fi
if grep -E -q 'SCRIPT ERROR|Parse Error' "$log"; then
	echo "doctool log has a script error." >&2
	exit 1
fi

xml_count="$(find "$tmp" -name '*.xml' | wc -l | tr -d ' ')"
echo "doctool wrote ${xml_count} XML files."

missing=0
while IFS= read -r file; do
	names="$(grep -E '^class_name[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$file" || true)"
	if [[ -z "$names" ]]; then
		continue
	fi
	while IFS= read -r line; do
		declared="${line#class_name}"
		declared="${declared#"${declared%%[![:space:]]*}"}"
		declared="${declared%%[[:space:]]*}"
		if [[ ! -f "$tmp/${declared}.xml" ]]; then
			echo "doctool wrote no XML for class_name ${declared} (${file})." >&2
			missing=1
		fi
	done <<< "$names"
done < <(find addons/wyrd -type f -name '*.gd' ! -path 'addons/wyrd/cli/*')
if [[ "$missing" -ne 0 ]]; then
	exit 1
fi

godot --headless --path . -s res://tools/api_docs.gd -- --in "$tmp" --out res://docs/api
