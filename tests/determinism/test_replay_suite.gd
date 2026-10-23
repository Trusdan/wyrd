extends GutTest

const _Driver := preload("res://tests/determinism/replay_driver.gd")
const _Cases := preload("res://tests/determinism/replay_cases.gd")
const _Inventory := preload("res://tests/determinism/replay_inventory.gd")
const _OLD := "res://tests/migration/packs/harbor_old.wyrdmanifest.tres"
const _NEW := "res://tests/migration/packs/harbor_new.wyrdmanifest.tres"

var driver: RefCounted


func before_all() -> void:
	_Driver.reset()
	_Driver.started_ms = Time.get_ticks_msec()
	driver = _Driver.new()


func test_routes_match_play_and_replay_twice() -> void:
	var names: PackedStringArray = driver.route_names()
	assert_eq(names.size(), 32, "Gullhaven route count")
	var providers: Array = ["", "echo"]
	for provider in providers:
		print("route replay provider=%s" % (provider if str(provider) != "" else "none"))
		for index in names.size():
			var name := String(names[index])
			var spec: Dictionary = driver.suite().ROUTES[name]
			var played: String = driver.play_canon(spec, str(provider))
			var recorded: Dictionary = driver.record_route(name, str(provider))
			assert_eq(driver.canon(recorded["events"]), played, "%s %s driver" % [name, provider])
			_assert_replay("%s %s" % [name, provider], recorded, driver.replay_route(name, str(provider), recorded))
			_assert_replay("%s %s again" % [name, provider], recorded, driver.replay_route(name, str(provider), recorded))


func test_no_provider_route_splits() -> void:
	var names: PackedStringArray = driver.route_names()
	for index in names.size():
		var name := String(names[index])
		var recorded: Dictionary = driver.record_route(name, "")
		var splits: Array = driver.choose_plain(driver.split_indexes(recorded["segments"]))
		for point in splits:
			var problems: PackedStringArray = driver.plain_route_split(name, recorded, int(point))
			assert_eq(problems.size(), 0, "%s @%s\n%s" % [name, str(point), "\n".join(problems)])


func test_echo_route_splits() -> void:
	var names: PackedStringArray = driver.route_names()
	for index in names.size():
		var name := String(names[index])
		var recorded: Dictionary = driver.record_route(name, "echo")
		var splits: Array = driver.split_indexes(recorded["segments"])
		if splits.is_empty():
			_Driver.echo_notes.append("%s (no split)" % name)
			continue
		var mid := int(splits[int(splits.size() / 2)])
		for point in splits:
			var result: Dictionary = driver.echo_route_split(name, recorded, int(point))
			var problems: PackedStringArray = result["problems"]
			assert_eq(problems.size(), 0, "%s echo @%s\n%s" % [name, str(point), "\n".join(problems)])
			if int(point) == mid:
				var shown := str(result["diff"])
				if shown == "":
					shown = "(empty)"
				_Driver.echo_notes.append("%s k=%d\n%s" % [name, mid, shown])


func test_m4_matrix_replays() -> void:
	var size := int(load("res://tests/scenario/test_m4_matrix.gd").get_script_constant_map()["MATRIX_SIZE"])
	var runs: Array = _Cases.m4_runs()
	assert_eq(size, 39)
	assert_eq(runs.size(), size, "M4 cases")
	_replay_runs(runs)


func test_m5_matrix_replays() -> void:
	var size := int(load("res://tests/scenario/test_m5_matrix.gd").get_script_constant_map()["MATRIX_SIZE"])
	var runs: Array = _Cases.m5_runs()
	assert_eq(size, 6)
	assert_eq(runs.size(), size, "M5 cases")
	_replay_runs(runs)


func test_m6_runtime_cases_replay() -> void:
	var runs: Array = _Cases.m6_runs()
	assert_gt(runs.size(), 0)
	_replay_runs(runs)


