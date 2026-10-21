extends GutTest

const _Harbor := preload("res://tests/scenario/m9_gullhaven.gd")
const _MANIFEST := "res://example/content/gullhaven/harbor.wyrdmanifest.tres"
const _FIXTURE := "res://tests/fixtures/cast_index/scale_casts.wyrd"
const _MUTATIONS := 200
const _OFFERS := 32


class OptOut extends WyrdWorldAdapter:
	var calls := 0
	var inner := WyrdFakeWorld.new()

	func reports_changes() -> bool:
		return false

	func candidates(filter: WyrdEntityFilter) -> PackedStringArray:
		calls += 1
		return inner.candidates(filter)

	func exists(id: StringName) -> bool:
		return inner.exists(id)

	func kind(id: StringName) -> StringName:
		return inner.kind(id)

	func tags(id: StringName) -> PackedStringArray:
		return inner.tags(id)

	func is_alive(id: StringName) -> bool:
		return inner.is_alive(id)

	func display_name(id: StringName) -> String:
		return inner.display_name(id)


class SpyWorld extends WyrdWorldAdapter:
	var calls := 0
	var inner := WyrdFakeWorld.new()

	func reports_changes() -> bool:
		return true

	func candidates(filter: WyrdEntityFilter) -> PackedStringArray:
		calls += 1
		return inner.candidates(filter)

	func exists(id: StringName) -> bool:
		return inner.exists(id)

	func kind(id: StringName) -> StringName:
		return inner.kind(id)

	func tags(id: StringName) -> PackedStringArray:
		return inner.tags(id)

	func is_alive(id: StringName) -> bool:
		return inner.is_alive(id)

	func display_name(id: StringName) -> String:
		return inner.display_name(id)


func test_plans_classify_gullhaven_and_the_fixture() -> void:
	var harbor := _content(_MANIFEST)
	var found := {}
	for row in _cast_rows(harbor):
		var plan: WyrdCastPlan = row["plan"]
		assert_not_null(plan, row["id"])
		found[row["id"]] = _class_text(plan)
		if _class_text(plan) != "scan":
			assert_false(plan.key.is_empty(), row["id"])
	assert_eq(found["ferry_toll.lookout"], "scope")
	assert_eq(found["mooring_post.post"], "local")
	assert_eq(found["net_delivery.sender"], "local|local")
	assert_eq(found["net_delivery.net"], "local")
	assert_eq(found["stolen_catch.victim"], "local|local")
	assert_eq(found["stolen_catch.catch"], "local")
	assert_eq(found["cut_line.witness"], "local|local")
	assert_eq(found["cut_line.post"], "local")
	assert_eq(found["night_walk.walker"], "local|local")
	assert_eq(found["night_walk.dest"], "local")
	assert_eq(found["tavern_stew_low.cook"], "pin")
	assert_eq(found["tavern_stew_mid.cook"], "pin")
	assert_eq(found["tavern_stew_high.cook"], "pin")
	assert_eq(_plan_of(harbor, "net_delivery", "sender").key, _plan_of(harbor, "stolen_catch", "victim").key)
	assert_eq(_plan_of(harbor, "mooring_post", "post").key, _plan_of(harbor, "cut_line", "post").key)
	assert_eq(_plan_of(harbor, "tavern_stew_low", "cook").key, _plan_of(harbor, "tavern_stew_mid", "cook").key)
	assert_eq(_plan_of(harbor, "tavern_stew_low", "cook").key, _plan_of(harbor, "tavern_stew_high", "cook").key)
	assert_eq(_plan_of(harbor, "ferry_toll", "lookout").key, _plan_of(harbor, "tavern_stew_low", "cook").key)
	var fixture := _compile_fixture()
	var file: WyrdFileDef = fixture["file"]
	var by_id := {}
	for template in file.templates:
		by_id[template.id] = template
	assert_eq(_template_classes(by_id["scale_scope"]), "scope")
	assert_eq(_template_classes(by_id["scale_pin"]), "pin")
	assert_eq(_template_classes(by_id["scale_local"]), "local|local")
	assert_eq(_template_classes(by_id["scale_local_again"]), "local|local")
	assert_eq(_template_classes(by_id["scale_kind"]), "local")
	assert_eq(_template_classes(by_id["scale_rest"]), "rest")
	assert_eq(_template_classes(by_id["scale_mixed"]), "local|local|pin|rest")
	assert_eq(_template_classes(by_id["scale_chance"]), "scan")
	assert_true(by_id["scale_chance"].slots[0].cast_plan.scan)
	assert_eq(by_id["scale_local"].slots[0].cast_plan.key, by_id["scale_local_again"].slots[0].cast_plan.key)
	assert_eq(by_id["scale_local"].slots[0].cast_plan.key, by_id["scale_mixed"].slots[0].cast_plan.key)
	assert_ne(by_id["scale_kind"].slots[0].cast_plan.key, by_id["scale_local"].slots[0].cast_plan.key)
	print("CAST_INDEX_PLANS %s" % JSON.stringify(found))


