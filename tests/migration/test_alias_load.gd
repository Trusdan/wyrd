extends GutTest

## An old harbor save loads through the new pack's alias tables.

const _OLD := "res://tests/migration/packs/harbor_old.wyrdmanifest.tres"
const _NEW := "res://tests/migration/packs/harbor_new.wyrdmanifest.tres"


func test_old_save_loads_into_new_content() -> void:
	var saved := _played()
	var runtime := _boot(_NEW)
	var hits := _watch(runtime)
	var report := runtime.load_state(saved)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(report.error_count(), 0)
	assert_eq(runtime.quests.stage("ferry_toll"), "depart")
	assert_eq(runtime.quests.stage("ferry_job#1"), "sign")
	assert_eq(runtime.roles.holder(&"dock_master"), &"player")
	assert_true(runtime.roles.revealed(&"dock_clerk", &"role.dock_master.holder"))
	assert_false(runtime.roles.revealed(&"player", &"role.dock_master.holder"))
	assert_eq(runtime.deeds.verb_at(0), &"settle")
	assert_eq(runtime.deeds.verb_at(1), &"arrived")
	assert_eq(runtime.deeds.verb_at(2), &"settle")
	assert_true(runtime.documents.has_read(&"player", &"tide_notice"))
	assert_false(runtime.documents.has_read(&"player", &"harbor_gazette"))
	assert_true(runtime.documents.has_copy(&"tide_notice", "kept"))
	assert_false(runtime.documents.has_copy(&"harbor_gazette", "kept"))
	var opened := runtime.documents.open(&"tide_notice", "kept", &"player")
	assert_eq(opened.pages[0][0]["text"], "The tide is in.")
	_assert_no_kept(report)
	assert_eq(report.rows, _expected_rows(saved, runtime), JSON.stringify(report.rows, "\t", true))
	assert_eq(hits[0], 1)
	_assert_new_ids(runtime.save_state())


func test_resave_and_old_content_add_no_alias_rows() -> void:
	var saved := _played()
	var runtime := _boot(_NEW)
	assert_true(runtime.load_state(saved).ok)
	var resaved := runtime.save_state()
	_assert_new_ids(resaved)
	var hits := _watch(runtime)
	var again := runtime.load_state(resaved)
	assert_true(again.ok, again.diagnostics.format())
	assert_eq(again.rows, [])
	assert_eq(hits[0], 1)
	var old := _boot(_OLD)
	var back := old.load_state(saved)
	assert_true(back.ok, back.diagnostics.format())
	assert_eq(back.rows, [])
	assert_eq(old.quests.stage("ferry_toll"), "offer")
	assert_eq(old.quests.stage("ferry_job#1"), "hire")
	assert_eq(old.roles.holder(&"ferry_master"), &"player")
	assert_true(old.roles.revealed(&"dock_clerk", &"role.ferry_master.holder"))
	assert_eq(old.deeds.verb_at(0), &"paid")
	assert_eq(old.deeds.verb_at(1), &"arrived")
	assert_true(old.documents.has_read(&"player", &"harbor_gazette"))
	assert_true(old.documents.has_copy(&"harbor_gazette", "kept"))


func test_a_refused_save_has_only_its_refused_row() -> void:
	var saved := _played()
	saved["seed"] = "nope"
	var runtime := _boot(_NEW)
	var before := JSON.stringify(runtime.save_state(), "\t", true)
	var hits := _watch(runtime)
	var report := runtime.load_state(saved)
	assert_push_error("16 hex")
	assert_false(report.ok)
	assert_eq(report.rows.size(), 1)
	var row: Dictionary = report.rows[0]
	assert_eq(String(row["kind"]), "refused")
	assert_eq(String(row["id"]), "seed")
	assert_eq(String(row["code"]), "E_SAVE_VERSION")
	assert_eq(String(row["from"]), "")
	assert_eq(String(row["to"]), "")
	assert_eq(int(row["count"]), 0)
	assert_eq(JSON.stringify(runtime.save_state(), "\t", true), before)
	assert_eq(hits[0], 1)


func test_a_document_collision_on_the_old_save() -> void:
	var saved := _played()
	var reads: Array = saved["documents"]["read"]
	reads.append({"doc": "harbor_gazette", "reader": "dock_clerk"})
	reads.append({"doc": "tide_notice", "reader": "player"})
	var runtime := _boot(_NEW)
	var report := runtime.load_state(saved)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(report.error_count(), 0)
	assert_true(runtime.documents.has_read(&"player", &"tide_notice"))
	assert_true(runtime.documents.has_read(&"dock_clerk", &"tide_notice"))
	assert_false(runtime.documents.has_read(&"player", &"harbor_gazette"))
	assert_true(runtime.documents.has_copy(&"tide_notice", "kept"))
	_assert_no_kept(report)
	_assert_collision(report, "document:harbor_gazette", "harbor_gazette", "tide_notice", 1)
	var rewrite := _find(report, "document:harbor_gazette", "")
	assert_eq(int(rewrite["count"]), 2)


