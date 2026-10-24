extends GutTest

## M11 exit suite. Each test names the criterion it proves. No timings.

const _Load := preload("res://tests/migration/fixture_load.gd")
const _Harness := preload("res://tests/scenario/s2c_harness.gd")
const _Driver := preload("res://tests/determinism/replay_driver.gd")
const _Inventory := preload("res://tests/determinism/replay_inventory.gd")
const _M10 := preload("res://tests/scenario/m10_gullhaven.gd")
const _Fuzz := preload("res://tests/migration/test_load_fuzz.gd")

const _FIXTURE_HASH := "f003b6b54c91ad8e"
const _LIVE_HASH := "918b2aad2be7d4fa"
const _HARBOR_OLD := "res://tests/migration/packs/harbor_old.wyrdmanifest.tres"
const _HARBOR_NEW := "res://tests/migration/packs/harbor_new.wyrdmanifest.tres"
const _STAGE_OLD := "res://tests/migration/packs/stage_old.wyrdmanifest.tres"
const _STAGE_NEW := "res://tests/migration/packs/stage_new.wyrdmanifest.tres"
const _NOTICE_OLD := "res://tests/migration/packs/notice_old.wyrdmanifest.tres"
const _NOTICE_NEW := "res://tests/migration/packs/notice_new.wyrdmanifest.tres"
const _ROUTE := "unset_rumour"
const _FUZZ_SEED := 20261023
const _FUZZ_SAMPLES := 8

const CRITERIA := {
	"X1": "Old-content save fixtures load in CI",
	"X2": "Replay tests pass",
	"S1": "Content aliases",
	"S2": "Missing-stage handling",
	"S3": "Kept but ignored",
	"S4": "Load report",
	"S5": "Refusal before import",
	"S6": "Save schema stays 4",
	"S7": "The migration test rule",
	"S8": "Host calls recorded",
	"S9": "Timing rows",
	"S10": "informational; see `bench/README.md` (M11 performance pass)",
}

const _FIXTURES := {
	"schema1_harbor.json": "res://tests/migration/fixtures/schema1_harbor.json",
	"schema2_harbor.json": "res://tests/fixtures/schema2_harbor.json",
	"schema3_harbor.json": "res://tests/fixtures/schema3_harbor.json",
	"schema4_ai_harbor.json": "res://tests/fixtures/schema4_ai_harbor.json",
	"gullhaven_v0.7.0-m9.json": "res://tests/migration/fixtures/gullhaven_v0.7.0-m9.json",
	"gullhaven_v0.8.0-m10.json": "res://tests/migration/fixtures/gullhaven_v0.8.0-m10.json",
}

const _OLD_PACK := """
language 1

facts
  world.note : symbol stored

quest old_errand "Old Errand"
  start when false
  stage wait
    waits_until false
  stage done
    waits_until false

template ferry_job "Ferry Job"
  stage hire
    waits_until false

role dock_clerk
  scope: world
  visibility: public
  succession: none
  vacancy: hold

document harbor_gazette "Harbor Gazette" #line:gazette_title
  text: frozen
  page
    The tide is in. #line:gazette_body

storylet storm_rumour
  scope: bark
  speaker: any
  - The storm is coming. #line:storm_line

storylet harbor.weather
  scope: topic weather
  speaker: any
  - The wind is up. #line:weather_line
"""

const _NEW_PACK := """
language 1

facts
  world.note : symbol stored

quest harbor_guild "The Harbor Guild"
  start when false
  stage post
    waits_until false
"""


func test_exit_X1_fixtures_load_and_round_trip() -> void:
	var cases: Array = [
		["res://tests/migration/fixtures/schema1_harbor.json", 1, "886d9ba3e5447ff4", false],
		["res://tests/fixtures/schema2_harbor.json", 2, _FIXTURE_HASH, false],
		["res://tests/fixtures/schema3_harbor.json", 3, _FIXTURE_HASH, false],
		["res://tests/fixtures/schema4_ai_harbor.json", 4, _FIXTURE_HASH, false],
		["res://tests/migration/fixtures/gullhaven_v0.7.0-m9.json", 4, "8bf113c14f107242", true],
		["res://tests/migration/fixtures/gullhaven_v0.8.0-m10.json", 4, _FIXTURE_HASH, true],
	]
	for item in cases:
		var path := String(item[0])
		var data := _Load.read(path)
		assert_eq(int(data["schema_version"]), int(item[1]), path)
		assert_eq(_Load.pack_hash(data), String(item[2]), path)
		var runtime := _open_current(bool(item[3]))
		var report := runtime.load_state(data)
		assert_true(report.ok, "%s %s" % [path, report.diagnostics.format()])
		var saved := runtime.save_state()
		assert_eq(int(saved["schema_version"]), 4, path)
		assert_eq(_Load.pack_hash(saved), _LIVE_HASH, path)
		var second := _open_current(bool(item[3]))
		var again := second.load_state(saved)
		assert_true(again.ok, "%s %s" % [path, again.diagnostics.format()])
		assert_eq(JSON.stringify(saved, "\t", true), JSON.stringify(second.save_state(), "\t", true), path)