func test_gullhaven_pools_match_the_scan() -> void:
	var opened := _Harbor.new().boot_generated(1)
	var runtime: WyrdRuntime = opened["runtime"]
	var rows := _cast_rows(runtime.content())
	var checks := 0
	for row in rows:
		_assert_pool(runtime.roles, row)
		checks += 1
		var accepted: Array = row["accepted"]
		for n in 16:
			var decision := "%s-%d" % [row["id"], n]
			assert_eq(
				runtime.roles.pick_id(accepted, &"cast", decision),
				runtime.roles.pick_id(row["scan_accepted"], &"cast", decision),
				decision
			)
	print("CAST_INDEX_GULLHAVEN slots=%d pick_keys=16" % checks)
	assert_gt(checks, 0)


func test_scale_world_matches_the_scan_across_mutations() -> void:
	var opened := _boot_scale()
	var runtime: WyrdRuntime = opened["runtime"]
	var world: WyrdFakeWorld = opened["world"]
	var rows := _cast_rows(runtime.content())
	var checks := 0
	for row in rows:
		_assert_pool(runtime.roles, row)
		checks += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261021
	var disposable: Array[String] = []
	for n in 20:
		var id := "scale_mut_%02d" % n
		disposable.append(id)
		world.add_entity(StringName(id), &"person", id, PackedStringArray(["scale_client"]), true)
	for step in _MUTATIONS:
		_mutate(runtime, world, rng, step, disposable)
		for row in rows:
			_assert_pool(runtime.roles, row)
			checks += 1
	print("CAST_INDEX_SCALE slots=%d mutations=%d comparisons=%d" % [rows.size(), _MUTATIONS, checks])
	assert_eq(rows.size() > 0, true)
	assert_eq(checks, rows.size() * (_MUTATIONS + 1))


func test_traced_routes_and_offers_match_with_the_index_off() -> void:
	var indexed := _play_routes(true)
	var scanned := _play_routes(false)
	assert_eq(indexed["trace"], scanned["trace"])
	assert_eq(indexed["proposals"], scanned["proposals"])
	assert_eq(indexed["save"], scanned["save"])
	var scale_on := _play_offers(true)
	var scale_off := _play_offers(false)
	assert_eq(scale_on["trace"], scale_off["trace"])
	assert_eq(scale_on["proposals"], scale_off["proposals"])
	assert_eq(scale_on["save"], scale_off["save"])
	assert_eq(scale_on["count"], _OFFERS)
	assert_eq(scale_off["count"], _OFFERS)


