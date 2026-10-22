#!/usr/bin/env bash
# Run the milestone bench. The default mode warns. `--mode gate` fails the
# full run when a same-job ratio is more than 20% worse than the base checkout.
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

# A fresh checkout has no global class cache. Import before any -s script so
# class_name types such as WyrdScalePack resolve.
import_project() {
	local path="$1"
	local log="$2"
	if [[ -f "$path/.godot/global_script_class_cache.cfg" ]]; then
		return 0
	fi
	echo "perf: importing ${path}"
	if ! godot --headless --path "$path" --import >"$log" 2>&1; then
		cat "$log" >&2 || true
		exit 1
	fi
}

echo "perf: generating ${profile} pack"
import_project "$head_dir" "$work/import-head.log"
if ! godot --headless --path "$head_dir" -s res://bench/scale_pack_cli.gd -- --profile "$profile" --out "$pack" >"$work/generate.log" 2>&1; then
	cat "$work/generate.log" >&2 || true
	exit 1
fi
tail -n 5 "$work/generate.log"

start_worker() {
	local name="$1"
	local path="$2"
	local box="$work/$name"
	mkdir -p "$box"
	import_project "$path" "$box/import.log"
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
scale = doc["scale"]
print("perf: prepared %s quests=%s facts=%s npcs=%s deeds=%s storylets=%s topics=%s speakers=%s" % (
    doc.get("profile"), scale["quests"], scale["facts"], scale["npcs"], scale["deeds"],
    scale.get("storylets", 0), scale.get("topics", 0), scale.get("speakers", 0)))
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
doc["samples_override"] = True
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

base_skipped=" "
record() {
	local build="$1"
	local phase="$2"
	local box="$3"
	local metric="$4"
	local line
	local code=0
	line="$(send "$box" "sample ${metric}")"
	set +e
	python3 - "$samples" "$build" "$phase" "$line" <<'PY'
import json, sys
path, build, phase, raw = sys.argv[1:]
row = json.loads(raw)
if not row.get("ok"):
    err = str(row.get("error", raw))
    if build == "base" and err.startswith("unknown metric"):
        sys.exit(2)
    sys.stderr.write(err + "\n")
    sys.exit(1)
row["build"] = build
row["phase"] = phase
with open(path, "a", encoding="utf-8") as handle:
    handle.write(json.dumps(row, separators=(",", ":")) + "\n")
PY
	code=$?
	set -e
	if [[ "$code" -eq 2 ]]; then
		if [[ "${base_skipped}" != *" ${metric} "* ]]; then
			echo "perf: base has no ${metric}; recording head only"
			base_skipped="${base_skipped} ${metric} "
		fi
		return 0
	fi
	if [[ "$code" -ne 0 ]]; then
		exit "$code"
	fi
}

for metric in "${metrics[@]}"; do
	read -r metric_warmups metric_samples < <(python3 - "$prepare" "$metric" "$profile" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
name, profile = sys.argv[2], sys.argv[3]
global_w = int(doc["warmups"])
global_s = int(doc["samples"])
row = None
for item in doc["metrics"]:
    if item["name"] == name:
        row = item
        break
if doc.get("samples_override"):
    samples = global_s
elif row is not None and "samples" in row:
    samples = int(row["samples"])
    if profile == "smoke":
        samples = min(samples, global_s)
else:
    samples = global_s
if row is not None and "warmups" in row:
    warmups = int(row["warmups"])
    if profile == "smoke":
        warmups = min(warmups, global_w)
else:
    warmups = global_w
print("%d %d" % (warmups, samples))
PY
)
	echo "perf: ${metric} warmups=${metric_warmups} samples=${metric_samples}"
	for ((i = 0; i < metric_warmups; i++)); do
		if [[ -n "$base_box" ]]; then
			record base warmup "$base_box" "$metric"
		fi
		record head warmup "$work/head" "$metric"
	done
	for ((i = 0; i < metric_samples; i++)); do
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
