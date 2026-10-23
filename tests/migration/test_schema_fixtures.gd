extends GutTest

## One save per schema loads, keeps the fixture's own key state, and round-trips.
## Schema 1 is generated. Schemas 2, 3, and 4 stay in tests/fixtures/.

const _Load := preload("res://tests/migration/fixture_load.gd")
const _Harness := preload("res://tests/scenario/s2c_harness.gd")
const _CURRENT_HASH := "f003b6b54c91ad8e"


func test_schema_1_fixture_loads_and_round_trips() -> void:
	_check("res://tests/migration/fixtures/schema1_harbor.json", 1, "886d9ba3e5447ff4")


func test_schema_2_fixture_loads_and_round_trips() -> void:
	_check("res://tests/fixtures/schema2_harbor.json", 2, "f003b6b54c91ad8e")


func test_schema_3_fixture_loads_and_round_trips() -> void:
	_check("res://tests/fixtures/schema3_harbor.json", 3, "f003b6b54c91ad8e")


func test_schema_4_fixture_loads_and_round_trips() -> void:
	_check("res://tests/fixtures/schema4_ai_harbor.json", 4, "f003b6b54c91ad8e")


func _check(path: String, schema: int, fixture_hash: String) -> void:
	var data := _Load.read(path)
	assert_eq(int(data["schema_version"]), schema)
	assert_eq(_Load.pack_hash(data), fixture_hash)
	var harness := _Harness.new()
	var opened: Dictionary = harness.open_pack(_Harness.HARBOR)
	var loaded = opened["report"]
	assert_true(loaded.ok, loaded.diagnostics.format())
	var runtime: WyrdRuntime = opened["runtime"]
	var current := WyrdRng.format_u64(runtime.content().manifest_hash)
	assert_eq(current, _CURRENT_HASH)
	var report := runtime.load_state(data)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(_Load.codes(report), _Load.manifest_warning(fixture_hash, current))
	_assert_key_state(runtime, data)
	var saved := runtime.save_state()
	assert_false(saved.is_empty())
	assert_eq(int(saved["schema_version"]), 4)
	var second: WyrdRuntime = harness.open_pack(_Harness.HARBOR)["runtime"]
	var again := second.load_state(saved)
	assert_true(again.ok, again.diagnostics.format())
	var resaved := second.save_state()
	assert_eq(JSON.stringify(saved, "\t", true), JSON.stringify(resaved, "\t", true))
	assert_engine_error_count(0)


func _assert_key_state(runtime: WyrdRuntime, data: Dictionary) -> void:
	assert_eq(WyrdRng.format_u64(runtime.game_seed()), String(data["seed"]))
	assert_eq(runtime.play_minutes(), int(data["minutes"]))
	var facts: Dictionary = data.get("facts", {})
	var world: Dictionary = facts.get("world", {})
	if world.has("player.coins"):
		assert_eq(int(runtime.facts.get(&"player.coins")), int(world["player.coins"]))
	var quests: Dictionary = data.get("quests", {})
	for quest_id in quests.keys():
		var row: Dictionary = quests[quest_id]
		var id := String(quest_id)
		assert_eq(String(runtime.quests.status(id)), String(row.get("status", "")), id)
		assert_eq(runtime.quests.stage(id), String(row.get("stage", "")), id)
	var roles: Dictionary = data.get("roles", {})
	var bindings: Dictionary = roles.get("bindings", {})
	for role in bindings.keys():
		var row: Dictionary = bindings[role]
		var id := String(role)
		assert_eq(String(runtime.roles.holder(StringName(id))), String(row.get("holder", "")), id)
	var frozen: Dictionary = roles.get("frozen", {})
	for quest_id in frozen.keys():
		var slots: Variant = frozen[quest_id]
		if not (slots is Dictionary):
			continue
		var bag: Dictionary = slots
		for slot_name in bag.keys():
			var snap: Variant = bag[slot_name]
			if not (snap is Dictionary) or not (snap as Dictionary).has("holder"):
				continue
			var slot := String(slot_name)
			assert_eq(
				String(runtime.roles.slot_holder(String(quest_id), StringName(slot))),
				String((snap as Dictionary)["holder"]),
				"%s.%s" % [quest_id, slot]
			)