func test_opt_out_host_scans_every_cast() -> void:
	var runtime := WyrdRuntime.new()
	var world := OptOut.new()
	world.inner.add_entity(&"ada", &"person", "Ada", PackedStringArray(["scale_client"]), true)
	world.inner.add_entity(&"bee", &"person", "Bee", PackedStringArray(["other"]), true)
	runtime.register_adapter(WyrdWorldAdapter, world)
	_load_scale(runtime)
	runtime.start_new_game(4)
	var slot: WyrdSlotDef = runtime.content().templates["scale_local"].slots[0]
	var first: Dictionary = runtime.roles.cast_pool(slot)
	var second: Dictionary = runtime.roles.cast_pool(slot)
	var scanned: Dictionary = runtime.roles.cast_pool_scan(slot)
	assert_eq(world.calls, 3)
	assert_eq(first["accepted"], scanned["accepted"])
	assert_eq(first["raw"], scanned["raw"])
	assert_eq(second["accepted"], scanned["accepted"])
	assert_eq(second["raw"], scanned["raw"])


func test_invalidation_refreshes_only_when_told() -> void:
	var runtime := WyrdRuntime.new()
	var world := SpyWorld.new()
	world.inner.changed = Callable(runtime, &"invalidate_world")
	world.inner.add_entity(&"ada", &"person", "Ada", PackedStringArray(["scale_client"]), true)
	runtime.register_adapter(WyrdWorldAdapter, world)
	_load_scale(runtime)
	runtime.start_new_game(4)
	var slot: WyrdSlotDef = runtime.content().templates["scale_local"].slots[0]
	var seen: Dictionary = runtime.roles.cast_pool(slot)
	assert_eq(seen["accepted"], ["ada"])
	assert_eq(world.calls, 1)
	runtime.roles.cast_pool(slot)
	assert_eq(world.calls, 1)
	world.inner.changed = Callable()
	world.inner.add_entity(&"ada", &"person", "Ada", PackedStringArray(["other"]), true)
	var stale: Dictionary = runtime.roles.cast_pool(slot)
	assert_eq(stale["accepted"], ["ada"])
	assert_eq(world.calls, 1)
	runtime.invalidate_world(PackedStringArray(["ada"]))
	var fresh: Dictionary = runtime.roles.cast_pool(slot)
	assert_eq(fresh["accepted"], [])
	assert_eq(world.calls, 2)
	runtime.invalidate_world()
	runtime.roles.cast_pool(slot)
	assert_eq(world.calls, 3)
	runtime.register_adapter(WyrdWorldAdapter, world)
	runtime.roles.cast_pool(slot)
	runtime.roles.cast_pool(slot)
	assert_eq(world.calls, 4)
	_load_scale(runtime)
	runtime.roles.cast_pool(slot)
	runtime.roles.cast_pool(slot)
	var after_load := world.calls
	assert_eq(after_load, 5)
	runtime.start_new_game(4)
	runtime.roles.cast_pool(slot)
	runtime.roles.cast_pool(slot)
	assert_eq(world.calls, after_load + 1)
	var saved := runtime.save_state()
	runtime.roles.cast_pool(slot)
	assert_eq(world.calls, after_load + 1)
	assert_true(runtime.load_state(saved).ok)
	runtime.roles.cast_pool(slot)
	runtime.roles.cast_pool(slot)
	assert_eq(world.calls, after_load + 2)


func test_tracing_off_skips_candidate_hashes() -> void:
	var quiet := _boot_scale()
	var runtime: WyrdRuntime = quiet["runtime"]
	runtime.trace.enabled = false
	runtime.generator.candidate_traces = 0
	for n in _OFFERS:
		assert_not_null(runtime.generator.propose({
			"key": "quiet-%d" % n,
			"source": "scale",
			"template": "scale_local",
		}))
	assert_eq(runtime.generator.candidate_traces, 0)
	var traced := _offer_digests(true)
	var scanned := _offer_digests(false)
	assert_eq(traced["lines"], scanned["lines"])
	assert_eq(traced["calls"], _OFFERS)
	assert_eq(scanned["calls"], _OFFERS)
	assert_gt(traced["lines"].size(), 0)


