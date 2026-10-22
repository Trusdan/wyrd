extends GutTest

const _Exit := preload("res://tests/scenario/m10_gullhaven.gd")
const _ANSWERS := 1000


func test_fuzz_falls_back_or_passes_and_replays() -> void:
	var exit := _Exit.new()
	var first := _drive(exit)
	var second := _drive(exit)
	assert_eq(int(first["answered"]), _ANSWERS)
	assert_eq(int(second["answered"]), _ANSWERS)
	assert_eq(str(first["trace"]), str(second["trace"]))
	var events: Array = first["events"]
	_assert_uses(events)
	var counts: Dictionary = exit.fuzz_outcomes(events)
	print("m10 fuzz outcomes %s" % JSON.stringify(counts))
	var total := 0
	for key in counts.keys():
		total += int(counts[key])
	assert_gte(int(counts["accepted"]), 1)
	assert_gte(int(counts["error"]), 1)
	assert_gte(int(counts["limits"]), 1)
	assert_eq(total, int(counts["accepted"]) + int(counts["error"]) + int(counts["limits"]) + int(counts["names"]) + int(counts["banned"]) + int(counts["spoiler"]) + int(counts["classifier"]) + int(counts["provider"]))


func _drive(exit: RefCounted) -> Dictionary:
	var opened: Dictionary = exit.boot("fuzz")
	var runtime: WyrdRuntime = opened["runtime"]
	var provider: RefCounted = opened["provider"]
	var ids: Array[String] = ["a_leave", "sg02", "sg03", "sg04", "sg05", "sg_storm"]
	var index := 0
	while int(provider.get("answered")) < _ANSWERS:
		var line_id := ids[index % ids.size()]
		index += 1
		var kind := runtime.ai.kind_for_line(line_id)
		var packet := runtime.ai.packet_for_line(line_id, kind, &"")
		runtime.ai.clear_cache()
		runtime.ai.request(kind, packet, {}, StringName(line_id))
		exit.pump(runtime)
		var view := WyrdLineView.new()
		view.id = line_id
		view.speaker = &"narrator"
		view.text = exit.authored(runtime, line_id)
		runtime.ai.present(view, line_id)
		var use := _last(runtime, "ai_use", line_id)
		var verdict := _latest_validate(runtime, str(use.get("key", "")))
		var failed := str(verdict.get("ok", "")) == "false" or _latest_result_failed(runtime, str(use.get("key", "")))
		if failed:
			assert_eq(view.text, exit.authored(runtime, line_id), line_id)
		if str(use.get("source", "")) == "ai":
			assert_eq(str(verdict.get("ok", "")), "true", line_id)
			assert_true(_had_ok_result(runtime, str(use.get("key", "")), use))
		if index > _ANSWERS + 5:
			break
	return {
		"answered": provider.get("answered"),
		"events": runtime.trace.events.duplicate(true),
		"trace": JSON.stringify(runtime.trace.snapshot()),
	}


func _assert_uses(events: Array) -> void:
	for index in events.size():
		var row: Dictionary = events[index]
		if str(row.get("kind", "")) != "ai_use" or str(row.get("source", "")) != "ai":
			continue
		var key := str(row.get("key", ""))
		var saw_ok := false
		var rejected := false
		for earlier in index:
			var prev: Dictionary = events[earlier]
			if str(prev.get("key", "")) != key:
				continue
			if str(prev.get("kind", "")) == "ai_result" and str(prev.get("ok", "")) == "true":
				saw_ok = true
			if str(prev.get("kind", "")) == "ai_validate":
				rejected = str(prev.get("ok", "")) != "true"
				if str(prev.get("ok", "")) == "true":
					rejected = false
		assert_true(saw_ok, key)
		assert_false(rejected, key)


func _last(runtime: WyrdRuntime, kind: String, path: String) -> Dictionary:
	var found := {}
	for item in runtime.trace.events:
		var row: Dictionary = item
		if str(row.get("kind", "")) == kind and str(row.get("path", "")) == path:
			found = row
	return found


func _latest_validate(runtime: WyrdRuntime, key: String) -> Dictionary:
	var found := {}
	for item in runtime.trace.events:
		var row: Dictionary = item
		if str(row.get("kind", "")) == "ai_validate" and str(row.get("key", "")) == key:
			found = row
	return found


func _latest_result_failed(runtime: WyrdRuntime, key: String) -> bool:
	var ok := true
	var seen := false
	for item in runtime.trace.events:
		var row: Dictionary = item
		if str(row.get("kind", "")) == "ai_result" and str(row.get("key", "")) == key:
			seen = true
			ok = str(row.get("ok", "")) == "true"
	return seen and not ok


func _had_ok_result(runtime: WyrdRuntime, key: String, use: Dictionary) -> bool:
	var at := runtime.trace.events.find(use)
	for index in at:
		var row: Dictionary = runtime.trace.events[index]
		if str(row.get("kind", "")) == "ai_result" and str(row.get("key", "")) == key and str(row.get("ok", "")) == "true":
			return true
	return false
