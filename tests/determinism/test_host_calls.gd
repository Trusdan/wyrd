extends GutTest

## Direct game writes and queries are host_call rows. Work Wyrd does itself is not.


const _M10 := preload("res://tests/scenario/m10_gullhaven.gd")
const _Harness := preload("res://tests/scenario/s2c_harness.gd")


func test_each_host_call_replays() -> void:
	_check(func(runtime: WyrdRuntime) -> void:
		runtime.facts.set_in(&"player.coins", 6, &"world")
	, "facts.set_in", ["player.coins", 6, "world"])
	_check(func(runtime: WyrdRuntime) -> void:
		runtime.facts.set(&"player.coins", 7)
	, "facts.set_in", ["player.coins", 7, "world"])
	_check(func(runtime: WyrdRuntime) -> void:
		runtime.facts.set_in(&"player.coins", 4, &"known/player")
		runtime.trace.clear()
		runtime.facts.clear_in(&"player.coins", &"known/player")
	, "facts.clear_in", ["player.coins", "known/player"], func(runtime: WyrdRuntime) -> void:
		runtime.facts.set_in(&"player.coins", 4, &"known/player")
	)
	_check(func(runtime: WyrdRuntime) -> void:
		runtime.deeds.record(&"paid", &"player", &"ferry", &"gullhaven", PackedStringArray(["toll"]), 1.0, null, &"public", true)
	, "deeds.record", ["paid", "player", "ferry", "gullhaven", ["toll"], 1.0, null, "public", true])
	_check(func(runtime: WyrdRuntime) -> void:
		runtime.deeds.compact()
	, "deeds.compact", [])
	_check(func(runtime: WyrdRuntime) -> void:
		runtime.social.set_kind(&"ferry_master", &"player", &"friend")
	, "social.set_kind", ["ferry_master", "player", "friend"])
	_check(func(runtime: WyrdRuntime) -> void:
		runtime.social.set_kind(&"ferry_master", &"player", &"friend")
		runtime.trace.clear()
		runtime.social.clear_kind(&"ferry_master", &"player", &"friend")
	, "social.clear_kind", ["ferry_master", "player", "friend"], func(runtime: WyrdRuntime) -> void:
		runtime.social.set_kind(&"ferry_master", &"player", &"friend")
	)
	_check(func(runtime: WyrdRuntime) -> void:
		runtime.social.set_baseline(&"ferry_master", &"player", &"affinity", 3.0)
	, "social.set_baseline", ["ferry_master", "player", "affinity", 3.0])
	_check(func(runtime: WyrdRuntime) -> void:
		runtime.social.adjust_baseline(&"ferry_master", &"player", &"affinity", 2.0)
	, "social.adjust_baseline", ["ferry_master", "player", "affinity", 2.0])
	_check(func(runtime: WyrdRuntime) -> void:
		runtime.social.set_baseline(&"ferry_master", &"player", &"affinity", 3.0)
		runtime.trace.clear()
		runtime.social.clear_baseline(&"ferry_master", &"player", &"affinity")
	, "social.clear_baseline", ["ferry_master", "player", "affinity"], func(runtime: WyrdRuntime) -> void:
		runtime.social.set_baseline(&"ferry_master", &"player", &"affinity", 3.0)
	)
	_check(func(runtime: WyrdRuntime) -> void:
		runtime.roles.define(&"watcher", "none")
	, "roles.define", ["watcher", "none", false, -1, "", "", "", "", ""])
	_check(func(runtime: WyrdRuntime) -> void:
		runtime.roles.assign(&"dock_runner", &"dock_apprentice")
	, "roles.assign", ["dock_runner", "dock_apprentice"])
	_check(func(runtime: WyrdRuntime) -> void:
		runtime.roles.assign(&"dock_runner", &"dock_apprentice")
		runtime.trace.clear()
		runtime.roles.vacate(&"dock_runner", &"left")
	, "roles.vacate", ["dock_runner", "left"], func(runtime: WyrdRuntime) -> void:
		runtime.roles.assign(&"dock_runner", &"dock_apprentice")
	)
	_check(func(runtime: WyrdRuntime) -> void:
		runtime.roles.define(&"watcher", "none")
		runtime.trace.clear()
		runtime.roles.tell(&"watcher", &"player")
	, "roles.tell", ["watcher", "player"], func(runtime: WyrdRuntime) -> void:
		runtime.roles.define(&"watcher", "none")
	)
	_check(func(runtime: WyrdRuntime) -> void:
		runtime.topics.unlock(&"host_topic")
	, "topics.unlock", ["host_topic"])
	_check(func(runtime: WyrdRuntime) -> void:
		runtime.topics.unlock(&"host_topic")
		runtime.trace.clear()
		runtime.topics.lock(&"host_topic")
	, "topics.lock", ["host_topic"], func(runtime: WyrdRuntime) -> void:
		runtime.topics.unlock(&"host_topic")
	)
	_check(func(runtime: WyrdRuntime) -> void:
		runtime.quests.start("dock_errand")
	, "quests.start", ["dock_errand"])
	_check(func(runtime: WyrdRuntime) -> void:
		runtime.quests.start("dock_errand")
		runtime.trace.clear()
		runtime.quests.advance("dock_errand", "sent")
	, "quests.advance", ["dock_errand", "sent"], func(runtime: WyrdRuntime) -> void:
		runtime.quests.start("dock_errand")
	)
	_check(func(runtime: WyrdRuntime) -> void:
		runtime.quests.start("dock_errand")
		runtime.trace.clear()
		runtime.quests.abandon("dock_errand")
	, "quests.abandon", ["dock_errand"], func(runtime: WyrdRuntime) -> void:
		runtime.quests.start("dock_errand")
	)
	_check(func(runtime: WyrdRuntime) -> void:
		runtime.director.query("bark", "", "ferry_master")
	, "director.query", ["bark", "", "ferry_master"])
	_check_cancel()
	_check_clear_cache()


