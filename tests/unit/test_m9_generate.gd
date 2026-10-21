extends GutTest

const MANIFEST := "res://tests/support/m9_generate.wyrdmanifest.tres"


class UnsortedWorld extends WyrdWorldAdapter:
	var inner := WyrdFakeWorld.new()
	var order: Array[String] = []

	func add_entity(id: StringName, entity_kind: StringName, entity_name: String, entity_tags: PackedStringArray, alive: bool) -> void:
		order.append(String(id))
		inner.add_entity(id, entity_kind, entity_name, entity_tags, alive)

	func candidates(filter: WyrdEntityFilter) -> PackedStringArray:
		var rows := PackedStringArray()
		for id in order:
			var who := StringName(id)
			if not inner.exists(who):
				continue
			if filter != null and filter.kind != &"" and inner.kind(who) != filter.kind:
				continue
			if filter != null and filter.tag != &"" and not inner.tags(who).has(String(filter.tag)):
				continue
			rows.append(id)
		return rows

	func exists(id: StringName) -> bool:
		return inner.exists(id)

	func kind(id: StringName) -> StringName:
		return inner.kind(id)

	func tags(id: StringName) -> PackedStringArray:
		return inner.tags(id)

	func attr(id: StringName, key: StringName) -> Variant:
		return inner.attr(id, key)

	func is_alive(id: StringName) -> bool:
		return inner.is_alive(id)

	func display_name(id: StringName) -> String:
		return inner.display_name(id)

	func members(faction: StringName) -> PackedStringArray:
		return inner.members(faction)

	func groups_of(agent: StringName) -> PackedStringArray:
		return inner.groups_of(agent)


func test_each_instance_reads_its_own_cast() -> void:
	var opened := _open(4)
	var runtime: WyrdRuntime = opened["runtime"]
	_people(opened["host"])
	var ada := runtime.quests.create_instance("errand", {"courier": "ada", "partner": "ada"}, {"parcel": "parcel.a", "site": "dock.a"})
	var bram := runtime.quests.create_instance("errand", {"courier": "bram", "partner": "bram"}, {"parcel": "parcel.b", "site": "dock.b"})
	var empty := runtime.quests.create_instance("errand", {"courier": "", "partner": ""}, {"parcel": "parcel.a", "site": "dock.a"})
	runtime.tick(0)
	assert_eq(ada, "errand#1")
	assert_eq(bram, "errand#2")
	assert_eq(empty, "errand#3")
	assert_eq(runtime.quests.status(ada), &"completed")
	assert_eq(runtime.quests.status(bram), &"active")
	assert_eq(runtime.quests.status(empty), &"active")
	assert_eq(_journal(runtime, ada), "The courier is Ada.")
	assert_eq(_journal(runtime, bram), "The courier is Bram.")
	assert_eq(_journal(runtime, empty), "The courier is {?holder(courier).name}.")
	assert_eq(_eval_value(runtime, ada, "holder(courier)"), "ada")
	assert_eq(_eval_value(runtime, bram, "holder(courier)"), "bram")
	assert_eq(_eval_value(runtime, empty, "holder(courier)"), "")
	assert_true(_eval_bool(runtime, ada, "filled(courier)"))
	assert_true(_eval_bool(runtime, bram, "filled(courier)"))
	assert_false(_eval_bool(runtime, empty, "filled(courier)"))
	assert_eq(_eval_value(runtime, ada, "slot_state(courier)"), "default")
	assert_eq(_eval_value(runtime, bram, "slot_state(courier)"), "default")
	assert_eq(_eval_value(runtime, empty, "slot_state(courier)"), "empty")
	assert_eq(_deed_targets(runtime, "delivery"), ["ada", "bram", ""])
	assert_eq(String(runtime.roles.holder(&"courier")), "ada")