func test_m7_console_and_plays_replay() -> void:
	var expect: Dictionary = load("res://tests/scenario/test_m7_exit.gd").get_script_constant_map()["_EXPECT"]
	var runs: Array = _Cases.m7_runs()
	assert_eq(expect.size(), 13)
	var kills := 0
	for item in runs:
		var id := str((item as Dictionary)["id"])
		if id.split(":").size() == 3 and not id.contains("choice") and not id.contains("coverage"):
			kills += 1
	assert_eq(kills, expect.size(), "M7 kill cases")
	_replay_runs(runs)


func test_m9_extra_plays_replay() -> void:
	var runs: Array = _Cases.m9_runs()
	assert_eq(runs.size(), 5, "stew, cap, guard, save, save loaded")
	_replay_runs(runs)


func test_alias_load_baseline() -> void:
	var saved := _alias_played()
	var first := _alias_boot(_NEW)
	var first_load := _load_traced(first, saved)
	assert_true(first_load["report"].ok, first_load["report"].diagnostics.format())
	_assert_ai_rows(first_load["events"], "alias first")
	var first_save := first.save_state()
	var second := _alias_boot(_NEW)
	var second_load := _load_traced(second, saved)
	assert_true(second_load["report"].ok, second_load["report"].diagnostics.format())
	_assert_ai_rows(second_load["events"], "alias second")
	var second_save := second.save_state()
	assert_eq(JSON.stringify(first_save, "\t", true), JSON.stringify(second_save, "\t", true), "post-load saves")
	var third := _alias_boot(_NEW)
	var third_load := _load_traced(third, first_save)
	assert_true(third_load["report"].ok, third_load["report"].diagnostics.format())
	assert_eq(third_load["report"].rows, [], "resolved load rows %s" % JSON.stringify(third_load["report"].rows))
	_assert_ai_rows(third_load["events"], "alias third")
	assert_eq(JSON.stringify(third.save_state(), "\t", true), JSON.stringify(first_save, "\t", true), "third save")
	var left := _tick_trace(first)
	var middle := _tick_trace(second)
	var right := _tick_trace(third)
	assert_eq(WyrdTrace.diff(left, middle), PackedStringArray(), "alias tick 1/2")
	assert_eq(WyrdTrace.diff(left, right), PackedStringArray(), "alias tick 1/3")


func test_call_inventory() -> void:
	var scanned := _scanned_calls()
	var entries: Array = _Inventory.entries()
	var by_call := {}
	var counts := {}
	var unrecorded: Array = []
	for item in entries:
		var row: Dictionary = item
		var call := str(row["call"])
		assert_false(by_call.has(call), "duplicate %s" % call)
		by_call[call] = row
		var category := str(row["category"])
		var bucket := category
		if category.begins_with("input:"):
			bucket = "input"
		counts[bucket] = int(counts.get(bucket, 0)) + 1
		if category != bucket:
			counts[category] = int(counts.get(category, 0)) + 1
		if category == "unrecorded":
			unrecorded.append("%s — %s" % [call, str(row["reason"])])
		assert_true(scanned.has(call), "entry has no method %s" % call)
	for call in scanned.keys():
		assert_true(by_call.has(call), "missing entry %s" % call)
	var arms := _replay_arms(FileAccess.get_file_as_string("res://addons/wyrd/runtime/trace/wyrd_trace.gd"))
	var input_kinds := {}
	for entry in by_call.values():
		var named := str((entry as Dictionary)["category"])
		if named.begins_with("input:"):
			input_kinds[named.substr("input:".length())] = true
	var replayed_kinds := {}
	for arm in arms:
		var row: Dictionary = arm
		if not bool(row["replayed"]):
			continue
		var covered := false
		for kind in row["kinds"]:
			replayed_kinds[str(kind)] = true
			if input_kinds.has(str(kind)):
				covered = true
		assert_true(covered, "replay arm has no input entry %s" % str(row["kinds"]))
	for entry in by_call.values():
		var category := str((entry as Dictionary)["category"])
		if category.begins_with("input:"):
			var kind := category.substr("input:".length())
			assert_true(replayed_kinds.has(kind), "input kind not replayed %s" % kind)
	unrecorded.sort()
	_Driver.unrecorded_lines = unrecorded
	_Driver.category_counts = counts
	var kind_list: Array = replayed_kinds.keys()
	kind_list.sort()
	_Driver.replay_kinds = kind_list
	var missing: Array = []
	for kind in kind_list:
		if not _Driver.seen_kinds.has(str(kind)):
			missing.append(str(kind))
	_Driver.unexercised = missing
	print("UNRECORDED")
	for line in unrecorded:
		print(line)
	print("CATEGORY COUNTS")
	var buckets: Array = counts.keys()
	buckets.sort()
	for bucket in buckets:
		print("%s %d" % [str(bucket), int(counts[bucket])])
	print("INPUT KINDS NOT EXERCISED")
	if missing.is_empty():
		print("(none)")
	else:
		for kind in missing:
			print(kind)