func test_nested_writes_log_no_host_call() -> void:
	var harness := _Harness.new()
	var room := _boot()
	var deeds_before := room.deeds.size()
	room.trace.clear()
	room.dialogue.open_scene("toll.offer_room")
	harness.line_rows(room)
	harness.choose_text(room, "Take the room")
	assert_eq(_host_rows(room).size(), 0)
	assert_true(bool(room.facts.get(&"harbor.room_taken")))
	var errand := _boot()
	errand.trace.clear()
	errand.dialogue.open_scene("toll.offer_room")
	harness.line_rows(errand)
	harness.choose_text(errand, "Ask the dock errand")
	assert_eq(_host_rows(errand).size(), 0)
	assert_eq(String(errand.quests.status("dock_errand")), "active")
	var left := _boot()
	left.trace.clear()
	left.dialogue.open_scene("toll.offer_room")
	left.dialogue.abort(&"left")
	assert_eq(_host_rows(left).size(), 0)
	assert_gt(left.deeds.size(), deeds_before)
	var succession := _boot()
	succession.roles.define(&"ferry_master", "relation(apprentice)")
	succession.social.set_kind(&"ferry_master", &"dock_apprentice", &"apprentice")
	succession.trace.clear()
	succession.roles.vacate(&"ferry_master", &"died")
	var calls := _calls(succession)
	assert_eq(calls, ["roles.vacate"])
	var ticking := _boot()
	ticking.trace.clear()
	var before := _save(ticking)
	ticking.tick(60)
	assert_eq(_host_rows(ticking).size(), 0)
	assert_ne(_save(ticking), before)
	var fresh := _boot()
	var provider := WyrdFakeAI.EchoNow.new()
	provider.host = fresh
	fresh.register_adapter(WyrdAIProvider, provider)
	fresh.ai.request(&"bark_paraphrase", {"text": "The gate is shut tonight."}, {}, &"toll.keeper")
	assert_gt(fresh.ai.cache_size(), 0)
	fresh.trace.clear()
	fresh.start_new_game(1)
	assert_eq(_host_rows(fresh).size(), 0)
	assert_eq(fresh.ai.cache_size(), 0)
	provider.host = fresh
	fresh.register_adapter(WyrdAIProvider, provider)
	fresh.ai.request(&"bark_paraphrase", {"text": "The gate is shut tonight."}, {}, &"toll.keeper")
	assert_gt(fresh.ai.cache_size(), 0)
	fresh.config().ai_save_cache = false
	var saved := fresh.save_state()
	fresh.trace.clear()
	var report := fresh.load_state(saved)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(_host_rows(fresh).size(), 0)
	assert_eq(fresh.ai.cache_size(), 0)


