extends GutTest


class Offer extends WyrdWorldAdapter:
	var ids := PackedStringArray()
	var seen_kind := ""
	var seen_tag := ""

	func candidates(filter: WyrdEntityFilter) -> PackedStringArray:
		if filter != null:
			seen_kind = String(filter.kind)
			seen_tag = String(filter.tag)
		return ids


func test_seeded_pick_keeps_only_matching_candidates() -> void:
	var opened := _boot(_LOCAL, 4)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	_people(host)
	var before: Dictionary = runtime.rng_stream(&"replay").to_state()
	runtime.trace.enabled = true
	runtime.roles.begin_quest("gate")
	var picked := String(runtime.roles.slot_holder("gate", &"lookout"))
	assert_eq(picked, _expect(["ada", "bea"], 4, "gate", "lookout"))
	assert_eq(runtime.roles.holder(&"watcher"), &"")
	assert_eq(runtime.roles.slot_state(&"lookout", "gate"), &"default")
	assert_eq(runtime.rng_stream(&"replay").to_state(), before)
	var row := _cast_event(runtime, "lookout")
	assert_eq(String(row["quest"]), "gate")
	assert_eq(String(row["role"]), "watcher")
	assert_eq(String(row["slot"]), "lookout")
	assert_eq(String(row["entity"]), picked)
	assert_eq(String(row["reason"]), "picked")
	assert_eq(_cast_count(runtime), 1)
	runtime.roles.assign(&"watcher", &"cy")
	runtime.roles.begin_quest("gate")
	assert_eq(String(runtime.roles.slot_holder("gate", &"lookout")), picked)
	assert_eq(runtime.roles.holder(&"watcher"), &"cy")
	assert_eq(_cast_count(runtime), 1)
	var again := _boot(_LOCAL, 4)
	var second: WyrdRuntime = again["runtime"]
	_people(again["host"])
	second.roles.begin_quest("gate")
	assert_eq(String(second.roles.slot_holder("gate", &"lookout")), picked)
	var other := _boot(_LOCAL, 11)
	var third: WyrdRuntime = other["runtime"]
	_people(other["host"])
	third.roles.begin_quest("gate")
	assert_eq(String(third.roles.slot_holder("gate", &"lookout")), _expect(["ada", "bea"], 11, "gate", "lookout"))


func test_no_candidate_is_empty_and_traces_are_not_collapsed() -> void:
	var opened := _boot(_EMPTY, 4)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.world.add_entity(&"cy", &"person", "Cy", PackedStringArray(), true)
	host.world.add_entity(&"dock.bell", &"object", "bell", PackedStringArray(), true)
	host.world.add_entity(&"player", &"person", "traveler", PackedStringArray(), true)
	runtime.trace.prefix = "other"
	runtime.trace.enabled = true
	runtime.roles.begin_quest("gate")
	assert_eq(_cast_count(runtime), 0)
	assert_eq(runtime.roles.slot_holder("gate", &"lookout"), &"")
	assert_eq(runtime.roles.slot_state(&"lookout", "gate"), &"empty")
	runtime.trace.prefix = ""
	runtime.start_new_game(4)
	runtime.trace.enabled = true
	runtime.roles.begin_quest("gate")
	assert_eq(_cast_count(runtime), 2)
	var lookout := _cast_event(runtime, "lookout")
	var clerk := _cast_event(runtime, "clerk")
	assert_eq(String(lookout["entity"]), "")
	assert_eq(String(lookout["reason"]), "empty")
	assert_eq(String(lookout["role"]), "watcher")
	assert_eq(String(clerk["entity"]), "")
	assert_eq(String(clerk["reason"]), "empty")
	assert_eq(String(clerk["role"]), "clerk")
	runtime.roles.begin_quest("gate")
	runtime.facts.set(&"player.coins", 1)
	runtime.roles.assign(&"watcher", &"ada")
	assert_eq(_cast_count(runtime), 2)
	assert_eq(runtime.roles.slot_holder("gate", &"lookout"), &"")
	assert_eq(runtime.roles.slot_holder("gate", &"clerk"), &"")


