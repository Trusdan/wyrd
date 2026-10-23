extends GutTest

## Social cache matches a bypassed recomputation, and invalidation follows the scheduler.


const _PATH := """
language 1
scene room
  when path_exists(ada, cy, [friend], 2): narrator: Linked. #line:linked
  -> end
"""


func test_cached_reads_match_the_bypass() -> void:
	var runtime := _scripted()
	assert_lt(runtime.deeds.witness_indexes(&"ferry").size(), runtime.deeds.actor_indexes(&"player").size())
	assert_eq(runtime.deeds.target_indexes(&"ferry").size(), 1)
	var first := _readout(runtime)
	assert_eq(float(first["axis"]), 90.0)
	assert_eq(int(first["disp"]), 95)
	assert_eq(float(first["rep"]), 95.0)
	assert_true(bool(first["path"]))
	assert_false(bool(first["path_short"]))
	runtime.trace.enabled = true
	runtime.trace.clear()
	var second := _readout(runtime)
	assert_eq(JSON.stringify(second), JSON.stringify(first))
	assert_eq(_events(runtime, "miss").size(), 0)
	assert_gt(_events(runtime, "hit").size(), 0)
	runtime.social.set_cache(false)
	var fresh := _readout(runtime)
	assert_eq(JSON.stringify(fresh), JSON.stringify(first))
	assert_eq(runtime.social.cache_entries(), 0)
	assert_false(runtime.social.cache_enabled())


func test_a_relationship_change_drops_the_cache() -> void:
	var runtime := _open()
	runtime.social.set_baseline(&"ferry", &"player", &"affinity", 5.0)
	runtime.social.set_kind(&"ada", &"bea", &"friend")
	assert_eq(runtime.social.axis(&"ferry", &"player", &"affinity"), 5.0)
	assert_true(runtime.social.path_exists(&"ada", &"bea", PackedStringArray(["friend"]), 1))
	runtime.trace.enabled = true
	runtime.social.set_baseline(&"ferry", &"player", &"affinity", 8.0)
	runtime.social.clear_kind(&"ada", &"bea", &"friend")
	assert_eq(_events(runtime, "invalidate").size(), 1)
	assert_eq(str(_events(runtime, "invalidate")[0]["key"]), "relation")
	assert_eq(runtime.social.axis(&"ferry", &"player", &"affinity"), 8.0)
	assert_false(runtime.social.path_exists(&"ada", &"bea", PackedStringArray(["friend"]), 1))
	_assert_bypass(runtime)


func test_a_deed_drops_the_cache() -> void:
	var runtime := _open()
	runtime.config().set_axis_delta(&"paid", &"affinity", 10.0)
	runtime.deeds.record(&"paid", &"player", &"ferry")
	assert_eq(runtime.social.axis(&"ferry", &"player", &"affinity"), 10.0)
	runtime.trace.enabled = true
	runtime.deeds.record(&"paid", &"player", &"ferry")
	assert_eq(runtime.social.axis(&"ferry", &"player", &"affinity"), 20.0)
	assert_eq(_events(runtime, "invalidate").size(), 1)
	assert_eq(str(_events(runtime, "invalidate")[0]["key"]), "deed")
	_assert_bypass(runtime)


func test_a_time_bucket_drops_the_cache() -> void:
	var runtime := _open()
	runtime.config().half_life_verbs = PackedStringArray(["paid"])
	runtime.config().half_life_minutes = PackedFloat64Array([60.0])
	runtime.config().set_axis_delta(&"paid", &"affinity", 40.0)
	runtime.deeds.record(&"paid", &"player", &"ferry")
	var full := runtime.social.axis(&"ferry", &"player", &"affinity")
	assert_eq(full, 40.0)
	runtime.trace.enabled = true
	runtime.tick(30)
	assert_eq(_events(runtime, "invalidate").size(), 0)
	assert_eq(runtime.social.axis(&"ferry", &"player", &"affinity"), full)
	assert_eq(str(_events(runtime, "hit")[-1]["event"]), "hit")
	runtime.trace.clear()
	runtime.tick(30)
	var decayed := runtime.social.axis(&"ferry", &"player", &"affinity")
	assert_eq(decayed, 20.0)
	assert_eq(_events(runtime, "invalidate").size(), 1)
	assert_eq(str(_events(runtime, "invalidate")[0]["key"]), "time")
	assert_eq(int(_events(runtime, "invalidate")[0]["bucket"]), 60)
	_assert_bypass(runtime)


