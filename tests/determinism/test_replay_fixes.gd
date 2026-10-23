extends GutTest

const _Routes := preload("res://tests/scenario/m10_gullhaven.gd")


func test_warm_and_cold_saves_match() -> void:
	var suite := _Routes.new()
	var warm_open: Dictionary = suite.boot("")
	var warm: WyrdRuntime = warm_open["runtime"]
	_warm_cache(warm)
	assert_gt(warm.social.cache_entries(), 0, "warm cache")
	var saved: Dictionary = warm.save_state().duplicate(true)
	var cold_open: Dictionary = suite.boot("")
	var cold: WyrdRuntime = cold_open["runtime"]
	var report: WyrdLoadReport = cold.load_state(saved)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(cold.social.cache_entries(), 0, "cold cache")
	_shift(warm)
	_shift(cold)
	assert_eq(warm.scheduler().carry("cache_refresh"), 0, "warm carry")
	assert_eq(cold.scheduler().carry("cache_refresh"), 0, "cold carry")
	var warm_state := warm.save_state()
	var cold_state := cold.save_state()
	var warm_sched := _scheduler_json(warm_state)
	var cold_sched := _scheduler_json(cold_state)
	assert_eq(warm_sched, cold_sched, "scheduler %s" % _first_diff(warm_sched, cold_sched))
	var warm_json := JSON.stringify(warm_state, "", true)
	var cold_json := JSON.stringify(cold_state, "", true)
	assert_eq(warm_json, cold_json, "save %s" % _first_diff(warm_json, cold_json))


func test_route_hashes_match_after_save_and_load() -> void:
	var suite := _Routes.new()
	for name in ["dock_rumour", "storm_rumour"]:
		var spec: Dictionary = suite.ROUTES[name]
		var steps: Array = spec["steps"]
		var straight := _boot_route(suite, spec)
		_play_steps(suite, straight, steps, 0, steps.size())
		var expected := suite.gameplay_hash(straight)
		for k in steps.size() + 1:
			var runtime := _boot_route(suite, spec)
			_play_steps(suite, runtime, steps, 0, k)
			if not runtime.can_save():
				continue
			suite.run_step(runtime, {"op": "save_load"}, [])
			suite.pump(runtime)
			_play_steps(suite, runtime, steps, k, steps.size())
			var got := suite.gameplay_hash(runtime)
			assert_eq(got, expected, "%s @%d %s" % [str(name), k, _first_diff(expected, got)])


func test_internal_accept_is_not_replayed() -> void:
	var suite := _Routes.new()
	var first := _arm_stew(suite)
	first.trace.clear()
	assert_true(first.generator.offer(&"tavern", "stew-low", &"low"))
	first.tick(0)
	var recorded: Array = first.trace.snapshot()
	var accepts := _kind(recorded, "gen_accept")
	assert_eq(accepts.size(), 1, "gen_accept rows %d" % accepts.size())
	assert_eq(str(accepts[0].get("origin", "")), "queue")
	assert_eq(str(accepts[0].get("ok", "")), "true")
	for replay_i in 2:
		var again := _arm_stew(suite)
		again.trace.clear()
		WyrdTrace.replay(again, recorded)
		var got: Array = again.trace.snapshot()
		var mismatch := WyrdTrace.diff(recorded, got)
		assert_eq(mismatch, PackedStringArray(), "replay %d\n%s" % [replay_i + 1, "\n".join(mismatch)])
		assert_eq(_with_reason(got, "gen_accept", "accepted").size(), 0, "replay %d accepted" % (replay_i + 1))


func test_host_accept_is_replayed() -> void:
	var suite := _Routes.new()
	var first := _generated(suite)
	first.facts.set(&"harbor.stew_wanted", true)
	first.trace.clear()
	var proposal: WyrdProposal = first.generator.propose({
		"key": "stew-low",
		"source": "exit",
		"template": "tavern_stew_low",
		"tier": "low",
	})
	assert_not_null(proposal)
	assert_eq(first.generator.accept(proposal), "tavern_stew_low#1")
	var accepts := _kind(first.trace.snapshot(), "gen_accept")
	assert_eq(accepts.size(), 1)
	assert_eq(str(accepts[0].get("origin", "")), "host")
	var recorded: Array = first.trace.snapshot()
	var second := _generated(suite)
	second.facts.set(&"harbor.stew_wanted", true)
	second.trace.clear()
	WyrdTrace.replay(second, recorded)
	assert_eq(second.quests.template_counter("tavern_stew_low"), 1)