func test_exit_X1_old_gullhaven_saves_keep_playing() -> void:
	for path in [
		"res://tests/migration/fixtures/gullhaven_v0.7.0-m9.json",
		"res://tests/migration/fixtures/gullhaven_v0.8.0-m10.json",
	]:
		var runtime := _open_current(true)
		var report := runtime.load_state(_Load.read(path))
		assert_true(report.ok, report.diagnostics.format())
		assert_eq(String(runtime.quests.status("ferry_toll")), "active", path)
		assert_eq(runtime.quests.stage("ferry_toll"), "cross", path)
		runtime.tick(1)
		runtime.dialogue.open_scene("toll.depart")
		var harness := _Harness.new()
		assert_eq(harness.ids_of(harness.line_rows(runtime)), PackedStringArray(["a_cross", "a_leave"]), path)


func test_exit_X2_a_route_replays_twice() -> void:
	var driver := _Driver.new()
	var recorded: Dictionary = driver.record_route(_ROUTE, "")
	var once: Dictionary = driver.replay_route(_ROUTE, "", recorded)
	var twice: Dictionary = driver.replay_route(_ROUTE, "", recorded)
	assert_eq(WyrdTrace.diff(recorded["events"], once["events"]), PackedStringArray())
	assert_eq(WyrdTrace.diff(recorded["events"], twice["events"]), PackedStringArray())
	assert_eq(str(once["hash"]), str(recorded["hash"]))
	assert_eq(str(twice["hash"]), str(recorded["hash"]))


func test_exit_X2_a_route_splits_across_save_and_load() -> void:
	var driver := _Driver.new()
	var recorded: Dictionary = driver.record_route(_ROUTE, "")
	var splits: Array = driver.split_indexes(recorded["segments"])
	assert_gt(splits.size(), 0, _ROUTE)
	var result: Dictionary = driver.plain_route_split(_ROUTE, recorded, int(splits[0]))
	var problems: PackedStringArray = result["problems"]
	assert_eq(problems.size(), 0, "\n".join(problems))


func test_exit_X2_the_inventory_lists_every_public_call() -> void:
	var scanned := _scanned_calls()
	var entries: Array = _Inventory.entries()
	var by_call := {}
	for item in entries:
		var row: Dictionary = item
		var call := str(row["call"])
		assert_false(by_call.has(call), call)
		var category := str(row["category"])
		var listed := category.begins_with("input:") or category in ["read", "setup", "boundary", "debug", "internal", "unrecorded"]
		assert_true(listed, "%s %s" % [call, category])
		assert_false(str(row["reason"]).is_empty(), call)
		by_call[call] = true
		assert_true(scanned.has(call), call)
	for call in scanned.keys():
		assert_true(by_call.has(call), "missing %s" % call)


func test_exit_S1_rewrites_stage_role_verb_document_and_trail() -> void:
	var saved := _harbor_played()
	var runtime := _boot(_HARBOR_NEW)
	var report := runtime.load_state(saved)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(runtime.quests.stage("ferry_toll"), "depart")
	assert_eq(runtime.quests.stage("ferry_job#1"), "sign")
	assert_eq(runtime.roles.holder(&"dock_master"), &"player")
	assert_eq(runtime.deeds.verb_at(0), &"settle")
	assert_true(runtime.documents.has_read(&"player", &"tide_notice"))
	assert_true(runtime.documents.has_copy(&"tide_notice", "kept"))
	for row_id in ["stage:ferry_toll", "stage:ferry_job#1", "trail:ferry_toll:offer", "trail:ferry_job#1:hire", "role:ferry_master", "verb:paid", "document:harbor_gazette"]:
		var row := _find(report, row_id, "")
		assert_eq(String(row["kind"]), "alias", row_id)
		assert_eq(int(row["count"]) > 0, true, row_id)


func test_exit_S1_publish_state_and_rumor_verb() -> void:
	var saved := _notice_played()
	var runtime := _boot(_NOTICE_NEW)
	runtime.register_rumor_policy(_policy())
	var report := runtime.load_state(saved)
	assert_true(report.ok, report.diagnostics.format())
	var loaded := runtime.save_state()
	var publish: Dictionary = loaded["flight"]["publish"]
	assert_eq(int(publish["counters"]["tide_notice"]), 1)
	assert_false((publish["counters"] as Dictionary).has("harbor_gazette"))
	var jobs: Array = loaded["flight"]["rumor"]["jobs"]
	assert_eq(String((jobs[0] as Dictionary)["verb"]), "settle")
	var document := _find(report, "document:harbor_gazette", "")
	var verb := _find(report, "verb:paid", "")
	assert_eq(String(document["kind"]), "alias")
	assert_eq(String(verb["kind"]), "alias")


