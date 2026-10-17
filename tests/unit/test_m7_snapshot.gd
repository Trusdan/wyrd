extends GutTest

const _Facade := preload("res://addons/wyrd/runtime/wyrd.gd")


func test_snapshot_reads_live_sections() -> void:
	var runtime := _prime()
	var shot := runtime.debug.snapshot()
	assert_eq(shot["sections"], ["facts", "roles", "quests", "dirty", "deeds", "social", "precedence", "provenance"])
	assert_eq(str(shot["prefix"]), "")
	assert_eq(int(shot["offset"]), 0)
	assert_eq(int(shot["limit"]), 0)
	var coins := _find(shot["facts"], "world/harbor.coins")
	assert_eq(int(coins["value"]), 1)
	assert_eq(str(coins["fact"]), "harbor.coins")
	assert_eq(str(coins["layer"]), "world")
	assert_eq(int(coins["until"]), 5000)
	var believed := _find(shot["facts"], "believed/dock_hand/harbor.coins")
	assert_eq(int(believed["value"]), 2)
	assert_false(believed.has("until"))
	var role := _find(shot["roles"], "ferry_master")
	assert_eq(str(role["holder"]), "player")
	assert_eq(str(role["status"]), "default")
	assert_eq(str(role["strategy"]), "none")
	assert_true((role["history"] as Array).size() >= 1)
	assert_eq(str((role["history"] as Array)[0]["holder"]), "ferry")
	var quest := _find(shot["quests"], "toll")
	assert_eq(str(quest["status"]), "active")
	assert_eq(str(quest["stage"]), "wait")
	assert_eq(str(quest["waiting"]), "waits_until: harbor.coins == 2")
	assert_eq(quest["regions"], {})
	assert_eq(_indexes(shot["dirty"]), _live_indexes(runtime))
	var deed := _find(shot["deeds"], "player/paid/ferry")
	assert_eq(float(deed["magnitude"]), 8.0)
	assert_eq(float(deed["weight"]), 8.0)
	assert_false(bool(deed["memorable"]))
	assert_eq(deed["witnesses"], ["dock_hand"])
	var edge := _find(shot["social"], "ferry/dock_hand")
	assert_eq(int(edge["disposition"]), 52)
	assert_eq((edge["axes"] as Dictionary).keys(), ["affinity", "trust"])
	assert_almost_eq(float((edge["axes"] as Dictionary)["affinity"]), 4.0, 0.001)
	var watched := _find(shot["social"], "ferry/player")
	assert_eq(int(watched["disposition"]), 50)
	var council := _find(shot["precedence"], "dock_hand")
	assert_eq(council["groups"], ["harbor_council", "ferry_crew"])
	assert_true(_find(shot["precedence"], "lane_watch").is_empty())
	var wrote := _find(shot["provenance"], "harbor.coins")
	assert_eq(str(wrote["scene"]), "toll_booth")
	assert_eq(str(wrote["choice"]), "pay")
	assert_eq(int(wrote["time"]), 0)
	assert_true(_find(shot["provenance"], "dock.ropes").is_empty())
	assert_eq(runtime.trace.events.size(), 0)


