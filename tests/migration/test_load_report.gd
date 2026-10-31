extends GutTest

## Load report rows, the load_report_ready signal, and refusal before import.

const _Load := preload("res://tests/migration/fixture_load.gd")
const _Harness := preload("res://tests/scenario/s2c_harness.gd")
const _SCHEMA4 := "res://tests/fixtures/schema4_ai_harbor.json"
const _M9 := "res://tests/migration/fixtures/gullhaven_v0.7.0-m9.json"
const _M10 := "res://tests/migration/fixtures/gullhaven_v0.8.0-m10.json"


func test_clean_load_has_no_rows() -> void:
	var runtime := _fresh()
	var saved := runtime.save_state()
	var hits := _watch(runtime)
	var report := runtime.load_state(saved)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(report.rows.size(), 0)
	assert_eq(report.diagnostics.items.size(), 0)
	assert_eq(hits[0], 1)


func test_fixture_rows_match_diagnostics() -> void:
	var paths: Array[String] = [
		"res://tests/fixtures/schema2_harbor.json",
		"res://tests/fixtures/schema3_harbor.json",
		_SCHEMA4,
		"res://tests/migration/fixtures/schema1_harbor.json",
		_M9,
		_M10,
	]
	for path in paths:
		var runtime := _fresh()
		var report := runtime.load_state(_Load.read(path))
		assert_eq(report.rows.size(), report.diagnostics.items.size(), path)
		var row_codes := PackedStringArray()
		for row in report.rows:
			row_codes.append(String((row as Dictionary)["code"]))
		row_codes.sort()
		assert_eq(row_codes, _Load.codes(report), path)


func test_manifest_row_names_both_hashes() -> void:
	var runtime := _fresh()
	var hits := _watch(runtime)
	var report := runtime.load_state(_Load.read(_M9))
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(report.rows.size(), 1)
	var row: Dictionary = report.rows[0]
	_assert_keys(row)
	assert_eq(String(row["kind"]), "manifest")
	assert_eq(String(row["code"]), "W_SAVE_MANIFEST")
	assert_eq(String(row["from"]), "8bf113c14f107242")
	assert_eq(String(row["to"]), "918b2aad2be7d4fa")
	assert_eq(int(row["count"]), 0)
	assert_eq(String(row["id"]), "")
	assert_eq(hits[0], 1)


func test_kept_storylet_row() -> void:
	var runtime := _fresh()
	var data := _copy(runtime.save_state())
	data["storylets"] = {"unknown_story": {"seen": 1}}
	var hits := _watch(runtime)
	var report := runtime.load_state(data)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(report.diagnostics.items.size(), 0)
	assert_eq(report.rows.size(), 1)
	var row: Dictionary = report.rows[0]
	assert_eq(String(row["kind"]), "kept")
	assert_eq(String(row["id"]), "unknown_story")
	assert_eq(String(row["from"]), "storylet")
	assert_eq(int(row["count"]), 1)
	assert_eq(String(row["code"]), "")
	assert_eq(hits[0], 1)


func test_rows_sort_by_kind_then_id_then_code() -> void:
	var data := _copy(_Load.read(_M9))
	data["storylets"] = {"unknown_story": {"seen": 1}}
	data["sequences"] = {"unknown_seq": {"count": 1, "done": false}}
	var report := _fresh().load_state(data)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(report.rows.size(), 3)
	assert_eq(String(report.rows[0]["kind"]), "kept")
	assert_eq(String(report.rows[0]["id"]), "unknown_seq")
	assert_eq(String(report.rows[0]["from"]), "sequence")
	assert_eq(String(report.rows[1]["kind"]), "kept")
	assert_eq(String(report.rows[1]["id"]), "unknown_story")
	assert_eq(String(report.rows[2]["kind"]), "manifest")
	assert_eq(String(report.rows[2]["code"]), "W_SAVE_MANIFEST")