func test_exit_S1_a_collision_keeps_the_new_id() -> void:
	var saved := _harbor_played()
	var reads: Array = saved["documents"]["read"]
	reads.append({"doc": "harbor_gazette", "reader": "dock_clerk"})
	reads.append({"doc": "tide_notice", "reader": "player"})
	var runtime := _boot(_HARBOR_NEW)
	var report := runtime.load_state(saved)
	assert_true(report.ok, report.diagnostics.format())
	assert_true(runtime.documents.has_read(&"player", &"tide_notice"))
	assert_true(runtime.documents.has_read(&"dock_clerk", &"tide_notice"))
	assert_false(runtime.documents.has_read(&"player", &"harbor_gazette"))
	var dropped := _find(report, "document:harbor_gazette", "W_SAVE_ALIAS")
	assert_eq(String(dropped["kind"]), "alias")
	assert_eq(String(dropped["from"]), "harbor_gazette")
	assert_eq(String(dropped["to"]), "tide_notice")


func test_exit_S1_a_resave_has_no_alias_rows() -> void:
	var runtime := _boot(_HARBOR_NEW)
	assert_true(runtime.load_state(_harbor_played()).ok)
	var again := runtime.load_state(runtime.save_state())
	assert_true(again.ok, again.diagnostics.format())
	assert_eq(again.rows, [])


func test_exit_S1_lints_chain_and_manifest_hash() -> void:
	var conflict := _compile_source("template ferry_job \"Ferry Job\"\n  on_deed pay\n  stage hire\n    waits_until false\nverb pay was: pay\n")
	assert_true(_codes(conflict).has("E_ALIAS_CONFLICT"))
	var duplicate := _compile_source("verb settle was: paid\nverb keep was: paid\n")
	assert_true(_codes(duplicate).has("E_ALIAS_DUPLICATE"))
	var cycle := _compile_source("verb pay was: paid\nverb paid was: pay\n")
	assert_true(_codes(cycle).has("E_ALIAS_CYCLE"))
	var chain := _compile_source("verb c was: b\nverb b was: a\n")
	assert_false(_codes(chain).has("E_ALIAS_CYCLE"))
	var verbs: Dictionary = (chain["pack"] as WyrdLinkedPack).aliases["verb"]
	assert_eq(String(verbs["a"]), "c")
	assert_eq(String(verbs["b"]), "c")
	var gullhaven := _open_current(true)
	assert_eq(WyrdRng.format_u64(gullhaven.content().manifest_hash), _LIVE_HASH)
	assert_true(gullhaven.content().aliases.is_empty())


func test_exit_S2_alias_field_trail_and_first_stage() -> void:
	var saved := _stage_played()
	var runtime := _boot(_STAGE_NEW)
	var report := runtime.load_state(saved)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(runtime.quests.stage("tide_bell"), "toll", "alias before on_missing_stage")
	assert_eq(runtime.quests.stage("ferry_toll"), "depart", "on_missing_stage")
	assert_eq(runtime.quests.stage("dock_errand"), "hire", "latest surviving trail stage")
	var without: Dictionary = _stage_played()
	(without["quests"]["dock_errand"] as Dictionary).erase("trail")
	var fresh := _boot(_STAGE_NEW)
	var bare := fresh.load_state(without)
	assert_true(bare.ok, bare.diagnostics.format())
	assert_eq(fresh.quests.stage("dock_errand"), "wait", "first stage when the save has no trail")
	var alias := _find(report, "stage:tide_bell", "")
	assert_eq(String(alias["kind"]), "alias")
	assert_eq(String(alias["from"]), "ring")
	assert_eq(String(alias["to"]), "toll")
	var by_field := _find(report, "ferry_toll", "W_SAVE_STAGE")
	assert_eq(String(by_field["kind"]), "missing_stage")
	assert_eq(String(by_field["to"]), "depart")
	var by_trail := _find(report, "dock_errand", "W_SAVE_STAGE")
	assert_eq(String(by_trail["kind"]), "missing_stage")
	assert_eq(String(by_trail["to"]), "hire")
	var by_first := _find(bare, "dock_errand", "W_SAVE_STAGE")
	assert_eq(String(by_first["kind"]), "missing_stage")
	assert_eq(String(by_first["from"]), "gone")
	assert_eq(String(by_first["to"]), "wait")
	var leaf := _find(report, "lantern_watch/wick", "W_SAVE_STAGE")
	assert_eq(String(leaf["kind"]), "missing_stage")
	assert_eq(String(leaf["code"]), "W_SAVE_STAGE")


