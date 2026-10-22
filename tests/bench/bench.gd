extends SceneTree

const _Runtime := preload("res://addons/wyrd/runtime/wyrd_runtime.gd")
const _Hash := preload("res://addons/wyrd/runtime/rng/wyrd_hash.gd")
const _Rng := preload("res://addons/wyrd/runtime/rng/wyrd_rng.gd")
const _Conditions := preload("res://tests/bench/wyrd_condition_bench.gd")
const _Ai := preload("res://tests/bench/wyrd_ai_bench.gd")

## Times a placeholder hash-and-rng workload and a fixed 10k-fact / 5k-condition case.
## Not a CI gate. Condition numbers are recorded only.

func _init() -> void:
	var iterations := 10000
	var out_path := "res://tests/bench/out/latest.json"
	var args := OS.get_cmdline_user_args()
	var index := 0
	while index < args.size():
		if args[index] == "--iterations" and index + 1 < args.size():
			iterations = int(args[index + 1])
			index += 2
		elif args[index] == "--out" and index + 1 < args.size():
			out_path = args[index + 1]
			index += 2
		else:
			index += 1
	if iterations < 1:
		push_error("bench iterations must be >= 1")
		quit(1)
		return

	var names: Array[StringName] = [
		&"gullhaven",
		&"ferry_master",
		&"harbormaster",
		&"tavern_owner",
		&"constable",
	]
	var rng: RefCounted = _Rng.new(0x57595244)
	var started := Time.get_ticks_usec()
	var checksum := 0
	for n in iterations:
		var key: StringName = names[n % names.size()]
		checksum = _Hash.of_string_name(key) ^ _Hash.of_int(rng.randi())
	var elapsed := Time.get_ticks_usec() - started
	var version_info := Engine.get_version_info()
	var conditions: Dictionary = _Conditions.new().measure()
	if not bool(conditions["checksum_match"]):
		push_error("condition bench checksums diverged")
		quit(1)
		return
	var dirty: Dictionary = conditions["dirty"]
	if not bool(dirty["checksum_match"]):
		push_error("dirty-set bench disagreed with a full scan")
		quit(1)
		return
	var ai: Dictionary = _Ai.new().measure()
	if not bool(ai["ok"]):
		push_error("ai bench self-check failed")
		quit(1)
		return
	var payload := {
		"workload": "placeholder_hash_and_rng",
		"iterations": iterations,
		"elapsed_usec": elapsed,
		"checksum": checksum,
		"conditions": conditions,
		"ai": ai,
		"wyrd": _Runtime.read_version(),
		"godot": version_info["string"],
	}
	var absolute := out_path
	if out_path.begins_with("res://"):
		absolute = ProjectSettings.globalize_path(out_path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null:
		push_error("bench could not write %s" % absolute)
		quit(1)
		return
	file.store_string(JSON.stringify(payload, "  ") + "\n")
	file.close()
	print("bench wrote %s" % absolute)
	quit(0)
