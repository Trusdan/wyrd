extends GutTest

const _Harness := preload("res://tests/scenario/s2c_harness.gd")
const _FIXTURE := "res://tests/fixtures/schema4_ai_harbor.json"


func test_only_a_passing_delivery_is_cached() -> void:
	var runtime := _runtime()
	var provider := _provider("The gate is shut tonight.", true)
	runtime.register_adapter(WyrdAIProvider, provider)
	runtime.ai.request(&"bark_paraphrase", {"text": "The gate is shut."}, {}, &"toll.keeper")
	assert_eq(runtime.ai.cache_size(), 1)
	assert_eq(str(_rows(runtime, "ai_cache")[0]["op"]), "insert")
	assert_eq(int(_rows(runtime, "ai_cache")[0]["count"]), 1)
	assert_eq(str(_rows(runtime, "ai_cache")[0]["key"]), runtime.ai.cache_keys()[0])
	assert_eq(runtime.ai.cached_text(runtime.ai.cache_keys()[0]), "The gate is shut tonight.")
	runtime.trace.clear()
	provider.text = "{"
	runtime.ai.request(&"bark_paraphrase", {"text": "The gate is shut."}, {}, &"toll.keeper")
	assert_eq(runtime.ai.cache_size(), 1)
	assert_eq(_rows(runtime, "ai_cache").size(), 0)
	assert_eq(str(_rows(runtime, "ai_validate")[0]["rule"]), "limits")
	runtime.trace.clear()
	provider.ok = false
	provider.text = "The gate is shut tonight."
	runtime.ai.request(&"gossip", {"text": "The gate is shut."}, {}, &"toll.keeper")
	assert_eq(runtime.ai.cache_size(), 1)
	assert_eq(_rows(runtime, "ai_cache").size(), 0)
	assert_eq(str(_rows(runtime, "ai_validate")[0]["rule"]), "provider")


func test_eviction_traces_oldest() -> void:
	var runtime := _runtime()
	runtime.config().ai_cache_max = 1
	var provider := _provider("The gate is shut.", true)
	runtime.register_adapter(WyrdAIProvider, provider)
	runtime.ai.request(&"bark_paraphrase", {"text": "The gate is shut."}, {}, &"toll.keeper")
	var first := String(runtime.ai.cache_keys()[0])
	runtime.trace.clear()
	provider.text = "The lane is quiet."
	runtime.ai.request(&"bark_paraphrase", {"text": "The lane is quiet."}, {}, &"toll.lane")
	var rows := _rows(runtime, "ai_cache")
	assert_eq(rows.size(), 2)
	assert_eq(str(rows[0]["op"]), "insert")
	assert_eq(int(rows[0]["count"]), 2)
	assert_eq(str(rows[1]["op"]), "evict")
	assert_eq(str(rows[1]["key"]), first)
	assert_eq(int(rows[1]["count"]), 1)
	assert_eq(runtime.ai.cache_size(), 1)
	assert_eq(runtime.ai.cached_text(first), "")
	assert_eq(runtime.ai.cached_text(runtime.ai.cache_keys()[0]), "The lane is quiet.")


func test_new_game_clears_and_a_second_clear_is_silent() -> void:
	var runtime := _runtime()
	var provider := _provider("The gate is shut.", true)
	runtime.register_adapter(WyrdAIProvider, provider)
	runtime.ai.request(&"bark_paraphrase", {"text": "The gate is shut."}, {}, &"toll.keeper")
	assert_eq(runtime.ai.cache_size(), 1)
	runtime.start_new_game(1)
	assert_eq(runtime.ai.cache_size(), 0)
	assert_eq(str(_rows(runtime, "ai_cache")[0]["op"]), "clear")
	assert_eq(str(_rows(runtime, "ai_cache")[0]["key"]), "-")
	assert_eq(int(_rows(runtime, "ai_cache")[0]["count"]), 0)
	runtime.start_new_game(1)
	assert_eq(_rows(runtime, "ai_cache").size(), 0)


