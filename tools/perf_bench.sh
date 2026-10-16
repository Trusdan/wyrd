#!/usr/bin/env bash
# Run the milestone bench. Smoke warns. The full run fails when a same-job
# ratio is more than 20% worse than the base checkout.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
profile="smoke"
head_dir="$root"
base_dir=""
mode="warn"
filter=""
out_path=""
summary_path="${GITHUB_STEP_SUMMARY:-}"
tag=""
samples_override=""

while [[ $# -gt 0 ]]; do
	case "$1" in
	--profile)
		profile="$2"
		shift 2
		;;
	--head)
		head_dir="$2"
		shift 2
		;;
	--base)
		base_dir="$2"
		shift 2
		;;
	--mode)
		mode="$2"
		shift 2
		;;
	--bench-filter)
		filter="$2"
		shift 2
		;;
	--out)
		out_path="$2"
		shift 2
		;;
	--summary)
		summary_path="$2"
		shift 2
		;;
	--tag)
		tag="$2"
		shift 2
		;;
	--samples)
		samples_override="$2"
		shift 2
		;;
	*)
		echo "perf: unknown argument $1" >&2
		exit 1
		;;
	esac
done

if [[ "$profile" != "smoke" && "$profile" != "full" ]]; then
	echo "perf: profile must be smoke or full" >&2
	exit 1
fi
if [[ "$mode" != "warn" && "$mode" != "gate" ]]; then
	echo "perf: mode must be warn or gate" >&2
	exit 1
fi
if [[ -z "$out_path" ]]; then
	echo "perf: --out is required" >&2
	exit 1
fi
if ! command -v godot >/dev/null 2>&1; then
	echo "perf: godot is not on PATH" >&2
	exit 1
fi
if [[ ! -f "$head_dir/bench/perf_worker.gd" ]]; then
	echo "perf: head has no harness" >&2
	exit 1
fi

work="$(mktemp -d)"
pack="$work/pack"
samples="$work/samples.jsonl"
prepare="$work/prepare.json"
pids=()

cleanup() {
	local pid
	if [[ -f "$work/head/godot.log" ]]; then
		cp "$work/head/godot.log" /tmp/wyrd-perf-head.log || true
	fi
	if [[ -f "$work/base/godot.log" ]]; then
		cp "$work/base/godot.log" /tmp/wyrd-perf-base.log || true
	fi
	for pid in "${pids[@]:-}"; do
		kill "$pid" >/dev/null 2>&1 || true
	done
	if [[ "${PERF_KEEP:-}" != "1" ]]; then
		rm -rf "$work"
	fi
}
trap cleanup EXIT

echo "perf: generating ${profile} pack"
godot --headless --path "$head_dir" -s res://bench/scale_pack_cli.gd -- --profile "$profile" --out "$pack" >"$work/generate.log"
tail -n 5 "$work/generate.log"

start_worker() {
	local name="$1"
	local path="$2"
	local box="$work/$name"
	mkdir -p "$box"
	if [[ ! -f "$path/.godot/global_script_class_cache.cfg" ]]; then
		godot --headless --path "$path" --import >"$box/import.log" 2>&1
	fi
	godot --headless --path "$path" -s res://bench/perf_worker.gd -- \
		--mailbox "$box" --pack "$pack" --profile "$profile" >"$box/godot.log" 2>&1 &
	pids+=("$!")
	local spins=0
	while [[ ! -f "$box/ready" ]]; do
		sleep 0.1
		spins=$((spins + 1))
		if (( spins > 1800 )); then
			echo "perf: ${name} worker did not start" >&2
			cat "$box/godot.log" >&2 || true
			exit 1
		fi
	done
}

send() {
	local box="$1"
	local cmd="$2"
	local limit="${3:-12000}"
	rm -f "$box/resp"
	printf '%s\n' "$cmd" >"$box/req.tmp"
	mv "$box/req.tmp" "$box/req"
	local spins=0
	while [[ ! -f "$box/resp" ]]; do
		sleep 0.05
		spins=$((spins + 1))
		if (( spins > limit )); then
			echo "perf: timed out waiting for ${cmd}" >&2
			cat "$box/godot.log" >&2 || true
			exit 1
		fi
	done
	cat "$box/resp"
	rm -f "$box/resp"
}