func test_prefix_pages_and_unknown_section_is_dropped() -> void:
	var runtime := _prime()
	var harbor := runtime.debug.snapshot(PackedStringArray(["facts"]), "harbor", 0, 1)
	assert_eq(int(harbor["facts"]["total"]), 3)
	assert_eq((harbor["facts"]["rows"] as Array).size(), 1)
	assert_eq(str((harbor["facts"]["rows"] as Array)[0]["key"]), "believed/dock_hand/harbor.coins")
	var next := runtime.debug.snapshot(PackedStringArray(["facts"]), "harbor", 1, 1)
	assert_eq(str((next["facts"]["rows"] as Array)[0]["key"]), "known/ferry/harbor.tide")
	var rest := runtime.debug.snapshot(PackedStringArray(["facts"]), "harbor", 0, 0)
	assert_eq((rest["facts"]["rows"] as Array).size(), 3)
	assert_true(_find(rest["facts"], "world/dock.ropes").is_empty())
	var world := runtime.debug.snapshot(PackedStringArray(["facts"]), "world/", 0, 0)
	assert_eq(int(world["facts"]["total"]), 2)
	var dropped := runtime.debug.snapshot(PackedStringArray(["facts", "graph", "facts"]))
	assert_push_error("unknown section")
	assert_eq(dropped["sections"], ["facts"])
	assert_false(dropped.has("graph"))
	var negative := runtime.debug.snapshot(PackedStringArray(["provenance"]), "", -4, -2)
	assert_eq(int(negative["offset"]), 0)
	assert_eq(int(negative["limit"]), 0)
	assert_eq((negative["provenance"]["rows"] as Array).size(), 1)


func test_trace_filters_and_load_stays_quiet() -> void:
	var runtime := _prime()
	runtime.trace.enabled = true
	var full := runtime.debug.snapshot()
	var logged := _rows(runtime, "debug_snapshot")
	assert_eq(logged.size(), 1)
	assert_eq(str(logged[0]["sections"]), "*")
	assert_eq(str(logged[0]["path"]), "*")
	assert_eq(str(logged[0]["prefix"]), "-")
	assert_eq(str(logged[0]["key"]), "")
	assert_eq(int(logged[0]["rows"]), _page_rows(full))
	runtime.trace.clear()
	runtime.trace.prefix = "facts"
	runtime.debug.snapshot()
	assert_eq(_rows(runtime, "debug_snapshot").size(), 0)
	runtime.debug.snapshot(PackedStringArray(["facts", "deeds"]))
	assert_eq(_rows(runtime, "debug_snapshot").size(), 1)
	assert_eq(str(_rows(runtime, "debug_snapshot")[0]["path"]), "facts,deeds")
	runtime.trace.clear()
	runtime.debug.snapshot(PackedStringArray(["deeds", "facts"]))
	assert_eq(_rows(runtime, "debug_snapshot").size(), 0)
	runtime.trace.prefix = "harbor"
	runtime.debug.snapshot(PackedStringArray(), "harbor")
	var kept := _rows(runtime, "debug_snapshot")
	assert_eq(kept.size(), 1)
	assert_eq(str(kept[0]["key"]), "harbor")
	assert_eq(str(kept[0]["prefix"]), "harbor")
	var saved := runtime.save_state()
	assert_eq(int(saved["schema_version"]), 3)
	assert_false(saved.has("snapshot"))
	assert_false(saved.has("debug"))
	assert_false(saved.has("dirty"))
	var loaded := _boot()
	loaded.trace.enabled = true
	assert_true(loaded.load_state(saved).ok)
	assert_eq(loaded.trace.events.size(), 0)
	_apply_view(loaded)
	var again := loaded.debug.snapshot()
	assert_eq(_rows(loaded, "debug_snapshot").size(), 1)
	assert_eq(JSON.stringify(again["facts"]), JSON.stringify(full["facts"]))
	assert_eq(JSON.stringify(again["roles"]), JSON.stringify(full["roles"]))
	assert_eq(JSON.stringify(again["quests"]), JSON.stringify(full["quests"]))
	assert_eq(JSON.stringify(again["deeds"]), JSON.stringify(full["deeds"]))
	assert_eq(JSON.stringify(again["social"]), JSON.stringify(full["social"]))
	assert_eq(JSON.stringify(again["precedence"]), JSON.stringify(full["precedence"]))
	assert_eq(JSON.stringify(again["provenance"]), JSON.stringify(full["provenance"]))
	assert_eq(_indexes(again["dirty"]), _live_indexes(loaded))