func test_params_and_assumes_read_the_instance() -> void:
	var opened := _open(4)
	var runtime: WyrdRuntime = opened["runtime"]
	_people(opened["host"])
	var live := runtime.quests.create_instance("errand", {"courier": "ada", "partner": "ada"}, {"parcel": "parcel.a", "site": "dock.a"})
	(opened["host"] as WyrdFakeHost).world.add_entity(&"parcel.dead", &"item", "Dead", PackedStringArray(["parcel"]), false)
	var dead := runtime.quests.create_instance("errand", {"courier": "bram", "partner": "bram"}, {"parcel": "parcel.dead", "site": "dock.b"})
	var assumes: WyrdCompiledCondition = (runtime.content().templates["errand"] as WyrdTemplateDef).assumes
	runtime.push_scope(live)
	assert_eq(_text(runtime.eval_value(_compile_value(runtime, "holder(parcel)"))), "parcel.a")
	assert_true(runtime.eval_bool(assumes))
	runtime.pop_scope()
	runtime.push_scope(dead)
	assert_eq(_text(runtime.eval_value(_compile_value(runtime, "holder(parcel)"))), "parcel.dead")
	assert_false(runtime.eval_bool(assumes))
	runtime.pop_scope()


func test_chance_keys_are_per_instance() -> void:
	var opened := _open(3)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.trace.enabled = true
	runtime.quests.create_instance("roll")
	runtime.quests.create_instance("roll")
	runtime.quests.start("clock")
	var roll := _choice(runtime, "roll.bet")
	var clock := _choice(runtime, "clock.bet")
	runtime.trace.clear()
	runtime.push_scope("roll#1")
	runtime.eval_bool(roll)
	runtime.pop_scope()
	runtime.push_scope("roll#2")
	runtime.eval_bool(roll)
	runtime.pop_scope()
	runtime.eval_bool(clock)
	var keys := _roll_keys(runtime)
	assert_true(keys.has("roll#1:choice"))
	assert_true(keys.has("roll#2:choice"))
	assert_true(keys.has("clock.bet:choice"))
	for key in keys:
		if String(key).begins_with("clock"):
			assert_false(String(key).contains("#"))
	var differed := false
	for seed in range(1, 24):
		var left := _chance_pass(seed, "roll#1")
		var right := _chance_pass(seed, "roll#2")
		if left != right:
			differed = true
			break
	assert_true(differed)


func test_hand_written_slots_still_use_the_primary_row() -> void:
	var opened := _open(4)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.world.add_entity(&"ada", &"object", "Ada", PackedStringArray(["guide_a"]), true)
	host.world.add_entity(&"bram", &"object", "Bram", PackedStringArray(["guide_b"]), true)
	runtime.quests.start("alpha")
	runtime.quests.start("beta")
	assert_eq(runtime.roles.slot_holder("alpha", &"guide"), &"ada")
	assert_eq(runtime.roles.slot_holder("beta", &"guide"), &"bram")
	assert_eq(runtime.roles.holder(&"guide"), &"ada")
	assert_eq(_text(runtime.eval_value(_compile_value(runtime, "holder(guide)"))), "ada")