start_worker head "$head_dir"
send "$work/head" prepare >"$prepare"
python3 - "$prepare" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
if not doc.get("ok"):
    sys.stderr.write(doc.get("error", "prepare failed") + "\n")
    sys.exit(1)
print("perf: prepared %s quests=%s facts=%s npcs=%s deeds=%s" % (
    doc.get("profile"), doc["scale"]["quests"], doc["scale"]["facts"], doc["scale"]["npcs"], doc["scale"]["deeds"]))
PY

base_box=""
if [[ -n "$base_dir" ]]; then
	if [[ -f "$base_dir/bench/perf_worker.gd" ]]; then
		start_worker base "$base_dir"
		base_box="$work/base"
		send "$base_box" prepare >"$work/base-prepare.json"
		python3 - "$work/base-prepare.json" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
if not doc.get("ok"):
    sys.stderr.write("base prepare failed: %s\n" % doc.get("error", ""))
    sys.exit(1)
PY
	else
		echo "perf: base has no harness; recording head only"
	fi
fi

if [[ -n "$samples_override" ]]; then
	python3 - "$prepare" "$samples_override" <<'PY'
import json, sys
path, count = sys.argv[1], int(sys.argv[2])
doc = json.load(open(path, encoding="utf-8"))
doc["samples"] = count
json.dump(doc, open(path, "w", encoding="utf-8"))
PY
fi

mapfile -t metrics < <(python3 - "$prepare" "$filter" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
prefix = sys.argv[2]
for row in doc["metrics"]:
    if row["name"].startswith(prefix):
        print(row["name"])
PY
)
if [[ ${#metrics[@]} -eq 0 ]]; then
	echo "perf: no metrics match ${filter}" >&2
	exit 1
fi
warmups="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["warmups"])' "$prepare")"
samples_n="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["samples"])' "$prepare")"

record() {
	local build="$1"
	local phase="$2"
	local box="$3"
	local metric="$4"
	local line
	line="$(send "$box" "sample ${metric}")"
	python3 - "$samples" "$build" "$phase" "$line" <<'PY'
import json, sys
path, build, phase, raw = sys.argv[1:]
row = json.loads(raw)
if not row.get("ok"):
    sys.stderr.write(row.get("error", raw) + "\n")
    sys.exit(1)
row["build"] = build
row["phase"] = phase
with open(path, "a", encoding="utf-8") as handle:
    handle.write(json.dumps(row, separators=(",", ":")) + "\n")
PY
}

for metric in "${metrics[@]}"; do
	echo "perf: ${metric}"
	for ((i = 0; i < warmups; i++)); do
		if [[ -n "$base_box" ]]; then
			record base warmup "$base_box" "$metric"
		fi
		record head warmup "$work/head" "$metric"
	done
	for ((i = 0; i < samples_n; i++)); do
		if [[ -n "$base_box" ]]; then
			record base sample "$base_box" "$metric"
		fi
		record head sample "$work/head" "$metric"
	done
done

send "$work/head" quit >/dev/null || true
if [[ -n "$base_box" ]]; then
	send "$base_box" quit >/dev/null || true
fi

wyrd_version="$(tr -d '[:space:]' <"$head_dir/addons/wyrd/VERSION")"
godot_version="$(godot --version | head -n 1)"
mkdir -p "$(dirname "$out_path")"
set +e
python3 "$root/tools/perf_reduce.py" \
	--samples "$samples" \
	--prepare "$prepare" \
	--mode "$mode" \
	--out "$out_path" \
	--summary "$summary_path" \
	--tag "$tag" \
	--wyrd "$wyrd_version" \
	--godot "$godot_version" \
	--profile "$profile"
code=$?
set -e
echo "perf: wrote ${out_path}"
exit "$code"