func test_exit_S2_arrives_entered_without_effects() -> void:
	var saved := _stage_played()
	var runtime := _boot(_STAGE_NEW)
	var report := runtime.load_state(saved)
	assert_true(report.ok, report.diagnostics.format())
	var loaded := runtime.save_state()
	var toll: Dictionary = loaded["quests"]["ferry_toll"]
	assert_true(bool(toll["entered"]))
	assert_eq(JSON.stringify(runtime.facts.export_state(), "\t", true), JSON.stringify(saved["facts"], "\t", true))
	assert_eq(JSON.stringify(runtime.deeds.export_state(), "\t", true), JSON.stringify(saved["deeds"], "\t", true))
	assert_eq(runtime.quests.journal("ferry_toll"), saved["quests"]["ferry_toll"]["journal"])
	assert_null(runtime.facts.get(&"world.stage_moved"))
	assert_eq(runtime.quests.advance("dock_errand", "wait"), "")
	assert_eq(runtime.quests.stage("dock_errand"), "wait")


func test_exit_S2_a_removed_leaf_restarts_its_region() -> void:
	var saved := _stage_played()
	var runtime := _boot(_STAGE_NEW)
	var report := runtime.load_state(saved)
	assert_true(report.ok, report.diagnostics.format())
	var wick: Dictionary = runtime.save_state()["quests"]["lantern_watch"]["regions"]["wick"]
	assert_eq(String(wick["stage"]), "trim")
	assert_true(bool(wick["entered"]))
	assert_null(runtime.facts.get(&"world.wick_lit"))
	var row := _find(report, "lantern_watch/wick", "W_SAVE_STAGE")
	assert_eq(String(row["kind"]), "missing_stage")
	assert_eq(String(row["from"]), "dark")
	assert_eq(String(row["to"]), "trim")


func test_exit_S2_a_bad_target_is_rejected() -> void:
	var compiled := _compile_unit("""
language 1

quest ferry_toll "Ferry Toll"
  on_missing_stage: missing
  stage arrive
    waits_until false
""")
	var codes := _codes(compiled)
	assert_true(codes.has("E_MISSING_STAGE_TARGET"))


func test_exit_S3_removed_content_is_kept_and_returns() -> void:
	var saved := _removed_played()
	var dropped := _boot_source(_NEW_PACK)
	var report := dropped.load_state(saved)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(String(_find(report, "old_errand", "")["kind"]), "kept")
	assert_eq(String(_find(report, "old_errand", "")["from"]), "quest")
	assert_eq(String(_find(report, "dock_clerk", "")["kind"]), "kept")
	assert_eq(String(_find(report, "dock_clerk", "")["from"]), "role")
	assert_eq(String(_find(report, "harbor_gazette", "")["kind"]), "kept")
	assert_eq(String(_find(report, "harbor_gazette", "")["from"]), "document")
	assert_eq(String(_find(report, "storm_rumour", "")["kind"]), "kept")
	assert_eq(String(_find(report, "storm_rumour", "")["from"]), "storylet")
	assert_eq(String(_find(report, "weather", "")["kind"]), "kept")
	assert_eq(String(_find(report, "weather", "")["from"]), "topic")
	var template := _find(report, "ferry_job", "W_SAVE_TEMPLATE")
	assert_eq(String(template["kind"]), "template")
	assert_eq(JSON.stringify(dropped.facts.export_state(), "\t", true), JSON.stringify(saved["facts"], "\t", true))
	var held := dropped.save_state()
	assert_eq(JSON.stringify(held["quests"]["old_errand"], "\t", true), JSON.stringify(saved["quests"]["old_errand"], "\t", true))
	dropped.tick(1)
	var after := dropped.save_state()
	assert_eq(JSON.stringify(after["quests"]["old_errand"], "\t", true), JSON.stringify(saved["quests"]["old_errand"], "\t", true))
	var returned := _boot_source(_OLD_PACK)
	var back := returned.load_state(after)
	assert_true(back.ok, back.diagnostics.format())
	assert_eq(String(returned.quests.status("old_errand")), "active")
	assert_eq(returned.quests.stage("old_errand"), "wait")
	assert_eq(returned.quests.advance("old_errand", "done"), "")
	assert_eq(returned.roles.holder(&"dock_clerk"), &"player")
	assert_true(returned.documents.has_copy(&"harbor_gazette", "kept"))
	assert_true(returned.topics.is_unlocked(&"weather"))
	assert_gt(returned.storylets.seen_of("storm_rumour"), 0)
	assert_eq(returned.quests.stage("ferry_job#1"), "hire")