func test_a_gen_accept_without_origin_is_replayed() -> void:
	var suite := _Routes.new()
	var first := _generated(suite)
	first.facts.set(&"harbor.stew_wanted", true)
	first.trace.clear()
	var proposal: WyrdProposal = first.generator.propose({
		"key": "stew-low",
		"source": "exit",
		"template": "tavern_stew_low",
		"tier": "low",
	})
	assert_not_null(proposal)
	assert_eq(first.generator.accept(proposal), "tavern_stew_low#1")
	var recorded: Array = first.trace.snapshot().duplicate(true)
	var stripped := 0
	for item in recorded:
		if item is Dictionary and str(item.get("kind", "")) == "gen_accept":
			item.erase("origin")
			stripped += 1
	assert_eq(stripped, 1)
	var second := _generated(suite)
	second.facts.set(&"harbor.stew_wanted", true)
	second.trace.clear()
	WyrdTrace.replay(second, recorded)
	assert_eq(second.quests.template_counter("tavern_stew_low"), 1)


func _scheduler_json(state: Dictionary) -> String:
	var flight: Variant = state.get("flight", {})
	if not flight is Dictionary:
		return "{}"
	var scheduler: Variant = (flight as Dictionary).get("scheduler", {})
	return JSON.stringify(scheduler, "", true)


func _warm_cache(runtime: WyrdRuntime) -> void:
	var names := PackedStringArray([
		"player", "tavern_owner", "ferry_master", "storm_watcher",
		"dock_apprentice", "dock_hand", "net_mender", "tide_clerk",
	])
	for source in names:
		for target in names:
			if source == target:
				continue
			runtime.social.axis(StringName(source), StringName(target), &"affinity")
			runtime.social.disposition(StringName(source), StringName(target))
	runtime.social.reputation(&"player", &"dockhands")


func _shift(runtime: WyrdRuntime) -> void:
	runtime.social.set_baseline(&"ferry_master", &"player", &"affinity", 3.0)
	runtime.tick(0)


func _boot_route(suite, spec: Dictionary) -> WyrdRuntime:
	var opened: Dictionary = suite.boot_spec(spec, "")
	var runtime: WyrdRuntime = opened["runtime"]
	return runtime


func _play_steps(suite, runtime: WyrdRuntime, steps: Array, from: int, to: int) -> void:
	var shown: Array = []
	for index in range(from, to):
		suite.run_step(runtime, steps[index], shown)
		suite.pump(runtime)


func _generated(suite) -> WyrdRuntime:
	var opened: Dictionary = suite.boot("", 1, true)
	var runtime: WyrdRuntime = opened["runtime"]
	return runtime


func _arm_stew(suite) -> WyrdRuntime:
	var runtime := _generated(suite)
	runtime.config().scheduler_share_generate = 64
	runtime.facts.set(&"harbor.stew_wanted", true)
	return runtime


func _kind(events: Array, kind: String) -> Array:
	var rows: Array = []
	for item in events:
		if item is Dictionary and str(item.get("kind", "")) == kind:
			rows.append(item)
	return rows


func _with_reason(events: Array, kind: String, reason: String) -> Array:
	var rows: Array = []
	for item in _kind(events, kind):
		if str(item.get("reason", "")) == reason:
			rows.append(item)
	return rows


func _first_diff(left: String, right: String) -> String:
	if left == right:
		return ""
	var parsed_left: Variant = JSON.parse_string(left)
	var parsed_right: Variant = JSON.parse_string(right)
	if not (parsed_left is Dictionary and parsed_right is Dictionary):
		return "len %d/%d" % [left.length(), right.length()]
	return _diff_value(parsed_left, parsed_right, "")


func _diff_value(left: Variant, right: Variant, path: String) -> String:
	if left is Dictionary and right is Dictionary:
		var keys: Array = left.keys()
		for key in right.keys():
			if not keys.has(key):
				keys.append(key)
		keys.sort()
		for key in keys:
			var here := str(key) if path == "" else "%s.%s" % [path, str(key)]
			if not left.has(key):
				return "%s missing on first" % here
			if not right.has(key):
				return "%s missing on second" % here
			var nested := _diff_value(left[key], right[key], here)
			if nested != "":
				return nested
		return ""
	if left is Array and right is Array:
		if JSON.stringify(left, "", true) == JSON.stringify(right, "", true):
			return ""
		return "%s array" % path
	if str(left) == str(right):
		return ""
	return "%s %s vs %s" % [path, str(left), str(right)]