func test_without_returns_the_same_array_when_nothing_is_excluded() -> void:
	var generator := WyrdGenerator.new()
	var ids := ["ada", "bee", "cy"]
	var same: Array = generator._without(ids, {})
	assert_true(is_same(same, ids))
	assert_eq(same, ["ada", "bee", "cy"])
	var kept: Array = generator._without(ids, {"bee": true})
	assert_eq(kept, ["ada", "cy"])
	assert_false(is_same(kept, ids))
	assert_eq(ids, ["ada", "bee", "cy"])


func _class_text(plan: WyrdCastPlan) -> String:
	if plan.scan:
		return "scan"
	return "|".join(plan.classes)


func _plan_of(content: WyrdContent, owner: String, slot_name: String) -> WyrdCastPlan:
	for row in _cast_rows(content):
		if row["owner"] == owner and row["name"] == slot_name:
			return row["plan"]
	return null


func _template_classes(template: WyrdTemplateDef) -> String:
	return _class_text(template.slots[0].cast_plan)


func _content(path: String) -> WyrdContent:
	var runtime := WyrdRuntime.new()
	var report := runtime.load_content(load(path) as WyrdContentManifest)
	assert_true(report.ok, report.diagnostics.format())
	return runtime.content()


func _cast_rows(content: WyrdContent) -> Array:
	var rows: Array = []
	if content == null:
		return rows
	var quest_ids: Array = content.quests.keys()
	quest_ids.sort()
	for quest_id in quest_ids:
		var quest: WyrdQuestDef = content.quests[quest_id]
		for slot in quest.slots:
			if slot.mode != &"cast":
				continue
			rows.append(_row(quest.id, slot.name, "slot", slot, null))
	var template_ids: Array = content.templates.keys()
	template_ids.sort()
	for template_id in template_ids:
		var template: WyrdTemplateDef = content.templates[template_id]
		for slot in template.slots:
			if slot.mode != &"cast":
				continue
			rows.append(_row(template.id, slot.name, "slot", slot, null))
		for param in template.params:
			rows.append(_row(template.id, param.name, "param", null, param))
	return rows


func _row(owner: String, slot_name: String, kind: String, slot: WyrdSlotDef, param: WyrdParamDef) -> Dictionary:
	var plan: WyrdCastPlan = slot.cast_plan if slot != null else param.cast_plan
	return {
		"id": "%s.%s" % [owner, slot_name],
		"kind": kind,
		"name": slot_name,
		"owner": owner,
		"param": param,
		"plan": plan,
		"slot": slot,
	}


func _assert_pool(roles: WyrdRoles, row: Dictionary) -> void:
	var live := {}
	var scanned := {}
	if row["kind"] == "slot":
		live = roles.cast_pool(row["slot"])
		scanned = roles.cast_pool_scan(row["slot"])
	else:
		live = roles.param_pool(row["param"])
		scanned = roles.param_pool_scan(row["param"])
	assert_eq(live["accepted"], scanned["accepted"], row["id"])
	assert_eq(live["raw"], scanned["raw"], row["id"])
	row["accepted"] = live["accepted"]
	row["scan_accepted"] = scanned["accepted"]


func _compile_fixture() -> Dictionary:
	var diagnostics := WyrdDiagnostics.new()
	var pack := WyrdPack.compile(PackedStringArray([_FIXTURE]), "scale", 1, null, diagnostics, _FIXTURE, true)
	var errors: Array[String] = []
	for item in diagnostics.items:
		if item.severity != WyrdDiagnostic.SEVERITY_ERROR:
			continue
		errors.append(String(item.code))
	assert_eq(errors, ["E_CHANCE_CONTEXT"])
	var file: WyrdFileDef = pack.units[0]["file"]
	return {"file": file, "pack": pack}


func _boot_scale() -> Dictionary:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	_load_scale(runtime)
	runtime.start_new_game(4)
	_fill_scale(host.world, runtime)
	return {"host": host, "runtime": runtime, "world": host.world}