func test_exit_S3_a_host_defined_role_adds_no_kept_row() -> void:
	var saved := _notice_played()
	var runtime := _boot(_NOTICE_NEW)
	runtime.roles.define(&"harbor_watch")
	runtime.register_rumor_policy(_policy())
	var report := runtime.load_state(saved)
	assert_true(report.ok, report.diagnostics.format())
	assert_false(_has_kind(report, "kept", "harbor_watch"))
	assert_eq(String(_find(report, "dock_clerk", "")["kind"]), "kept")


func test_exit_S4_rows_signal_and_manifest() -> void:
	var clean := _open_current(true)
	var clean_hits := _watch(clean)
	var clean_saved := _Load.read("res://tests/migration/fixtures/gullhaven_v0.8.0-m10.json")
	var clean_report := clean.load_state(clean_saved)
	assert_true(clean_report.ok, clean_report.diagnostics.format())
	assert_eq(clean_report.rows, _debug_manifest_rows(clean_saved, clean))
	assert_eq(clean_hits[0], 1)
	var parsed: Variant = JSON.parse_string(JSON.stringify(_Load.read("res://tests/migration/fixtures/gullhaven_v0.7.0-m9.json")))
	var data: Dictionary = parsed
	data["storylets"] = {"unknown_story": {"seen": 1}}
	data["sequences"] = {"unknown_seq": {"count": 1, "done": false}}
	var mixed := _open_current(true)
	var mixed_hits := _watch(mixed)
	var mixed_report := mixed.load_state(data)
	assert_true(mixed_report.ok, mixed_report.diagnostics.format())
	assert_eq(mixed_hits[0], 1)
	for row in mixed_report.rows:
		var keys: Array = (row as Dictionary).keys()
		keys.sort()
		assert_eq(keys, ["code", "count", "from", "id", "kind", "to"])
	assert_eq(mixed_report.rows, _sorted_rows(mixed_report.rows))
	assert_eq(String(mixed_report.rows[0]["kind"]), "kept")
	assert_eq(String(mixed_report.rows[0]["id"]), "unknown_seq")
	if OS.is_debug_build():
		var manifest := _find(mixed_report, "", "W_SAVE_MANIFEST")
		assert_eq(String(manifest["kind"]), "manifest")
		assert_eq(String(manifest["from"]), "8bf113c14f107242")
		assert_eq(String(manifest["to"]), _LIVE_HASH)
	var refused_runtime := _open_current(true)
	var refused_hits := _watch(refused_runtime)
	var bad: Dictionary = JSON.parse_string(JSON.stringify(refused_runtime.save_state()))
	bad["seed"] = "nope"
	var refused := refused_runtime.load_state(bad)
	assert_push_error("16 hex")
	assert_false(refused.ok)
	assert_eq(refused_hits[0], 1)
	var loading := WyrdRuntime.new()
	var content_hits := _watch(loading)
	var loaded := loading.load_content(load(_Harness.HARBOR))
	assert_true(loaded.ok, loaded.diagnostics.format())
	assert_eq(loaded.rows, [])
	assert_eq(content_hits[0], 0)


func test_exit_S5_a_refused_save_is_unchanged() -> void:
	var base := _Load.read("res://tests/fixtures/schema4_ai_harbor.json")
	var seed: Dictionary = JSON.parse_string(JSON.stringify(base))
	seed["seed"] = "not-a-seed"
	_assert_refused(seed, "seed", "16 hex")
	var typed: Dictionary = JSON.parse_string(JSON.stringify(base))
	(typed["quests"]["ferry_toll"] as Dictionary)["outcomes"] = "nope"
	_assert_refused(typed, "quests.ferry_toll.outcomes")
	var newer: Dictionary = JSON.parse_string(JSON.stringify(base))
	newer["schema_version"] = 5
	_assert_refused(newer, "schema_version")


func test_exit_S6_schema_stays_4() -> void:
	var runtime := _open_current(true)
	var fresh := runtime.save_state()
	assert_eq(int(fresh["schema_version"]), 4)
	var incoming: Variant = JSON.parse_string(JSON.stringify(fresh))
	var saved: Dictionary = incoming
	saved["schema_version"] = 5
	var before := JSON.stringify(runtime.save_state(), "\t", true)
	var report := runtime.load_state(saved)
	assert_false(report.ok)
	assert_eq(String(_find(report, "schema_version", "E_SAVE_VERSION")["kind"]), "refused")
	assert_eq(JSON.stringify(runtime.save_state(), "\t", true), before)