func test_handler_during_a_choice_is_not_recorded() -> void:
	var runtime := _prepare_room()
	_connect_handler(runtime)
	_play_room(runtime)
	assert_eq(_host_rows(runtime).size(), 0)
	assert_true(bool(runtime.facts.get(&"harbor.mooring_check")))
	var recorded: Array = runtime.trace.snapshot()
	var again := _prepare_room()
	_connect_handler(again)
	WyrdTrace.replay(again, recorded)
	assert_eq(WyrdTrace.diff(recorded, again.trace.events), PackedStringArray())
	assert_true(bool(again.facts.get(&"harbor.mooring_check")))
	assert_eq(again.facts.get(&"player.coins"), runtime.facts.get(&"player.coins"))


func test_no_ops_are_skipped_and_a_repeat_unlock_is_kept() -> void:
	var same := _boot()
	same.facts.set(&"player.coins", 3)
	same.trace.clear()
	assert_true(same.facts.set_in(&"player.coins", 3, &"world"))
	assert_eq(same.trace.events.size(), 0)
	var missing := _boot()
	assert_true(missing.facts.clear_in(&"player.coins", &"known/player"))
	assert_eq(missing.trace.events.size(), 0)
	var refused := _boot()
	refused.facts.set_in(&"not.a.fact", 1, &"world")
	assert_push_error("no schema entry")
	assert_eq(_calls(refused), ["facts.set_in"])
	var cancel := _boot()
	assert_false(cancel.ai.cancel(4))
	assert_eq(cancel.trace.events.size(), 0)
	var empty := _boot()
	empty.ai.clear_cache()
	assert_eq(empty.trace.events.size(), 0)
	var quest := _boot()
	quest.quests.advance("missing", "one")
	assert_push_error("unknown quest")
	assert_eq(quest.trace.events.size(), 0)
	quest.quests.start("dock_errand")
	quest.trace.clear()
	quest.quests.advance("dock_errand", "missing")
	assert_push_error("unknown stage")
	assert_eq(quest.trace.events.size(), 0)
	var topic := _boot()
	topic.topics.unlock(&"twice")
	topic.topics.unlock(&"twice")
	assert_eq(_calls(topic), ["topics.unlock", "topics.unlock"])
	_replay_ok(topic)


func test_an_old_trace_replays_when_the_host_repeats_its_calls() -> void:
	var runtime := _boot()
	runtime.facts.set(&"player.coins", 5)
	runtime.topics.unlock(&"old_topic")
	runtime.deeds.record(&"paid", &"player", &"", &"gullhaven", PackedStringArray(["toll"]))
	var full: Array = runtime.trace.snapshot()
	var stripped: Array = []
	var calls: Array = []
	for item in full:
		if item is Dictionary and String((item as Dictionary).get("kind", "")) == "host_call":
			calls.append(item)
		else:
			stripped.append(item)
	assert_gt(calls.size(), 0)
	var again := _boot()
	for item in calls:
		_repeat(again, item)
	WyrdTrace.replay(again, stripped)
	assert_eq(_save(runtime), _save(again))
	var found := WyrdTrace.diff(full, again.trace.events)
	for line in found:
		assert_eq(String(line).split(" ")[-1], "host_call")
	assert_eq(WyrdTrace.diff(_without_host(full), _without_host(again.trace.events)), PackedStringArray())