func test_pick_ranks_priority_then_specificity_then_weight() -> void:
	var opened := _open(4)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.trace.enabled = true
	runtime.facts.set(&"guild.urgent", true)
	runtime.facts.set(&"guild.open", true)
	runtime.facts.set(&"guild.favor", true)
	var urgent := runtime.generator.propose({"key": "rank", "source": "host"})
	assert_eq(urgent.template, "urgent")
	assert_eq(_pick(runtime).get("score"), "3/1")
	runtime.facts.set(&"guild.urgent", false)
	var specific := runtime.generator.propose({"key": "rank", "source": "host"})
	assert_eq(specific.template, "specific")
	assert_eq(_pick(runtime).get("score"), "1/2")
	var first := _band_pick(11)
	var again := _band_pick(11)
	assert_eq(first, again)
	assert_true(first == "light" or first == "heavy")
	var saw_light := false
	var saw_heavy := false
	for seed in range(1, 40):
		var picked := _band_pick(seed)
		if picked == "light":
			saw_light = true
		if picked == "heavy":
			saw_heavy = true
	assert_true(saw_light)
	assert_true(saw_heavy)
	runtime.facts.set(&"guild.open", false)
	runtime.facts.set(&"guild.favor", false)
	runtime.facts.set(&"guild.silent", true)
	assert_null(runtime.generator.propose({"key": "silent", "source": "host"}))
	assert_eq(String(_propose_row(runtime).get("reason")), "no_template")
	runtime.facts.set(&"guild.silent", false)
	runtime.config().pressure_tiers = PackedStringArray(["low", "mid", "high"])
	runtime.facts.set(&"guild.tiered", true)
	assert_null(runtime.generator.propose({"key": "low", "source": "host", "tier": "low"}))
	assert_eq(String(_propose_row(runtime).get("reason")), "no_template")
	var mid := runtime.generator.propose({"key": "mid", "source": "host", "tier": "mid"})
	assert_eq(mid.template, "tiered")
	runtime.facts.set(&"guild.tiered", false)
	runtime.facts.set(&"guild.urgent", true)
	runtime.facts.set(&"guild.deed", true)
	var host_pick := runtime.generator.propose({"key": "host", "source": "host"})
	assert_eq(host_pick.template, "urgent")
	runtime.trace.clear()
	runtime.deeds.record(&"theft", &"bram", &"player", &"slip")
	assert_eq(runtime.generator.pending_count(), 0)
	runtime.deeds.record(&"theft", &"bram", &"clerk", &"slip")
	assert_eq(runtime.generator.pending_count(), 1)
	var entry: Dictionary = runtime.generator.take_next()
	assert_eq(String(entry["template"]), "deeded")
	runtime.generator.fulfill(entry)
	assert_eq(String(_pick(runtime).get("template")), "deeded")
	runtime.facts.set(&"guild.urgent", false)
	runtime.facts.set(&"guild.deed", false)
	runtime.facts.set(&"guild.capped", true)
	runtime.generator.finish_reservations()
	runtime.trace.clear()
	runtime.generator.fulfill({"key": "one", "origin": "host", "payload": {}, "source": &"host", "template": "", "tier": &""})
	runtime.generator.fulfill({"key": "two", "origin": "host", "payload": {}, "source": &"host", "template": "", "tier": &""})
	assert_eq(runtime.generator.pending_creations().size(), 1)
	assert_eq(runtime.quests.active_count("capped"), 0)
	assert_eq(String(_pick(runtime).get("reason")), "no_template")
	var created := runtime.generator.accept(runtime.generator.pending_creations()[0])
	assert_eq(created, "capped#1")
	runtime.trace.clear()
	runtime.generator.fulfill({"key": "three", "origin": "host", "payload": {}, "source": &"host", "template": "", "tier": &""})
	assert_eq(runtime.quests.active_count("capped"), 1)
	assert_null(runtime.generator.proposal("p99"))
	assert_eq(String(_pick(runtime).get("reason")), "no_template")
	assert_null(runtime.generator.propose({"key": "none", "source": "host"}))


func test_cast_and_bind_sort_scope_and_snapshot() -> void:
	var seed := _sorted_seed()
	var opened := _open(seed)
	var runtime: WyrdRuntime = opened["runtime"]
	var world := UnsortedWorld.new()
	world.add_entity(&"bram", &"object", "Bram", PackedStringArray(["runner"]), true)
	world.add_entity(&"ada", &"object", "Ada", PackedStringArray(["runner"]), true)
	world.add_entity(&"parcel.a", &"item", "Parcel", PackedStringArray(["parcel"]), true)
	world.add_entity(&"dock.a", &"object", "Bollard", PackedStringArray(["bollard"]), true)
	runtime.register_adapter(WyrdWorldAdapter, world)
	var host: WyrdFakeHost = opened["host"]
	host.inventory.set_owner(&"parcel.a", &"player")
	host.spatial.set_place(&"dock.a", &"slip")
	host.spatial.set_place(&"parcel.a", &"bench")
	runtime.facts.set(&"guild.errand", true)
	runtime.trace.enabled = true
	var proposal := runtime.generator.propose({"key": "cast", "source": "host"})
	assert_not_null(proposal)
	assert_eq(String(proposal.casts["courier"]), "ada")
	assert_eq(String(proposal.casts["partner"]), "ada")
	var parcel: Dictionary = proposal.params["parcel"]
	var site: Dictionary = proposal.params["site"]
	assert_eq(String(parcel["entity"]), "parcel.a")
	assert_eq(String(parcel["owner"]), "player")
	assert_eq(String(parcel["place"]), "bench")
	assert_eq(String(site["entity"]), "dock.a")
	assert_eq(String(site["place"]), "slip")
	assert_false(site.has("owner"))
	assert_eq(runtime.quests.template_counter("gap"), 0)
	runtime.facts.set(&"guild.errand", false)
	runtime.facts.set(&"guild.gap", true)
	runtime.trace.clear()
	assert_null(runtime.generator.propose({"key": "gap", "source": "host"}))
	assert_eq(runtime.quests.template_counter("gap"), 0)
	assert_eq(String(_propose_row(runtime).get("reason")), "no_candidate")
	assert_eq(_rows(runtime, "gen_cast").size(), 1)
	assert_eq(String(_rows(runtime, "gen_cast")[0]["slot"]), "courier")