func test_a_role_collision_on_the_old_save() -> void:
	var saved := _played()
	var bindings: Dictionary = saved["roles"]["bindings"]
	var kept: Dictionary = (bindings["ferry_master"] as Dictionary).duplicate(true)
	kept["holder"] = "dock_clerk"
	bindings["dock_master"] = kept
	var runtime := _boot(_NEW)
	var report := runtime.load_state(saved)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(report.error_count(), 0)
	assert_eq(runtime.roles.holder(&"dock_master"), &"dock_clerk")
	assert_true(runtime.roles.revealed(&"dock_clerk", &"role.dock_master.holder"))
	_assert_collision(report, "role:ferry_master", "ferry_master", "dock_master", 1)
	var rewrite := _find(report, "role:ferry_master", "")
	assert_eq(int(rewrite["count"]), 2)


func _played() -> Dictionary:
	var runtime := _boot(_OLD)
	runtime.quests.start("ferry_toll")
	assert_eq(runtime.quests.advance("ferry_toll", "offer"), "")
	var id := runtime.quests.create_instance("ferry_job")
	assert_eq(id, "ferry_job#1")
	assert_eq(runtime.quests.advance(id, "hire"), "")
	runtime.roles.assign(&"ferry_master", &"player")
	runtime.roles.tell(&"ferry_master", &"dock_clerk")
	runtime.deeds.record(&"paid", &"player")
	runtime.deeds.record(&"arrived", &"player")
	runtime.deeds.record(&"paid", &"player")
	assert_true(runtime.documents.create_copy(&"harbor_gazette", "kept"))
	var opened := runtime.documents.open(&"harbor_gazette", "kept", &"player")
	assert_eq(opened.pages[0][0]["text"], "The tide is in.")
	assert_eq(runtime.quests.stage("ferry_toll"), "offer")
	assert_eq(runtime.quests.stage("ferry_job#1"), "hire")
	return runtime.save_state()


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
	world.add_entity(&"dock_clerk", &"person", "clerk", PackedStringArray(), true)
	return runtime


func _watch(runtime: WyrdRuntime) -> Array:
	var hits := [0]
	runtime.load_report_ready.connect(func(_report): hits[0] += 1)
	return hits


func _expected_rows(saved: Dictionary, runtime: WyrdRuntime) -> Array:
	var rows: Array = [
		_alias("document:harbor_gazette", "harbor_gazette", "tide_notice", 2, ""),
		_alias("role:ferry_master", "ferry_master", "dock_master", 3, ""),
		_alias("stage:ferry_job#1", "hire", "sign", 1, ""),
		_alias("stage:ferry_toll", "offer", "depart", 1, ""),
		_alias("verb:paid", "paid", "settle", 2, ""),
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


func _assert_new_ids(data: Dictionary) -> void:
	var quests: Dictionary = data["quests"]
	assert_eq(String(quests["ferry_toll"]["stage"]), "depart")
	assert_eq(String(quests["ferry_job#1"]["stage"]), "sign")
	var roles: Dictionary = data["roles"]
	assert_false((roles["bindings"] as Dictionary).has("ferry_master"))
	assert_true((roles["bindings"] as Dictionary).has("dock_master"))
	assert_false((roles["defs"] as Dictionary).has("ferry_master"))
	assert_true((roles["defs"] as Dictionary).has("dock_master"))
	assert_false((roles["told"] as Dictionary).has("ferry_master"))
	assert_true((roles["told"] as Dictionary).has("dock_master"))
	for item in data["deeds"]["rows"]:
		var verb := String((item as Dictionary)["verb"])
		assert_ne(verb, "paid")
		assert_ne(verb, "pay")
	for item in data["documents"]["read"]:
		assert_eq(String((item as Dictionary)["doc"]), "tide_notice")
	for item in data["documents"]["copies"]:
		assert_eq(String((item as Dictionary)["doc"]), "tide_notice")
	var known: Dictionary = data["facts"]["known"]["dock_clerk"]
	assert_true(known.has("role.ferry_master.holder"))


func _assert_no_kept(report: WyrdLoadReport) -> void:
	for row in report.rows:
		assert_ne(String((row as Dictionary)["kind"]), "kept")


func _assert_collision(report: WyrdLoadReport, id: String, old: String, new_id: String, count: int) -> void:
	var found := 0
	for item in report.diagnostics.items:
		if String(item.code) != "W_SAVE_ALIAS":
			continue
		found += 1
		assert_eq(item.severity, WyrdDiagnostic.SEVERITY_WARNING)
		assert_eq(item.message, "saved %s \"%s\" was dropped because \"%s\" is also saved" % [id.split(":")[0], old, new_id])
	assert_eq(found, 1)
	var row := _find(report, id, "W_SAVE_ALIAS")
	assert_eq(String(row["from"]), old)
	assert_eq(String(row["to"]), new_id)
	assert_eq(int(row["count"]), count)
	assert_eq(String(row["kind"]), "alias")


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
