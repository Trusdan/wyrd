extends GutTest

## Schema 3 keeps a mid-spread save on the same path as a run that never saved.
##
## tests/fixtures/schema3_harbor.json is save_state() after open_pack(HARBOR)
## and tick(1), written with JSON.stringify(state, "\t", true): tab indent,
## sorted keys, no trailing newline. The content hash is the Gullhaven
## manifest hash at capture. Update the fixture by hand if that content changes.


const _Harness := preload("res://tests/scenario/s2c_harness.gd")

const _BODY := """
language 1
facts
  harbor.toll_fate : symbol stored
  harbor.gazette : symbol stored
quest harbor_guild "The Harbor Guild"
  stage post
document harbor_gazette "Harbor Gazette" publishes_by harbor_guild every 1 minute delay 1 minute
  claim harbor.toll_fate
  fact harbor.gazette
  verb whispered
"""


func test_claim_tags_round_trip_symbol_and_float() -> void:
	var symbol: Variant = WyrdSave.unpack_claim(JSON.parse_string(JSON.stringify(WyrdSave.pack_claim(&"stolen"))))
	assert_eq(symbol, &"stolen")
	assert_true(symbol is StringName)
	var packed: Dictionary = WyrdSave.pack_claim(1.0)
	assert_eq(str(packed["t"]), "float")
	var restored: Variant = WyrdSave.unpack_claim(JSON.parse_string(JSON.stringify(packed)))
	assert_eq(typeof(restored), TYPE_FLOAT)
	assert_eq(restored, 1.0)
	var whole: Variant = WyrdSave.unpack_claim(JSON.parse_string(JSON.stringify(WyrdSave.pack_claim(2))))
	assert_eq(typeof(whole), TYPE_INT)
	assert_eq(whole, 2)


func test_schema_2_fixture_loads_with_empty_flight() -> void:
	var text := FileAccess.get_file_as_string("res://tests/fixtures/schema2_harbor.json")
	var parsed: Variant = JSON.parse_string(text)
	assert_true(parsed is Dictionary)
	var data: Dictionary = parsed
	assert_eq(int(data["schema_version"]), 2)
	assert_false(data.has("flight"))
	var opened := _Harness.new().open_pack(_Harness.HARBOR)
	var runtime: WyrdRuntime = opened["runtime"]
	var report := runtime.load_state(data)
	assert_true(report.ok, report.diagnostics.format())
	assert_false(report.diagnostics.has_warnings(), report.diagnostics.format())
	assert_eq(runtime.facts.get(&"harbor.toll_fate"), &"stolen")
	assert_eq(runtime.facts.get(&"player.coins"), 4)
	assert_gt(runtime.scheduler().dirty_count(), 0)
	assert_eq(runtime.scheduler().carry("rumor"), 0)
	assert_eq(runtime.scheduler().carry("publish"), 0)
	assert_eq(runtime.scheduler().carry("cache_refresh"), 0)
	assert_eq(runtime.slice_remainder_units(), 0)
	var resaved := runtime.save_state()
	assert_eq(int(resaved["schema_version"]), 4)
	assert_false(resaved.has("generator"))
	assert_eq(runtime.quests.active_count("errand"), 0)
	runtime.tick(1)
	assert_eq(runtime.scheduler().carry("rumor"), 0)
	assert_eq(runtime.facts.get(&"harbor.toll_fate"), &"stolen")


func test_schema_3_fixture_loads_and_round_trips() -> void:
	var text := FileAccess.get_file_as_string("res://tests/fixtures/schema3_harbor.json")
	var parsed: Variant = JSON.parse_string(text)
	assert_true(parsed is Dictionary)
	var data: Dictionary = parsed
	assert_eq(int(data["schema_version"]), 3)
	assert_true(data.has("flight"))
	var opened := _Harness.new().open_pack(_Harness.HARBOR)
	var runtime: WyrdRuntime = opened["runtime"]
	var report := runtime.load_state(data)
	assert_true(report.ok, report.diagnostics.format())
	assert_false(report.diagnostics.has_warnings(), report.diagnostics.format())
	assert_eq(runtime.play_minutes(), 1)
	assert_eq(runtime.quests.status("mooring_post"), &"dormant")
	assert_eq(runtime.quests.status("bell_repair"), &"active")
	assert_eq(runtime.quests.stage("bell_repair"), "repair")
	assert_eq(runtime.roles.holder(&"ferry_master"), &"ferry_master")
	var covered: Dictionary = runtime.publish.export_state().get("covered", {})
	assert_eq(int(covered.get("harbor_gazette", -1)), 1)
	assert_eq(JSON.stringify(runtime.save_state(), "\t", true), text.replace("\"schema_version\": 3,", "\"schema_version\": 4,"))
	runtime.tick(1)