func test_proposals_accept_stale_and_reset() -> void:
	var opened := _open(4)
	var runtime: WyrdRuntime = opened["runtime"]
	_people(opened["host"])
	runtime.facts.set(&"guild.errand", true)
	var first := runtime.generator.propose({"key": "a", "source": "host"})
	var second := runtime.generator.propose({"key": "b", "source": "host"})
	assert_eq(first.id, "p1")
	assert_eq(second.id, "p2")
	assert_eq(runtime.generator.accept(first), "errand#1")
	assert_eq(runtime.generator.accept(first), "accepted")
	assert_eq(runtime.generator.accept(second), "stale")
	var ghost := WyrdProposal.new()
	ghost.id = "p9"
	assert_eq(runtime.generator.accept(ghost), "unknown")
	assert_eq(runtime.generator.accept(null), "unknown")
	runtime.start_new_game(4)
	assert_null(runtime.generator.proposal("p1"))
	runtime.facts.set(&"guild.band", true)
	var restarted := runtime.generator.propose({"key": "c", "source": "host"})
	assert_eq(restarted.id, "p1")
	var saved := JSON.stringify(runtime.save_state(), "\t", true)
	var parsed: Variant = JSON.parse_string(saved)
	var fresh := _open(4)
	var loaded: WyrdRuntime = fresh["runtime"]
	assert_true(loaded.load_state(parsed).ok)
	assert_null(loaded.generator.proposal("p1"))
	loaded.facts.set(&"guild.band", true)
	assert_eq(loaded.generator.propose({"key": "d", "source": "host"}).id, "p1")


func test_background_creation_waits_until_the_next_tick() -> void:
	var opened := _open(4)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.world.add_entity(&"ada", &"object", "Ada", PackedStringArray(["runner"]), true)
	host.world.add_entity(&"parcel.a", &"item", "Parcel", PackedStringArray(["parcel"]), true)
	host.world.add_entity(&"dock.a", &"object", "Bollard", PackedStringArray(["bollard"]), true)
	host.inventory.set_owner(&"parcel.a", &"player")
	host.spatial.set_place(&"dock.a", &"slip")
	host.spatial.set_place(&"parcel.a", &"bench")
	runtime.quests.start("beat")
	runtime.facts.set(&"guild.tick", true)
	runtime.facts.set(&"guild.errand", true)
	runtime.config().scheduler_share_generate = 64
	runtime.trace.enabled = true
	assert_true(runtime.generator.offer(&"guild", "one", &"", {}))
	assert_true(runtime.generator.offer(&"guild", "two", &"", {}))
	runtime.trace.clear()
	runtime.tick(0)
	var create_at := _index(runtime, "gen_create", "errand#1")
	var beat_at := _status_at(runtime, "beat", "completed")
	assert_gt(create_at, beat_at)
	assert_eq(runtime.quests.status("errand#1"), &"active")
	assert_eq(runtime.quests.status("errand#2"), &"active")
	assert_true(runtime.quests.waiting_reason("errand#1").begins_with("waits_until"))
	assert_eq(runtime.generator.pending_count(), 0)
	runtime.tick(0)
	assert_eq(runtime.quests.status("errand#1"), &"completed")
	var other := _open(_split_seed())
	var split: WyrdRuntime = other["runtime"]
	var world := UnsortedWorld.new()
	world.add_entity(&"bram", &"object", "Bram", PackedStringArray(["runner"]), true)
	world.add_entity(&"ada", &"object", "Ada", PackedStringArray(["runner"]), true)
	world.add_entity(&"parcel.a", &"item", "Parcel", PackedStringArray(["parcel"]), true)
	world.add_entity(&"dock.a", &"object", "Bollard", PackedStringArray(["bollard"]), true)
	split.register_adapter(WyrdWorldAdapter, world)
	split.facts.set(&"guild.errand", true)
	split.config().scheduler_share_generate = 64
	assert_true(split.generator.offer(&"guild", "one", &"", {}))
	assert_true(split.generator.offer(&"guild", "two", &"", {}))
	split.tick(0)
	assert_ne(String(split.roles.slot_holder("errand#1", &"courier")), String(split.roles.slot_holder("errand#2", &"courier")))


