extends GutTest

## A removed stage moves by on_missing_stage, trail, or the first stage.

const _OLD := "res://tests/migration/packs/stage_old.wyrdmanifest.tres"
const _NEW := "res://tests/migration/packs/stage_new.wyrdmanifest.tres"


func test_each_removed_stage_moves() -> void:
	var saved := _played()
	var runtime := _boot(_NEW)
	var hits := _watch(runtime)
	var report := runtime.load_state(saved)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(report.error_count(), 0)
	assert_eq(runtime.quests.stage("ferry_toll"), "depart")
	assert_eq(runtime.quests.stage("dock_errand"), "hire")
	assert_eq(runtime.quests.stage("ferry_job#1"), "sign")
	assert_eq(runtime.quests.stage("tide_bell"), "toll")
	assert_eq(runtime.quests.stage("harbor_watch"), "offer")
	assert_eq(runtime.quests.stage("lantern_watch"), "watch")
	var loaded := runtime.save_state()
	var toll: Dictionary = loaded["quests"]["ferry_toll"]
	assert_eq(toll["trail"], ["arrive", "offer", "depart"])
	assert_true(bool(toll["entered"]))
	assert_eq(String(toll["variant"]), "")
	assert_eq(int(toll["step_at"]), 2)
	assert_eq(String(toll["outcomes"]["route"]), "done")
	assert_eq(loaded["quests"]["dock_errand"]["trail"], ["wait", "gone", "hire"])
	assert_eq(loaded["quests"]["ferry_job#1"]["trail"], ["wait", "hire", "sign"])
	assert_eq(String(loaded["quests"]["ferry_job#1"]["template"]), "ferry_job")
	assert_eq(int(loaded["quests"]["ferry_job#1"]["n"]), 1)
	assert_eq(loaded["quests"]["tide_bell"]["trail"], ["toll"])
	assert_eq(loaded["quests"]["harbor_watch"]["trail"], ["dock", "offer"])
	assert_eq(loaded["quests"]["lantern_watch"]["trail"], ["watch"])
	var wick: Dictionary = loaded["quests"]["lantern_watch"]["regions"]["wick"]
	assert_eq(String(wick["stage"]), "trim")
	assert_true(bool(wick["entered"]))
	assert_eq(int(wick["step_at"]), 2)
	_assert_unchanged(runtime, saved)
	assert_null(runtime.facts.get(&"world.stage_moved"))
	assert_null(runtime.facts.get(&"world.job_signed"))
	assert_null(runtime.facts.get(&"world.wick_lit"))
	assert_eq(_warnings(report), [
		"saved stage \"gone\" of \"dock_errand\" is gone; moved to \"hire\"",
		"saved stage \"hire\" of \"ferry_job#1\" is gone; moved to \"sign\"",
		"saved stage \"offer\" of \"ferry_toll\" is gone; moved to \"depart\"",
		"saved stage \"dark\" of \"lantern_watch/wick\" is gone; moved to \"trim\"",
	])
	assert_eq(report.rows, _expected_rows(saved, runtime), JSON.stringify(report.rows, "\t", true))
	assert_eq(hits[0], 1)
	runtime.tick(0)
	assert_eq(runtime.quests.stage("ferry_toll"), "done")
	assert_null(runtime.facts.get(&"world.stage_moved"))
	assert_null(runtime.facts.get(&"world.job_signed"))
	assert_null(runtime.facts.get(&"world.wick_lit"))
	assert_eq(runtime.quests.journal("ferry_toll"), saved["quests"]["ferry_toll"]["journal"])
	assert_eq(runtime.quests.stage("dock_errand"), "hire")
	assert_eq(runtime.quests.advance("dock_errand", "wait"), "")
	assert_eq(runtime.quests.stage("dock_errand"), "wait")
	assert_eq(runtime.quests.stage("ferry_job#1"), "sign")
	assert_eq(String(runtime.save_state()["quests"]["lantern_watch"]["regions"]["wick"]["stage"]), "trim")
	var resaved := runtime.save_state()
	assert_eq(
		JSON.stringify(resaved["quests"]["old_errand"], "\t", true),
		JSON.stringify(saved["quests"]["old_errand"], "\t", true)
	)
	var again := _boot(_NEW)
	var second := again.load_state(resaved)
	assert_true(second.ok, second.diagnostics.format())
	assert_eq(_kinds(second, "missing_stage"), [])
	assert_eq(second.rows, [_kept("old_errand", "quest")], JSON.stringify(second.rows, "\t", true))


func test_a_save_without_trail_uses_the_first_stage() -> void:
	var saved := _played()
	(saved["quests"]["dock_errand"] as Dictionary).erase("trail")
	var runtime := _boot(_NEW)
	var report := runtime.load_state(saved)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(runtime.quests.stage("dock_errand"), "wait")
	assert_eq(runtime.quests.stage("ferry_toll"), "depart")
	assert_eq(runtime.quests.stage("tide_bell"), "toll")
	var moved := _find(report, "dock_errand", "W_SAVE_STAGE")
	assert_eq(String(moved["from"]), "gone")
	assert_eq(String(moved["to"]), "wait")
	assert_eq(String(moved["kind"]), "missing_stage")


