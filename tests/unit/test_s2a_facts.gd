extends GutTest


func test_types_perspectives_and_subscribed_signal() -> void:
	var opened := _pack(_STORED)
	var runtime: WyrdRuntime = opened["runtime"]
	var seen: Array = []
	runtime.facts.fact_changed.connect(func(key: StringName, old_value: Variant, new_value: Variant) -> void:
		seen.append([String(key), old_value, new_value])
	)
	runtime.facts.subscribe(&"player")
	runtime.facts.set(&"player.coins", 2)
	runtime.facts.set(&"ferry.toll_coins", 1)
	assert_eq(seen.size(), 1)
	assert_eq(seen[0][0], "player.coins")
	assert_null(seen[0][1])
	assert_eq(seen[0][2], 2)
	runtime.facts.set(&"player.coins", 2)
	assert_eq(seen.size(), 1)
	assert_false(runtime.facts.set_in(&"player.coins", "nope", &"world"))
	assert_push_error("expected int")
	assert_eq(runtime.facts.get(&"player.coins"), 2)
	assert_eq(_kinds(runtime), ["type"])
	assert_true(runtime.facts.set_in(&"player.coins", 9, &"known/player"))
	assert_eq(runtime.facts.get_in(&"player.coins", &"known/player"), 9)
	assert_eq(runtime.facts.get(&"player.coins"), 2)
	assert_false(runtime.facts.set_in(&"player.coins", 1, &"believed/player"))
	assert_push_error("is M5")
	assert_false(runtime.facts.set_in(&"player.coins", 1, &"held/crew"))
	assert_push_error("is M5")
	assert_null(runtime.facts.get_in(&"player.coins", &"believed/player"))
	assert_null(runtime.facts.get_in(&"player.coins", &"held/crew"))
	assert_true(_kinds(runtime).has("m5"))
	assert_false(runtime.facts.set_in(&"world.season", &"storm", &"world"))
	assert_push_error("not writable")
	assert_true(_kinds(runtime).has("resolved"))
	assert_null(runtime.facts.get(&"missing.fact"))


func test_resolvers_events_and_poll() -> void:
	var opened := _pack(_RESOLVED)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.world.add_entity(&"ferry_master", &"person", "Ferry Master", PackedStringArray(), true)
	host.clock.season_name = &"storm"
	host.clock.hour_value = 1
	runtime.tick(0)
	assert_eq(runtime.facts.get(&"npc.ferry_master.alive"), true)
	assert_eq(runtime.facts.get(&"world.season"), &"storm")
	assert_eq(_flag(runtime, "h1", "when"), 0)
	host.clock.season_name = &"calm"
	host.world.add_entity(&"ferry_master", &"person", "Ferry Master", PackedStringArray(), false)
	runtime.tick(0)
	assert_eq(runtime.last_rechecks(), 0)
	assert_eq(runtime.facts.get(&"world.season"), &"storm")
	assert_eq(runtime.facts.get(&"npc.ferry_master.alive"), true)
	runtime.events.emit(&"season_changed", {})
	runtime.facts.invalidate(&"npc.ferry_master.alive")
	runtime.tick(0)
	assert_eq(runtime.facts.get(&"world.season"), &"calm")
	assert_eq(runtime.facts.get(&"npc.ferry_master.alive"), false)
	assert_eq(_flag(runtime, "season", "when"), 0)
	host.clock.hour_value = 20
	runtime.tick(14)
	assert_eq(_flag(runtime, "h1", "when"), 0)
	runtime.tick(1)
	assert_eq(_flag(runtime, "h1", "when"), 1)
	assert_gt(runtime.last_rechecks(), 0)


const _STORED := """
language 1
events
  season_changed()
facts
  player.coins : int stored
  ferry.toll_coins : int stored
  world.season : symbol source: time.season invalidate: on_event(season_changed)
scene room
  when player.coins >= 2: narrator: Paid. #line:paid
  -> end
"""

const _RESOLVED := """
language 1
events
  season_changed()
  entity_alive_changed(entity: symbol, alive: bool)
facts
  npc.{id}.alive : bool source: world.is_alive invalidate: on_event(entity_alive_changed)
  world.season : symbol source: time.season invalidate: on_event(season_changed)
  world.hour : int source: time.hour invalidate: poll(15)
scene room
  when world.season == storm: narrator: Rain. #line:season
  when world.hour > 10: narrator: Late. #line:h1
  when npc.ferry_master.alive: narrator: Here. #line:alive
  -> end
"""


func _pack(body: String) -> Dictionary:
	var path := "user://wyrd_s2a_%d.wyrd" % body.hash()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(body)
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"sample"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(5)
	return {"host": host, "runtime": runtime}


func _kinds(runtime: WyrdRuntime) -> Array:
	var kinds: Array = []
	for row in runtime.trace_log():
		kinds.append(str(row["kind"]))
	return kinds


func _flag(runtime: WyrdRuntime, record: String, site: String) -> int:
	var content := runtime.content()
	for i in content.conditions.size():
		if content.records[i] == record and content.sites[i] == site:
			return int(runtime.condition_flags()[i])
	return -1
