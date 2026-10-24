extends GutTest

## Current-schema loads share deed-row dictionaries without writing them.
## Results only. No timings.


const _Harness := preload("res://tests/scenario/s2c_harness.gd")


func test_current_schema_load_leaves_the_input_and_round_trips() -> void:
	var runtime := _boot()
	var deed_id := runtime.deeds.record(
		&"paid",
		&"player",
		&"ferry_master",
		&"gullhaven",
		PackedStringArray(["toll"]),
		2.0,
		PackedStringArray(["nia"]),
		&"secret",
		true
	)
	runtime.deeds.note_believer(deed_id, &"nia", 4)
	var saved := runtime.save_state()
	var before: Dictionary = saved.duplicate(true)
	var rows: Array = (saved["deeds"] as Dictionary)["rows"]
	var row0: Dictionary = rows[0]
	var verb := String(row0.get("verb", ""))
	var fresh := _blank()
	var report := fresh.load_state(saved)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(saved, before)
	assert_true(is_same((saved["deeds"] as Dictionary)["rows"], rows))
	assert_true(is_same(rows[0], row0))
	var exported: Dictionary = fresh.deeds.export_state().duplicate(true)
	row0["verb"] = "mutated_after_load"
	assert_eq(fresh.deeds.export_state(), exported)
	row0["verb"] = verb
	assert_eq(saved, before)
	fresh.tick(1)
	fresh.deeds.record(&"left", &"player")
	fresh.deeds.compact()
	assert_eq(saved, before)
	var text := JSON.stringify(before, "\t", true)
	var again := _blank()
	var loaded := again.load_state(JSON.parse_string(text))
	assert_true(loaded.ok, loaded.diagnostics.format())
	assert_eq(JSON.stringify(again.save_state(), "\t", true), text)


func test_older_schema_still_migrates_and_leaves_the_input() -> void:
	var schema2 := _load_fixture("res://tests/fixtures/schema2_harbor.json", 2)
	assert_eq(schema2.facts.get(&"player.coins"), 4)
	var schema3 := _load_fixture("res://tests/fixtures/schema3_harbor.json", 3)
	assert_eq(schema3.play_minutes(), 1)
	assert_eq(schema3.quests.stage("bell_repair"), "repair")


func test_a_refused_save_leaves_the_input() -> void:
	var saved := _boot().save_state()
	saved["seed"] = "nope"
	var before: Dictionary = saved.duplicate(true)
	var refused := _blank().load_state(saved)
	assert_push_error("16 hex")
	assert_false(refused.ok)
	assert_eq(saved, before)
	var future: Dictionary = before.duplicate(true)
	future["schema_version"] = 5
	var future_before: Dictionary = future.duplicate(true)
	var blank := _blank()
	assert_false(blank.load_state(future).ok)
	assert_eq(future, future_before)
	assert_null(blank.facts.get(&"player.coins"))


func _load_fixture(path: String, version: int) -> WyrdRuntime:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(parsed is Dictionary, path)
	var data: Dictionary = parsed
	assert_eq(int(data["schema_version"]), version, path)
	var before: Dictionary = data.duplicate(true)
	var runtime := _blank()
	var report := runtime.load_state(data)
	assert_true(report.ok, "%s %s" % [path, report.diagnostics.format()])
	assert_eq(data, before, path)
	assert_eq(int(runtime.save_state()["schema_version"]), 4, path)
	return runtime


func _boot() -> WyrdRuntime:
	return _Harness.new().boot_gullhaven(false, 4)["runtime"]


func _blank() -> WyrdRuntime:
	return _Harness.new().open_pack(_Harness.HARBOR)["runtime"]