func test_generate_handler_spills_one_unit_and_defers_the_wait() -> void:
	var opened := _open(4)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.facts.set(&"guild.band", true)
	runtime.trace.enabled = true
	assert_true(runtime.generator.offer(&"guild", "toll", &"", {}))
	runtime.trace.clear()
	runtime.tick(0)
	assert_eq(runtime.generator.pending_count(), 0)
	assert_eq(_generate_units(runtime), 1)
	var id := _accepted(runtime)
	assert_true(id == "light#1" or id == "heavy#1")
	assert_eq(runtime.quests.status(id), &"active")
	assert_true(runtime.quests.waiting_reason(id).begins_with("waits_until"))
	for key in _roll_keys(runtime):
		assert_false(String(key).contains("#"))
	runtime.tick(0)
	assert_eq(runtime.quests.status(id), &"completed")


func test_save_keeps_params_and_resets_proposals() -> void:
	var opened := _open(4)
	var runtime: WyrdRuntime = opened["runtime"]
	_people(opened["host"])
	runtime.facts.set(&"guild.errand", true)
	runtime.config().scheduler_share_generate = 64
	runtime.generator.offer(&"guild", "save", &"", {})
	runtime.tick(0)
	var before := JSON.stringify(runtime.quests.export_generator())
	assert_true(before.contains("params"))
	var text := JSON.stringify(runtime.save_state(), "\t", true)
	var parsed: Variant = JSON.parse_string(text)
	var loaded := _open(9)
	var fresh: WyrdRuntime = loaded["runtime"]
	assert_true(fresh.load_state(parsed).ok)
	assert_eq(JSON.stringify(fresh.quests.export_generator()), before)
	assert_eq(fresh.roles.slot_holder("errand#1", &"courier"), runtime.roles.slot_holder("errand#1", &"courier"))
	assert_eq(fresh.quests.param_entity("errand#1", "parcel"), runtime.quests.param_entity("errand#1", "parcel"))
	assert_null(fresh.generator.proposal("p1"))
	fresh.facts.set(&"guild.errand", false)
	fresh.facts.set(&"guild.band", true)
	var next := fresh.generator.propose({"key": "next", "source": "host"})
	assert_not_null(next)
	assert_eq(next.id, "p1")
	var bare := _open(4)
	var empty_save: Dictionary = (bare["runtime"] as WyrdRuntime).save_state()
	assert_false(empty_save.has("generator"))
	var stripped: Dictionary = parsed
	((stripped["generator"] as Dictionary)["instances"] as Dictionary)["errand#1"].erase("params")
	var again := _open(4)
	var restored: WyrdRuntime = again["runtime"]
	assert_true(restored.load_state(stripped).ok)
	assert_eq(restored.quests.param_entity("errand#1", "parcel"), &"")
	assert_ne(restored.roles.slot_holder("errand#1", &"courier"), &"")