func test_members_config_and_formula_drop_the_cache() -> void:
	var runtime := _open()
	_host(runtime).world.add_member(&"harbor_guild", &"ferry")
	runtime.social.set_baseline(&"dock", &"player", &"affinity", 20.0)
	assert_eq(runtime.social.reputation(&"player", &"harbor_guild"), 50.0)
	runtime.trace.enabled = true
	_host(runtime).world.add_member(&"harbor_guild", &"dock")
	runtime.invalidate_groups()
	assert_eq(runtime.social.reputation(&"player", &"harbor_guild"), 55.0)
	assert_eq(str(_events(runtime, "invalidate")[-1]["key"]), "members")
	runtime.social.set_kind(&"ferry", &"player", &"apprentice")
	runtime.config().set_axis_delta(&"paid", &"affinity", 40.0)
	runtime.config().set_kind_scale(&"apprentice", &"affinity", 2.0)
	runtime.deeds.record(&"paid", &"player", &"ferry")
	runtime.trace.clear()
	assert_eq(runtime.social.axis(&"ferry", &"player", &"affinity"), 80.0)
	runtime.config().set_kind_scale(&"apprentice", &"affinity", 1.0)
	assert_eq(runtime.social.axis(&"ferry", &"player", &"affinity"), 40.0)
	assert_eq(str(_events(runtime, "invalidate")[-1]["key"]), "config")
	runtime.trace.clear()
	assert_eq(runtime.social.disposition(&"ferry", &"player"), 70)
	runtime.social.register_formula(func(_a: StringName, _b: StringName, _axes: Dictionary) -> int:
		return 80
	)
	assert_eq(str(_events(runtime, "invalidate")[0]["key"]), "formula")
	assert_eq(runtime.social.disposition(&"ferry", &"player"), 80)
	_assert_bypass(runtime)


func test_cache_refresh_rebuilds_and_a_fresh_read_skips() -> void:
	var runtime := _open()
	runtime.social.set_baseline(&"ada", &"bea", &"affinity", 4.0)
	runtime.social.set_kind(&"ada", &"bea", &"friend")
	assert_eq(runtime.social.axis(&"ada", &"bea", &"affinity"), 4.0)
	assert_true(runtime.social.path_exists(&"ada", &"bea", PackedStringArray(["friend"]), 1))
	var filled := runtime.social.cache_entries()
	assert_gt(filled, 0)
	runtime.trace.enabled = true
	runtime.social.set_baseline(&"ada", &"bea", &"affinity", 9.0)
	assert_eq(runtime.scheduler().carry("cache_refresh"), 0)
	assert_eq(runtime.social.cache_entries(), 0)
	runtime.trace.clear()
	runtime.tick(0)
	assert_eq(runtime.scheduler().carry("cache_refresh"), 0)
	assert_eq(_scheduler_units(runtime, "cache_refresh"), 0)
	assert_eq(runtime.social.axis(&"ada", &"bea", &"affinity"), 9.0)
	assert_gt(_events(runtime, "miss").size(), 0)
	runtime.trace.clear()
	assert_eq(runtime.social.axis(&"ada", &"bea", &"affinity"), 9.0)
	assert_eq(str(_events(runtime, "hit")[0]["event"]), "hit")
	_assert_bypass(runtime)
	var again := _open()
	again.social.set_baseline(&"ada", &"bea", &"affinity", 4.0)
	assert_eq(again.social.axis(&"ada", &"bea", &"affinity"), 4.0)
	var queued := again.social.cache_entries()
	again.trace.enabled = true
	again.social.set_baseline(&"ada", &"bea", &"affinity", 9.0)
	assert_eq(again.social.axis(&"ada", &"bea", &"affinity"), 9.0)
	assert_eq(_events(again, "miss").size(), 1)
	again.trace.clear()
	again.tick(0)
	assert_eq(again.scheduler().carry("cache_refresh"), 0)
	assert_eq(_scheduler_units(again, "cache_refresh"), 0)
	assert_eq(_events(again, "miss").size(), 0)
	assert_eq(_events(again, "invalidate").size(), 0)
	assert_eq(again.social.axis(&"ada", &"bea", &"affinity"), 9.0)
	assert_gt(queued, 0)