func test_decayed_weight_survives_save() -> void:
	var runtime := _prime()
	runtime.config().half_life_verbs = PackedStringArray(["paid"])
	runtime.config().half_life_minutes = PackedFloat64Array([60.0])
	runtime.tick(120)
	var shot := runtime.debug.snapshot(PackedStringArray(["deeds"]))
	var deed := _find(shot["deeds"], "player/paid/ferry")
	assert_almost_eq(float(deed["weight"]), 2.0, 0.001)
	assert_eq(float(deed["magnitude"]), 8.0)
	var saved := runtime.save_state()
	var loaded := _boot()
	loaded.config().half_life_verbs = PackedStringArray(["paid"])
	loaded.config().half_life_minutes = PackedFloat64Array([60.0])
	assert_true(loaded.load_state(saved).ok)
	var again := _find(loaded.debug.snapshot(PackedStringArray(["deeds"]))["deeds"], "player/paid/ferry")
	assert_almost_eq(float(again["weight"]), 2.0, 0.001)
	assert_eq(int(again["t"]), int(deed["t"]))


func test_filtered_page_matches_full_then_filter() -> void:
	var runtime := _prime()
	runtime.deeds.record(
		&"paid",
		&"player",
		&"ferry",
		&"gullhaven",
		PackedStringArray(),
		3.0,
		PackedStringArray([&"dock_hand"]),
		&"public",
		false
	)
	runtime.deeds.record(
		&"arrived",
		&"dock_hand",
		&"player",
		&"gullhaven",
		PackedStringArray(),
		1.0,
		PackedStringArray([&"lane_watch"]),
		&"public",
		false
	)
	var full: Dictionary = runtime.debug.snapshot()
	var cases: Array = [
		["", "", 0, 0],
		["", "harbor", 0, 0],
		["", "harbor", 1, 1],
		["facts", "harbor", 0, 1],
		["facts", "harbor.coins", 0, 0],
		["facts", "world/", 0, 0],
		["deeds", "player/paid/ferry", 0, 1],
		["deeds,facts", "player", 0, 2],
		["social", "ferry/", 0, 0],
		["social", "lane_watch/", 0, 0],
		["precedence", "lane_watch", 0, 0],
		["precedence", "dock", 0, 1],
		["roles", "ferry", 0, 0],
		["quests", "toll", 0, 0],
		["dirty", "", 1, 1],
		["provenance", "harbor", 0, 0],
		["facts", "harbor", 50, 1],
		["facts,facts", "dock", 0, 0],
		["", "missing", 0, 5],
	]
	for item in cases:
		var spec: Array = item
		var section_text := str(spec[0])
		var prefix := str(spec[1])
		var offset := int(spec[2])
		var limit := int(spec[3])
		var sections := PackedStringArray()
		if not section_text.is_empty():
			sections = section_text.split(",")
		var shot: Dictionary = runtime.debug.snapshot(sections, prefix, offset, limit)
		var expected := _legacy_document(full, sections, prefix, offset, limit)
		var label := "%s prefix=%s offset=%d limit=%d" % [section_text, prefix, offset, limit]
		var page_limit := 0
		if limit > 0:
			page_limit = limit
		assert_eq(shot["sections"], expected["sections"], label)
		assert_eq(str(shot["prefix"]), prefix, label)
		assert_eq(int(shot["offset"]), maxi(offset, 0), label)
		assert_eq(int(shot["limit"]), page_limit, label)
		for section_name in shot["sections"]:
			var name := String(section_name)
			assert_eq(JSON.stringify(shot[name]), JSON.stringify(expected[name]), "%s %s" % [label, name])
		for section_name in full["sections"]:
			var name := String(section_name)
			if (shot["sections"] as Array).has(name):
				continue
			assert_false(shot.has(name), "%s kept %s" % [label, name])


func test_facade_snapshot() -> void:
	var node = _Facade.new()
	var shot: Dictionary = node.debug.snapshot(PackedStringArray(["provenance"]))
	assert_eq(shot["sections"], ["provenance"])
	assert_eq(int(shot["provenance"]["total"]), 0)
	node.free()