func test_host_offer_propose_and_accept_replay() -> void:
	var opened := _open(4)
	var runtime: WyrdRuntime = opened["runtime"]
	_people(opened["host"])
	runtime.facts.set(&"guild.errand", true)
	runtime.trace.enabled = true
	runtime.trace.clear()
	runtime.generator.offer(&"guild", "toll", &"", {"note": "kept"})
	var proposal := runtime.generator.propose({"key": "cast", "payload": {"note": "kept"}, "source": "host"})
	runtime.generator.accept(proposal)
	var recorded := runtime.trace.snapshot()
	var replayed := _open(4)
	var second: WyrdRuntime = replayed["runtime"]
	_people(replayed["host"])
	second.facts.set(&"guild.errand", true)
	second.trace.enabled = true
	WyrdTrace.replay(second, recorded)
	assert_eq(WyrdTrace.diff(recorded, second.trace.snapshot()), PackedStringArray())
	var changed := _open(4)
	var third: WyrdRuntime = changed["runtime"]
	_people(changed["host"])
	third.facts.set(&"guild.errand", true)
	(changed["host"] as WyrdFakeHost).world.add_entity(&"parcel.dead", &"item", "Dead", PackedStringArray(["parcel"]), false)
	third.trace.enabled = true
	WyrdTrace.replay(third, recorded)
	var diff := WyrdTrace.diff(recorded, third.trace.snapshot())
	assert_eq(diff.size(), 1)
	assert_true(String(diff[0]).ends_with("gen_candidates"))
	var index := int(String(diff[0]).split(" ")[0])
	assert_true(String(third.trace.events[index]["key"]).contains("parcel"))


func test_deed_offers_regenerate_on_replay() -> void:
	var opened := _open(4)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.facts.set(&"guild.deed", true)
	runtime.quests.start("watch")
	runtime.trace.enabled = true
	runtime.trace.clear()
	runtime.events.emit(&"met", {"who": 3})
	var recorded := runtime.trace.snapshot()
	assert_gt(_rows(runtime, "gen_offer").size(), 0)
	assert_eq(String(_rows(runtime, "gen_offer")[0]["origin"]), "deed")
	var replayed := _open(4)
	var second: WyrdRuntime = replayed["runtime"]
	second.facts.set(&"guild.deed", true)
	second.quests.start("watch")
	second.trace.enabled = true
	WyrdTrace.replay(second, recorded)
	assert_eq(WyrdTrace.diff(recorded, second.trace.snapshot()), PackedStringArray())


func _open(seed: int) -> Dictionary:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var manifest := load(MANIFEST) as WyrdContentManifest
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(seed)
	return {"host": host, "report": report, "runtime": runtime}


func _people(host: WyrdFakeHost) -> void:
	host.world.add_entity(&"ada", &"object", "Ada", PackedStringArray(["runner", "guide_a"]), true)
	host.world.add_entity(&"bram", &"object", "Bram", PackedStringArray(["runner", "guide_b"]), true)
	host.world.add_entity(&"parcel.a", &"item", "Parcel", PackedStringArray(["parcel"]), true)
	host.world.add_entity(&"parcel.b", &"item", "Other", PackedStringArray(["parcel"]), true)
	host.world.add_entity(&"dock.a", &"object", "Bollard", PackedStringArray(["bollard"]), true)
	host.world.add_entity(&"dock.b", &"object", "Post", PackedStringArray(["bollard"]), true)
	host.inventory.set_owner(&"parcel.a", &"player")
	host.inventory.set_owner(&"parcel.b", &"bram")
	host.spatial.set_place(&"dock.a", &"slip")
	host.spatial.set_place(&"dock.b", &"pier")
	host.spatial.set_place(&"parcel.a", &"bench")


func _compile(runtime: WyrdRuntime, text: String) -> WyrdCompiledCondition:
	return _compile_at(runtime, text, true)


func _compile_value(runtime: WyrdRuntime, text: String) -> WyrdCompiledCondition:
	return _compile_at(runtime, text, false)


func _compile_at(runtime: WyrdRuntime, text: String, as_bool: bool) -> WyrdCompiledCondition:
	var diagnostics := WyrdDiagnostics.new()
	var compiled := WyrdCondition.new().compile(
		text,
		runtime.content().schema,
		diagnostics,
		"sample.wyrd",
		1,
		1,
		WyrdCondition.CONTEXT_STORYLET,
		1440,
		null,
		as_bool
	)
	assert_false(diagnostics.has_errors(), "%s %s" % [text, diagnostics.format()])
	return compiled


func _eval_bool(runtime: WyrdRuntime, instance: String, text: String) -> bool:
	runtime.push_scope(instance)
	var value := runtime.eval_bool(_compile(runtime, text))
	runtime.pop_scope()
	return value


func _eval_value(runtime: WyrdRuntime, instance: String, text: String) -> String:
	runtime.push_scope(instance)
	var value := _text(runtime.eval_value(_compile_value(runtime, text)))
	runtime.pop_scope()
	return value