func test_offer_order_is_sorted_and_the_filter_is_empty() -> void:
	var opened := _boot(_COINS, 6)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.facts.set(&"player.coins", 1)
	var offer := Offer.new()
	offer.ids = PackedStringArray(["bea", "ada", "bea", ""])
	runtime.register_adapter(WyrdWorldAdapter, offer)
	runtime.trace.enabled = true
	runtime.roles.begin_quest("gate")
	assert_eq(offer.seen_kind, "")
	assert_eq(offer.seen_tag, "")
	assert_eq(String(runtime.roles.slot_holder("gate", &"lookout")), _expect(["ada", "bea"], 6, "gate", "lookout"))
	assert_eq(String(runtime.roles.slot_holder("gate", &"clerk")), _expect(["ada", "bea"], 6, "gate", "clerk"))
	assert_eq(String(_cast_event(runtime, "lookout")["reason"]), "picked")
	assert_eq(String(_cast_event(runtime, "clerk")["reason"]), "picked")
	offer.ids = PackedStringArray(["cy"])
	runtime.roles.begin_quest("gate")
	assert_eq(String(runtime.roles.slot_holder("gate", &"lookout")), _expect(["ada", "bea"], 6, "gate", "lookout"))
	assert_eq(_cast_count(runtime), 2)


func test_an_object_is_picked_when_the_host_offers_it() -> void:
	var opened := _boot(_COINS, 3)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.world.add_entity(&"dock.bell", &"object", "bell", PackedStringArray(), true)
	runtime.facts.set(&"player.coins", 1)
	runtime.roles.begin_quest("gate")
	assert_eq(runtime.roles.slot_holder("gate", &"lookout"), &"dock.bell")
	assert_eq(runtime.roles.slot_state(&"lookout", "gate"), &"default")
	assert_eq(runtime.roles.holder(&"watcher"), &"")


func test_null_world_and_missing_evaluator_cast_empty() -> void:
	var runtime := WyrdRuntime.new()
	var path := "user://wyrd_m4_cast_null.wyrd"
	_write(path, _LOCAL)
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.trace.enabled = true
	runtime.roles.begin_quest("gate")
	assert_eq(runtime.roles.slot_holder("gate", &"lookout"), &"")
	assert_eq(String(_cast_event(runtime, "lookout")["reason"]), "empty")
	var opened := _boot(_LOCAL, 2)
	var hosted: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.world.add_entity(&"ada", &"person", "Ada", PackedStringArray(["local"]), true)
	hosted.roles.eval_with = Callable()
	hosted.roles.begin_quest("gate")
	assert_push_error("cast has no condition evaluator")
	assert_eq(hosted.roles.slot_holder("gate", &"lookout"), &"")
	assert_eq(hosted.roles.slot_state(&"lookout", "gate"), &"empty")


func test_cast_freeze_round_trips_on_schema_1() -> void:
	var opened := _boot(_LOCAL, 8)
	var runtime: WyrdRuntime = opened["runtime"]
	_people(opened["host"])
	runtime.roles.begin_quest("gate")
	var picked := String(runtime.roles.slot_holder("gate", &"lookout"))
	var saved := runtime.save_state()
	assert_eq(int(saved["schema_version"]), 1)
	assert_eq(WyrdSave.migrations.size(), 0)
	var frozen: Dictionary = ((saved["roles"] as Dictionary)["frozen"] as Dictionary)["gate"]
	assert_eq(String((frozen["lookout"] as Dictionary)["holder"]), picked)
	assert_eq(String((frozen["lookout"] as Dictionary)["status"]), "default")
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(saved))
	var fresh := WyrdRuntime.new()
	var next := WyrdFakeHost.new()
	next.register_into(fresh)
	next.world.add_entity(&"cy", &"person", "Cy", PackedStringArray(["local"]), true)
	var path := "user://wyrd_m4_cast.wyrd"
	_write(path, _LOCAL)
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	assert_true(fresh.load_content(manifest).ok)
	fresh.start_new_game(1)
	var loaded := fresh.load_state(parsed)
	assert_true(loaded.ok, loaded.diagnostics.format())
	fresh.trace.enabled = true
	fresh.roles.begin_quest("gate")
	assert_eq(String(fresh.roles.slot_holder("gate", &"lookout")), picked)
	assert_eq(_cast_count(fresh), 0)


