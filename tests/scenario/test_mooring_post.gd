extends GutTest

const _Harness := preload("res://tests/scenario/s2c_harness.gd")
const _QUEST := "mooring_post"


func test_seed_1_picks_a_bollard_and_names_it() -> void:
	var opened := _open(1)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	_start(runtime)
	var picked := String(runtime.roles.slot_holder(_QUEST, &"post"))
	assert_eq(picked, _expect(1))
	assert_ne(picked, "bram")
	assert_ne(picked, "dock.crate")
	var journal: Array = runtime.quests.journal(_QUEST)
	assert_gt(journal.size(), 0)
	var shown := host.world.display_name(StringName(picked))
	assert_eq(str(journal[journal.size() - 1]["text"]), "The %s holds the mooring." % shown)
	runtime.trace.enabled = true
	var lines := _cast_lines(runtime)
	assert_eq(lines.size(), 0)


func test_remove_entity_shows_the_locked_gone_journal() -> void:
	var opened := _open(1)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	_start(runtime)
	var picked := StringName(runtime.roles.slot_holder(_QUEST, &"post"))
	host.world.remove_entity(picked)
	runtime.tick(1)
	assert_eq(runtime.quests.variant_of(_QUEST), "post.locked_gone")
	assert_eq(runtime.roles.slot_state(&"post", _QUEST), &"locked_gone")
	var journal: Array = runtime.quests.journal(_QUEST)
	assert_eq(str(journal[journal.size() - 1]["text"]), "The mooring post is gone.")


func test_save_load_resumes_on_the_unsaved_path() -> void:
	var live := _open(1)
	var live_runtime: WyrdRuntime = live["runtime"]
	_start(live_runtime)
	var picked := String(live_runtime.roles.slot_holder(_QUEST, &"post"))
	var saved := live_runtime.save_state()
	live_runtime.trace.clear()
	(live["host"] as WyrdFakeHost).world.remove_entity(StringName(picked))
	live_runtime.tick(1)
	var unsaved_trace: Array = live_runtime.trace.snapshot()
	var unsaved_facts: Variant = live_runtime.save_state()["facts"]
	var fresh := _open(1)
	var loaded: WyrdRuntime = fresh["runtime"]
	var report := loaded.load_state(JSON.parse_string(JSON.stringify(saved)))
	assert_true(report.ok, report.diagnostics.format())
	loaded.trace.clear()
	(fresh["host"] as WyrdFakeHost).world.remove_entity(StringName(picked))
	loaded.tick(1)
	assert_eq(WyrdTrace.diff(unsaved_trace, loaded.trace.snapshot()), PackedStringArray())
	assert_eq(JSON.stringify(loaded.save_state()["facts"]), JSON.stringify(unsaved_facts))
	assert_eq(loaded.quests.variant_of(_QUEST), "post.locked_gone")
	assert_eq(loaded.facts.get(&"harbor.mooring_check"), true)


func test_trace_replay_matches() -> void:
	var recorded := _traced()
	var again := _traced(recorded)
	assert_eq(WyrdTrace.diff(recorded, again), PackedStringArray())
	assert_true(_has(recorded, "cast"))
	assert_true(_has(recorded, "slot_state"))
	assert_true(_slot_kind(recorded, "cast") != "")
	assert_gt(recorded.size(), 0)


func _open(seed_value: int) -> Dictionary:
	var opened := _Harness.new().open_pack(_Harness.HARBOR)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.world.add_entity(&"dock.bollard_north", &"object", "North Bollard", PackedStringArray(["bollard"]), true)
	host.world.add_entity(&"dock.bollard_south", &"object", "South Bollard", PackedStringArray(["bollard"]), true)
	host.world.add_entity(&"dock.crate", &"object", "crate", PackedStringArray(), true)
	host.world.add_entity(&"bram", &"person", "Bram", PackedStringArray(["bollard"]), true)
	runtime.start_new_game(seed_value)
	runtime.trace.enabled = true
	return opened


func _start(runtime: WyrdRuntime) -> void:
	runtime.facts.set(&"harbor.mooring_check", true)
	# The template conditions share the first tick's wait budget, so the cast lands on the next tick.
	runtime.tick(2)


func _expect(seed_value: int) -> String:
	var ids := ["dock.bollard_north", "dock.bollard_south"]
	ids.sort()
	var rng := WyrdRng.for_decision(seed_value, &"cast", &"mooring_post|post", 2)
	return String(ids[rng.randi_bounded(ids.size())])


func _traced(recorded: Array = []) -> Array:
	var opened := _open(1)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.facts.set(&"harbor.mooring_check", true)
	runtime.trace.clear()
	if recorded.is_empty():
		runtime.tick(2)
	else:
		WyrdTrace.replay(runtime, recorded)
	return runtime.trace.snapshot()


func _cast_lines(runtime: WyrdRuntime) -> Array:
	var rows: Array = []
	for row in runtime.trace.events:
		if String(row.get("kind", "")) == "cast" and String(row.get("quest", "")) != _QUEST:
			rows.append(row)
	return rows


func _has(events: Array, kind: String) -> bool:
	for row in events:
		if String(row.get("kind", "")) == kind:
			return true
	return false


func _slot_kind(events: Array, kind: String) -> String:
	for row in events:
		if String(row.get("kind", "")) == kind:
			return String(row.get("slot_kind", ""))
	return ""