func test_adjust_baseline_drops_entries_and_zero_does_not() -> void:
	var runtime := _open()
	runtime.social.set_baseline(&"ada", &"bea", &"affinity", 4.0)
	runtime.social.set_kind(&"ada", &"bea", &"friend")
	assert_eq(runtime.social.axis(&"ada", &"bea", &"affinity"), 4.0)
	var reputation := runtime.social.reputation(&"bea", &"ada")
	var filled := runtime.social.cache_entries()
	assert_gt(filled, 0)
	runtime.trace.enabled = true
	assert_false(runtime.social.adjust_baseline(&"ada", &"bea", &"affinity", 0.0))
	assert_eq(runtime.social.cache_entries(), filled)
	assert_eq(runtime.scheduler().carry("cache_refresh"), 0)
	assert_eq(runtime.social.axis(&"ada", &"bea", &"affinity"), 4.0)
	assert_push_warning("zero")
	runtime.trace.clear()
	assert_true(runtime.social.adjust_baseline(&"ada", &"bea", &"affinity", 5.0))
	assert_eq(runtime.social.cache_entries(), 0)
	assert_eq(runtime.scheduler().carry("cache_refresh"), 0)
	runtime.tick(0)
	assert_eq(runtime.scheduler().carry("cache_refresh"), 0)
	assert_eq(runtime.social.cache_entries(), 0)
	assert_eq(runtime.social.axis(&"ada", &"bea", &"affinity"), 9.0)
	assert_eq(runtime.social.reputation(&"bea", &"ada"), reputation)


func test_social_cache_trace_filters_and_load_is_quiet() -> void:
	var runtime := _boot(_PATH)
	runtime.social.set_baseline(&"ferry", &"player", &"affinity", 3.0)
	runtime.trace.enabled = false
	runtime.trace.clear()
	assert_eq(runtime.social.axis(&"ferry", &"player", &"affinity"), 3.0)
	runtime.social.set_baseline(&"ferry", &"player", &"affinity", 4.0)
	assert_eq(runtime.social.axis(&"ferry", &"player", &"affinity"), 4.0)
	assert_eq(runtime.trace.events.size(), 0)
	runtime.trace.enabled = true
	runtime.trace.prefix = "no-such"
	runtime.social.set_baseline(&"ferry", &"player", &"affinity", 5.0)
	assert_eq(_events(runtime, "invalidate").size(), 0)
	runtime.trace.prefix = "affinity"
	runtime.trace.clear()
	assert_eq(runtime.social.axis(&"ferry", &"player", &"affinity"), 5.0)
	var hits := _events(runtime, "miss")
	assert_eq(hits.size(), 1)
	assert_eq(str(hits[0]["who"]), "ferry")
	assert_eq(str(hits[0]["key"]), "player")
	assert_eq(str(hits[0]["path"]), "affinity")
	assert_eq(str(hits[0]["cache"]), "axis")
	runtime.scheduler().push("cache_refresh", "row-0")
	var saved := runtime.save_state()
	assert_eq(int(saved["schema_version"]), 4)
	var packed := JSON.stringify(saved)
	assert_false(packed.contains("social_cache"))
	assert_false(packed.contains("axis\t"))
	var flight: Dictionary = saved.get("flight", {})
	var scheduler: Dictionary = flight.get("scheduler", {})
	var refresh: Array = scheduler.get("cache_refresh", [])
	assert_gt(refresh.size(), 0)
	var loaded := _boot(_PATH)
	loaded.trace.enabled = true
	var report := loaded.load_state(saved)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(loaded.trace.events.size(), 0)
	assert_eq(loaded.social.cache_entries(), 0)
	assert_eq(loaded.scheduler().carry("cache_refresh"), refresh.size())
	assert_eq(loaded.social.axis(&"ferry", &"player", &"affinity"), 5.0)
	assert_eq(int(loaded.save_state()["schema_version"]), 4)