func test_template_row() -> void:
	var runtime := _fresh()
	var data := runtime.save_state()
	data["generator"] = {
		"counters": {"no_such": 1},
		"instances": {"no_such#1": {"casts": {}}},
	}
	var hits := _watch(runtime)
	var report := runtime.load_state(data)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(_codes(report), _one("W_SAVE_TEMPLATE"))
	assert_eq(report.rows.size(), 1)
	var row: Dictionary = report.rows[0]
	assert_eq(String(row["kind"]), "template")
	assert_eq(String(row["id"]), "no_such")
	assert_eq(int(row["count"]), 1)
	assert_eq(String(row["code"]), "W_SAVE_TEMPLATE")
	assert_eq(hits[0], 1)


func test_ai_row() -> void:
	var runtime := _fresh()
	var data := runtime.save_state()
	data["ai"] = "nope"
	var hits := _watch(runtime)
	var report := runtime.load_state(data)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(_codes(report), _one("W_SAVE_AI"))
	assert_eq(report.rows.size(), 1)
	var row: Dictionary = report.rows[0]
	assert_eq(String(row["kind"]), "ai")
	assert_eq(String(row["code"]), "W_SAVE_AI")
	assert_eq(int(row["count"]), 0)
	assert_eq(hits[0], 1)


func test_policy_row() -> void:
	var runtime := _fresh()
	var data := runtime.save_state()
	var flight: Dictionary = data.get("flight", {}) if data.get("flight") is Dictionary else {}
	flight["rumor"] = {
		"jobs": [{
			"chance": 0.5,
			"deed": "9",
			"key": "k",
			"kinds": [],
			"max_hops": 1,
			"policy": "missing_policy",
			"value": "x",
			"verb": "say",
		}],
	}
	data["flight"] = flight
	var hits := _watch(runtime)
	var report := runtime.load_state(data)
	assert_push_error("missing_policy")
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(_codes(report), _one("E_SAVE_POLICY"))
	assert_eq(report.rows.size(), 1)
	var row: Dictionary = report.rows[0]
	assert_eq(String(row["kind"]), "policy")
	assert_eq(String(row["id"]), "9")
	assert_eq(String(row["code"]), "E_SAVE_POLICY")
	assert_eq(hits[0], 1)


func test_bad_seed_refuses_before_import() -> void:
	var data := _copy(_Load.read(_SCHEMA4))
	data["seed"] = "not-a-seed"
	_refuse(data, "seed", "16 hex")


func test_bad_pack_hash_refuses_before_import() -> void:
	var data := _copy(_Load.read(_SCHEMA4))
	(data["content"]["packs"][0] as Dictionary)["hash"] = "zz"
	_refuse(data, "content.packs.0.hash", "16 hex")


func test_bad_rng_state_refuses_before_import() -> void:
	var data := _copy(_Load.read(_SCHEMA4))
	data["rng"] = {
		"chance": {
			"inc": "0000000000000001",
			"seed": "0000000000000001",
			"state": "zz",
			"v": 1,
		},
	}
	_refuse(data, "rng.chance", "WyrdRng")


func test_schema_5_refuses_before_import() -> void:
	var data := _copy(_Load.read(_SCHEMA4))
	data["schema_version"] = 5
	var report := _refuse(data, "schema_version", "")
	assert_true(String(report.diagnostics.items[0].message).find("no migration from save schema 5") >= 0)


func test_missing_schema_refuses_before_import() -> void:
	var data := _copy(_Load.read(_SCHEMA4))
	data.erase("schema_version")
	var report := _refuse(data, "schema_version", "")
	assert_true(String(report.diagnostics.items[0].message).find("missing") >= 0)


func test_wrong_typed_field_refuses_before_import() -> void:
	var data := _fresh().save_state()
	(data["quests"]["ferry_toll"] as Dictionary)["outcomes"] = "nope"
	var report := _refuse(data, "quests.ferry_toll.outcomes", "")
	assert_true(String(report.diagnostics.items[0].message).find("quests.ferry_toll.outcomes must be a dictionary") >= 0)
	assert_engine_error_count(0)


func test_no_packs_and_no_content_stays_save_version() -> void:
	var runtime := WyrdRuntime.new()
	var before := _text(runtime)
	var hits := _watch(runtime)
	var report := runtime.load_state({"schema_version": 4, "seed": "0000000000000001"})
	assert_false(report.ok)
	_assert_refused(report, "content", "E_SAVE_VERSION")
	assert_eq(String(report.diagnostics.items[0].message), "load content before loading a save")
	assert_eq(_text(runtime), before)
	assert_eq(hits[0], 1)
	assert_false(runtime.save_state().is_empty())