func test_schema_3_save_without_flight_clears_dirty_waits() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/schema3_harbor.json"))
	assert_true(parsed is Dictionary)
	var data: Dictionary = parsed
	data.erase("flight")
	var opened := _Harness.new().open_pack(_Harness.HARBOR)
	var runtime: WyrdRuntime = opened["runtime"]
	assert_gt(runtime.scheduler().dirty_count(), 0)
	var report := runtime.load_state(data)
	assert_true(report.ok, report.diagnostics.format())
	assert_false(report.diagnostics.has_warnings(), report.diagnostics.format())
	assert_eq(runtime.scheduler().dirty_count(), 0)
	assert_eq(runtime.scheduler().carry("rumor"), 0)
	assert_eq(runtime.scheduler().carry("publish"), 0)
	assert_eq(runtime.scheduler().carry("cache_refresh"), 0)
	assert_eq(runtime.scheduler().carry("waits"), 0)
	assert_eq(runtime.slice_remainder_units(), 0)
	assert_eq(WyrdSave.FLIGHT_SINCE_SCHEMA, 3)


func test_mid_spread_save_matches_an_unsaved_run() -> void:
	for mode in ["30", "144", "minute"]:
		_assert_matrix(mode, false)
		_assert_matrix(mode, true)


func test_a_missing_policy_drops_only_that_rumor() -> void:
	var saved := _two_rumors()
	var full := _open_rumors(true)
	var partial := _open_rumors(false)
	var full_report := full.load_state(saved)
	assert_true(full_report.ok, full_report.diagnostics.format())
	assert_false(full_report.diagnostics.has_errors(), full_report.diagnostics.format())
	var partial_report := partial.load_state(saved)
	assert_push_error("harbor_toll")
	assert_push_error("harbor_bell")
	assert_true(partial_report.ok, partial_report.diagnostics.format())
	var text := partial_report.diagnostics.format()
	assert_true(text.contains("harbor_toll"), text)
	assert_true(text.contains("deed 1"), text)
	assert_true(text.contains("harbor_bell"), text)
	assert_true(text.contains("deed 3"), text)
	assert_eq(partial.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"), &"waived")
	assert_eq(partial.facts.get(&"harbor.toll_fate"), &"lost_at_sea")
	assert_eq(partial.facts.get(&"player.coins"), 4)
	assert_false(_rumor_deeds(partial).has("1"))
	assert_false(_token_deeds(partial).has("1"))
	assert_eq(partial.rumors.reach_level("3", &"gullhaven"), -1)
	assert_false(_token_deeds(partial).has("3"))
	assert_true(_rumor_deeds(partial).has("2"))
	assert_eq(_job_policy(partial, "2"), "harbor_whisper")
	assert_eq(_job_policy(full, "2"), "harbor_whisper")
	assert_eq(_token_rows(partial, "2"), _token_rows(full, "2"))
	assert_eq(full.rumors.reach_level("3", &"gullhaven"), 0)
	full.trace.clear()
	partial.trace.clear()
	full.config().scheduler_work_per_tick = 64
	partial.config().scheduler_work_per_tick = 64
	full.tick(0)
	partial.tick(0)
	assert_eq(partial.facts.get_in(&"harbor.toll_fate", &"believed/dock_apprentice"), &"waived")
	assert_eq(
		partial.facts.get_in(&"harbor.toll_fate", &"believed/dock_apprentice"),
		full.facts.get_in(&"harbor.toll_fate", &"believed/dock_apprentice")
	)
	assert_null(partial.facts.get_in(&"harbor.toll_fate", &"believed/ferry_master"))
	assert_eq(full.facts.get_in(&"harbor.toll_fate", &"believed/ferry_master"), &"waived")
	assert_eq(partial.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"), &"waived")
	assert_eq(_rows_for(partial, "harbor_whisper"), _rows_for(full, "harbor_whisper"))
	assert_eq(_job_policy(partial, "2"), "harbor_whisper")
	assert_false(_rumor_deeds(partial).has("1"))
	assert_false(_rumor_deeds(partial).has("3"))


func _assert_matrix(mode: String, cache_on: bool) -> void:
	var label := "%s cache=%s" % [mode, "on" if cache_on else "off"]
	var live := _drive(mode, false, cache_on)
	var saved := _drive(mode, true, cache_on)
	assert_eq(_beliefs(saved), _beliefs(live), label)
	assert_eq(String(saved.facts.get(&"harbor.toll_fate")), String(live.facts.get(&"harbor.toll_fate")), label)
	assert_eq(String(saved.facts.get(&"harbor.gazette")), String(live.facts.get(&"harbor.gazette")), label)
	assert_true(String(saved.facts.get(&"harbor.gazette")).contains("harbor_gazette#"), label)
	assert_eq(saved.rumors.reach_level("2", &"gullhaven"), live.rumors.reach_level("2", &"gullhaven"), label)
	if cache_on:
		assert_eq(JSON.stringify(saved.facts.export_state()), JSON.stringify(live.facts.export_state()), label)
		assert_eq(JSON.stringify(saved.publish.export_state()), JSON.stringify(live.publish.export_state()), label)
		assert_eq(JSON.stringify(_trace(saved, true)), JSON.stringify(_trace(live, true)), label)
	else:
		assert_eq(JSON.stringify(_trace(saved)), JSON.stringify(_trace(live)), label)
	assert_eq(_beliefs(saved)["dock_hand"], "waived", label)
	var flags: Dictionary = saved.get_meta(&"flight_seen")
	assert_true(bool(flags["rumor"]), label)
	assert_true(bool(flags["publish"]), label)
	assert_true(bool(flags["reach"]), label)
	assert_true(bool(flags["held"]), label)
	if mode != "minute":
		assert_true(bool(flags["slice"]), label)


func _drive(mode: String, persist: bool, cache_on: bool) -> WyrdRuntime:
	var runtime := _boot(cache_on)
	var flags := {"held": false, "publish": false, "reach": false, "rumor": false, "slice": false}
	var step := 720
	if mode == "30":
		step = 24
	elif mode == "144":
		step = 5
	var slice := float(step) / float(WyrdScheduler.SLICE_UNITS_PER_MINUTE)
	var elapsed := 0
	var asked := false
	while elapsed < 3 * WyrdScheduler.SLICE_UNITS_PER_MINUTE:
		runtime.tick(slice)
		elapsed += step
		if elapsed == 2 * WyrdScheduler.SLICE_UNITS_PER_MINUTE and not asked:
			asked = true
			runtime.eval_bool(_compile(runtime, "belief(storm_watcher, harbor.toll_fate) == stolen"))
		if not _marks(mode).has(elapsed):
			continue
		_note(runtime, flags)
		if persist:
			_reload(runtime, cache_on)
	runtime.config().scheduler_work_per_tick = 64
	runtime.config().scheduler_share_waits = 40
	runtime.config().scheduler_share_rumor = 12
	runtime.config().scheduler_share_publish = 8
	runtime.config().scheduler_share_cache = 4
	runtime.tick(0)
	runtime.set_meta(&"flight_seen", flags)
	return runtime


func _marks(mode: String) -> Array:
	if mode == "minute":
		return [720, 1440]
	return [360, 1080, 1800]


func _note(runtime: WyrdRuntime, flags: Dictionary) -> void:
	var saved := runtime.save_state()
	var flight: Dictionary = saved.get("flight", {})
	var scheduler: Dictionary = flight.get("scheduler", {})
	var rumor_tokens: Variant = scheduler.get("rumor", [])
	if rumor_tokens is Array and not (rumor_tokens as Array).is_empty():
		flags["rumor"] = true
	var publish_tokens: Variant = scheduler.get("publish", [])
	if publish_tokens is Array and not (publish_tokens as Array).is_empty():
		flags["publish"] = true
	if int(scheduler.get("slice", 0)) != 0:
		flags["slice"] = true
	var rumor: Dictionary = flight.get("rumor", {})
	var reach: Variant = rumor.get("reach", [])
	if reach is Array and not (reach as Array).is_empty():
		flags["reach"] = true
	var held: Variant = rumor.get("held", [])
	if held is Array and not (held as Array).is_empty():
		flags["held"] = true


func _reload(runtime: WyrdRuntime, cache_on: bool) -> void:
	var before := runtime.trace.events.size()
	var parsed: Variant = JSON.parse_string(JSON.stringify(runtime.save_state()))
	var report := runtime.load_state(parsed)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(runtime.trace.events.size(), before)
	if not cache_on:
		runtime.social.set_cache(false)


func _boot(cache_on: bool) -> WyrdRuntime:
	var path := "user://wyrd_m8_schema3.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file)
	file.store_string(_BODY)
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	runtime.set_meta(&"host", host)
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(4)
	runtime.social.set_cache(cache_on)
	runtime.config().rumor_coarse_minutes = 1
	runtime.config().scheduler_work_per_tick = 1
	runtime.config().scheduler_share_waits = 0
	runtime.config().scheduler_share_rumor = 1
	runtime.config().scheduler_share_publish = 0
	runtime.config().scheduler_share_cache = 0
	runtime.facts.set(&"harbor.toll_fate", &"lost_at_sea")
	var policy := WyrdRumorPolicy.new()
	policy.id = &"harbor_toll"
	policy.kinds = PackedStringArray(["friend"])
	policy.max_hops = 2
	policy.pass_chance = 1.0
	policy.verbs = PackedStringArray(["whispered"])
	policy.mutations = [_change()]
	runtime.register_rumor_policy(policy)
	runtime.social.set_kind(&"line_fisher", &"dock_hand", &"friend")
	runtime.social.set_kind(&"dock_hand", &"ferry_master", &"friend")
	host.spatial.set_precision(&"gullhaven", &"coarse")
	host.spatial.set_precision(&"dock", &"precise")
	host.spatial.set_place(&"line_fisher", &"dock")
	host.spatial.set_place(&"dock_hand", &"dock")
	host.spatial.set_place(&"ferry_master", &"dock")
	host.spatial.set_place(&"storm_watcher", &"gullhaven")
	runtime.trace.enabled = true
	_whisper(runtime, &"dock")
	_whisper(runtime, &"gullhaven")
	return runtime


func _whisper(runtime: WyrdRuntime, place: StringName) -> void:
	runtime.perception_claim("harbor.toll_fate", &"stolen")
	runtime.deeds.record(&"whispered", &"line_fisher", &"", place)
	runtime.clear_perception_claim()


func _change() -> Dictionary:
	return {
		"field": "harbor.toll_fate",
		"keep_chance_fn": Callable(self, &"_keep_none"),
		"to": Callable(self, &"_waive"),
	}


func _keep_none(_value: Variant, _hop_n: int) -> float:
	return 0.0


func _waive(_value: Variant, _hop_n: int) -> StringName:
	return &"waived"


func _beliefs(runtime: WyrdRuntime) -> Dictionary:
	var out := {}
	for person in ["dock_hand", "ferry_master", "line_fisher", "storm_watcher"]:
		var value: Variant = runtime.facts.get_in(&"harbor.toll_fate", StringName("believed/%s" % person))
		if value != null:
			out[person] = String(value)
	return out


func _trace(runtime: WyrdRuntime, skip_cache: bool = false) -> Array:
	if not skip_cache:
		return runtime.trace.events
	var out: Array = []
	for row in runtime.trace.events:
		if String(row.get("kind", "")) == "social_cache":
			continue
		out.append(row)
	return out


const _RUMORS := """
language 1
facts
  harbor.toll_fate : symbol stored
  player.coins : int stored
quest harbor_guild "The Harbor Guild"
  stage post
"""


func _two_rumors() -> Dictionary:
	var runtime := _open_rumors(true)
	runtime.config().scheduler_work_per_tick = 1
	runtime.config().scheduler_share_waits = 0
	runtime.config().scheduler_share_rumor = 1
	runtime.config().scheduler_share_publish = 0
	runtime.config().scheduler_share_cache = 0
	runtime.facts.set(&"harbor.toll_fate", &"lost_at_sea")
	runtime.facts.set(&"player.coins", 4)
	_speak(runtime, &"whispered", &"line_fisher", &"dock")
	runtime.tick(0)
	_speak(runtime, &"arrived", &"storm_watcher", &"dock")
	_speak(runtime, &"paid", &"storm_watcher", &"gullhaven")
	return JSON.parse_string(JSON.stringify(runtime.save_state()))


func _open_rumors(every_policy: bool) -> WyrdRuntime:
	var path := "user://wyrd_m8_schema3_policy.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file)
	file.store_string(_RUMORS)
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	runtime.set_meta(&"host", host)
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(4)
	runtime.social.set_cache(false)
	host.spatial.set_precision(&"gullhaven", &"coarse")
	host.spatial.set_precision(&"dock", &"precise")
	host.spatial.set_place(&"line_fisher", &"dock")
	host.spatial.set_place(&"dock_hand", &"dock")
	host.spatial.set_place(&"ferry_master", &"dock")
	host.spatial.set_place(&"storm_watcher", &"gullhaven")
	host.spatial.set_place(&"dock_apprentice", &"dock")
	runtime.social.set_kind(&"line_fisher", &"dock_hand", &"friend")
	runtime.social.set_kind(&"dock_hand", &"ferry_master", &"friend")
	runtime.social.set_kind(&"storm_watcher", &"dock_apprentice", &"friend")
	if every_policy:
		_policy(runtime, &"harbor_toll", PackedStringArray(["whispered"]), 2)
		_policy(runtime, &"harbor_bell", PackedStringArray(["paid"]), 1)
	_policy(runtime, &"harbor_whisper", PackedStringArray(["arrived"]), 1)
	runtime.trace.enabled = true
	return runtime


func _policy(runtime: WyrdRuntime, id: StringName, verbs: PackedStringArray, hops: int) -> void:
	var policy := WyrdRumorPolicy.new()
	policy.id = id
	policy.kinds = PackedStringArray(["friend"])
	policy.max_hops = hops
	policy.pass_chance = 1.0
	policy.verbs = verbs
	policy.mutations = [_change()]
	runtime.register_rumor_policy(policy)


func _speak(runtime: WyrdRuntime, verb: StringName, actor: StringName, place: StringName) -> void:
	runtime.perception_claim("harbor.toll_fate", &"stolen")
	runtime.deeds.record(verb, actor, &"", place)
	runtime.clear_perception_claim()


func _rumor_deeds(runtime: WyrdRuntime) -> Dictionary:
	var found := {}
	var flight: Dictionary = runtime.rumors.export_state()
	for bag_name in ["jobs", "reach", "held", "gone", "seen", "queued"]:
		var rows: Variant = flight.get(bag_name, [])
		if not (rows is Array):
			continue
		for item in rows:
			if item is Dictionary:
				found[str((item as Dictionary).get("deed", ""))] = true
	for token in _list_of(flight.get("drawn", [])):
		found[_pair_deed(token)] = true
	return found


func _token_deeds(runtime: WyrdRuntime) -> Dictionary:
	var found := {}
	for token in runtime.scheduler().carry_tokens("rumor"):
		found[_token_deed(token)] = true
	return found


func _token_rows(runtime: WyrdRuntime, deed_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for token in runtime.scheduler().carry_tokens("rumor"):
		if _token_deed(token) == deed_id:
			out.append(token)
	return out


func _token_deed(token: String) -> String:
	var parts := token.split("\t")
	if parts.size() >= 2 and parts[0] == "reach":
		return parts[1]
	if parts.is_empty():
		return ""
	return parts[0]


func _pair_deed(token: String) -> String:
	var cut := token.find("\t")
	if cut < 0:
		return token
	return token.substr(0, cut)


func _list_of(raw: Variant) -> Array:
	if raw is Array:
		return raw
	return []


func _job_policy(runtime: WyrdRuntime, deed_id: String) -> String:
	for item in _list_of(runtime.rumors.export_state().get("jobs", [])):
		if item is Dictionary and str((item as Dictionary).get("deed", "")) == deed_id:
			return str((item as Dictionary).get("policy", ""))
	return ""


func _rows_for(runtime: WyrdRuntime, policy_id: String) -> Array:
	var out: Array = []
	for row in runtime.trace.events:
		var kind := String(row.get("kind", ""))
		if not kind.begins_with("rumor_"):
			continue
		if String(row.get("path", "")) == policy_id:
			out.append(row)
	return out


func _compile(runtime: WyrdRuntime, text: String) -> WyrdCompiledCondition:
	var diagnostics := WyrdDiagnostics.new()
	var compiled := WyrdCondition.new().compile(
		text,
		runtime.content().schema,
		diagnostics,
		"sample.wyrd",
		1,
		1
	)
	assert_false(diagnostics.has_errors(), "%s %s" % [text, diagnostics.format()])
	return compiled