func test_replay_report() -> void:
	var elapsed := Time.get_ticks_msec() - _Driver.started_ms
	var lines: Array = []
	lines.append("suite_ms %d" % elapsed)
	lines.append("plain_split_limit %s" % str(_Driver.limit_plain_splits))
	lines.append("split_points %d" % _Driver.split_points)
	lines.append("OP TABLE")
	var ops: Array = _Driver.MODE.keys()
	ops.sort()
	for op in ops:
		var seen := "seen" if _Driver.op_modes.has(op) else "unused"
		lines.append("%s %s %s" % [str(op), str(_Driver.MODE[op]), seen])
	lines.append("ECHO MIDDLE DIFFS")
	for note in _Driver.echo_notes:
		lines.append(str(note))
	lines.append("CATEGORY COUNTS")
	var buckets: Array = _Driver.category_counts.keys()
	buckets.sort()
	for bucket in buckets:
		lines.append("%s %d" % [str(bucket), int(_Driver.category_counts[bucket])])
	lines.append("UNRECORDED")
	for line in _Driver.unrecorded_lines:
		lines.append(str(line))
	lines.append("NOT EXERCISED")
	for kind in _Driver.unexercised:
		lines.append(str(kind))
	var text := "\n".join(lines)
	print(text)
	var file := FileAccess.open("/tmp/replay_suite_report.txt", FileAccess.WRITE)
	file.store_string(text + "\n")
	file.close()
	assert_gt(elapsed, 0)
	assert_eq(driver.route_names().size(), 32)


func _replay_runs(runs: Array) -> void:
	for item in runs:
		var run: Dictionary = item
		var recorded: Dictionary = driver.record_case(run)
		_assert_replay(str(run["id"]), recorded, driver.replay_case(run, recorded))
		_assert_replay("%s again" % str(run["id"]), recorded, driver.replay_case(run, recorded))
		var splits: Array = driver.split_indexes(recorded["segments"])
		for point in splits:
			var problems: PackedStringArray = driver.plain_case_split(run, recorded, int(point))
			assert_eq(problems.size(), 0, "%s @%s\n%s" % [str(run["id"]), str(point), "\n".join(problems)])


func _assert_replay(label: String, recorded: Dictionary, replayed: Dictionary) -> void:
	var mismatch: String = driver.explain(recorded["events"], replayed["events"])
	assert_eq(mismatch, "", "%s\n%s" % [label, mismatch])
	assert_eq(driver.canon(replayed["events"]), driver.canon(recorded["events"]), "%s bytes" % label)
	assert_eq(str(replayed["hash"]), str(recorded["hash"]), "%s hash" % label)


func _alias_played() -> Dictionary:
	var runtime := _alias_boot(_OLD)
	runtime.quests.start("ferry_toll")
	runtime.quests.advance("ferry_toll", "offer")
	var id := runtime.quests.create_instance("ferry_job")
	runtime.quests.advance(id, "hire")
	runtime.roles.assign(&"ferry_master", &"player")
	runtime.roles.tell(&"ferry_master", &"dock_clerk")
	runtime.deeds.record(&"paid", &"player")
	runtime.deeds.record(&"arrived", &"player")
	runtime.deeds.record(&"paid", &"player")
	runtime.documents.create_copy(&"harbor_gazette", "kept")
	runtime.documents.open(&"harbor_gazette", "kept", &"player")
	return runtime.save_state()


