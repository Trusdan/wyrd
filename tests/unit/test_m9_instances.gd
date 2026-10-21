extends GutTest

const _Pack := preload("res://tests/support/wyrd_test_templates.gd")
const _Harness := preload("res://tests/scenario/s2c_harness.gd")


class CountingWorld extends WyrdWorldAdapter:
	var calls := 0
	var inner := WyrdFakeWorld.new()

	func candidates(filter: WyrdEntityFilter) -> PackedStringArray:
		calls += 1
		return inner.candidates(filter)

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


func test_create_instance_numbers_and_starts() -> void:
	var opened := _Pack.open(4)
	var runtime: WyrdRuntime = opened["runtime"]
	assert_true(opened["report"].ok, opened["report"].diagnostics.format())
	var before := JSON.stringify((runtime.quests.export_state() as Dictionary)["dormant"])
	var seen: Array = []
	runtime.quests.quest_state_changed.connect(func(quest_id: String, status: StringName) -> void:
		seen.append([quest_id, status])
	)
	runtime.trace.enabled = true
	var first := runtime.quests.create_instance("errand")
	var second := runtime.quests.create_instance("errand")
	assert_eq(first, "errand#1")
	assert_eq(second, "errand#2")
	assert_eq(runtime.quests.status("errand#1"), &"active")
	assert_eq(runtime.quests.stage("errand#1"), "work")
	assert_true(_saw(seen, "errand#1", &"active"))
	var created := _kind(runtime, "gen_create")
	assert_eq(created.size(), 2)
	assert_eq(String(created[0]["template"]), "errand")
	assert_eq(String(created[0]["instance"]), "errand#1")
	assert_eq(int(created[0]["n"]), 1)
	assert_eq(String(created[0]["ok"]), "true")
	assert_eq(String(created[0]["reason"]), "created")
	assert_gt(_after(runtime, "gen_create", "quest_start", "errand#1"), -1)
	assert_gt(_after(runtime, "gen_create", "quest_status", "errand#1"), -1)
	assert_eq(JSON.stringify((runtime.quests.export_state() as Dictionary)["dormant"]), before)
	assert_false((runtime.quests.export_state() as Dictionary)["dormant"].has("template"))
	assert_eq(_quest_rows(runtime, "dormant").size(), 0)


func test_refusal_changes_nothing() -> void:
	var opened := _Pack.open(4)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.trace.enabled = true
	var before := JSON.stringify(runtime.save_state())
	assert_eq(runtime.quests.create_instance("missing"), "")
	assert_eq(runtime.quests.create_instance("errand", {"nope": "ada"}), "")
	assert_eq(JSON.stringify(runtime.save_state()), before)
	assert_eq(runtime.quests.status("errand#1"), &"")
	var refused := _kind(runtime, "gen_create")
	assert_eq(refused.size(), 2)
	assert_eq(String(refused[0]["ok"]), "false")
	assert_eq(String(refused[0]["reason"]), "unknown_template")
	assert_eq(String(refused[0]["instance"]), "")
	assert_eq(int(refused[0]["n"]), 0)
	assert_eq(String(refused[1]["ok"]), "false")
	assert_eq(String(refused[1]["reason"]), "bad_cast")
	assert_eq(int(refused[1]["n"]), 0)
	assert_false(runtime.save_state().has("generator"))


func test_supplied_casts_skip_candidates() -> void:
	var opened := _Pack.open(4)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.inventory.set_owner(&"coin.toll", &"player")
	var world := CountingWorld.new()
	runtime.register_adapter(WyrdWorldAdapter, world)
	runtime.trace.enabled = true
	var id := runtime.quests.create_instance("errand", {"coin": "coin.toll", "post": "dock.bollard"})
	assert_eq(id, "errand#1")
	assert_eq(world.calls, 0)
	assert_eq(runtime.roles.slot_holder(id, &"post"), &"dock.bollard")
	assert_eq(runtime.roles.slot_holder(id, &"coin"), &"coin.toll")
	var casts := _kind(runtime, "cast")
	assert_eq(casts.size(), 2)
	for row in casts:
		assert_eq(String(row["quest"]), id)
		assert_eq(String(row["reason"]), "given")
	var coin := _cast(runtime, "coin")
	assert_eq(String(coin["owner"]), "player")
	assert_eq(String(coin["kind"]), "cast")
	assert_eq(String(coin["slot_kind"]), "item")


