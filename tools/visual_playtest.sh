#!/usr/bin/env bash
# Run the example playtest in a real window under xvfb and check the screenshots.
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
if ! command -v xvfb-run >/dev/null 2>&1; then
	echo "xvfb-run is not on PATH. Install xvfb." >&2
	exit 1
fi

out="${1:-${root}/visual-playtest-out}"
case "$out" in
	/*) ;;
	*) out="${root}/${out}" ;;
esac
if [[ "$out" == "$root" ]]; then
	echo "refusing to write screenshots into the project root" >&2
	exit 1
fi

size="$(python3 - "$root/tools/visual_playtest_expectations.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
width = int(data["width"])
height = int(data["height"])
if width < 100 or height < 100:
    sys.exit("window size in the expectations file is too small")
print(f"{width}x{height}")
PY
)"

rm -rf "$out"
mkdir -p "$out"

godot --headless --path . --import

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe
set +e
timeout --signal=TERM 240 xvfb-run -a -s "-screen 0 ${size}x24" \
	godot --path . \
		--display-driver x11 \
		--rendering-driver opengl3 \
		--rendering-method gl_compatibility \
		--audio-driver Dummy \
		--resolution "$size" \
		--single-window \
		res://tools/visual_playtest.tscn -- --out "$out" \
	>"$log" 2>&1
code=$?
set -e
cat "$log"
cp "$log" "$out/godot.log"

python3 - "$log" "$out" "$code" <<'PY'
import json, sys
from pathlib import Path

log_path, out_s, code_s = sys.argv[1:]
code = int(code_s)
out = Path(out_s)
# Engine shutdown noise. Any other ERROR or WARNING fails the run.
allow = (
    "ObjectDB instances were leaked",
    "resources still in use at exit",
    # llvmpipe under xvfb cannot change V-Sync. Godot prints this on startup.
    "Could not set V-Sync mode, as changing V-Sync mode is not supported by the graphics driver.",
    # The example quest's cast slot prints this on every new game. Role tests require it.
    "binds once to the current holder; casting is M4",
)
bad = []
text = Path(log_path).read_text(errors="replace")
for line in text.splitlines():
    if any(part in line for part in allow):
        continue
    if "SCRIPT ERROR" in line or "Parse Error" in line or "ERROR:" in line or "WARNING:" in line:
        bad.append(line)
problems = []
if code != 0:
    problems.append(f"godot exited {code}")
if bad:
    problems.append("log has script errors or warnings:\n" + "\n".join(bad))
report_path = out / "report.json"
if not report_path.is_file():
    problems.append("missing report.json")
else:
    data = json.loads(report_path.read_text(encoding="utf-8"))
    if not data.get("ok"):
        problems.append("report ok is false")
if not (out / "index.html").is_file():
    problems.append("missing index.html")
if not (out / "index.md").is_file():
    problems.append("missing index.md")
elif "state.md" not in (out / "index.md").read_text(encoding="utf-8"):
    problems.append("index.md does not link state.md")
state_md = out / "state.md"
if not state_md.is_file():
    problems.append("missing state.md")
state_path = out / "state.jsonl"
if not state_path.is_file():
    problems.append("missing state.jsonl")
elif report_path.is_file() and json.loads(report_path.read_text(encoding="utf-8")).get("ok"):
    lines = [line for line in state_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if not lines:
        problems.append("state.jsonl is empty")
    else:
        sample = json.loads(lines[-1])
        for key in ("scenario", "step", "facts", "quest", "outcomes", "slots", "journal"):
            if key not in sample:
                problems.append("state.jsonl missing %s" % key)
if not list(out.glob("*.png")):
    problems.append("no screenshots")
if "visual-playtest: ok" not in text:
    problems.append("driver did not report success")
if problems:
    print("visual-playtest failed:", file=sys.stderr)
    for item in problems:
        print(item, file=sys.stderr)
    sys.exit(1)
print("visual-playtest passed")
PY
