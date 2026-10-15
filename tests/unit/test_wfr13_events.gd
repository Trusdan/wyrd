extends GutTest

## WFR13 host world events: schema, emit, invalidation, handlers, save, and replay.


func test_schema_accepts_typed_events_and_rejects_bad_ones() -> void:
	var good := _diagnostics(_PACK)
	assert_false(good.has_errors(), good.format())
	var duplicate := _diagnostics("""
		language 1
		events
		  season_changed()
		  season_changed()
		""")
	assert_true(duplicate.format().contains("E_EVENT_DUPLICATE"))
	var bad_type := _diagnostics("""
		language 1
		events
		  item_inserted(item: widget)
		""")
	assert_true(bad_type.format().contains("E_EVENT_TYPE"))
	var bad_shape := _diagnostics("""
		language 1
		events
		  season_changed
		""")
	assert_true(bad_shape.format().contains("E_EVENT_ARG"))
	var unknown := _diagnostics("""
		language 1
		facts
		  world.season : symbol source: time.season invalidate: on_event(season_changed)
		""")
	assert_true(unknown.format().contains("E_EVENT_UNKNOWN"))
	var missing := _diagnostics("""
		language 1
		facts
		  npc.{id}.alive : bool source: world.is_alive
		""")
	assert_true(missing.format().contains("E_RESOLVER_NO_INVALIDATE"))
	var waiting := _diagnostics("""
		language 1
		facts
		  world.weather : symbol source: world.weather invalidate: per_query
		quest gate "Gate"
		  stage wait
		    waits_until world.weather == calm
		    ~ outcome gate = done
		""")
	assert_true(waiting.format().contains("E_WAIT_RESOLVER_MODE"))
	var outside := _diagnostics("""
		language 1
		events
		  season_changed()
		quest gate "Gate"
		  on season_changed where true:
		    ~ outcome gate = done
		  stage wait
		    ~ outcome gate = done
		""")
	assert_true(outside.format().contains("on <event> is only valid in a stage"))
	var field := _diagnostics("""
		language 1
		events
		  mechanism_state(object: symbol, state: symbol, actor: symbol)
		facts
		  harbor.bell_count : int stored
		quest bell "Bell"
		  stage wait
		    on mechanism_state where event.missing == dock_bell:
		      ~ inc harbor.bell_count by 1
		""")
	assert_true(field.format().contains("E_EVENT_ARG"))


func test_pattern_invalidate_drops_every_concrete_cache() -> void:
	var opened := _boot(_PACK)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.world.add_entity(&"ada", &"person", "Ada", PackedStringArray(), true)
	host.world.add_entity(&"ferry_master", &"person", "Bram", PackedStringArray(), true)
	assert_eq(runtime.facts.get(&"npc.ada.alive"), true)
	assert_eq(runtime.facts.get(&"npc.ferry_master.alive"), true)
	host.world.add_entity(&"ada", &"person", "Ada", PackedStringArray(), false)
	host.world.add_entity(&"ferry_master", &"person", "Bram", PackedStringArray(), false)
	assert_eq(runtime.facts.get(&"npc.ada.alive"), true)
	runtime.events.emit(&"entity_alive_changed", {"alive": false, "entity": &"ada"})
	assert_eq(runtime.facts.get(&"npc.ada.alive"), false)
	assert_eq(runtime.facts.get(&"npc.ferry_master.alive"), false)
	var ada: Dictionary = runtime.facts.cache_view("npc.ada.alive")
	assert_eq(str(ada["mode"]), "on_event")
	assert_eq(str(ada["event"]), "entity_alive_changed")
	assert_true(bool(ada["cached"]))