func test_exit_S7_fixture_sha256_and_a_fuzz_sample() -> void:
	var listed := _readme_sha256()
	assert_eq(listed.size(), _FIXTURES.size())
	for name in _FIXTURES.keys():
		var path := String(_FIXTURES[name])
		assert_true(listed.has(name), name)
		assert_eq(_sha256(path), String(listed[name]), name)
	var fuzz := _Fuzz.new()
	var bases: Array = [
		_Load.read("res://tests/fixtures/schema4_ai_harbor.json"),
		_Load.read("res://tests/migration/fixtures/gullhaven_v0.7.0-m9.json"),
		_Load.read("res://tests/migration/fixtures/gullhaven_v0.8.0-m10.json"),
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = _FUZZ_SEED
	var classes: Array[String] = ["drop", "type", "truncate", "hex"]
	var clean := 0
	var warned := 0
	var refused := 0
	for index in _FUZZ_SAMPLES:
		var kind: String = classes[index % 4]
		var parsed: Variant = JSON.parse_string(JSON.stringify(bases[index % 3]))
		var doc: Dictionary = parsed
		var where := fuzz._mutate(doc, kind, rng)
		var runtime: WyrdRuntime = _Harness.new().boot_gullhaven()["runtime"]
		var before := JSON.stringify(runtime.save_state(), "\t", true)
		var hits := _watch(runtime)
		var report := runtime.load_state(doc)
		assert_true(report is WyrdLoadReport, "%d %s" % [index, where])
		if _fuzz_noise(index, kind, where, report, fuzz):
			return
		assert_eq(hits[0], 1, "%d %s" % [index, where])
		if fuzz._refusing(report):
			assert_false(report.ok)
			assert_eq(fuzz._refused_rows(report), 1)
			assert_eq(JSON.stringify(runtime.save_state(), "\t", true), before)
			refused += 1
		else:
			assert_true(report.ok, "%d %s %s" % [index, kind, where])
			if report.diagnostics.items.is_empty():
				clean += 1
			else:
				warned += 1
	fuzz.free()
	assert_eq(clean + warned + refused, _FUZZ_SAMPLES)


func test_exit_S8_host_calls_record_replay_and_skip() -> void:
	var runtime: WyrdRuntime = _M10.new().boot("")["runtime"]
	runtime.trace.clear()
	runtime.facts.set(&"player.coins", 9)
	var rows := _host_rows(runtime)
	assert_eq(rows.size(), 1)
	assert_eq(String((rows[0] as Dictionary)["call"]), "facts.set_in")
	var recorded: Array = runtime.trace.snapshot()
	var again: WyrdRuntime = _M10.new().boot("")["runtime"]
	again.trace.clear()
	WyrdTrace.replay(again, recorded)
	assert_eq(WyrdTrace.diff(recorded, again.trace.snapshot()), PackedStringArray())
	assert_eq(again.facts.get(&"player.coins"), 9)
	var nested: WyrdRuntime = _M10.new().boot("")["runtime"]
	nested.trace.clear()
	var harness := _Harness.new()
	nested.dialogue.open_scene("toll.offer_room")
	harness.line_rows(nested)
	harness.choose_text(nested, "Take the room")
	assert_eq(_host_rows(nested).size(), 0)
	assert_true(bool(nested.facts.get(&"harbor.room_taken")))
	var same: WyrdRuntime = _M10.new().boot("")["runtime"]
	same.facts.set(&"player.coins", 3)
	same.trace.clear()
	assert_true(same.facts.set_in(&"player.coins", 3, &"world"))
	assert_eq(same.trace.events.size(), 0)


func test_exit_S9_a_timing_row_compares_equal() -> void:
	var clean := _timing_events(false)
	var warned := _timing_events(true)
	assert_eq(WyrdTrace.diff(clean, warned), PackedStringArray())
	assert_eq(warned.size(), clean.size() + 1)
	var frame: Dictionary = warned[2]
	assert_eq(bool(frame.get("timing", false)), true)
	assert_eq(String(frame.get("kind", "")), "scheduler")


func test_exit_S10_the_bench_note_is_informational() -> void:
	var text := FileAccess.get_file_as_string("res://bench/README.md")
	assert_true(text.contains("## M11 performance pass"))


func test_exit_every_criterion_has_a_test() -> void:
	var names: Array = []
	for item in get_script().get_script_method_list():
		names.append(String((item as Dictionary).get("name", "")))
	for id in CRITERIA.keys():
		var prefix := "test_exit_%s_" % String(id)
		var found := false
		for name in names:
			if String(name).begins_with(prefix):
				found = true
				break
		assert_true(found, "%s %s" % [id, String(CRITERIA[id])])


func _open_current(gullhaven: bool) -> WyrdRuntime:
	var harness := _Harness.new()
	var opened: Dictionary = harness.boot_gullhaven() if gullhaven else harness.open_pack(_Harness.HARBOR)
	var loaded = opened["report"]
	assert_true(loaded.ok, loaded.diagnostics.format())
	return opened["runtime"]


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
	world.add_entity(&"dock_clerk", &"person", "clerk", PackedStringArray(), true)
	return runtime


func _boot_source(body: String) -> WyrdRuntime:
	var path := "user://wyrd_m11_exit_%d.wyrd" % body.hash()
	var handle := FileAccess.open(path, FileAccess.WRITE)
	handle.store_string(body.strip_edges() + "\n")
	handle.close()
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(7)
	var world := runtime.adapter(WyrdWorldAdapter) as WyrdFakeWorld
	world.add_entity(&"player", &"person", "traveler", PackedStringArray(), true)
	return runtime


func _harbor_played() -> Dictionary:
	var runtime := _boot(_HARBOR_OLD)
	runtime.quests.start("ferry_toll")
	assert_eq(runtime.quests.advance("ferry_toll", "offer"), "")
	var id := runtime.quests.create_instance("ferry_job")
	assert_eq(id, "ferry_job#1")
	assert_eq(runtime.quests.advance(id, "hire"), "")
	runtime.roles.assign(&"ferry_master", &"player")
	runtime.deeds.record(&"paid", &"player")
	assert_true(runtime.documents.create_copy(&"harbor_gazette", "kept"))
	var opened := runtime.documents.open(&"harbor_gazette", "kept", &"player")
	assert_eq(opened.pages[0][0]["text"], "The tide is in.")
	return runtime.save_state()


func _notice_played() -> Dictionary:
	var runtime := _boot(_NOTICE_OLD)
	runtime.roles.define(&"harbor_watch")
	runtime.config().scheduler_work_per_tick = 0
	runtime.facts.set(&"harbor.toll_fate", &"lost_at_sea")
	_host(runtime).clock.set_minutes(60)
	runtime.tick(0)
	runtime.register_rumor_policy(_policy())
	runtime.perception_claim("harbor.toll_fate", &"lost_at_sea")
	runtime.deeds.record(&"paid", &"player", &"", &"gullhaven")
	runtime.clear_perception_claim()
	return runtime.save_state()


func _stage_played() -> Dictionary:
	var runtime := _boot(_STAGE_OLD)
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
	return runtime.save_state()


func _removed_played() -> Dictionary:
	var runtime := _boot_source(_OLD_PACK)
	runtime.quests.start("old_errand")
	var id := runtime.quests.create_instance("ferry_job")
	assert_eq(id, "ferry_job#1")
	runtime.roles.assign(&"dock_clerk", &"player")
	assert_true(runtime.documents.create_copy(&"harbor_gazette", "kept"))
	runtime.topics.unlock(&"weather")
	runtime.storylets.note_selected("storm_rumour", 0)
	runtime.facts.set(&"world.note", &"kept")
	return runtime.save_state()


func _policy() -> WyrdRumorPolicy:
	var policy := WyrdRumorPolicy.new()
	policy.id = &"harbor_toll"
	policy.kinds = PackedStringArray(["friend"])
	policy.max_hops = 2
	policy.pass_chance = 1.0
	return policy


func _host(runtime: WyrdRuntime) -> WyrdFakeHost:
	return runtime.get_meta(&"host") as WyrdFakeHost


func _debug_manifest_rows(saved: Dictionary, runtime: WyrdRuntime) -> Array:
	if not OS.is_debug_build():
		return []
	var packs: Array = saved["content"]["packs"]
	var from_hash := String((packs[0] as Dictionary)["hash"])
	return [{
		"code": "W_SAVE_MANIFEST",
		"count": 0,
		"from": from_hash,
		"id": "",
		"kind": "manifest",
		"to": WyrdRng.format_u64(runtime.content().manifest_hash),
	}]


func _watch(runtime: WyrdRuntime) -> Array:
	var hits := [0]
	runtime.load_report_ready.connect(func(_report): hits[0] += 1)
	return hits


func _find(report: WyrdLoadReport, id: String, code: String) -> Dictionary:
	for row in report.rows:
		var body: Dictionary = row
		if String(body["id"]) == id and String(body["code"]) == code:
			return body
	push_error("missing row %s %s" % [id, code])
	return {}


func _has_kind(report: WyrdLoadReport, kind: String, id: String) -> bool:
	for row in report.rows:
		var body: Dictionary = row
		if String(body["kind"]) == kind and String(body["id"]) == id:
			return true
	return false


func _sorted_rows(rows: Array) -> Array:
	var copy: Array = rows.duplicate()
	copy.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if String(a["kind"]) != String(b["kind"]):
			return String(a["kind"]) < String(b["kind"])
		if String(a["id"]) != String(b["id"]):
			return String(a["id"]) < String(b["id"])
		return String(a["code"]) < String(b["code"])
	)
	return copy


