extends GutTest

## Direct coverage for the S2a store, queue, events, config, and load refusal.


func test_resolvers_invalidation_and_poll() -> void:
	var clock := {"now": 0}
	var world := WyrdFakeWorld.new()
	var time := WyrdFakeTime.new()
	world.add_entity(&"ada", &"person", "Ada", PackedStringArray(), true)
	time.season_name = &"storm"
	time.hour_value = 1
	time.minutes = 4
	var store := _store(clock, world, time)
	var notified: Array = []
	store.on_keys = func(keys: PackedStringArray) -> void: notified.append(keys.duplicate())
	assert_eq(store.get_in(&"npc.ada.alive"), true)
	world.add_entity(&"ada", &"person", "Ada", PackedStringArray(), false)
	assert_eq(store.get_in(&"npc.ada.alive"), true)
	store.invalidate(&"npc")
	assert_eq(store.get_in(&"npc.ada.alive"), false)
	assert_true(str(notified[0]).contains("npc.ada.alive"))
	assert_eq(store.get_in(&"world.season"), &"storm")
	time.season_name = &"calm"
	assert_eq(store.get_in(&"world.season"), &"storm")
	store.invalidate_event(&"season_changed")
	assert_eq(store.get_in(&"world.season"), &"calm")
	assert_eq(store.get_in(&"world.hour"), 1)
	time.hour_value = 9
	store.refresh_poll(9)
	assert_eq(store.get_in(&"world.hour"), 1)
	store.refresh_poll(10)
	assert_eq(store.get_in(&"world.hour"), 9)
	assert_eq(store.get_in(&"world.tick"), 4)
	time.minutes = 11
	assert_eq(store.get_in(&"world.tick"), 11)
	assert_null(store.get_in(&"npc.{id}.alive"))
	assert_null(store.get_in(&"missing.resolver"))
	assert_push_error("not on an adapter")
	assert_null(store.get_in(&"missing.resolver"))
	assert_null(store.get_in(&"bare"))
	assert_push_error("missing an adapter")


func test_subscribe_set_in_and_missing_facts() -> void:
	var store := _store({"now": 0}, WyrdFakeWorld.new(), WyrdFakeTime.new())
	var seen: Array = []
	store.fact_changed.connect(func(key: StringName, old_value: Variant, new_value: Variant) -> void:
		seen.append([String(key), old_value, new_value])
	)
	store.subscribe(&"player")
	assert_null(store.get_in(&"player.coins"))
	assert_true(store.set_in(&"player.coins", 2, &"world"))
	assert_eq(seen.size(), 1)
	assert_eq(seen[0], ["player.coins", null, 2])
	assert_true(store.set_in(&"player.coins", 2, &"world"))
	assert_eq(seen.size(), 1)
	assert_true(store.set_in(&"meter.level", 3, &"world"))
	assert_eq(store.get_in(&"meter.level"), 3.0)
	assert_eq(seen.size(), 1)
	store.subscribe(&"")
	assert_true(store.set_in(&"meter.level", 4.5, &"world"))
	assert_eq(seen.size(), 2)
	assert_true(store.set_in(&"mood.tone", "storm", &"known/player"))
	assert_eq(store.get_in(&"mood.tone", &"known/player"), &"storm")
	assert_null(store.get_in(&"mood.tone", &"world"))
	assert_null(store.get_in(&"mood.tone", &"known/clerk"))
	assert_true(store.remember(&"role.keeper.holder", &"ada", &"known/player"))
	assert_eq(store.get_in(&"role.keeper.holder", &"known/player"), &"ada")
	assert_false(store.remember(&"role.keeper.holder", &"ada", &"world"))
	assert_push_error("remember only writes known")
	assert_false(store.set_in(&"player.coins", "nope", &"world"))
	assert_push_error("expected int")
	assert_eq(store.get_in(&"player.coins"), 2)
	assert_false(store.set_in(&"player.coins", 1, &"believed/player"))
	assert_push_error("is M5")
	assert_false(store.set_in(&"player.coins", 1, &"held/crew"))
	assert_push_error("is M5")
	assert_false(store.set_in(&"player.coins", 1, &"known/"))
	assert_push_error("unknown perspective")
	assert_false(store.set_in(&"npc.{id}.alive", true, &"world"))
	assert_push_error("not a concrete")
	assert_false(store.set_in(&"no.such", 1, &"world"))
	assert_push_error("no schema")
	assert_false(store.set_in(&"world.season", &"calm", &"world"))
	assert_push_error("not writable")
	var schema := store._schema
	store.clear_values()
	assert_null(store.get_in(&"player.coins"))
	var eval := WyrdRpnEval.new()
	eval.fact_reader = func(key: String) -> Variant: return store.get_in(StringName(key))
	for text in ["player.coins > 0", "player.coins == 0", "player.coins != 0", "player.coins >= 0"]:
		var compiled := WyrdCondition.new().compile(text, schema, WyrdDiagnostics.new(), "sample.wyrd", 1, 1)
		assert_eq(eval.eval(compiled, {}), false, text)


