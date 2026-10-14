#!/usr/bin/env bash
# Grep a pull-request diff for terms listed in WYRD_HYGIENE_DENYLIST.
# The list is newline-separated. This script never prints the list or a matching line.
# Vendored GUT is excluded: it is third-party code, not Wyrd content.
set -euo pipefail

if [[ -z "${WYRD_HYGIENE_DENYLIST:-}" ]]; then
	echo "::warning::WYRD_HYGIENE_DENYLIST is unset; skipping the content-hygiene check."
	exit 0
fi

base="${1:-origin/main}"
if ! git rev-parse --verify "${base}^{commit}" >/dev/null 2>&1; then
	echo "::error::Content hygiene could not find the base revision."
	exit 1
fi

umask 077
deny="$(mktemp)"
diff_file="$(mktemp)"
trap 'rm -f "$deny" "$diff_file"' EXIT

# Trim whitespace and drop empty lines. Do not echo the terms.
while IFS= read -r line || [[ -n "$line" ]]; do
	trimmed="${line#"${line%%[![:space:]]*}"}"
	trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
	if [[ -n "$trimmed" ]]; then
		printf '%s\n' "$trimmed" >> "$deny"
	fi
done <<< "$WYRD_HYGIENE_DENYLIST"

if [[ ! -s "$deny" ]]; then
	echo "::warning::WYRD_HYGIENE_DENYLIST is empty; skipping the content-hygiene check."
	exit 0
fi

git diff --no-color --unified=3 "${base}...HEAD" -- . ':(exclude)addons/gut' > "$diff_file"

if grep -F -i -q -f "$deny" "$diff_file"; then
	echo "::error::Content hygiene failed: the diff matches a term on the deny-list."
	exit 1
fi

echo "Content hygiene passed."