func _assert_refused(data: Dictionary, id: String, needle: String = "") -> void:
	var runtime := _open_current(false)
	var before := JSON.stringify(runtime.save_state(), "\t", true)
	var report := runtime.load_state(data)
	if needle != "":
		assert_push_error(needle)
	assert_false(report.ok, id)
	var row := _find(report, id, "E_SAVE_VERSION")
	assert_eq(String(row["kind"]), "refused", id)
	assert_eq(JSON.stringify(runtime.save_state(), "\t", true), before, id)


func _compile_source(body: String) -> Dictionary:
	return _compile_unit("language 1\n" + body)


func _compile_unit(text: String) -> Dictionary:
	var path := "user://wyrd_m11_exit_lint_%d.wyrd" % text.hash()
	var handle := FileAccess.open(path, FileAccess.WRITE)
	handle.store_string(text)
	handle.close()
	var diagnostics := WyrdDiagnostics.new()
	var pack := WyrdPack.compile(PackedStringArray([path]), "gullhaven", 1, null, diagnostics)
	return {"diagnostics": diagnostics, "pack": pack}


func _codes(compiled: Dictionary) -> Array:
	var diagnostics: WyrdDiagnostics = compiled["diagnostics"]
	var codes: Array = []
	for item in diagnostics.items:
		codes.append(String(item.code))
	return codes