func test_save_puts_instance_casts_on_the_generator() -> void:
	var opened := _Pack.open(4)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.quests.create_instance("errand", {"post": "dock.bollard", "coin": "coin.toll"})
	runtime.quests.create_instance("errand", {"post": "dock.second"})
	var saved := runtime.save_state()
	var quests: Dictionary = saved["quests"]
	assert_eq(String((quests["errand#1"] as Dictionary)["template"]), "errand")
	assert_eq(int((quests["errand#1"] as Dictionary)["n"]), 1)
	assert_eq(int((quests["errand#2"] as Dictionary)["n"]), 2)
	assert_false((quests["dormant"] as Dictionary).has("template"))
	assert_false((quests["dormant"] as Dictionary).has("n"))
	assert_false((quests["gate"] as Dictionary).has("template"))
	var generator: Dictionary = saved["generator"]
	assert_eq(int((generator["counters"] as Dictionary)["errand"]), 2)
	var casts: Dictionary = ((generator["instances"] as Dictionary)["errand#1"] as Dictionary)["casts"]
	assert_eq(String((casts["post"] as Dictionary)["holder"]), "dock.bollard")
	assert_eq(String((casts["coin"] as Dictionary)["holder"]), "coin.toll")
	var frozen: Dictionary = (saved["roles"] as Dictionary)["frozen"]
	for quest_id in frozen.keys():
		assert_false(String(quest_id).contains("#"))


func test_json_round_trip_matches_and_continues() -> void:
	var opened := _Pack.open(4)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.quests.create_instance("errand", {"post": "dock.bollard", "coin": "coin.toll"})
	runtime.quests.create_instance("errand")
	var text := JSON.stringify(runtime.save_state(), "\t", true)
	var parsed: Variant = JSON.parse_string(text)
	assert_true(parsed is Dictionary)
	var fresh_open := _Pack.open(4)
	var fresh: WyrdRuntime = fresh_open["runtime"]
	var report := fresh.load_state(parsed)
	assert_true(report.ok, report.diagnostics.format())
	assert_false(report.diagnostics.has_warnings(), report.diagnostics.format())
	assert_eq(fresh.quests.status("errand#1"), runtime.quests.status("errand#1"))
	assert_eq(fresh.quests.stage("errand#1"), runtime.quests.stage("errand#1"))
	assert_eq(fresh.quests.journal("errand#1"), runtime.quests.journal("errand#1"))
	assert_eq(fresh.roles.slot_holder("errand#1", &"post"), &"dock.bollard")
	assert_eq(fresh.roles.slot_holder("errand#2", &"post"), &"")
	assert_eq(JSON.stringify(fresh.save_state(), "\t", true), text)
	runtime.trace.enabled = true
	fresh.trace.enabled = true
	runtime.trace.clear()
	fresh.trace.clear()
	runtime.facts.set(&"harbor.release", true)
	fresh.facts.set(&"harbor.release", true)
	runtime.tick(1)
	fresh.tick(1)
	assert_eq(WyrdTrace.diff(runtime.trace.snapshot(), fresh.trace.snapshot()), PackedStringArray())
	assert_eq(JSON.stringify(runtime.facts.export_state()), JSON.stringify(fresh.facts.export_state()))
	assert_eq(fresh.quests.create_instance("errand"), "errand#3")


func test_missing_template_keeps_rows_and_warns() -> void:
	var opened := _Pack.open(4)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.quests.create_instance("errand", {"post": "dock.bollard"})
	runtime.quests.create_instance("errand", {"post": "dock.second"})
	var text := JSON.stringify(runtime.save_state(), "\t", true)
	var parsed: Variant = JSON.parse_string(text)
	var blind_open := _Pack.open(4, false)
	var blind: WyrdRuntime = blind_open["runtime"]
	var report := blind.load_state(parsed)
	assert_true(report.ok, report.diagnostics.format())
	var warnings: Array = []
	for item in report.diagnostics.items:
		if item.code == WyrdDiagnostic.W_SAVE_TEMPLATE:
			warnings.append(item.message)
	assert_eq(warnings, ["load_missing kind=template id=errand instances=2"])
	assert_eq(blind.quests.active_count("errand"), 0)
	assert_eq(blind.quests.status("errand#1"), &"")
	assert_eq(int(((blind.save_state()["generator"] as Dictionary)["counters"] as Dictionary)["errand"]), 2)
	assert_eq(JSON.stringify(blind.save_state(), "\t", true), text)
	blind.tick(1)
	assert_eq(blind.quests.status("errand#1"), &"")
	assert_eq(blind.quests.active_count("errand"), 0)
	var restored_open := _Pack.open(4)
	var restored: WyrdRuntime = restored_open["runtime"]
	var again := restored.load_state(JSON.parse_string(text))
	assert_true(again.ok, again.diagnostics.format())
	assert_false(again.diagnostics.has_warnings(), again.diagnostics.format())
	assert_eq(restored.quests.status("errand#1"), &"active")
	assert_eq(restored.quests.status("errand#2"), &"active")
	assert_eq(restored.roles.slot_holder("errand#1", &"post"), &"dock.bollard")
	assert_eq(restored.quests.create_instance("errand"), "errand#3")


