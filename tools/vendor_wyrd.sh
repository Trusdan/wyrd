#!/usr/bin/env bash
# Copy addons/wyrd into a host project.
#
# Usage:
#   tools/vendor_wyrd.sh [--ref REF] [SOURCE] DEST
#   tools/vendor_wyrd.sh SOURCE DEST REF
#
# SOURCE defaults to ".". DEST is the host project directory (the parent of
# addons/). REF is an optional git tag, branch, or commit. With no REF the
# script copies the working tree and prints git describe of HEAD. With a REF
# it copies that commit.
#
# The copy is addons/wyrd only. A second run replaces that directory and
# removes files the source no longer has. Other host files stay.
set -euo pipefail

usage() {
	cat <<'EOF'
usage: tools/vendor_wyrd.sh [--ref REF] [SOURCE] DEST
       tools/vendor_wyrd.sh SOURCE DEST REF

SOURCE  Wyrd git checkout. Default: .
DEST    Host project directory. Receives DEST/addons/wyrd.
REF     Git tag, branch, or commit. Default: working tree, describe HEAD.
EOF
}

ref=""
positional=()
while [[ $# -gt 0 ]]; do
	case "$1" in
		--ref)
			if [[ $# -lt 2 || -z "${2:-}" ]]; then
				echo "wyrd vendor: --ref needs a value" >&2
				usage >&2
				exit 2
			fi
			ref="$2"
			shift 2
			;;
		-h|--help)
			usage
			exit 0
			;;
		--)
			shift
			positional+=("$@")
			break
			;;
		-*)
			echo "wyrd vendor: unknown option ${1}" >&2
			usage >&2
			exit 2
			;;
		*)
			positional+=("$1")
			shift
			;;
	esac
done

source_arg="."
dest_arg=""
case "${#positional[@]}" in
	1)
		dest_arg="${positional[0]}"
		;;
	2)
		source_arg="${positional[0]}"
		dest_arg="${positional[1]}"
		;;
	3)
		if [[ -n "$ref" ]]; then
			echo "wyrd vendor: pass the ref once" >&2
			usage >&2
			exit 2
		fi
		source_arg="${positional[0]}"
		dest_arg="${positional[1]}"
		ref="${positional[2]}"
		;;
	*)
		usage >&2
		exit 2
		;;
esac

if [[ -z "$dest_arg" ]]; then
	usage >&2
	exit 2
fi

if ! command -v rsync >/dev/null 2>&1; then
	echo "wyrd vendor: rsync is required" >&2
	exit 1
fi

if [[ ! -d "$source_arg" ]]; then
	echo "wyrd vendor: source is not a directory: ${source_arg}" >&2
	exit 1
fi
source_root="$(cd "$source_arg" && pwd)"

if ! git -C "$source_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	echo "wyrd vendor: source is not a git checkout: ${source_root}" >&2
	exit 1
fi

git_root="$(git -C "$source_root" rev-parse --show-toplevel)"
if [[ "$source_root" != "$git_root" ]]; then
	echo "wyrd vendor: source must be the checkout root: ${git_root}" >&2
	exit 1
fi

if [[ ! -d "$source_root/addons/wyrd" ]]; then
	echo "wyrd vendor: missing addons/wyrd in ${source_root}" >&2
	exit 1
fi

mkdir -p "$dest_arg"
dest_root="$(cd "$dest_arg" && pwd)"
src_addon="${source_root}/addons/wyrd"

case "$dest_root" in
	"$source_root"|"${source_root}/addons"|"$src_addon"|"${src_addon}"/*)
		echo "wyrd vendor: refusing to copy onto the source addon" >&2
		exit 1
		;;
esac
case "$source_root" in
	"$dest_root"|"${dest_root}"/*)
		echo "wyrd vendor: source is inside dest" >&2
		exit 1
		;;
esac

commit=""
if [[ -n "$ref" ]]; then
	if ! commit="$(git -C "$source_root" rev-parse --verify "${ref}^{commit}" 2>/dev/null)"; then
		echo "wyrd vendor: unknown ref: ${ref}" >&2
		exit 1
	fi
	if ! git -C "$source_root" cat-file -e "${commit}:addons/wyrd/VERSION" 2>/dev/null; then
		echo "wyrd vendor: addons/wyrd/VERSION is missing at ${ref}" >&2
		exit 1
	fi
else
	commit="$(git -C "$source_root" rev-parse HEAD)"
fi

describe="$(git -C "$source_root" describe --tags --always "$commit")"
exact_tag=""
if exact_tag="$(git -C "$source_root" describe --tags --exact-match "$commit" 2>/dev/null)"; then
	:
else
	exact_tag=""
fi

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

if [[ -n "$ref" ]]; then
	if ! git -C "$source_root" archive --format=tar "$commit" addons/wyrd | tar -x -C "$stage"; then
		echo "wyrd vendor: could not read addons/wyrd at ${ref}" >&2
		exit 1
	fi
else
	mkdir -p "${stage}/addons"
	rsync -a "${src_addon}/" "${stage}/addons/wyrd/"
fi

if [[ ! -f "${stage}/addons/wyrd/VERSION" ]]; then
	echo "wyrd vendor: addons/wyrd/VERSION is missing in the source tree" >&2
	exit 1
fi

version="$(tr -d '\r' < "${stage}/addons/wyrd/VERSION")"
version="${version#"${version%%[![:space:]]*}"}"
version="${version%"${version##*[![:space:]]}"}"
if [[ -z "$version" || "$version" == *$'\n'* ]]; then
	echo "wyrd vendor: VERSION must be one non-empty line" >&2
	exit 1
fi

mkdir -p "${dest_root}/addons"
rsync -a --delete "${stage}/addons/wyrd/" "${dest_root}/addons/wyrd/"
printf '%s\n' "$version" > "${dest_root}/addons/wyrd/VERSION"

written="$(tr -d '[:space:]' < "${dest_root}/addons/wyrd/VERSION")"
if [[ "$written" != "$version" ]]; then
	echo "wyrd vendor: VERSION verify failed" >&2
	exit 1
fi

echo "wyrd vendor: VERSION ${version}"
if [[ -n "$exact_tag" ]]; then
	echo "wyrd vendor: tag ${exact_tag}"
fi
echo "wyrd vendor: git describe ${describe}"
if [[ -z "$ref" && -n "$(git -C "$source_root" status --porcelain -- addons/wyrd)" ]]; then
	echo "wyrd vendor: working tree (addons/wyrd differs from ${describe})"
fi
echo "wyrd vendor: copied addons/wyrd to ${dest_root}/addons/wyrd"
