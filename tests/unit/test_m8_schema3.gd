extends GutTest

## Schema 3 keeps a mid-spread save on the same path as a run that never saved.


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
	assert_eq(runtime.scheduler().carry("rumor"), 0)
	assert_eq(runtime.scheduler().carry("publish"), 0)
	assert_eq(runtime.scheduler().carry("cache_refresh"), 0)
	assert_eq(runtime.slice_remainder_units(), 0)
	assert_eq(int(runtime.save_state()["schema_version"]), 3)
	runtime.tick(1)
	assert_eq(runtime.scheduler().carry("rumor"), 0)
	assert_eq(runtime.facts.get(&"harbor.toll_fate"), &"stolen")


func test_mid_spread_save_matches_an_unsaved_run() -> void:
	for mode in ["30", "144", "minute"]:
		var live := _drive(mode, false)
		var saved := _drive(mode, true)
		assert_eq(_beliefs(saved), _beliefs(live), mode)
		assert_eq(String(saved.facts.get(&"harbor.toll_fate")), String(live.facts.get(&"harbor.toll_fate")))
		assert_eq(String(saved.facts.get(&"harbor.gazette")), String(live.facts.get(&"harbor.gazette")), mode)
		assert_true(String(saved.facts.get(&"harbor.gazette")).contains("harbor_gazette#"), mode)
		assert_eq(saved.rumors.reach_level("2", &"gullhaven"), live.rumors.reach_level("2", &"gullhaven"), mode)
		assert_eq(JSON.stringify(_trace(saved)), JSON.stringify(_trace(live)), mode)
		assert_eq(_beliefs(saved)["dock_hand"], "waived", mode)
		var flags: Dictionary = saved.get_meta(&"flight_seen")
		assert_true(bool(flags["rumor"]), mode)
		assert_true(bool(flags["publish"]), mode)
		assert_true(bool(flags["reach"]), mode)
		assert_true(bool(flags["held"]), mode)
		if mode != "minute":
			assert_true(bool(flags["slice"]), mode)


func _drive(mode: String, persist: bool) -> WyrdRuntime:
	var runtime := _boot()
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
			_reload(runtime)
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


func _reload(runtime: WyrdRuntime) -> void:
	var before := runtime.trace.events.size()
	var parsed: Variant = JSON.parse_string(JSON.stringify(runtime.save_state()))
	var report := runtime.load_state(parsed)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(runtime.trace.events.size(), before)
	runtime.social.set_cache(false)


func _boot() -> WyrdRuntime:
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
	runtime.social.set_cache(false)
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


func _trace(runtime: WyrdRuntime) -> Array:
	return runtime.trace.events


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