func _readme_sha256() -> Dictionary:
	var text := FileAccess.get_file_as_string("res://tests/migration/fixtures/README.md")
	var current := ""
	var found := {}
	for line in text.split("\n"):
		if line.begins_with("## ") or line.begins_with("### "):
			var title := line.trim_prefix("### ").trim_prefix("## ").strip_edges()
			current = title if title.ends_with(".json") else ""
			continue
		if current == "" or not line.begins_with("- sha256:"):
			continue
		var open := line.find("`")
		var close := line.find("`", open + 1)
		found[current] = line.substr(open + 1, close - open - 1)
		current = ""
	return found


func _sha256(path: String) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(FileAccess.get_file_as_bytes(path))
	return hashing.finish().hex_encode()


func _fuzz_noise(index: int, kind: String, where: String, report: WyrdLoadReport, fuzz: GutTest) -> bool:
	for item in get_errors():
		var err: GutTrackedError = item
		if err.handled:
			continue
		if err.is_engine_error():
			err.handled = true
			assert_true(false, "mutation %d %s %s: engine error" % [index, kind, where])
			return true
		if not err.is_push_error():
			continue
		var text := "%s %s" % [str(err.code), str(err.rationale)]
		var rng_noise := text.find("WyrdRng") >= 0 or text.find("16 hex") >= 0 or text.find("state rejected") >= 0
		var allowed := (not report.ok) and rng_noise
		var has_policy: bool = fuzz._has_code(report, "E_SAVE_POLICY")
		var policy := text.find("WyrdRumor") >= 0 and has_policy
		if allowed or policy:
			err.handled = true
			continue
		err.handled = true
		assert_true(false, "mutation %d %s %s: push_error %s" % [index, kind, where, text])
		return true
	return false


func _host_rows(runtime: WyrdRuntime) -> Array:
	var rows: Array = []
	for item in runtime.trace.events:
		if item is Dictionary and String((item as Dictionary).get("kind", "")) == "host_call":
			rows.append(item)
	return rows


func _timing_events(warned: bool) -> Array:
	var trace := WyrdTrace.new()
	trace.enabled = true
	trace.add("line", {"id": "a_leave", "text": "The boat leaves the dock."})
	trace.add("choices", {"rows": ["Take the room"]})
	if warned:
		trace.add("scheduler", {
			"carry": 0,
			"key": "frame",
			"queue": "frame",
			"threshold": 2000,
			"timing": true,
			"units": 4,
			"us": 2500,
		})
	trace.add("command", {"name": "assign_lodging", "ok": true, "reason": "-"})
	return trace.snapshot()


func _scanned_calls() -> Dictionary:
	var found := {}
	var runtime := WyrdRuntime.new()
	_take(found, "WyrdRuntime", runtime.get_script())
	var facade: Node = load("res://addons/wyrd/runtime/wyrd.gd").new()
	_take(found, "Wyrd", facade.get_script())
	var props: Array = [
		"facts", "events", "deeds", "social", "rumors", "publish", "roles",
		"topics", "documents", "quests", "dialogue", "storylets", "sequences",
		"director", "generator", "ai", "trace", "debug", "coverage",
	]
	for prop in props:
		var obj: Object = facade.get(prop)
		var script := obj.get_script() as Script
		_take(found, script.get_global_name(), script)
	_take(found, "WyrdConsole", load("res://addons/wyrd/runtime/console/wyrd_console.gd"))
	found["WyrdFactStore.set"] = true
	facade.free()
	return found


func _take(found: Dictionary, label: String, script: Script) -> void:
	for item in script.get_script_method_list():
		var method: Dictionary = item
		var name := String(method.get("name", ""))
		if name.begins_with("_"):
			continue
		found["%s.%s" % [label, name]] = true
