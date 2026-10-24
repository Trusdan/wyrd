extends GutTest

## Gullhaven saves from the two previous content tags load into a fresh boot.
## tick(30) during generation already advanced ferry_toll from pay_toll to cross.

const _Load := preload("res://tests/migration/fixture_load.gd")
const _Harness := preload("res://tests/scenario/s2c_harness.gd")
const _CURRENT_HASH := "918b2aad2be7d4fa"


func test_v070_m9_save_loads_at_cross_and_plays_depart() -> void:
	_check("res://tests/migration/fixtures/gullhaven_v0.7.0-m9.json", "8bf113c14f107242")


func test_v080_m10_save_loads_at_cross_and_plays_depart() -> void:
	_check("res://tests/migration/fixtures/gullhaven_v0.8.0-m10.json", "f003b6b54c91ad8e")


func _check(path: String, fixture_hash: String) -> void:
	var data := _Load.read(path)
	assert_eq(int(data["schema_version"]), 4)
	assert_eq(_Load.pack_hash(data), fixture_hash)
	var harness := _Harness.new()
	var opened: Dictionary = harness.boot_gullhaven()
	var loaded = opened["report"]
	assert_true(loaded.ok, loaded.diagnostics.format())
	var runtime: WyrdRuntime = opened["runtime"]
	var current := WyrdRng.format_u64(runtime.content().manifest_hash)
	assert_eq(current, _CURRENT_HASH)
	var report := runtime.load_state(data)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(_Load.codes(report), _Load.manifest_warning(fixture_hash, current))
	assert_eq(WyrdRng.format_u64(runtime.game_seed()), String(data["seed"]))
	assert_eq(runtime.play_minutes(), 30)
	assert_eq(int(runtime.facts.get(&"player.coins")), 2)
	assert_eq(String(runtime.quests.status("ferry_toll")), "active")
	assert_eq(runtime.quests.stage("ferry_toll"), "cross")
	var quests: Dictionary = data.get("quests", {})
	for quest_id in quests.keys():
		var row: Dictionary = quests[quest_id]
		var id := String(quest_id)
		assert_eq(String(runtime.quests.status(id)), String(row.get("status", "")), id)
		assert_eq(runtime.quests.stage(id), String(row.get("stage", "")), id)
		if id == "ferry_toll":
			assert_eq(_journal_ids(runtime, id), _saved_journal_ids(row))
			assert_true(_journal_ids(runtime, id).has("j_ft_01"))
	var roles: Dictionary = data.get("roles", {})
	var bindings: Dictionary = roles.get("bindings", {})
	for role in bindings.keys():
		var row: Dictionary = bindings[role]
		var id := String(role)
		assert_eq(String(runtime.roles.holder(StringName(id))), String(row.get("holder", "")), id)
	var frozen: Dictionary = roles.get("frozen", {})
	var toll: Dictionary = frozen.get("ferry_toll", {})
	var lookout: Dictionary = toll.get("lookout", {})
	assert_eq(String(runtime.roles.slot_holder("ferry_toll", &"lookout")), String(lookout.get("holder", "")))
	var saved := runtime.save_state()
	assert_false(saved.is_empty())
	assert_eq(int(saved["schema_version"]), 4)
	var second: WyrdRuntime = harness.boot_gullhaven()["runtime"]
	var again := second.load_state(saved)
	assert_true(again.ok, again.diagnostics.format())
	assert_eq(JSON.stringify(saved, "\t", true), JSON.stringify(second.save_state(), "\t", true))
	# cross is waiting on toll.depart. One minute, then play that scene.
	runtime.tick(1)
	runtime.dialogue.open_scene("toll.depart")
	var rows := harness.line_rows(runtime)
	assert_eq(harness.ids_of(rows), PackedStringArray(["a_cross", "a_leave"]))
	assert_engine_error_count(0)


func _journal_ids(runtime: WyrdRuntime, quest_id: String) -> PackedStringArray:
	var ids := PackedStringArray()
	for entry in runtime.quests.journal(quest_id):
		ids.append(String(entry.get("id", "")))
	return ids


func _saved_journal_ids(row: Dictionary) -> PackedStringArray:
	var ids := PackedStringArray()
	for entry in row.get("journal", []):
		if entry is Dictionary:
			ids.append(String((entry as Dictionary).get("id", "")))
	return ids