func _prime() -> WyrdRuntime:
	var opened := _boot()
	var runtime: WyrdRuntime = opened
	var host: WyrdFakeHost = runtime.get_meta("host")
	host.world.add_entity(&"player", &"person", "Player", PackedStringArray(), true)
	host.world.add_entity(&"ferry", &"person", "Ferry", PackedStringArray(), true)
	host.world.add_entity(&"dock_hand", &"person", "Dock hand", PackedStringArray(), true)
	host.world.set_groups(&"dock_hand", PackedStringArray([&"harbor_council", &"ferry_crew"]))
	host.world.set_groups(&"lane_watch", PackedStringArray([&"harbor_council"]))
	_apply_view(runtime)
	runtime.effects.scene_id = "toll_booth"
	runtime.effects.choice_id = "pay"
	var pay := WyrdEffectDef.new()
	pay.kind = &"set"
	pay.fact_key = "harbor.coins"
	pay.value = _value(runtime, "1")
	assert_eq(runtime.effects.run_one(pay), "")
	var belief := WyrdEffectDef.new()
	belief.kind = &"believe"
	belief.agent = "dock_hand"
	belief.fact_key = "harbor.coins"
	belief.value = _value(runtime, "2")
	assert_eq(runtime.effects.run_one(belief), "")
	var known := WyrdEffectDef.new()
	known.kind = &"learn"
	known.agent = "ferry"
	known.fact_key = "harbor.tide"
	known.value = _value(runtime, "3")
	assert_eq(runtime.effects.run_one(known), "")
	runtime.facts.set(&"dock.ropes", 4)
	runtime.facts.note_evidence("harbor.coins", 1, "gullhaven", 5000, "toll_posted", "player", "ferry")
	runtime.tick(0)
	assert_eq(str(runtime.quests.status("toll")), "active")
	assert_eq(runtime.quests.waiting_reason("toll"), "waits_until: harbor.coins == 2")
	runtime.social.set_baseline(&"ferry", &"dock_hand", &"affinity", 4.0)
	runtime.social.set_kind(&"player", &"ferry", &"crew")
	runtime.deeds.record(&"paid", &"player", &"ferry", &"gullhaven", PackedStringArray(), 8.0, PackedStringArray([&"dock_hand"]), &"public", false)
	runtime.roles.vacate(&"ferry_master", &"left")
	runtime.roles.assign(&"ferry_master", &"player")
	return runtime


func _apply_view(runtime: WyrdRuntime) -> void:
	var host: WyrdFakeHost = runtime.get_meta("host")
	host.world.set_groups(&"dock_hand", PackedStringArray([&"harbor_council", &"ferry_crew"]))
	host.world.set_groups(&"lane_watch", PackedStringArray([&"harbor_council"]))
	runtime.config().axis_names = PackedStringArray(["trust"])
	runtime.invalidate_groups()


func _boot() -> WyrdRuntime:
	var compiled := _compile(_PACK)
	assert_false(compiled["diagnostics"].has_errors(), compiled["diagnostics"].format())
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([str(compiled["path"])])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(7)
	runtime.set_meta("host", host)
	return runtime


func _value(runtime: WyrdRuntime, text: String) -> WyrdCompiledCondition:
	return WyrdCondition.new().compile(text, runtime.content().schema, WyrdDiagnostics.new(), "", 1, 1, WyrdCondition.CONTEXT_STORYLET, 1440, null, false)


