extends GutTest

## A Gullhaven save at pay_toll loads into the side pack at toll_due.


const _Harness := preload("res://tests/scenario/s2c_harness.gd")
const _Election := preload("res://example/playtest/harbor_election.gd")
const _NEXT := "res://example/versions/gullhaven_next/harbor_next.wyrdmanifest.tres"


func test_pay_toll_save_loads_as_toll_due() -> void:
	var harness := _Harness.new()
	var opened: Dictionary = harness.boot_gullhaven()
	var runtime: WyrdRuntime = opened["runtime"]
	assert_eq(runtime.quests.offered_scene("ferry_toll"), "toll.offer_room")
	runtime.dialogue.open_scene("toll.offer_room")
	_drain(runtime)
	harness.choose_text(runtime, "Take the room")
	_drain(runtime)
	assert_eq(runtime.quests.stage("ferry_toll"), "pay_toll")
	assert_false(runtime.dialogue.is_open())
	var saved := runtime.save_state()
	assert_false(saved.is_empty())
	var next := _boot_next()
	var hits := [0]
	next.load_report_ready.connect(func(_report: WyrdLoadReport) -> void: hits[0] += 1)
	var report := next.load_state(saved)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(next.quests.stage("ferry_toll"), "toll_due")
	assert_eq(report.rows, _expected_rows(saved, next), JSON.stringify(report.rows, "\t", true))
	assert_eq(hits[0], 1)
	var kept := false
	for entry in next.quests.journal("ferry_toll"):
		if String(entry["id"]) == "j_ft_01":
			kept = true
	assert_true(kept, "j_ft_01")
	next.tick(1)
	assert_eq(next.quests.stage("ferry_toll"), "cross")
	var resaved := next.save_state()
	var again := next.load_state(resaved)
	assert_true(again.ok, again.diagnostics.format())
	assert_eq(again.rows, [])
	var checked: Dictionary = WyrdCli.execute(PackedStringArray(["check", "--manifest", _NEXT]))
	assert_eq(int(checked["exit_code"]), 0, String(checked["output"]))


func _boot_next() -> WyrdRuntime:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	runtime.register_adapter(WyrdElectionAdapter, _Election.new())
	runtime.roles.set_host_decides(func(_role: StringName, _departed: StringName) -> void:
		pass
	)
	var loaded := runtime.load_content(load(_NEXT) as WyrdContentManifest)
	assert_true(loaded.ok, loaded.diagnostics.format())
	runtime.start_new_game(1)
	host.world.add_entity(&"player", &"person", "traveler", PackedStringArray(), true)
	host.world.add_entity(&"tavern_owner", &"person", "innkeeper", PackedStringArray(), true)
	host.world.add_entity(&"ferry_master", &"person", "Bram", PackedStringArray(), true)
	host.world.add_entity(&"storm_watcher", &"person", "watcher", PackedStringArray(), true)
	host.world.add_entity(&"dock_apprentice", &"person", "Nia", PackedStringArray(), true)
	host.world.add_entity(&"dock.bell", &"object", "bell", PackedStringArray(), true)
	return runtime


func _drain(runtime: WyrdRuntime) -> void:
	var guard := 0
	while runtime.dialogue.line() != null and guard < 30:
		runtime.dialogue.advance()
		guard += 1


func _expected_rows(saved: Dictionary, runtime: WyrdRuntime) -> Array:
	var rows: Array = [
		_alias("stage:ferry_toll", "pay_toll", "toll_due", 1, ""),
		_alias("trail:ferry_toll:pay_toll", "pay_toll", "toll_due", 1, ""),
	]
	if OS.is_debug_build():
		var packs: Array = saved["content"]["packs"]
		var from_hash := String((packs[0] as Dictionary)["hash"])
		rows.append({
			"code": "W_SAVE_MANIFEST",
			"count": 0,
			"from": from_hash,
			"id": "",
			"kind": "manifest",
			"to": WyrdRng.format_u64(runtime.content().manifest_hash),
		})
	return rows


func _alias(id: String, from_id: String, to_id: String, count: int, code: String) -> Dictionary:
	return {
		"code": code,
		"count": count,
		"from": from_id,
		"id": id,
		"kind": "alias",
		"to": to_id,
	}