func test_json_round_trip_replays_an_int_fact_and_deed_tags() -> void:
	var runtime := _boot()
	runtime.facts.set(&"player.coins", 6)
	runtime.deeds.record(&"paid", &"player", &"ferry", &"gullhaven", PackedStringArray(["cut", "toll"]))
	var parsed: Variant = JSON.parse_string(JSON.stringify(runtime.trace.snapshot()))
	assert_true(parsed is Array)
	var again := _boot()
	WyrdTrace.replay(again, parsed)
	assert_eq(_save(runtime), _save(again))
	assert_eq(again.facts.get(&"player.coins"), 6)
	assert_eq(typeof(again.facts.get(&"player.coins")), TYPE_INT)
	assert_true(_save(again).contains("\"toll\""))


func _check(action: Callable, call_name: String, args: Array, prepare: Callable = Callable()) -> void:
	var runtime := _boot()
	action.call(runtime)
	var rows := _host_rows(runtime)
	assert_eq(rows.size(), 1, call_name)
	assert_eq(String((rows[0] as Dictionary)["call"]), call_name)
	assert_eq((rows[0] as Dictionary)["args"], args)
	assert_eq(String((runtime.trace.events[0] as Dictionary)["kind"]), "host_call")
	_replay_ok(runtime, prepare)


func _check_cancel() -> void:
	var runtime := _boot()
	var provider := WyrdFakeAI.EchoLater.new()
	runtime.register_adapter(WyrdAIProvider, provider)
	runtime.trace.clear()
	var request_id := runtime.ai.request(&"bark_paraphrase", {"text": "The gate is shut tonight."}, {}, &"toll.keeper")
	assert_gt(request_id, 0)
	runtime.ai.cancel(request_id)
	var rows := _host_rows(runtime)
	assert_eq(rows.size(), 1)
	assert_eq(String((rows[0] as Dictionary)["call"]), "ai.cancel")
	assert_eq((rows[0] as Dictionary)["args"], [request_id])
	var recorded: Array = runtime.trace.snapshot()
	var again := _boot()
	again.register_adapter(WyrdAIProvider, WyrdFakeAI.EchoLater.new())
	again.trace.clear()
	WyrdTrace.replay(again, recorded)
	assert_eq(WyrdTrace.diff(recorded, again.trace.events), PackedStringArray())
	assert_eq(_save(runtime), _save(again))
	var third := _boot()
	third.register_adapter(WyrdAIProvider, WyrdFakeAI.EchoLater.new())
	third.trace.clear()
	WyrdTrace.replay(third, recorded)
	assert_eq(_save(runtime), _save(third))


func _check_clear_cache() -> void:
	var runtime := _boot()
	var provider := WyrdFakeAI.EchoNow.new()
	provider.host = runtime
	runtime.register_adapter(WyrdAIProvider, provider)
	runtime.trace.clear()
	runtime.ai.request(&"bark_paraphrase", {"text": "The gate is shut tonight."}, {}, &"toll.keeper")
	assert_gt(runtime.ai.cache_size(), 0)
	runtime.trace.clear()
	runtime.ai.clear_cache()
	var rows := _host_rows(runtime)
	assert_eq(rows.size(), 1)
	assert_eq(String((rows[0] as Dictionary)["call"]), "ai.clear_cache")
	assert_eq((rows[0] as Dictionary)["args"], [])
	var recorded: Array = runtime.trace.snapshot()
	var again := _boot()
	again.ai.clear_cache()
	again.trace.clear()
	# The recorded call clears a cache. Seed the same entry, then replay that call.
	var seeded := WyrdFakeAI.EchoNow.new()
	seeded.host = again
	again.register_adapter(WyrdAIProvider, seeded)
	again.ai.request(&"bark_paraphrase", {"text": "The gate is shut tonight."}, {}, &"toll.keeper")
	again.trace.clear()
	WyrdTrace.replay(again, recorded)
	assert_eq(WyrdTrace.diff(recorded, again.trace.events), PackedStringArray())
	assert_eq(again.ai.cache_size(), 0)
	assert_eq(_save(runtime), _save(again))


