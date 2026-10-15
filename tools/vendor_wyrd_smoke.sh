#!/usr/bin/env bash
# Smoke: vendor_wyrd.sh copies addons/wyrd into a temp host and VERSION matches.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

strip() {
	tr -d '[:space:]' < "$1"
}

tmp="$(mktemp -d)"
ref_dest="$(mktemp -d)"
trap 'rm -rf "$tmp" "$ref_dest"' EXIT

log="$(tools/vendor_wyrd.sh "$tmp")"
printf '%s\n' "$log"
grep -q "git describe" <<<"$log"
test -f "$tmp/addons/wyrd/VERSION"
test "$(strip addons/wyrd/VERSION)" = "$(strip "$tmp/addons/wyrd/VERSION")"
test -f "$tmp/addons/wyrd/plugin.cfg"
test -f "$tmp/addons/wyrd/runtime/wyrd.gd"
test ! -e "$tmp/addons/gut"
test ! -e "$tmp/example"
test ! -e "$tmp/tests"

(cd addons/wyrd && find . -type f -o -type l | sort) > "$tmp/src-list"
(cd "$tmp/addons/wyrd" && find . -type f -o -type l | sort) > "$tmp/dst-list"
diff -q "$tmp/src-list" "$tmp/dst-list"

echo keep > "$tmp/keep.txt"
mkdir -p "$tmp/addons/other"
echo keep > "$tmp/addons/other/keep.txt"
echo extra > "$tmp/addons/wyrd/not-from-wyrd.txt"
tools/vendor_wyrd.sh "$tmp" >/dev/null
test -f "$tmp/keep.txt"
test -f "$tmp/addons/other/keep.txt"
test ! -e "$tmp/addons/wyrd/not-from-wyrd.txt"
test "$(strip addons/wyrd/VERSION)" = "$(strip "$tmp/addons/wyrd/VERSION")"

tools/vendor_wyrd.sh "$root" "$ref_dest" HEAD >/dev/null
head_version="$(git show HEAD:addons/wyrd/VERSION | tr -d '[:space:]')"
test "$(strip "$ref_dest/addons/wyrd/VERSION")" = "$head_version"
test ! -e "$ref_dest/addons/gut"
test ! -e "$ref_dest/example"
test ! -e "$ref_dest/tests"

if tools/vendor_wyrd.sh "$root" >/dev/null; then
	echo "vendor smoke: copying onto the source should fail" >&2
	exit 1
fi
if tools/vendor_wyrd.sh --ref "not-a-real-ref" "$tmp" >/dev/null; then
	echo "vendor smoke: an unknown ref should fail" >&2
	exit 1
fi

echo "vendor smoke passed"