func test_tick_queue_budget_order_and_unwatch() -> void:
	var queue := WyrdTickQueue.new()
	var ran: Array = []
	queue.watch(5)
	queue.watch(1)
	queue.watch(3)
	assert_eq(queue.tick(2, func(index: int) -> void: ran.append(index)), 2)
	assert_eq(ran, [1, 3])
	assert_eq(queue.dirty_count(), 1)
	assert_eq(queue.last_rechecks, 2)
	assert_eq(queue.tick(0, func(index: int) -> void: ran.append(index)), 0)
	assert_eq(queue.dirty_count(), 1)
	assert_eq(queue.last_rechecks, 0)
	queue.unwatch(5)
	assert_eq(queue.dirty_count(), 0)
	queue.mark(PackedInt32Array([1, 99]))
	assert_eq(queue.dirty_count(), 1)
	ran.clear()
	assert_eq(queue.tick(8, func(index: int) -> void: ran.append(index)), 1)
	assert_eq(ran, [1])
	queue.watch(4)
	queue.clear()
	assert_eq(queue.dirty_count(), 0)
	assert_eq(queue.last_rechecks, 0)
	assert_eq(queue.tick(4, func(_index: int) -> void: pass), 0)


func test_events_and_config() -> void:
	var events := WyrdEvents.new()
	events.emit(&"season_changed", {"from": &"storm"})
	var seen: Array = []
	events.on_emit = func(name: StringName, payload: Dictionary) -> void: seen.append([String(name), payload])
	events.emit(&"season_changed", {"from": &"calm"})
	assert_eq(seen.size(), 1)
	assert_eq(seen[0][0], "season_changed")
	assert_eq(seen[0][1]["from"], &"calm")
	var cfg := WyrdConfig.new()
	assert_eq(cfg.hour_bucket_minutes, 60)
	assert_eq(cfg.disposition_default, 50)
	assert_eq(cfg.hostile_threshold, 20)
	assert_eq(cfg.scheduler_work_per_tick, 64)
	assert_eq(cfg.half_life_for(&"gift"), 0.0)
	cfg.half_life_verbs = PackedStringArray(["gift", "insult"])
	cfg.half_life_minutes = PackedFloat64Array([30.0])
	assert_eq(cfg.half_life_for(&"gift"), 30.0)
	assert_eq(cfg.half_life_for(&"insult"), 0.0)
	cfg.set_axis_delta(&"gift", &"affinity", 4.0)
	cfg.set_axis_delta(&"gift", &"affinity", 6.0)
	assert_eq(cfg.axis_delta(&"gift", &"affinity"), 6.0)
	cfg.axis_verbs.append("gift")
	cfg.axis_names.append("affinity")
	cfg.axis_deltas.append(1.5)
	assert_eq(cfg.axis_delta(&"gift", &"affinity"), 7.5)