func test_path_exists_follows_directed_kinds() -> void:
	var runtime := _boot(_PATH)
	runtime.tick(0)
	assert_eq(_flag(runtime, "linked"), 0)
	assert_false(runtime.social.path_exists(&"ada", &"cy", PackedStringArray(["friend"]), 2))
	assert_true(runtime.social.path_exists(&"ada", &"ada", PackedStringArray(), 0))
	assert_false(runtime.social.path_exists(&"ada", &"ada", PackedStringArray(), -1))
	assert_false(runtime.social.path_exists(&"ada", &"cy", PackedStringArray(), 3))
	runtime.social.set_kind(&"ada", &"bea", &"friend")
	runtime.social.set_kind(&"bea", &"ada", &"friend")
	runtime.social.set_kind(&"bea", &"cy", &"crew")
	assert_false(runtime.social.path_exists(&"ada", &"cy", PackedStringArray(["friend"]), 2))
	assert_false(runtime.social.path_exists(&"ada", &"cy", PackedStringArray(["crew"]), 1))
	assert_true(runtime.social.path_exists(&"ada", &"cy", PackedStringArray(["crew", "friend"]), 2))
	assert_false(runtime.social.path_exists(&"cy", &"ada", PackedStringArray(["friend", "crew"]), 2))
	assert_false(runtime.social.path_exists(&"ada", &"missing", PackedStringArray(["friend"]), 4))
	runtime.social.set_kind(&"bea", &"cy", &"friend")
	runtime.tick(0)
	assert_eq(_flag(runtime, "linked"), 1)
	assert_true(_eval(runtime, "path_exists(ada, cy, [friend], 2)"))
	assert_false(_eval(runtime, "path_exists(ada, cy, [friend], 1)"))
	assert_true(_eval(runtime, "path_exists(ada, ada, [crew], 0)"))
	runtime.social.set_cache(false)
	assert_true(runtime.social.path_exists(&"ada", &"cy", PackedStringArray(["friend"]), 2))
	assert_false(runtime.social.path_exists(&"ada", &"missing", PackedStringArray(["friend"]), 4))


func test_reputation_fills_the_same_cache_keys() -> void:
	var direct := _reputation_tokens(true, true)
	var filled := _reputation_tokens(false, true)
	var bypass := _reputation_tokens(false, false)
	assert_eq(float(direct["score"]), float(filled["score"]))
	assert_eq(float(bypass["score"]), float(filled["score"]))
	assert_gt((filled["keys"] as PackedStringArray).size(), 0)
	assert_eq(direct["keys"], filled["keys"])
	assert_eq(filled["keys"], PackedStringArray([
		"axis\tada\tplayer\taffinity",
		"axis\tada\tplayer\trespect",
		"axis\tbea\tplayer\taffinity",
		"axis\tbea\tplayer\trespect",
		"axis\tcy\tplayer\taffinity",
		"axis\tcy\tplayer\trespect",
		"disp\tada\tplayer",
		"disp\tbea\tplayer",
		"disp\tcy\tplayer",
		"rep\tplayer\tharbor_guild",
	]))
	assert_eq(bypass["keys"], PackedStringArray())


func test_full_scale_cache_stays_lean() -> void:
	# Key text plus 8 bytes for an axis value, or 4 for disposition. Not process memory.
	var social := WyrdSocial.new()
	var count := 500
	social.fill_pair_matrix(count)
	var pairs := count * (count - 1)
	var axis_key := "axis\tdock_hand_000\tdock_hand_001\taffinity"
	var disp_key := "disp\tdock_hand_000\tdock_hand_001"
	var bytes := pairs * (axis_key.length() + 8 + disp_key.length() + 4)
	assert_eq(social.cache_entries(), pairs * 2)
	assert_eq(social.cache_bytes(), bytes)
	assert_eq(bytes, 21207500)
	assert_lt(bytes, 32 * 1024 * 1024)
	assert_lt(bytes, 384 * 1024 * 1024)


func _reputation_tokens(direct: bool, cache_on: bool) -> Dictionary:
	var runtime := _open()
	var host := _host(runtime)
	for who in ["ada", "bea", "cy"]:
		host.world.add_member(&"harbor_guild", StringName(who))
	runtime.config().set_axis_delta(&"paid", &"affinity", 4.0)
	runtime.config().set_axis_delta(&"paid", &"respect", 2.0)
	runtime.deeds.record(&"paid", &"player", &"ada", &"", PackedStringArray(), 1.0, PackedStringArray([&"ada", &"bea"]))
	assert_eq(runtime.social.cache_entries(), 0)
	runtime.social.set_cache(cache_on)
	if direct:
		for who in host.world.members(&"harbor_guild"):
			runtime.social.disposition(StringName(who), &"player")
	var score := runtime.social.reputation(&"player", &"harbor_guild")
	var keys := _cache_keys(runtime.social)
	runtime.social.set_baseline(&"ada", &"player", &"affinity", 1.0)
	return {"keys": keys, "score": score}


func _cache_keys(social: WyrdSocial) -> PackedStringArray:
	var keys: Array[String] = []
	_append_cache_keys(social._axis_cache, keys)
	_append_cache_keys(social._disp_cache, keys)
	_append_cache_keys(social._rep_cache, keys)
	_append_cache_keys(social._path_cache, keys)
	keys.sort()
	var packed := PackedStringArray()
	for key in keys:
		packed.append(key)
	return packed