func test_save_writes_ai_only_when_asked_and_non_empty() -> void:
	var runtime := _runtime()
	var plain := JSON.stringify(runtime.save_state(), "", true)
	assert_false(runtime.save_state().has("ai"))
	var provider := _provider("The gate is shut.", true)
	runtime.register_adapter(WyrdAIProvider, provider)
	runtime.ai.request(&"bark_paraphrase", {"text": "The gate is shut."}, {}, &"toll.one")
	provider.text = "The lane is quiet."
	runtime.ai.request(&"bark_paraphrase", {"text": "The lane is quiet."}, {}, &"toll.two")
	var saved := runtime.save_state()
	assert_true(saved.has("ai"))
	assert_eq(int(saved["ai"]["v"]), 1)
	var rows: Array = saved["ai"]["cache"]
	assert_eq(rows.size(), 2)
	assert_eq(str(rows[0]["t"]), "The gate is shut.")
	assert_eq(str(rows[1]["t"]), "The lane is quiet.")
	assert_eq(str(rows[0]["k"]), String(runtime.ai.cache_keys()[0]))
	runtime.config().ai_save_cache = false
	assert_false(runtime.save_state().has("ai"))
	assert_eq(JSON.stringify(runtime.save_state(), "", true), plain)
	runtime.config().ai_save_cache = true
	runtime.ai.clear_cache()
	assert_false(runtime.save_state().has("ai"))
	assert_eq(JSON.stringify(runtime.save_state(), "", true), plain)


func test_load_round_trip() -> void:
	var runtime := _runtime()
	var provider := _provider("The gate is shut.", true)
	runtime.register_adapter(WyrdAIProvider, provider)
	runtime.ai.request(&"bark_paraphrase", {"text": "The gate is shut."}, {}, &"toll.keeper")
	var saved := runtime.save_state()
	var key := String(runtime.ai.cache_keys()[0])
	runtime.trace.clear()
	var report := runtime.load_state(saved)
	assert_true(report.ok, report.diagnostics.format())
	assert_false(report.diagnostics.has_warnings(), report.diagnostics.format())
	assert_eq(runtime.ai.cache_keys(), PackedStringArray([key]))
	assert_eq(runtime.ai.cached_text(key), "The gate is shut.")
	var row: Dictionary = _rows(runtime, "ai_cache")[0]
	assert_eq(str(row["op"]), "load")
	assert_eq(str(row["key"]), "-")
	assert_eq(int(row["count"]), 1)


func test_malformed_ai_warns_and_clears() -> void:
	var runtime := _runtime()
	_fill(runtime)
	var base := runtime.save_state()
	for bad in ["nope", {"v": 2, "cache": []}, {"v": 1, "cache": "rows"}, {"cache": []}]:
		_fill(runtime)
		var doc: Dictionary = base.duplicate(true)
		doc["ai"] = bad
		runtime.trace.clear()
		var report := runtime.load_state(doc)
		assert_true(report.ok, report.diagnostics.format())
		assert_eq(_warning_count(report, "not valid and was ignored"), 1, str(bad))
		assert_eq(runtime.ai.cache_size(), 0)
		assert_eq(str(_rows(runtime, "ai_cache")[0]["op"]), "load")
		assert_eq(int(_rows(runtime, "ai_cache")[0]["count"]), 0)


func test_bad_rows_warn_once_and_keep_the_rest() -> void:
	var runtime := _runtime()
	_fill(runtime)
	var doc := runtime.save_state()
	var rows: Array = doc["ai"]["cache"]
	rows.append({"k": "ABCDEF0123456789", "t": "no"})
	rows.append({"k": "0123456789abcdef", "t": "{x}"})
	doc["ai"]["cache"] = rows
	runtime.trace.clear()
	var report := runtime.load_state(doc)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(_warning_count(report, "2 entries were not valid and were skipped"), 1)
	assert_eq(runtime.ai.cache_size(), 2)
	assert_eq(str(_rows(runtime, "ai_cache")[0]["op"]), "load")
	assert_eq(int(_rows(runtime, "ai_cache")[0]["count"]), 2)


func test_missing_ai_key_clears() -> void:
	var runtime := _runtime()
	_fill(runtime)
	var doc := runtime.save_state()
	doc.erase("ai")
	runtime.trace.clear()
	var report := runtime.load_state(doc)
	assert_true(report.ok, report.diagnostics.format())
	assert_false(report.diagnostics.has_warnings(), report.diagnostics.format())
	assert_eq(runtime.ai.cache_size(), 0)
	assert_eq(str(_rows(runtime, "ai_cache")[0]["op"]), "clear")
	assert_eq(int(_rows(runtime, "ai_cache")[0]["count"]), 0)