func _text(value: Variant) -> String:
	if value == null:
		return ""
	return str(value)


func _journal(runtime: WyrdRuntime, quest_id: String) -> String:
	var rows: Array = runtime.quests.journal(quest_id)
	if rows.is_empty():
		return ""
	return String((rows[0] as Dictionary).get("text", ""))


func _deed_targets(runtime: WyrdRuntime, verb: String) -> Array:
	var out: Array = []
	for index in runtime.deeds.size():
		if String(runtime.deeds.verb_at(index)) != verb:
			continue
		out.append(String(runtime.deeds.target_at(index)))
	return out


func _choice(runtime: WyrdRuntime, scene_id: String) -> WyrdCompiledCondition:
	var scene := runtime.content().scenes[scene_id] as WyrdSceneDef
	for item in scene.items:
		var step := item as WyrdSceneItem
		if step != null and step.choice != null and step.choice.condition != null:
			return step.choice.condition
	return null


func _roll_keys(runtime: WyrdRuntime) -> PackedStringArray:
	var keys := PackedStringArray()
	for row in _rows(runtime, "roll"):
		keys.append(String(row.get("key", "")))
	return keys


func _chance_pass(seed: int, instance: String) -> bool:
	var opened := _open(seed)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.quests.create_instance("roll")
	runtime.trace.enabled = true
	runtime.push_scope(instance)
	var hit := runtime.eval_bool(_choice(runtime, "roll.bet"))
	runtime.pop_scope()
	return hit


func _rows(runtime: WyrdRuntime, kind: String) -> Array:
	var out: Array = []
	for row in runtime.trace.events:
		if str(row.get("kind", "")) == kind:
			out.append(row)
	return out


func _pick(runtime: WyrdRuntime) -> Dictionary:
	var rows := _rows(runtime, "gen_pick")
	if rows.is_empty():
		return {}
	return rows[rows.size() - 1]


func _propose_row(runtime: WyrdRuntime) -> Dictionary:
	var rows := _rows(runtime, "gen_propose")
	if rows.is_empty():
		return {}
	return rows[rows.size() - 1]


func _band_pick(seed: int) -> String:
	var opened := _open(seed)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.facts.set(&"guild.band", true)
	runtime.trace.enabled = true
	var proposal := runtime.generator.propose({"key": "band", "source": "host"})
	if proposal == null:
		return ""
	return proposal.template


func _sorted_seed() -> int:
	for seed in range(1, 40):
		var rng := WyrdRng.for_decision(seed, &"generator", StringName("cast:errand#1.courier"), 0)
		if rng.randi_bounded(2) == 0:
			return seed
	return 1


func _split_seed() -> int:
	for seed in range(1, 80):
		var first := WyrdRng.for_decision(seed, &"generator", StringName("cast:errand#1.courier"), 0)
		var second := WyrdRng.for_decision(seed, &"generator", StringName("cast:errand#2.courier"), 0)
		if first.randi_bounded(2) != second.randi_bounded(2):
			return seed
	return 1


func _index(runtime: WyrdRuntime, kind: String, instance: String) -> int:
	for i in runtime.trace.events.size():
		var row: Dictionary = runtime.trace.events[i]
		if str(row.get("kind", "")) == kind and str(row.get("instance", "")) == instance:
			return i
	return -1


func _status_at(runtime: WyrdRuntime, quest_id: String, to_status: String) -> int:
	for i in runtime.trace.events.size():
		var row: Dictionary = runtime.trace.events[i]
		if str(row.get("kind", "")) != "quest_status":
			continue
		if str(row.get("quest", "")) == quest_id and str(row.get("to", "")) == to_status:
			return i
	return -1


func _generate_units(runtime: WyrdRuntime) -> int:
	for row in runtime.trace.events:
		if str(row.get("kind", "")) != "scheduler":
			continue
		if str(row.get("queue", "")) != "generate":
			continue
		return int(row.get("units", 0))
	return -1


func _accepted(runtime: WyrdRuntime) -> String:
	var rows := _rows(runtime, "gen_accept")
	if rows.is_empty():
		return ""
	return String(rows[0].get("instance", ""))