func _legacy_document(full: Dictionary, sections: PackedStringArray, prefix: String, offset: int, limit: int) -> Dictionary:
	var page_offset := maxi(offset, 0)
	var page_limit := limit if limit > 0 else 0
	var chosen: Array = []
	var seen := {}
	var source: Array = []
	if sections.is_empty():
		source = ["facts", "roles", "quests", "dirty", "deeds", "social", "precedence", "provenance"]
	else:
		for section_name in sections:
			source.append(String(section_name))
	for section_name in source:
		var name := String(section_name).strip_edges()
		if not ["facts", "roles", "quests", "dirty", "deeds", "social", "precedence", "provenance"].has(name):
			continue
		if seen.has(name):
			continue
		seen[name] = true
		chosen.append(name)
	var out := {
		"limit": page_limit,
		"offset": page_offset,
		"prefix": prefix,
		"sections": chosen,
	}
	for section_name in chosen:
		var name := String(section_name)
		var rows: Array = (full[name]["rows"] as Array).duplicate()
		out[name] = _legacy_page(rows, prefix, page_offset, page_limit, name == "facts")
	return out


func _legacy_page(rows: Array, prefix: String, offset: int, limit: int, also_fact: bool) -> Dictionary:
	var filtered: Array = []
	for item in rows:
		if item is Dictionary and _legacy_matches(item, prefix, also_fact):
			filtered.append(item)
	filtered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _legacy_before(a, b))
	var total := filtered.size()
	var start := mini(offset, total)
	var ending := total if limit <= 0 else mini(start + limit, total)
	var page: Array = []
	for index in range(start, ending):
		page.append(filtered[index])
	return {"limit": limit, "offset": offset, "rows": page, "total": total}


func _legacy_matches(row: Dictionary, prefix: String, also_fact: bool) -> bool:
	if prefix.is_empty() or str(row.get("key", "")).begins_with(prefix):
		return true
	return also_fact and str(row.get("fact", "")).begins_with(prefix)


func _legacy_before(a: Dictionary, b: Dictionary) -> bool:
	var left := str(a.get("key", ""))
	var right := str(b.get("key", ""))
	if left != right:
		return left < right
	if a.has("id") or b.has("id"):
		return int(a.get("id", 0)) < int(b.get("id", 0))
	if a.has("index") or b.has("index"):
		return int(a.get("index", 0)) < int(b.get("index", 0))
	return false


func _find(section: Dictionary, key: String) -> Dictionary:
	for row in section["rows"]:
		if row is Dictionary and str((row as Dictionary).get("key", "")) == key:
			return row
	return {}


func _indexes(section: Dictionary) -> Array:
	var found: Array = []
	for row in section["rows"]:
		if row is Dictionary:
			found.append(int((row as Dictionary).get("index", -1)))
	found.sort()
	return found


func _live_indexes(runtime: WyrdRuntime) -> Array:
	var found: Array = []
	for index in runtime.condition_count():
		if runtime.condition_dirty(index):
			found.append(index)
	found.sort()
	return found


func _page_rows(shot: Dictionary) -> int:
	var count := 0
	for name in shot["sections"]:
		count += (shot[String(name)]["rows"] as Array).size()
	return count


func _rows(runtime: WyrdRuntime, kind: String) -> Array:
	var found: Array = []
	for item in runtime.trace.events:
		if item is Dictionary and String((item as Dictionary).get("kind", "")) == kind:
			found.append(item)
	return found


func _compile(body: String) -> Dictionary:
	var path := "user://wyrd_m7_snapshot_%d.wyrd" % body.hash()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(body.strip_edges() + "\n")
	file.close()
	var diagnostics := WyrdDiagnostics.new()
	var pack := WyrdPack.compile(PackedStringArray([path]), "harbor", 1, null, diagnostics, path, true)
	return {"diagnostics": diagnostics, "pack": pack, "path": path}


const _PACK := """
language 1
facts
  harbor.coins : int stored
  harbor.tide : int stored
  dock.ropes : int stored
quest toll "Harbor Toll"
  start when harbor.coins == 1
  stage wait
    waits_until harbor.coins == 2
role ferry_master
  default_holder: ferry
  succession: none
  vacancy: hold
"""
