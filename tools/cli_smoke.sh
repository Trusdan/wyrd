#!/usr/bin/env bash
# Run the CLI entry once per command. Writes only under mktemp.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if ! command -v godot >/dev/null 2>&1; then
	echo "godot is not on PATH." >&2
	exit 1
fi

work="$(mktemp -d)"
cleanup() {
	rm -rf "$work"
}
trap cleanup EXIT

manifest="example/content/gullhaven/harbor.wyrdmanifest.tres"

run_case() {
	local label="$1"
	local expect="$2"
	shift 2
	local out="$work/case.out"
	local code=0
	set +e
	godot --headless --path . -s res://addons/wyrd/cli/wyrd_cli.gd -- "$@" </dev/null >"$out" 2>&1
	code=$?
	set -e
	local body
	body="$(cat "$out")"
	if grep -F -q "SCRIPT ERROR" <<<"$body" || grep -F -q "Parse Error" <<<"$body"; then
		echo "cli smoke failed: ${label}" >&2
		printf '%s\n' "$body" >&2
		exit 1
	fi
	if [[ "$code" -ne "$expect" ]]; then
		echo "cli smoke failed: ${label} (exit ${code}, expected ${expect})" >&2
		printf '%s\n' "$body" >&2
		exit 1
	fi
}

run_case "no arguments" 0
run_case "nosuch" 1 nosuch
run_case "check --watch" 1 check --watch
run_case "check" 0 check --manifest "$manifest"
run_case "test" 0 test --manifest "$manifest"
run_case "tag-lines" 0 tag-lines --dry-run --manifest "$manifest"
run_case "export-json" 0 export-json --manifest "$manifest" -o "$work/export.json"
run_case "pot" 0 pot --manifest "$manifest" --out "$work/out.pot"
run_case "defs" 0 defs --manifest "$manifest" --out "$work/tags"
run_case "facts" 0 facts --manifest "$manifest"
run_case "roles" 0 roles --manifest "$manifest"
run_case "why-not" 1 why-not --manifest "$manifest"
run_case "voice-check" 1 voice-check --manifest "$manifest"
run_case "script-export" 1 script-export --manifest "$manifest"
run_case "unvoiced-report" 0 unvoiced-report --manifest "$manifest"
run_case "storylets" 0 storylets --manifest "$manifest"
run_case "cooldowns" 0 cooldowns --manifest "$manifest"
run_case "choices" 0 choices --manifest "$manifest"
run_case "coverage" 0 coverage --manifest "$manifest"
run_case "console" 1 console --manifest "$manifest"

dirty="$(git status --porcelain)"
if [[ -n "$dirty" ]]; then
	echo "cli smoke failed: git status is not empty" >&2
	printf '%s\n' "$dirty" >&2
	exit 1
fi

echo "cli smoke passed"
