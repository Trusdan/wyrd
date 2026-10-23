extends GutTest

## Document aliases rewrite publish state. Verb aliases rewrite in-flight rumors.
## A role neither the content nor the host defines is a kept row.

const _OLD := "res://tests/migration/packs/notice_old.wyrdmanifest.tres"
const _NEW := "res://tests/migration/packs/notice_new.wyrdmanifest.tres"


func test_publish_rumor_and_a_removed_role() -> void:
	var saved := _played()
	var runtime := _boot(_NEW)
	runtime.roles.define(&"harbor_watch")
	runtime.register_rumor_policy(_policy())
	var hits := _watch(runtime)
	var report := runtime.load_state(saved)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(report.error_count(), 0)
	assert_eq(report.rows, _expected_rows(saved, runtime), JSON.stringify(report.rows, "\t", true))
	assert_eq(hits[0], 1)
	var loaded := runtime.save_state()
	var publish: Dictionary = loaded["flight"]["publish"]
	assert_eq(int(publish["counters"]["tide_notice"]), 1)
	assert_false((publish["counters"] as Dictionary).has("harbor_gazette"))
	assert_eq(int(publish["covered"]["tide_notice"]), 60)
	assert_eq(publish["queued"], ["tide_notice\t60"])
	var tokens: Array = loaded["flight"]["scheduler"]["publish"]
	assert_eq(String(tokens[0]), "issue\ttide_notice\t1\t60")
	var jobs: Array = loaded["flight"]["rumor"]["jobs"]
	assert_eq(String((jobs[0] as Dictionary)["verb"]), "settle")
	assert_eq(String(loaded["deeds"]["rows"][0]["verb"]), "settle")
	assert_eq(
		JSON.stringify(runtime.facts.export_state(), "\t", true),
		JSON.stringify(saved["facts"], "\t", true)
	)
	assert_false(_has_kept(report, "harbor_watch"))
	assert_eq(_find(report, "dock_clerk", ""), _kept("dock_clerk", "role"))
	runtime.config().scheduler_work_per_tick = 64
	runtime.tick(0)
	assert_eq(_issue_lines(runtime), ["tide_notice#1 due=60 deeds=0 ids= claim=lost_at_sea source=world"])
	assert_eq(int(runtime.save_state()["flight"]["publish"]["counters"]["tide_notice"]), 1)
	_host(runtime).clock.set_minutes(120)
	runtime.tick(60)
	var later: Array = _issue_lines(runtime)
	assert_eq(later[0], "tide_notice#1 due=60 deeds=0 ids= claim=lost_at_sea source=world")
	assert_true(String(later[1]).begins_with("tide_notice#2"))
	assert_eq(int(runtime.save_state()["flight"]["publish"]["counters"]["tide_notice"]), 2)


func _played() -> Dictionary:
	var runtime := _boot(_OLD)
	runtime.roles.define(&"harbor_watch")
	runtime.config().scheduler_work_per_tick = 0
	runtime.facts.set(&"harbor.toll_fate", &"lost_at_sea")
	_host(runtime).clock.set_minutes(60)
	runtime.tick(0)
	runtime.register_rumor_policy(_policy())
	runtime.perception_claim("harbor.toll_fate", &"lost_at_sea")
	runtime.deeds.record(&"paid", &"player", &"", &"gullhaven")
	runtime.clear_perception_claim()
	var saved := runtime.save_state()
	assert_eq(int(saved["flight"]["publish"]["counters"]["harbor_gazette"]), 1)
	assert_eq(int(saved["flight"]["publish"]["covered"]["harbor_gazette"]), 60)
	assert_eq(saved["flight"]["publish"]["queued"], ["harbor_gazette\t60"])
	assert_eq(String(saved["flight"]["scheduler"]["publish"][0]), "issue\tharbor_gazette\t1\t60")
	assert_false(saved["flight"]["publish"].has("cursor"))
	assert_eq(String(saved["flight"]["rumor"]["jobs"][0]["verb"]), "paid")
	assert_eq(String(saved["deeds"]["rows"][0]["verb"]), "paid")
	return saved


func _boot(path: String) -> WyrdRuntime:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	runtime.set_meta(&"host", host)
	var manifest := load(path) as WyrdContentManifest
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(7)
	var world := runtime.adapter(WyrdWorldAdapter) as WyrdFakeWorld
	world.add_entity(&"player", &"person", "traveler", PackedStringArray(), true)
	return runtime


func _host(runtime: WyrdRuntime) -> WyrdFakeHost:
	return runtime.get_meta(&"host") as WyrdFakeHost


func _policy() -> WyrdRumorPolicy:
	var policy := WyrdRumorPolicy.new()
	policy.id = &"harbor_toll"
	policy.kinds = PackedStringArray(["friend"])
	policy.max_hops = 2
	policy.pass_chance = 1.0
	return policy


func _watch(runtime: WyrdRuntime) -> Array:
	var hits := [0]
	runtime.load_report_ready.connect(func(_report): hits[0] += 1)
	return hits


func _issue_lines(runtime: WyrdRuntime) -> Array:
	var value: Variant = runtime.facts.get(&"harbor.gazette")
	if value == null:
		return []
	var rows: Array = []
	for line in String(value).split("\n"):
		if not line.is_empty() and not line.begins_with("skip "):
			rows.append(line)
	return rows


func _expected_rows(saved: Dictionary, runtime: WyrdRuntime) -> Array:
	var rows: Array = [
		_alias("document:harbor_gazette", "harbor_gazette", "tide_notice", 4, ""),
		_alias("verb:paid", "paid", "settle", 2, ""),
		_kept("dock_clerk", "role"),
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


func _has_kept(report: WyrdLoadReport, id: String) -> bool:
	for item in report.rows:
		var row: Dictionary = item
		if String(row["kind"]) == "kept" and String(row["id"]) == id:
			return true
	return false


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


func _kept(id: String, store: String) -> Dictionary:
	return {
		"code": "",
		"count": 1,
		"from": store,
		"id": id,
		"kind": "kept",
		"to": "",
	}