func _append_cache_keys(table: Dictionary, into: Array[String]) -> void:
	for key in table.keys():
		into.append(String(key))


func _scripted() -> WyrdRuntime:
	var runtime := _open()
	var host := _host(runtime)
	host.world.add_member(&"harbor_guild", &"ferry")
	host.world.add_member(&"harbor_guild", &"player")
	runtime.config().set_axis_delta(&"paid", &"affinity", 40.0)
	runtime.config().set_kind_scale(&"apprentice", &"affinity", 2.0)
	runtime.config().half_life_verbs = PackedStringArray(["paid"])
	runtime.config().half_life_minutes = PackedFloat64Array([60.0])
	runtime.social.set_kind(&"ferry", &"player", &"apprentice")
	runtime.social.set_baseline(&"ferry", &"player", &"affinity", 10.0)
	runtime.social.set_kind(&"ada", &"bea", &"friend")
	runtime.social.set_kind(&"bea", &"cy", &"friend")
	for index in 5:
		runtime.deeds.record(&"paid", &"player", StringName("other_%d" % index))
	runtime.deeds.record(&"paid", &"player", &"ferry", &"", PackedStringArray(), 1.0, PackedStringArray([&"ferry"]))
	runtime.deeds.record(&"waved", &"player", &"slip")
	for index in 4:
		runtime.deeds.record(&"paid", StringName("npc_%d" % index), &"dock", &"", PackedStringArray(), 1.0, PackedStringArray([&"ferry"]))
	runtime.tick(10)
	return runtime


func _readout(runtime: WyrdRuntime) -> Dictionary:
	return {
		"axis": runtime.social.axis(&"ferry", &"player", &"affinity"),
		"disp": runtime.social.disposition(&"ferry", &"player"),
		"friend": runtime.social.axis(&"ferry", StringName("npc_0"), &"affinity"),
		"path": runtime.social.path_exists(&"ada", &"cy", PackedStringArray(["friend"]), 2),
		"path_order": runtime.social.path_exists(&"ada", &"cy", PackedStringArray(["crew", "friend"]), 2),
		"path_short": runtime.social.path_exists(&"ada", &"cy", PackedStringArray(["friend"]), 1),
		"rep": runtime.social.reputation(&"player", &"harbor_guild"),
		"self": runtime.social.path_exists(&"ada", &"ada", PackedStringArray(), 0),
	}


func _assert_bypass(runtime: WyrdRuntime) -> void:
	var cached := _readout(runtime)
	runtime.social.set_cache(false)
	var fresh := _readout(runtime)
	assert_eq(JSON.stringify(fresh), JSON.stringify(cached))
	assert_eq(runtime.social.cache_entries(), 0)


func _events(runtime: WyrdRuntime, event: String) -> Array:
	var rows: Array = []
	for item in runtime.trace.snapshot():
		var row: Dictionary = item
		if str(row.get("kind", "")) == "social_cache" and str(row.get("event", "")) == event:
			rows.append(row)
	return rows


func _scheduler_units(runtime: WyrdRuntime, queue: String) -> int:
	var units := 0
	for item in runtime.trace.snapshot():
		var row: Dictionary = item
		if str(row.get("kind", "")) != "scheduler" or str(row.get("queue", "")) != queue:
			continue
		units = maxi(units, int(row.get("units", 0)))
	return units


func _open() -> WyrdRuntime:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	runtime.set_meta(&"host", host)
	runtime.start_new_game(4)
	return runtime


func _boot(body: String) -> WyrdRuntime:
	var runtime := _open()
	var path := "user://wyrd_m8_social_cache.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(body)
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(4)
	return runtime


func _host(runtime: WyrdRuntime) -> WyrdFakeHost:
	return runtime.get_meta(&"host") as WyrdFakeHost


func _eval(runtime: WyrdRuntime, text: String) -> bool:
	var diagnostics := WyrdDiagnostics.new()
	var compiled := WyrdCondition.new().compile(text, runtime.content().schema, diagnostics, "sample.wyrd", 1, 1)
	assert_false(diagnostics.has_errors(), "%s %s" % [text, diagnostics.format()])
	return runtime.eval_bool(compiled)


func _flag(runtime: WyrdRuntime, record: String) -> int:
	var content := runtime.content()
	for i in content.conditions.size():
		if content.records[i] == record and content.sites[i] == "when":
			return int(runtime.condition_flags()[i])
	return -1