func test_listed_packs_with_no_content_are_content_missing() -> void:
	var runtime := WyrdRuntime.new()
	var before := _text(runtime)
	var hits := _watch(runtime)
	var report := runtime.load_state({
		"content": {
			"packs": [
				{"hash": "0000000000000001", "id": "roads"},
				{"hash": "0000000000000002", "id": "harbor"},
				{"hash": "0000000000000003", "id": ""},
			],
		},
		"schema_version": 5,
		"seed": "0000000000000001",
	})
	assert_false(report.ok)
	_assert_refused(report, "content", "E_CONTENT_MISSING")
	assert_eq(String(report.diagnostics.items[0].message), "content not loaded; missing packs \"harbor\", \"roads\"")
	assert_eq(_text(runtime), before)
	assert_eq(hits[0], 1)
	assert_false(runtime.save_state().is_empty())


func test_scene_open_refuses_before_import() -> void:
	var runtime := _fresh()
	var before := _text(runtime)
	var hits := _watch(runtime)
	var incoming: Dictionary = JSON.parse_string(before)
	runtime.dialogue.open_scene("toll.offer_room")
	(incoming["facts"]["world"] as Dictionary)["player.coins"] = 99
	var report := runtime.load_state(incoming)
	assert_push_error("a scene is open")
	assert_false(report.ok)
	_assert_refused(report, "scene", "E_SAVE_OPEN")
	assert_eq(hits[0], 1)
	assert_eq(runtime.facts.get(&"player.coins"), 4)
	runtime.dialogue._stack.clear()
	assert_eq(_text(runtime), before)


func test_load_content_does_not_emit() -> void:
	var runtime := WyrdRuntime.new()
	var hits := _watch(runtime)
	var report := runtime.load_content(load(_Harness.HARBOR))
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(report.rows.size(), 0)
	assert_eq(hits[0], 0)


func test_facade_repeats_the_signal() -> void:
	var facade = load("res://addons/wyrd/runtime/wyrd.gd").new()
	var hits := [0]
	facade.load_report_ready.connect(func(_report): hits[0] += 1)
	var loaded = facade.load_content(load(_Harness.HARBOR))
	assert_true(loaded.ok, loaded.diagnostics.format())
	assert_eq(loaded.rows.size(), 0)
	assert_eq(hits[0], 0)
	var report = facade.load_state(facade.save_state())
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(hits[0], 1)
	facade.free()


func _refuse(data: Dictionary, id: String, needle: String) -> WyrdLoadReport:
	var runtime := _fresh()
	var before := _text(runtime)
	var hits := _watch(runtime)
	var report := runtime.load_state(data)
	if needle != "":
		assert_push_error(needle)
	assert_false(report.ok, id)
	_assert_refused(report, id, "E_SAVE_VERSION")
	assert_eq(_text(runtime), before, id)
	assert_eq(hits[0], 1, id)
	assert_false(runtime.save_state().is_empty(), id)
	return report


func _assert_refused(report: WyrdLoadReport, id: String, code: String) -> void:
	var found := 0
	for row in report.rows:
		if String((row as Dictionary).get("kind", "")) != "refused":
			continue
		found += 1
		assert_eq(String((row as Dictionary)["id"]), id)
		assert_eq(String((row as Dictionary)["code"]), code)
	assert_eq(found, 1, id)


func _assert_keys(row: Dictionary) -> void:
	var keys: Array = row.keys()
	keys.sort()
	assert_eq(keys, ["code", "count", "from", "id", "kind", "to"])


func _fresh() -> WyrdRuntime:
	return _Harness.new().boot_gullhaven()["runtime"]


func _watch(runtime: WyrdRuntime) -> Array:
	var hits := [0]
	runtime.load_report_ready.connect(func(_report): hits[0] += 1)
	return hits


func _text(runtime: WyrdRuntime) -> String:
	return JSON.stringify(runtime.save_state(), "\t", true)


func _copy(data: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(data))


func _codes(report: WyrdLoadReport) -> PackedStringArray:
	return _Load.codes(report)


func _one(code: String) -> PackedStringArray:
	var out := PackedStringArray()
	out.append(code)
	return out