func test_failed_load_keeps_the_cache() -> void:
	var runtime := _runtime()
	_fill(runtime)
	var keys := runtime.ai.cache_keys()
	var doc := runtime.save_state()
	doc["seed"] = "not-a-seed"
	var report := runtime.load_state(doc)
	assert_false(report.ok)
	assert_push_error("16 hex digits")
	assert_eq(runtime.ai.cache_keys(), keys)
	assert_eq(runtime.ai.cached_text(String(keys[0])), "The gate is shut.")


func test_can_save_ignores_the_cache() -> void:
	var runtime := _runtime()
	assert_true(runtime.can_save())
	_fill(runtime)
	assert_true(runtime.can_save())
	assert_gt(runtime.ai.cache_size(), 0)


func test_default_provider_gullhaven_has_no_ai() -> void:
	var opened := _Harness.new().boot_gullhaven()
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.trace.enabled = true
	runtime.trace.clear()
	runtime.tick(1)
	runtime.deeds.record(&"arrived", &"player", &"", &"gullhaven")
	var hits := 0
	for row in runtime.trace.events:
		if str(row.get("kind", "")).begins_with("ai_"):
			hits += 1
	assert_eq(hits, 0)
	assert_false(runtime.save_state().has("ai"))
	assert_eq(runtime.ai.cache_size(), 0)


func test_schema4_fixture_loads_and_is_ignorable() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_FIXTURE))
	assert_true(parsed is Dictionary)
	var data: Dictionary = parsed
	assert_eq(int(data["schema_version"]), 4)
	assert_eq(int(data["ai"]["v"]), 1)
	var listed: Array = data["ai"]["cache"]
	assert_eq(listed.size(), 2)
	var opened := _Harness.new().open_pack(_Harness.HARBOR)
	var runtime: WyrdRuntime = opened["runtime"]
	var report := runtime.load_state(data)
	assert_true(report.ok, report.diagnostics.format())
	assert_false(report.diagnostics.has_warnings(), report.diagnostics.format())
	assert_eq(runtime.ai.cache_size(), 2)
	for row in listed:
		assert_eq(runtime.ai.cached_text(str(row["k"])), str(row["t"]))
	assert_eq(String(runtime.ai.cache_keys()[0]), str(listed[0]["k"]))
	assert_eq(String(runtime.ai.cache_keys()[1]), str(listed[1]["k"]))
	var stripped: Dictionary = data.duplicate(true)
	stripped.erase("ai")
	var other: WyrdRuntime = _Harness.new().open_pack(_Harness.HARBOR)["runtime"]
	var again := other.load_state(stripped)
	assert_true(again.ok, again.diagnostics.format())
	assert_eq(other.ai.cache_size(), 0)
	var left := runtime.save_state()
	left.erase("ai")
	var right := other.save_state()
	right.erase("ai")
	assert_eq(JSON.stringify(left, "", true), JSON.stringify(right, "", true))


func _fill(runtime: WyrdRuntime) -> void:
	if runtime.ai.cache_size() > 0:
		return
	var provider := _provider("The gate is shut.", true)
	runtime.register_adapter(WyrdAIProvider, provider)
	runtime.ai.request(&"bark_paraphrase", {"text": "The gate is shut."}, {}, &"toll.keeper")
	provider.text = "The lane is quiet."
	runtime.ai.request(&"bark_paraphrase", {"text": "The lane is quiet."}, {}, &"toll.lane")


func _warning_count(report: WyrdLoadReport, message: String) -> int:
	var hits := 0
	for item in report.diagnostics.items:
		if item.code == WyrdDiagnostic.W_SAVE_AI and str(item.message).contains(message):
			hits += 1
	return hits


func _runtime() -> WyrdRuntime:
	var body := """// [EXAMPLE CONTENT]
language 1

facts
  player.coins : int stored
"""
	var path := "user://wyrd_m10_cache.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(body)
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = "m10cache"
	manifest.files = PackedStringArray([path])
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(1)
	runtime.trace.enabled = true
	return runtime


func _provider(text: String, ok: bool) -> WyrdFakeAIText:
	var provider := WyrdFakeAIText.new()
	provider.text = text
	provider.ok = ok
	return provider


func _rows(runtime: WyrdRuntime, kind: String) -> Array:
	var rows: Array = []
	for event in runtime.trace.events:
		if str(event.get("kind", "")) == kind:
			rows.append(event)
	return rows
