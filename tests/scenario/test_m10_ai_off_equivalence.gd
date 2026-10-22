extends GutTest

const _Exit := preload("res://tests/scenario/m10_gullhaven.gd")


func test_every_route_matches_with_ai_off() -> void:
	var exit := _Exit.new()
	var modes: Array[String] = ["null", "echo", "garbage", "silent", "fuzz", "off"]
	var names: Array = exit.ROUTES.keys()
	names.sort()
	for name in names:
		var spec: Dictionary = exit.ROUTES[name]
		var hashes: PackedStringArray = PackedStringArray()
		var traces: PackedStringArray = PackedStringArray()
		for mode in modes:
			var provider := "echo" if mode == "off" else mode
			var opened := exit.boot_spec(spec, provider)
			var runtime: WyrdRuntime = opened["runtime"]
			if mode == "off":
				runtime.ai.set_enabled(false)
				runtime.trace.clear()
			var shown: Array = exit.play(runtime, spec["steps"])
			var problem := exit.audit_shown(runtime, shown)
			assert_eq(problem, "", "%s %s %s" % [name, mode, problem])
			if mode == "null" or mode == "off":
				assert_false(exit.source_is_ai(runtime), "%s %s" % [name, mode])
				_assert_authored_lines(exit, runtime, shown, str(name))
			hashes.append(exit.gameplay_hash(runtime))
			traces.append(exit.filtered_trace(runtime.trace.events))
		for index in hashes.size():
			assert_eq(hashes[index], hashes[0], "%s hash %s" % [name, modes[index]])
			assert_eq(traces[index], traces[0], "%s trace %s" % [name, modes[index]])


func _assert_authored_lines(exit: RefCounted, runtime: WyrdRuntime, shown: Array, name: String) -> void:
	for item in shown:
		var row: Dictionary = item
		assert_eq(str(row["text"]), str(row["authored"]), "%s %s" % [name, str(row["path"])])
	var cursor := 0
	for item in runtime.trace.events:
		if not (item is Dictionary):
			continue
		var event: Dictionary = item
		if str(event.get("kind", "")) != "line":
			continue
		var line_id := str(event.get("id", ""))
		var text := str(event.get("text", ""))
		var authored := ""
		if cursor < shown.size() and str((shown[cursor] as Dictionary)["path"]) == line_id:
			authored = str((shown[cursor] as Dictionary)["authored"])
			cursor += 1
		else:
			var found := false
			while cursor < shown.size():
				var captured: Dictionary = shown[cursor]
				cursor += 1
				if str(captured["path"]) == line_id:
					authored = str(captured["authored"])
					found = true
					break
			if not found:
				authored = str(exit.authored(runtime, line_id))
		assert_eq(text, authored, "%s %s" % [name, line_id])