func test_load_refuses_null_empty_and_errors_but_keeps_warnings() -> void:
	var runtime := WyrdRuntime.new()
	var refused := runtime.load_content(null)
	assert_false(refused.ok)
	assert_eq(refused.manifest_hash, 0)
	assert_null(runtime.content())
	assert_gt(refused.error_count(), 0)
	var empty := WyrdContentManifest.new()
	empty.pack_id = &"empty"
	var no_files := runtime.load_content(empty)
	assert_false(no_files.ok)
	assert_true(no_files.diagnostics.format().contains("no files"))
	var good := _load_body(runtime, _GOOD, &"good")
	assert_true(good.ok, good.diagnostics.format())
	runtime.facts.set(&"player.coins", 3)
	var warned := _load_body(runtime, _WARN, &"warn")
	assert_true(warned.ok, warned.diagnostics.format())
	assert_eq(warned.error_count(), 0)
	assert_true(warned.diagnostics.format().contains("W_EMPTY_UNCOVERED"))
	assert_eq(runtime.content().pack_id, "warn")
	assert_null(runtime.facts.get(&"player.coins"))
	var broken := _load_body(runtime, "this is not a content file\n", &"broken")
	assert_false(broken.ok)
	assert_eq(broken.manifest_hash, 0)
	assert_null(runtime.content())
	assert_eq(runtime.condition_count(), 0)


const _GOOD := """
language 1
facts
  player.coins : int stored
quest gate "Gate"
  slot keeper = dock_keeper mode: live
  on_empty: wait
  stage arrive
    -> done
  stage done
"""

const _WARN := """
language 1
quest gate "Gate"
  slot keeper = dock_keeper mode: live
  stage arrive
    scene room with keeper
    -> done
  stage done
scene room
  narrator: Waiting. #line:room
  -> end
"""


func _load_body(runtime: WyrdRuntime, body: String, pack_id: StringName) -> WyrdLoadReport:
	var path := "user://wyrd_s2a_store_%s.wyrd" % String(pack_id)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(body)
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = pack_id
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	return runtime.load_content(manifest)


func _store(clock: Dictionary, world: WyrdFakeWorld, time: WyrdFakeTime) -> WyrdFactStore:
	var schema := WyrdFactSchema.new()
	for fact in [
		_fact("player.coins", &"int", &"stored"),
		_fact("meter.level", &"float", &"stored"),
		_fact("mood.tone", &"symbol", &"stored"),
		_fact("npc.{id}.alive", &"bool", &"resolved", "world.is_alive", &"manual"),
		_fact("world.season", &"symbol", &"resolved", "time.season", &"on_event", "season_changed"),
		_fact("world.hour", &"int", &"resolved", "time.hour", &"poll", "10"),
		_fact("world.tick", &"int", &"resolved", "time.now_minutes", &"per_query"),
		_fact("missing.resolver", &"bool", &"resolved", "missing.thing"),
		_fact("bare", &"int", &"resolved", "noseparator"),
	]:
		schema.entries.append(fact)
	var store := WyrdFactStore.new()
	store.bind_schema(schema)
	store.clock = func() -> int: return int(clock["now"])
	store.resolver_of = func(head: String) -> Object:
		if head == "world":
			return world
		if head == "time":
			return time
		return null
	return store


func _fact(key: String, type_name: StringName, origin: StringName, resolver: String = "", invalidate: StringName = &"", arg: String = "") -> WyrdFact:
	var fact := WyrdFact.new()
	fact.key = key
	fact.segments = PackedStringArray(key.split("."))
	fact.type_name = type_name
	fact.origin = origin
	fact.resolver = resolver
	fact.invalidate = invalidate
	fact.invalidate_arg = arg
	fact.valid = true
	return fact