func test_active_count_wakes_a_hand_written_wait() -> void:
	var opened := _Pack.open(4)
	var runtime: WyrdRuntime = opened["runtime"]
	assert_eq(runtime.quests.active_count("errand"), 0)
	assert_eq(runtime.quests.active_count("missing"), 0)
	runtime.tick(1)
	assert_eq(runtime.quests.status("gate"), &"active")
	assert_eq(runtime.quests.stage("gate"), "hold")
	runtime.quests.create_instance("errand")
	assert_eq(runtime.quests.active_count("errand"), 1)
	assert_eq(runtime.quests.stage("gate"), "hold")
	runtime.quests.create_instance("errand")
	assert_eq(runtime.quests.active_count("errand"), 2)
	assert_eq(runtime.quests.stage("gate"), "hold")
	runtime.tick(1)
	assert_eq(runtime.quests.stage("gate"), "next")
	assert_eq(runtime.facts.get(&"harbor.release"), null)
	runtime.facts.set(&"harbor.release", true)
	runtime.tick(1)
	assert_eq(runtime.quests.status("errand#1"), &"completed")
	assert_eq(runtime.quests.status("errand#2"), &"completed")
	assert_eq(runtime.quests.active_count("errand"), 0)
	var casts: Dictionary = ((runtime.save_state()["generator"] as Dictionary)["instances"] as Dictionary)["errand#1"]
	assert_true((casts["casts"] as Dictionary).has("post"))


func test_migration_keeps_the_file_version_and_refuses_schema_5() -> void:
	var raw := FileAccess.get_file_as_string("res://tests/fixtures/schema3_harbor.json")
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary)
	var copy: Dictionary = (parsed as Dictionary).duplicate(true)
	var stepped: Dictionary = WyrdSave._add_generator(copy)
	assert_eq(stepped["generator"], {})
	assert_eq(int(stepped["schema_version"]), 3)
	assert_eq(int(copy["schema_version"]), 3)
	var opened := _Pack.open(4)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.facts.set(&"harbor.release", true)
	var saved := runtime.save_state()
	saved["schema_version"] = 5
	runtime.facts.set(&"harbor.release", false)
	var refused := runtime.load_state(saved)
	assert_false(refused.ok)
	assert_true(refused.diagnostics.format().contains("no migration from save schema 5"))
	assert_eq(runtime.facts.get(&"harbor.release"), false)
	var harbor := _Harness.new()
	var schema2: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/schema2_harbor.json"))
	var loaded = harbor.open_pack("res://example/content/gullhaven/harbor.wyrdmanifest.tres")
	var old: WyrdRuntime = loaded["runtime"]
	var report := old.load_state(schema2)
	assert_true(report.ok, report.diagnostics.format())
	assert_gt(old.scheduler().dirty_count(), 0)
	assert_eq(int(old.save_state()["schema_version"]), 4)
	assert_false(old.save_state().has("generator"))


func test_new_game_and_load_content_clear_instances() -> void:
	var opened := _Pack.open(4)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.quests.create_instance("errand")
	runtime.quests.create_instance("errand")
	runtime.start_new_game(4)
	assert_eq(runtime.quests.status("errand#1"), &"")
	assert_eq(runtime.quests.export_generator(), {})
	assert_eq(runtime.quests.create_instance("errand"), "errand#1")
	runtime.quests.create_instance("errand")
	var manifest: WyrdContentManifest = opened["manifest"]
	assert_true(runtime.load_content(manifest).ok)
	assert_eq(runtime.quests.status("errand#1"), &"")
	assert_eq(runtime.quests.export_generator(), {})
	assert_eq(runtime.quests.status("errand"), &"dormant")


func _saw(seen: Array, quest_id: String, status: StringName) -> bool:
	for row in seen:
		if row[0] == quest_id and row[1] == status:
			return true
	return false


func _kind(runtime: WyrdRuntime, kind: String) -> Array:
	var rows: Array = []
	for event in runtime.trace.events:
		if String(event.get("kind", "")) == kind:
			rows.append(event)
	return rows


func _cast(runtime: WyrdRuntime, slot_name: String) -> Dictionary:
	for event in _kind(runtime, "cast"):
		if String(event.get("slot", "")) == slot_name:
			return event
	return {}


func _after(runtime: WyrdRuntime, first: String, second: String, quest_id: String) -> int:
	var origin := -1
	for i in runtime.trace.events.size():
		var event: Dictionary = runtime.trace.events[i]
		if origin < 0 and String(event.get("kind", "")) == first and String(event.get("instance", "")) == quest_id:
			origin = i
		if origin >= 0 and String(event.get("kind", "")) == second and String(event.get("quest", "")) == quest_id:
			return i
	return -1


func _quest_rows(runtime: WyrdRuntime, quest_id: String) -> Array:
	var rows: Array = []
	for event in runtime.trace.events:
		if String(event.get("quest", "")) == quest_id:
			rows.append(event)
	return rows