func test_constant_cast_conditions_warn_and_candidate_compiles() -> void:
	var diagnostics := WyrdDiagnostics.new()
	var path := "user://wyrd_m4_cast_lint.wyrd"
	_write(path, _LINT)
	WyrdPack.compile(PackedStringArray([path]), "harbor", 1, null, diagnostics, path, true)
	var text := diagnostics.format()
	assert_false(text.contains("error["), text)
	assert_true(text.contains("cast condition is always true"), text)
	assert_true(text.contains("cast condition is never true"), text)
	assert_true(text.contains("W_SLOT_COND_ALWAYS"), text)
	assert_true(text.contains("W_SLOT_COND_NEVER"), text)
	assert_true(text.contains("W_EMPTY_UNCOVERED"), text)
	assert_true(text.contains("slot \"lookout\" can become empty"), text)
	assert_false(text.contains("slot \"clerk\" can become empty"), text)
	assert_false(text.contains("slot \"bell\" can become empty"), text)


const _LOCAL := """
language 1
quest gate "Gate"
  slot lookout = watcher mode: cast(has_tag(candidate, local))
  stage arrive
    waits_until false
"""

const _EMPTY := """
language 1
facts
  player.coins : int stored
quest gate "Gate"
  slot lookout = watcher mode: cast(has_tag(candidate, local))
  slot clerk = clerk mode: cast(player.coins >= 0)
  stage arrive
    waits_until false
"""

const _COINS := """
language 1
facts
  player.coins : int stored
quest gate "Gate"
  slot lookout = watcher mode: cast(player.coins >= 0)
  slot clerk = clerk mode: cast(player.coins >= 0)
  stage arrive
    waits_until false
"""

const _LINT := """
language 1
quest gate "Gate"
  slot lookout = watcher mode: cast(true)
  stage arrive
    scene room with lookout
quest other "Other"
  on_empty: wait
  slot clerk = clerk mode: cast(false)
  slot bell = herald mode: cast(has_tag(candidate, local))
  stage arrive
    waits_until false
scene room
  lookout: Here. #line:room
  -> end
"""


func _boot(body: String, seed_value: int) -> Dictionary:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var path := "user://wyrd_m4_cast.wyrd"
	_write(path, body)
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(seed_value)
	return {"host": host, "runtime": runtime}


func _people(host: WyrdFakeHost) -> void:
	host.world.add_entity(&"ada", &"person", "Ada", PackedStringArray(["local"]), true)
	host.world.add_entity(&"bea", &"person", "Bea", PackedStringArray(["local"]), true)
	host.world.add_entity(&"cy", &"person", "Cy", PackedStringArray(), true)
	host.world.add_entity(&"dock.bell", &"object", "bell", PackedStringArray(), true)
	host.world.add_entity(&"player", &"person", "traveler", PackedStringArray(), true)


func _expect(ids: Array, seed_value: int, quest_id: String, slot_name: String) -> String:
	var sorted: Array = ids.duplicate()
	sorted.sort()
	var key := StringName("%s|%s" % [quest_id, slot_name])
	var rng := WyrdRng.for_decision(seed_value, &"cast", key, 0)
	return String(sorted[rng.randi_bounded(sorted.size())])


func _cast_count(runtime: WyrdRuntime) -> int:
	var count := 0
	for row in runtime.trace.events:
		if String(row.get("kind", "")) == "cast":
			count += 1
	return count


func _cast_event(runtime: WyrdRuntime, slot_name: String) -> Dictionary:
	var found := {}
	for row in runtime.trace.events:
		if String(row.get("kind", "")) == "cast" and String(row.get("slot", "")) == slot_name:
			found = row
	return found


func _write(path: String, body: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(body)
	file.close()