func test_per_query_never_caches_and_rejected_emit_keeps_cache() -> void:
	var opened := _boot(_PACK)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.clock.minutes = 4
	assert_eq(runtime.facts.get(&"world.tick"), 4)
	var before: Dictionary = runtime.facts.cache_view("world.tick")
	assert_false(bool(before["cached"]))
	assert_eq(str(before["mode"]), "per_query")
	host.clock.minutes = 9
	assert_eq(runtime.facts.get(&"world.tick"), 9)
	host.clock.season_name = &"storm"
	assert_eq(runtime.facts.get(&"world.season"), &"storm")
	host.clock.season_name = &"calm"
	runtime.trace.enabled = true
	runtime.events.emit(&"season_changed", {"extra": 1})
	assert_push_error("unknown field")
	assert_eq(runtime.facts.get(&"world.season"), &"storm")
	runtime.events.emit(&"no_such_event", {})
	assert_push_error("unknown event")
	var rejected := 0
	for row in runtime.trace.snapshot():
		if str(row.get("kind", "")) == "emit_rejected":
			rejected += 1
	assert_eq(rejected, 2)


func test_emit_rechecks_only_dependents_in_index_order() -> void:
	var opened := _boot(_PACK)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.trace.enabled = true
	var expected := _indexes_reading(runtime, &"world.season")
	assert_gt(expected.size(), 0)
	assert_lt(expected.size(), runtime.condition_count())
	runtime.events.emit(&"season_changed", {})
	var once := _emit_rechecks(runtime)
	assert_eq(once, expected)
	runtime.trace.clear()
	runtime.events.emit(&"season_changed", {})
	assert_eq(_emit_rechecks(runtime), expected)
	var coins := _indexes_reading(runtime, &"player.coins")
	for index in coins:
		assert_false(once.has(index))


func test_batch_coalesces_one_recheck_wave() -> void:
	var opened := _boot(_PACK)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.trace.enabled = true
	runtime.events.begin_batch()
	runtime.events.begin_batch()
	runtime.events.emit(&"season_changed", {})
	runtime.events.emit(&"season_changed", {})
	runtime.events.end_batch()
	runtime.events.end_batch()
	var begins := 0
	var ends := 0
	var emit_waves := 0
	var end_rechecks: Array = []
	for row in runtime.trace.snapshot():
		var kind := str(row.get("kind", ""))
		if kind == "batch_begin":
			begins += 1
		elif kind == "batch_end":
			ends += 1
			end_rechecks = row.get("rechecks", [])
		elif kind == "emit":
			var rechecks: Array = row.get("rechecks", [])
			emit_waves += rechecks.size()
	assert_eq(begins, 1)
	assert_eq(ends, 1)
	assert_eq(emit_waves, 0)
	assert_eq(end_rechecks, _indexes_reading(runtime, &"world.season"))
	assert_eq(runtime.events.last_wave, 1)


func test_emit_during_a_scene_does_not_abort() -> void:
	var opened := _boot(_PACK)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	runtime.dialogue.open_scene("room")
	assert_eq(runtime.dialogue.line().text, "Hello.")
	host.clock.season_name = &"storm"
	runtime.events.emit(&"season_changed", {})
	assert_true(runtime.dialogue.is_open())
	assert_eq(runtime.dialogue.line().text, "Hello.")
	runtime.dialogue.advance()
	assert_eq(runtime.dialogue.line().text, "Rain.")


func test_on_handler_fires_once_and_wait_wakes() -> void:
	var opened := _boot(_PACK)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	runtime.facts.set(&"player.coins", 2)
	runtime.tick(0)
	assert_eq(runtime.quests.stage("bell"), "wait")
	assert_eq(runtime.quests.stage("gate"), "wait")
	runtime.events.emit(&"mechanism_state", {"actor": &"player", "object": &"dock_bell", "state": &"struck"})
	assert_eq(runtime.facts.get(&"harbor.bell_count"), 1)
	assert_eq(runtime.facts.get(&"harbor.bell_struck"), true)
	assert_null(runtime.facts.get(&"harbor.other"))
	assert_eq(runtime.quests.stage("bell"), "struck")
	assert_eq(runtime.quests.outcome("bell", "bell"), "done")
	runtime.events.emit(&"mechanism_state", {"actor": &"player", "object": &"dock_bell", "state": &"struck"})
	assert_eq(runtime.facts.get(&"harbor.bell_count"), 1)
	host.clock.season_name = &"storm"
	runtime.events.emit(&"season_changed", {})
	assert_eq(runtime.quests.stage("gate"), "done")
	assert_eq(runtime.quests.outcome("gate", "gate"), "done")


