extends GutTest

## Replay equivalence ignores wall-clock diagnostic rows and still catches decisions.


func test_a_frame_warn_row_does_not_break_replay_equivalence() -> void:
	var clean := _events(true, -1)
	var warned := _events(true, 2500)
	var slower := _events(true, 9000)
	assert_eq(WyrdTrace.diff(clean, warned), PackedStringArray())
	assert_eq(WyrdTrace.diff(warned, slower), PackedStringArray())
	assert_eq(WyrdTrace.diff(slower, clean), PackedStringArray())
	assert_eq(warned.size(), clean.size() + 1)
	assert_true(_has_frame(warned))
	assert_eq(int(_frame(warned).get("us", 0)), 2500)
	var runtime := WyrdRuntime.new()
	runtime.config().scheduler_frame_warn_usec = 1
	runtime.config().scheduler_work_per_tick = 1
	runtime.config().scheduler_share_waits = 0
	runtime.config().scheduler_share_rumor = 0
	runtime.config().scheduler_share_publish = 0
	runtime.config().scheduler_share_cache = 1
	runtime.scheduler().cache_handler = func(_token: String) -> void:
		OS.delay_msec(3)
	runtime.scheduler().push("cache_refresh", "row")
	runtime.trace.enabled = true
	runtime.trace.clear()
	runtime.tick(0)
	var live := runtime.trace.snapshot()
	var frame := _frame(live)
	assert_false(frame.is_empty(), "expected a soft frame warning")
	assert_eq(bool(frame.get("timing", false)), true)
	assert_gt(int(frame.get("us", 0)), 1)
	var without: Array = []
	for row in live:
		if row is Dictionary and bool((row as Dictionary).get("timing", false)):
			continue
		without.append(row)
	assert_eq(WyrdTrace.diff(live, without), PackedStringArray())
	assert_eq(live.size(), without.size() + 1)


func test_a_real_decision_difference_is_still_caught() -> void:
	var left := _events(true, 2500)
	var right := _events(false, -1)
	var found := WyrdTrace.diff(left, right)
	assert_gt(found.size(), 0)
	assert_eq(String(found[0]), "3 command")
	assert_false(" ".join(found).contains("scheduler"))
	var rumor_a := WyrdTrace.new()
	rumor_a.enabled = true
	rumor_a.add("scheduler", {"carry": 0, "key": "rumor", "queue": "rumor", "units": 2})
	var rumor_b := WyrdTrace.new()
	rumor_b.enabled = true
	rumor_b.add("scheduler", {"carry": 0, "key": "rumor", "queue": "rumor", "units": 3})
	var rumor := WyrdTrace.diff(rumor_a.snapshot(), rumor_b.snapshot())
	assert_eq(rumor.size(), 1)
	assert_eq(String(rumor[0]), "0 scheduler")


func _events(ok: bool, warn_us: int) -> Array:
	var trace := WyrdTrace.new()
	trace.enabled = true
	trace.add("line", {"id": "a_leave", "text": "The boat leaves the dock."})
	trace.add("choices", {"rows": ["Take the room"]})
	if warn_us >= 0:
		trace.add("scheduler", {
			"carry": 0,
			"key": "frame",
			"queue": "frame",
			"threshold": 2000,
			"timing": true,
			"units": 4,
			"us": warn_us,
		})
	trace.add("command", {"name": "assign_lodging", "ok": ok, "reason": "-"})
	trace.add("draw", {"op": "u32", "stream": "play", "value": 1})
	return trace.snapshot()


func _frame(events: Array) -> Dictionary:
	for row in events:
		if row is Dictionary and String((row as Dictionary).get("queue", "")) == "frame":
			return row
	return {}


func _has_frame(events: Array) -> bool:
	return not _frame(events).is_empty()
