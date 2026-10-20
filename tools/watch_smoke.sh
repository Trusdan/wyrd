#!/usr/bin/env bash
# Run check --watch as a real Godot process. Writes only under mktemp.
# set -m so this background job is not started with SIGINT ignored.
set -euo pipefail
set -m

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if ! command -v godot >/dev/null 2>&1; then
	echo "godot is not on PATH." >&2
	exit 1
fi

# facts.wyrd is the copied Gullhaven file. A comment-only extra file is one E_HEADER_MISSING.
src="example/content/gullhaven/facts.wyrd"
dir="$(mktemp -d)"
log="$(mktemp)"
pid=""

cleanup() {
	if [[ -n "${pid}" ]] && kill -0 "$pid" 2>/dev/null; then
		kill -TERM "$pid" 2>/dev/null || true
		wait "$pid" 2>/dev/null || true
	fi
	rm -rf "$dir"
	rm -f "$log"
}
trap cleanup EXIT

cp "$src" "$dir/facts.wyrd"

godot --headless --path . -s res://addons/wyrd/cli/wyrd_cli.gd -- check --watch "$dir" >"$log" 2>&1 &
pid=$!

from=1
wait_for() {
	local pattern="$1"
	local deadline=$((SECONDS + 60))
	while (( SECONDS < deadline )); do
		if ! kill -0 "$pid" 2>/dev/null; then
			local st=""
			st="$(ps -o stat= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
			if [[ "$st" != Z* ]]; then
				echo "watch process exited while waiting for: ${pattern}" >&2
				cat "$log" >&2
				exit 1
			fi
		fi
		if tail -c +"$from" "$log" | grep -q -- "$pattern"; then
			return 0
		fi
		sleep 0.2
	done
	echo "timed out after 60s waiting for: ${pattern}" >&2
	cat "$log" >&2
	exit 1
}

mark() {
	from=$(( $(wc -c < "$log") + 1 ))
}

wait_for "wyrd: check finished errors=0"
mark

printf '// broken\n' > "$dir/broken.wyrd"
wait_for "E_HEADER_MISSING"
wait_for "wyrd: check finished errors=1"
mark

rm -f "$dir/broken.wyrd"
wait_for "wyrd: check finished errors=0"

# SIGINT, then SIGTERM if it is still alive after 5s.
kill -INT "$pid" 2>/dev/null || true
deadline=$((SECONDS + 5))
while (( SECONDS < deadline )); do
	st="$(ps -o stat= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
	if [[ -z "$st" || "$st" == Z* ]]; then
		break
	fi
	sleep 0.1
done
st="$(ps -o stat= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
if [[ -n "$st" && "$st" != Z* ]]; then
	kill -TERM "$pid" 2>/dev/null || true
	deadline=$((SECONDS + 5))
	while (( SECONDS < deadline )); do
		st="$(ps -o stat= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
		if [[ -z "$st" || "$st" == Z* ]]; then
			break
		fi
		sleep 0.1
	done
fi
st="$(ps -o stat= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
if [[ -n "$st" && "$st" != Z* ]]; then
	echo "watch process still alive after SIGINT and SIGTERM" >&2
	cat "$log" >&2
	kill -KILL "$pid" 2>/dev/null || true
	exit 1
fi
wait "$pid" 2>/dev/null || true
pid=""
cat "$log"