func test_save_omits_events_and_replay_includes_emits() -> void:
	var opened := _boot(_PACK)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.clock.season_name = &"storm"
	runtime.facts.get(&"world.season")
	runtime.events.emit(&"season_changed", {})
	assert_gt(runtime.events.recent.size(), 0)
	var saved := runtime.save_state()
	assert_false(saved.has("events"))
	host.clock.season_name = &"calm"
	var report := runtime.load_state(saved)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(runtime.events.recent.size(), 0)
	var cold: Dictionary = runtime.facts.cache_view("world.season")
	assert_false(bool(cold["cached"]))
	assert_eq(runtime.facts.get(&"world.season"), &"calm")
	var recorded := _traced_emit()
	assert_push_error("unknown event")
	var again := _traced_replay(recorded)
	assert_push_error("unknown event")
	assert_eq(WyrdTrace.diff(recorded, again), PackedStringArray())
	assert_true(runtime.debug_dump().contains("cache"))


func _traced_emit() -> Array:
	var opened := _boot(_PACK)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.trace.enabled = true
	runtime.events.begin_batch()
	runtime.events.emit(&"season_changed", {})
	runtime.events.emit(&"nope", {})
	runtime.events.end_batch()
	return runtime.trace.snapshot()


func _traced_replay(recorded: Array) -> Array:
	var opened := _boot(_PACK)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.trace.enabled = true
	WyrdTrace.replay(runtime, recorded)
	return runtime.trace.snapshot()


func _indexes_reading(runtime: WyrdRuntime, key: StringName) -> Array:
	var hits: Array = []
	var content := runtime.content()
	for i in runtime.condition_count():
		var cond := content.conditions[i]
		if cond != null and cond.reads.has(key):
			hits.append(i)
	return hits


func _emit_rechecks(runtime: WyrdRuntime) -> Array:
	var found: Array = []
	for row in runtime.trace.snapshot():
		if str(row.get("kind", "")) == "emit":
			found = row.get("rechecks", [])
	return found


func _boot(body: String) -> Dictionary:
	var path := "user://wyrd_wfr13_%d.wyrd" % body.hash()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(body.strip_edges() + "\n")
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


func _diagnostics(body: String) -> WyrdDiagnostics:
	var lines := PackedStringArray()
	for line in body.strip_edges().split("\n"):
		if line.begins_with("\t\t"):
			lines.append(line.substr(2))
		else:
			lines.append(line)
	var path := "user://wyrd_wfr13_diag_%d.wyrd" % body.hash()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	file.close()
	var diagnostics := WyrdDiagnostics.new()
	WyrdPack.compile(PackedStringArray([path]), "sample", 1, null, diagnostics, path, true)
	return diagnostics


const _PACK := """
language 1
events
  season_changed()
  entity_alive_changed(entity: symbol, alive: bool)
  mechanism_state(object: symbol, state: symbol, actor: symbol)
facts
  player.coins : int stored
  harbor.bell_struck : bool stored
  harbor.bell_count : int stored
  harbor.other : int stored
  world.season : symbol source: time.season invalidate: on_event(season_changed)
  world.tick : int source: time.now_minutes invalidate: per_query
  npc.{id}.alive : bool source: world.is_alive invalidate: on_event(entity_alive_changed)
quest bell "Bell"
  start when player.coins >= 0
  stage wait
    waits_until harbor.bell_struck
    on mechanism_state where event.object == other and event.state == struck:
      ~ inc harbor.other by 5
      -> struck
    on mechanism_state where event.object == dock_bell and event.state == struck:
      ~ set harbor.bell_struck = true
      ~ inc harbor.bell_count by 1
      -> struck
  stage struck
    ~ outcome bell = done
quest gate "Gate"
  start when player.coins >= 0
  stage wait
    waits_until world.season == storm
    -> done
  stage done
    ~ outcome gate = done
scene room
  narrator: Hello. #line:hello
  when world.season == storm: narrator: Rain. #line:rain
  when player.coins > 0: narrator: Paid. #line:paid
  when npc.ada.alive: narrator: Here. #line:ada
  -> end
"""