func _alias_boot(path: String) -> WyrdRuntime:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var manifest := load(path) as WyrdContentManifest
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.config().scheduler_frame_warn_usec = 0
	runtime.start_new_game(7)
	var world := runtime.adapter(WyrdWorldAdapter) as WyrdFakeWorld
	world.add_entity(&"player", &"person", "traveler", PackedStringArray(), true)
	world.add_entity(&"dock_clerk", &"person", "clerk", PackedStringArray(), true)
	return runtime


func _load_traced(runtime: WyrdRuntime, saved: Dictionary) -> Dictionary:
	runtime.trace.enabled = true
	runtime.trace.prefix = ""
	runtime.trace.clear()
	var report := runtime.load_state(saved)
	return {"events": runtime.trace.snapshot(), "report": report}


func _assert_ai_rows(events: Array, label: String) -> void:
	for item in events:
		var kind := ""
		if item is Dictionary:
			kind = str((item as Dictionary).get("kind", ""))
		assert_true(kind.begins_with("ai_"), "%s load trace %s" % [label, JSON.stringify(item)])


func _tick_trace(runtime: WyrdRuntime) -> Array:
	runtime.config().scheduler_frame_warn_usec = 0
	runtime.trace.enabled = true
	runtime.trace.prefix = ""
	runtime.trace.clear()
	runtime.tick(60)
	return runtime.trace.snapshot()


func _scanned_calls() -> Dictionary:
	var found := {}
	var runtime := WyrdRuntime.new()
	_take(found, "WyrdRuntime", runtime.get_script())
	var facade: Node = load("res://addons/wyrd/runtime/wyrd.gd").new()
	_take(found, "Wyrd", facade.get_script())
	var props: Array = [
		"facts", "events", "deeds", "social", "rumors", "publish", "roles",
		"topics", "documents", "quests", "dialogue", "storylets", "sequences",
		"director", "generator", "ai", "trace", "debug", "coverage",
	]
	for prop in props:
		var obj: Object = facade.get(prop)
		var script := obj.get_script() as Script
		_take(found, script.get_global_name(), script)
	_take(found, "WyrdConsole", load("res://addons/wyrd/runtime/console/wyrd_console.gd"))
	found["WyrdFactStore.set"] = true
	facade.free()
	return found


func _take(found: Dictionary, label: String, script: Script) -> void:
	for item in script.get_script_method_list():
		var method: Dictionary = item
		var name := String(method.get("name", ""))
		if name.begins_with("_"):
			continue
		found["%s.%s" % [label, name]] = true


func _replay_arms(text: String) -> Array:
	var start := text.find("static func replay")
	var end := text.find("static func diff")
	var body := text.substr(start, end - start)
	var source_lines: PackedStringArray = body.split("\n")
	var arms: Array = []
	for line_i in source_lines.size():
		var stripped := source_lines[line_i].strip_edges()
		if not _arm_line(stripped):
			continue
		var kinds := _quoted(stripped)
		var replayed := not stripped.begins_with("_")
		var look := line_i + 1
		while look < source_lines.size() and source_lines[look].strip_edges() == "":
			look += 1
		if look < source_lines.size() and source_lines[look].strip_edges() == "pass":
			replayed = false
		arms.append({"kinds": kinds, "replayed": replayed})
	return arms


func _arm_line(stripped: String) -> bool:
	if stripped == "_:":
		return true
	if not stripped.ends_with(":"):
		return false
	if stripped.contains("(") or stripped.contains("="):
		return false
	var body := stripped.substr(0, stripped.length() - 1)
	var parts := body.split(",")
	if parts.is_empty():
		return false
	for part in parts:
		var item := str(part).strip_edges()
		if item.length() < 2 or not item.begins_with("\"") or not item.ends_with("\""):
			return false
	return true


func _quoted(line: String) -> PackedStringArray:
	var kinds := PackedStringArray()
	var cursor := 0
	while true:
		var open := line.find("\"", cursor)
		if open < 0:
			break
		var close := line.find("\"", open + 1)
		if close < 0:
			break
		kinds.append(line.substr(open + 1, close - open - 1))
		cursor = close + 1
	return kinds