func test_old_content_keeps_the_saved_stages() -> void:
	var saved := _played()
	var runtime := _boot(_OLD)
	var report := runtime.load_state(saved)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(report.rows, [])
	assert_eq(runtime.quests.stage("ferry_toll"), "offer")
	assert_eq(runtime.quests.stage("dock_errand"), "gone")
	assert_eq(runtime.quests.stage("lantern_watch"), "watch")
	assert_eq(String(runtime.save_state()["quests"]["lantern_watch"]["regions"]["wick"]["stage"]), "dark")
	assert_eq(runtime.quests.stage("old_errand"), "wait")


func _played() -> Dictionary:
	var runtime := _boot(_OLD)
	runtime.quests.start("ferry_toll")
	assert_eq(runtime.quests.advance("ferry_toll", "offer"), "")
	runtime.quests.start("dock_errand")
	assert_eq(runtime.quests.advance("dock_errand", "hire"), "")
	assert_eq(runtime.quests.advance("dock_errand", "gone"), "")
	var id := runtime.quests.create_instance("ferry_job")
	assert_eq(id, "ferry_job#1")
	assert_eq(runtime.quests.advance(id, "hire"), "")
	runtime.quests.start("lantern_watch")
	runtime.quests.start("tide_bell")
	runtime.quests.start("harbor_watch")
	assert_eq(runtime.quests.advance("harbor_watch", "offer"), "")
	runtime.quests.start("old_errand")
	runtime.facts.set(&"world.note", &"kept")
	runtime.deeds.record(&"arrived", &"player")
	var saved := runtime.save_state()
	assert_eq(saved["quests"]["ferry_toll"]["trail"], ["arrive", "offer"])
	assert_eq(saved["quests"]["dock_errand"]["trail"], ["wait", "hire", "gone"])
	assert_eq(saved["quests"]["ferry_job#1"]["trail"], ["wait", "hire"])
	assert_eq(saved["quests"]["lantern_watch"]["trail"], ["watch"])
	assert_eq(String(saved["quests"]["lantern_watch"]["regions"]["wick"]["stage"]), "dark")
	assert_eq(saved["quests"]["tide_bell"]["trail"], ["ring"])
	assert_eq(saved["quests"]["harbor_watch"]["trail"], ["arrive", "offer"])
	assert_eq(saved["quests"]["old_errand"]["trail"], ["wait"])
	assert_eq(String(saved["quests"]["ferry_toll"]["outcomes"]["route"]), "done")
	assert_false((saved["quests"]["ferry_toll"]["journal"] as Array).is_empty())
	return saved


func _boot(path: String) -> WyrdRuntime:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var manifest := load(path) as WyrdContentManifest
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(7)
	var world := runtime.adapter(WyrdWorldAdapter) as WyrdFakeWorld
	world.add_entity(&"player", &"person", "traveler", PackedStringArray(), true)
	return runtime


func _watch(runtime: WyrdRuntime) -> Array:
	var hits := [0]
	runtime.load_report_ready.connect(func(_report): hits[0] += 1)
	return hits


func _assert_unchanged(runtime: WyrdRuntime, saved: Dictionary) -> void:
	assert_eq(
		JSON.stringify(runtime.facts.export_state(), "\t", true),
		JSON.stringify(saved["facts"], "\t", true)
	)
	assert_eq(
		JSON.stringify(runtime.deeds.export_state(), "\t", true),
		JSON.stringify(saved["deeds"], "\t", true)
	)
	var quests: Dictionary = saved["quests"]
	for quest_id in quests.keys():
		var key := String(quest_id)
		if key == "old_errand":
			continue
		var row: Dictionary = quests[key]
		assert_eq(runtime.quests.journal(key), row.get("journal", []), key)


func _expected_rows(saved: Dictionary, runtime: WyrdRuntime) -> Array:
	var rows: Array = [
		_alias("stage:tide_bell", "ring", "toll", 1, ""),
		_alias("trail:harbor_watch:arrive", "arrive", "dock", 1, ""),
		_alias("trail:tide_bell:ring", "ring", "toll", 1, ""),
		_kept("old_errand", "quest"),
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
	rows.append(_move("dock_errand", "gone", "hire"))
	rows.append(_move("ferry_job#1", "hire", "sign"))
	rows.append(_move("ferry_toll", "offer", "depart"))
	rows.append(_move("lantern_watch/wick", "dark", "trim"))
	return rows


func _warnings(report: WyrdLoadReport) -> Array:
	var messages: Array = []
	for item in report.diagnostics.items:
		if String(item.code) == "W_SAVE_STAGE":
			messages.append(item.message)
	return messages


func _kinds(report: WyrdLoadReport, kind: String) -> Array:
	var rows: Array = []
	for item in report.rows:
		var row: Dictionary = item
		if String(row["kind"]) == kind:
			rows.append(row)
	return rows


func _find(report: WyrdLoadReport, id: String, code: String) -> Dictionary:
	for row in report.rows:
		var body: Dictionary = row
		if String(body["id"]) == id and String(body["code"]) == code:
			return body
	push_error("missing row %s %s" % [id, code])
	return {}


func _alias(id: String, from_id: String, to_id: String, count: int, code: String) -> Dictionary:
	return {
		"code": code,
		"count": count,
		"from": from_id,
		"id": id,
		"kind": "alias",
		"to": to_id,
	}


func _move(id: String, from_id: String, to_id: String) -> Dictionary:
	return {
		"code": "W_SAVE_STAGE",
		"count": 1,
		"from": from_id,
		"id": id,
		"kind": "missing_stage",
		"to": to_id,
	}


func _kept(id: String, store: String) -> Dictionary:
	return {
		"code": "",
		"count": 1,
		"from": store,
		"id": id,
		"kind": "kept",
		"to": "",
	}