func _boot() -> WyrdRuntime:
	var opened: Dictionary = _M10.new().boot("")
	return opened["runtime"]


func _prepare_room() -> WyrdRuntime:
	var runtime := _boot()
	runtime.facts.set(&"player.coins", 4)
	runtime.facts.subscribe(&"player")
	runtime.trace.clear()
	return runtime


func _connect_handler(runtime: WyrdRuntime) -> void:
	runtime.facts.fact_changed.connect(func(key: StringName, _old_value: Variant, _new_value: Variant) -> void:
		if String(key) != "player.coins":
			return
		runtime.facts.set_in(&"harbor.mooring_check", true, &"world")
	)


func _play_room(runtime: WyrdRuntime) -> void:
	var harness := _Harness.new()
	runtime.dialogue.open_scene("toll.offer_room")
	harness.line_rows(runtime)
	harness.choose_text(runtime, "Take the room")


func _replay_ok(source: WyrdRuntime, prepare: Callable = Callable()) -> void:
	var recorded: Array = source.trace.snapshot()
	var second := _boot()
	_prime(second, prepare)
	WyrdTrace.replay(second, recorded)
	assert_eq(WyrdTrace.diff(recorded, second.trace.events), PackedStringArray())
	assert_eq(_save(source), _save(second))
	var third := _boot()
	_prime(third, prepare)
	WyrdTrace.replay(third, recorded)
	assert_eq(WyrdTrace.diff(recorded, third.trace.events), PackedStringArray())
	assert_eq(_save(source), _save(third))


## A call that undoes earlier work needs that work on the fresh runtime first.
## The setup is not part of the recorded trace.
func _prime(runtime: WyrdRuntime, prepare: Callable) -> void:
	if not prepare.is_valid():
		return
	prepare.call(runtime)
	runtime.trace.clear()


func _repeat(runtime: WyrdRuntime, row: Dictionary) -> void:
	var call := str(row.get("call", ""))
	var args: Array = row.get("args", []) if row.get("args", []) is Array else []
	var dot := call.find(".")
	var target: Object = null
	match call.substr(0, dot):
		"facts":
			target = runtime.facts
		"deeds":
			target = runtime.deeds
		"topics":
			target = runtime.topics
		_:
			return
	if target == null:
		return
	var method := call.substr(dot + 1)
	var passed: Array = []
	for item in args:
		passed.append(item)
	if method == "set_in" and passed.size() >= 2:
		passed[1] = runtime.facts._saved_value(str(passed[0]), passed[1])
		passed[0] = StringName(str(passed[0]))
		if passed.size() >= 3:
			passed[2] = StringName(str(passed[2]))
	elif method == "record" and passed.size() >= 5:
		passed[0] = StringName(str(passed[0]))
		passed[1] = StringName(str(passed[1]))
		passed[2] = StringName(str(passed[2]))
		passed[3] = StringName(str(passed[3]))
		var tags := PackedStringArray()
		if passed[4] is Array:
			for tag in passed[4]:
				tags.append(str(tag))
		passed[4] = tags
		if passed.size() >= 8:
			passed[7] = StringName(str(passed[7]))
	elif method == "unlock" and passed.size() >= 1:
		passed[0] = StringName(str(passed[0]))
	target.callv(method, passed)


func _host_rows(runtime: WyrdRuntime) -> Array:
	var rows: Array = []
	for item in runtime.trace.events:
		if item is Dictionary and String((item as Dictionary).get("kind", "")) == "host_call":
			rows.append(item)
	return rows


func _calls(runtime: WyrdRuntime) -> Array:
	var names: Array = []
	for item in _host_rows(runtime):
		names.append(String((item as Dictionary).get("call", "")))
	return names


func _without_host(events: Array) -> Array:
	var rows: Array = []
	for item in events:
		if item is Dictionary and String((item as Dictionary).get("kind", "")) == "host_call":
			continue
		rows.append(item)
	return rows


func _save(runtime: WyrdRuntime) -> String:
	return JSON.stringify(runtime.save_state())