func _load_scale(runtime: WyrdRuntime) -> void:
	var path := "user://cast_index_scale.wyrd"
	var source := FileAccess.get_file_as_string(_FIXTURE)
	var cut := source.find("\ntemplate scale_chance")
	assert_gt(cut, 0)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(source.substr(0, cut) + "\n")
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"scale"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())


func _fill_scale(world: WyrdFakeWorld, runtime: WyrdRuntime) -> void:
	world.add_entity(&"player", &"person", "traveler", PackedStringArray(), true)
	world.add_entity(&"scale_keeper", &"person", "keeper", PackedStringArray(["scale_client"]), true)
	world.add_entity(&"scale_other", &"person", "other", PackedStringArray(), true)
	world.add_entity(&"scale_dead", &"person", "dead", PackedStringArray(["scale_client"]), false)
	world.add_entity(&"scale_hidden", &"person", "hidden", PackedStringArray(["scale_client"]), true)
	world.deny_exists = &"scale_hidden"
	for n in 50:
		var id := "scale_npc_%03d" % n
		world.add_entity(StringName(id), &"person", id, PackedStringArray(["scale_client"]), true)
	for n in 500:
		var id := "scale_obj_%05d" % n
		world.add_entity(StringName(id), &"object", id, PackedStringArray(["scale_crate"]), true)
	runtime.roles.assign(&"scale_keeper", &"scale_keeper")
	runtime.facts.set(&"scale.open", true)
	runtime.social.set_kind(&"scale_keeper", &"player", &"ally")
	runtime.social.set_kind(&"scale_npc_000", &"player", &"ally")


func _mutate(
	runtime: WyrdRuntime,
	world: WyrdFakeWorld,
	rng: RandomNumberGenerator,
	step: int,
	disposable: Array[String]
) -> void:
	var pick := disposable[step % disposable.size()]
	var who := StringName(pick)
	var roll := rng.randi_range(0, 11)
	if roll != 1 and not world.exists(who):
		world.add_entity(who, &"person", pick, PackedStringArray(["scale_client"]), true)
	match roll:
		0:
			world.add_entity(who, &"person", pick, PackedStringArray(["scale_client"]), true)
		1:
			world.remove_entity(who)
		2:
			world.add_entity(who, &"object", pick, PackedStringArray(["scale_crate", "moved"]), true)
		3:
			world.add_entity(who, &"person", pick, PackedStringArray(["scale_client"]), step % 2 == 0)
		4:
			world.set_attr(who, &"note", step)
		5:
			world.set_protected(who, step % 2 == 0)
		6:
			world.set_out_of_bounds(who, step % 2 == 1)
		7:
			world.deny_exists = who if step % 3 == 0 else &""
		8:
			runtime.roles.assign(&"scale_keeper", who if world.exists(who) else &"scale_keeper")
		9:
			runtime.roles.vacate(&"scale_keeper", &"left")
			runtime.roles.assign(&"scale_keeper", &"scale_keeper")
		10:
			world.add_member(&"scale_band", who)
		_:
			world.set_groups(who, PackedStringArray(["scale_band"]))


func _play_routes(index_on: bool) -> Dictionary:
	var opened := _Harbor.new().boot_generated(1)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	runtime.roles.cast_index_enabled = index_on
	runtime.trace.enabled = true
	var proposals: PackedStringArray = []
	var net := _propose(runtime, "nets", "net_delivery")
	proposals.append(_proposal_text(net))
	assert_eq(runtime.generator.accept(net), "net_delivery#1")
	host.inventory.set_owner(&"net.mended", &"net_mender")
	runtime.tick(0)
	runtime.tick(0)
	var looked := _Harbor.new().boot_generated(1)
	var cutter: WyrdRuntime = looked["runtime"]
	cutter.roles.cast_index_enabled = index_on
	cutter.trace.enabled = true
	var cut := _propose(cutter, "line", "cut_line")
	proposals.append(_proposal_text(cut))
	assert_eq(cutter.generator.accept(cut), "cut_line#1")
	_choose(cutter, looked["harness"], "cut.ask", "Thank them and look at the line")
	cutter.tick(0)
	var walked := _Harbor.new().boot_generated(1)
	var guide: WyrdRuntime = walked["runtime"]
	guide.roles.cast_index_enabled = index_on
	guide.trace.enabled = true
	var walk := _propose(guide, "walk", "night_walk")
	proposals.append(_proposal_text(walk))
	assert_eq(guide.generator.accept(walk), "night_walk#1")
	_choose(guide, walked["harness"], "night.walk", "Walk them there")
	return {
		"proposals": "\n".join(proposals),
		"save": "%s\n%s\n%s" % [
			JSON.stringify(runtime.save_state()),
			JSON.stringify(cutter.save_state()),
			JSON.stringify(guide.save_state()),
		],
		"trace": "%s\n%s\n%s" % [_trace_text(runtime), _trace_text(cutter), _trace_text(guide)],
	}


func _play_offers(index_on: bool) -> Dictionary:
	var opened := _boot_scale()
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.roles.cast_index_enabled = index_on
	runtime.trace.enabled = true
	var names := PackedStringArray([
		"scale_scope",
		"scale_pin",
		"scale_local",
		"scale_kind",
		"scale_rest",
		"scale_mixed",
		"scale_local_again",
	])
	var proposals: PackedStringArray = []
	for n in _OFFERS:
		var proposal := runtime.generator.propose({
			"key": "offer-%d" % n,
			"source": "scale",
			"template": names[n % names.size()],
		})
		proposals.append(_proposal_text(proposal))
		if proposal != null:
			runtime.generator.accept(proposal)
	return {
		"count": proposals.size(),
		"proposals": "\n".join(proposals),
		"save": JSON.stringify(runtime.save_state()),
		"trace": _trace_text(runtime),
	}


func _offer_digests(index_on: bool) -> Dictionary:
	var opened := _boot_scale()
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.roles.cast_index_enabled = index_on
	runtime.trace.enabled = true
	runtime.generator.candidate_traces = 0
	for n in _OFFERS:
		assert_not_null(runtime.generator.propose({
			"key": "digest-%d" % n,
			"source": "scale",
			"template": "scale_local",
		}))
	var lines: PackedStringArray = []
	for row in runtime.trace.events:
		if str(row.get("kind", "")) != "gen_candidates":
			continue
		lines.append("%s %s" % [str(row.get("count", "")), str(row.get("digest", ""))])
	return {"calls": runtime.generator.candidate_traces, "lines": lines}


func _propose(runtime: WyrdRuntime, key: String, template_id: String) -> WyrdProposal:
	match template_id:
		"net_delivery":
			runtime.facts.set(&"harbor.nets_wanted", true)
		"cut_line":
			runtime.facts.set(&"harbor.boat_adrift", true)
		"night_walk":
			runtime.facts.set(&"harbor.visitor_waiting", true)
	return runtime.generator.propose({
		"key": key,
		"source": "exit",
		"template": template_id,
	})


func _choose(runtime: WyrdRuntime, harness: RefCounted, scene_id: String, label: String) -> void:
	runtime.dialogue.open_scene(scene_id)
	harness.line_rows(runtime)
	harness.choose_text(runtime, label)
	harness.line_rows(runtime)


func _proposal_text(proposal: WyrdProposal) -> String:
	if proposal == null:
		return "null"
	return JSON.stringify({
		"casts": proposal.casts,
		"instance": proposal.instance,
		"params": proposal.params,
		"template": proposal.template,
	})


func _trace_text(runtime: WyrdRuntime) -> String:
	var lines: PackedStringArray = []
	for row in runtime.trace.events:
		var text := WyrdCli._format_gen(row)
		if text.is_empty():
			text = JSON.stringify(row)
		lines.append(text)
	return "\n".join(lines)
