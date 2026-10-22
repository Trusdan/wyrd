extends GutTest

const _Harness := preload("res://tests/scenario/s2c_harness.gd")


func test_valid_text_traces_validate_after_result() -> void:
	var runtime := _runtime()
	var provider := _provider("The gate is shut tonight.", true, false)
	runtime.register_adapter(WyrdAIProvider, provider)
	var id := runtime.ai.request(&"bark_paraphrase", {"text": "The gate is shut."}, {}, &"toll.keeper")
	assert_gt(id, 0)
	var result := _rows(runtime, "ai_result")
	var check := _rows(runtime, "ai_validate")
	assert_eq(result.size(), 1)
	assert_eq(check.size(), 1)
	assert_eq(str(result[0]["rule"]), "-")
	assert_eq(str(result[0]["ok"]), "true")
	assert_eq(str(result[0]["slot_kind"]), "bark_paraphrase")
	assert_eq(str(result[0]["path"]), "toll.keeper")
	assert_eq(int(result[0]["id"]), id)
	assert_eq(str(check[0]["ok"]), "true")
	assert_eq(str(check[0]["rule"]), "-")
	assert_eq(str(check[0]["slot_kind"]), "bark_paraphrase")
	assert_eq(str(check[0]["path"]), "toll.keeper")
	assert_gt(_index(runtime, "ai_validate"), _index(runtime, "ai_result"))


func test_each_failure_rule() -> void:
	var runtime := _runtime()
	var provider := _provider("{", true, false)
	runtime.register_adapter(WyrdAIProvider, provider)
	runtime.ai.request(&"bark_paraphrase", {"text": "The gate is shut."}, {}, &"toll.keeper")
	assert_eq(str(_rows(runtime, "ai_result")[0]["rule"]), "-")
	assert_eq(str(_rows(runtime, "ai_validate")[0]["rule"]), "limits")
	assert_eq(str(_rows(runtime, "ai_validate")[0]["ok"]), "false")
	runtime.trace.clear()
	provider.text = "Bram waits here."
	runtime.ai.request(&"bark_paraphrase", {"entities": [], "text": "The gate is shut."}, {}, &"toll.keeper")
	assert_eq(str(_rows(runtime, "ai_validate")[0]["rule"]), "names")
	runtime.trace.clear()
	runtime.config().ai_banned_terms = PackedStringArray(["shed"])
	provider.text = "The shed is shut."
	runtime.ai.request(&"bark_paraphrase", {"text": "The gate is shut."}, {}, &"toll.keeper")
	assert_eq(str(_rows(runtime, "ai_validate")[0]["rule"]), "banned")
	runtime.config().ai_banned_terms = PackedStringArray()
	runtime.facts.set_in(&"harbor.toll_fate", "hidden_bell", &"world")
	runtime.trace.clear()
	provider.text = "a hidden_bell sits."
	runtime.ai.request(&"gossip", {"facts": {}, "text": "The gate is shut."}, {}, &"toll.keeper")
	assert_eq(str(_rows(runtime, "ai_validate")[0]["rule"]), "spoiler")
	runtime.trace.clear()
	provider.text = "The gate is shut tonight."
	runtime.ai.register_classifier(Callable(self, &"_reject"))
	runtime.ai.request(&"bark_paraphrase", {"text": "The gate is shut."}, {}, &"toll.keeper")
	assert_eq(str(_rows(runtime, "ai_validate")[0]["rule"]), "classifier")


func test_provider_error_skips_the_five_rules() -> void:
	var runtime := _runtime()
	var provider := _provider("The gate is shut tonight.", false, false)
	runtime.register_adapter(WyrdAIProvider, provider)
	runtime.ai.request(&"bark_paraphrase", {"text": "The gate is shut."}, {}, &"toll.keeper")
	assert_eq(str(_rows(runtime, "ai_result")[0]["ok"]), "false")
	assert_eq(str(_rows(runtime, "ai_result")[0]["rule"]), "-")
	assert_eq(str(_rows(runtime, "ai_validate")[0]["rule"]), "provider")
	assert_eq(str(_rows(runtime, "ai_validate")[0]["ok"]), "false")


func test_off_thread_and_unknown_skip_validate() -> void:
	var runtime := _runtime()
	var provider := _provider("nope", true, true)
	runtime.register_adapter(WyrdAIProvider, provider)
	var id := runtime.ai.request(&"gossip", {"text": "hear"}, {}, &"toll.keeper")
	var worker := Thread.new()
	var box := {"returned": true}
	worker.start(func() -> void:
		box["returned"] = runtime.ai.deliver(id, _result(true, "nope"))
	)
	worker.wait_to_finish()
	assert_false(bool(box["returned"]))
	assert_push_error("main thread")
	assert_eq(_rows(runtime, "ai_validate").size(), 0)
	assert_eq(str(_rows(runtime, "ai_result")[0]["rule"]), "thread")
	runtime.trace.clear()
	assert_false(runtime.ai.deliver(404, _result(true, "missing")))
	assert_eq(_rows(runtime, "ai_validate").size(), 0)
	assert_eq(str(_rows(runtime, "ai_result")[0]["rule"]), "unknown_request")


func test_classifier_traces_and_survives_new_game_and_load() -> void:
	var harness := _Harness.new()
	var runtime: WyrdRuntime = harness.open_pack(_Harness.SAMPLE)["runtime"]
	runtime.start_new_game(3)
	var plain := JSON.stringify(runtime.save_state(), "", true)
	runtime.trace.enabled = true
	runtime.ai.register_classifier(Callable(self, &"_reject"))
	assert_eq(str(_rows(runtime, "ai_classifier")[0]["state"]), "set")
	runtime.ai.register_classifier(Callable())
	assert_eq(str(_rows(runtime, "ai_classifier")[1]["state"]), "clear")
	runtime.ai.register_classifier(Callable(self, &"_reject"))
	assert_eq(JSON.stringify(runtime.save_state(), "", true), plain)
	var provider := _provider("The gate is shut tonight.", true, false)
	runtime.register_adapter(WyrdAIProvider, provider)
	runtime.trace.clear()
	runtime.ai.request(&"bark_paraphrase", {"text": "The gate is shut."}, {}, &"dock.line")
	assert_eq(str(_rows(runtime, "ai_validate")[0]["rule"]), "classifier")
	assert_eq(JSON.stringify(runtime.save_state(), "", true), plain)
	runtime.trace.clear()
	runtime.start_new_game(3)
	runtime.trace.enabled = true
	runtime.register_adapter(WyrdAIProvider, _provider("The gate is shut tonight.", true, false))
	runtime.ai.request(&"bark_paraphrase", {"text": "The gate is shut."}, {}, &"dock.line")
	assert_eq(str(_rows(runtime, "ai_validate")[0]["rule"]), "classifier")
	var saved := runtime.save_state()
	runtime.trace.clear()
	var loaded := runtime.load_state(saved)
	assert_true(loaded.ok, loaded.diagnostics.format())
	runtime.trace.enabled = true
	runtime.register_adapter(WyrdAIProvider, _provider("The gate is shut tonight.", true, false))
	runtime.ai.request(&"bark_paraphrase", {"text": "The gate is shut."}, {}, &"dock.line")
	assert_eq(str(_rows(runtime, "ai_validate")[0]["rule"]), "classifier")
	assert_eq(JSON.stringify(runtime.save_state(), "", true), JSON.stringify(saved, "", true))


func test_banned_terms_come_from_config() -> void:
	var runtime := _runtime()
	runtime.config().ai_banned_terms = PackedStringArray(["shed"])
	var provider := _provider("The shed is shut.", true, false)
	runtime.register_adapter(WyrdAIProvider, provider)
	runtime.ai.request(&"bark_paraphrase", {"text": "The gate is shut."}, {}, &"toll.keeper")
	assert_eq(str(_rows(runtime, "ai_validate")[0]["rule"]), "banned")
	runtime.config().ai_banned_terms = PackedStringArray()
	runtime.trace.clear()
	provider.text = "The shed is shut."
	runtime.ai.request(&"bark_paraphrase", {"text": "The gate is shut."}, {}, &"toll.keeper")
	assert_eq(str(_rows(runtime, "ai_validate")[0]["rule"]), "-")


func test_gullhaven_trace_has_no_ai_lines() -> void:
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


func _reject(_text: String, _kind: StringName, _packet: Dictionary) -> bool:
	return false


func _runtime() -> WyrdRuntime:
	var body := """// [EXAMPLE CONTENT]
language 1

facts
  harbor.toll_fate : symbol stored
  player.coins : int stored
"""
	var path := "user://wyrd_m10_deliver.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(body)
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = "m10deliver"
	manifest.files = PackedStringArray([path])
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	host.world.add_entity(&"ferry_master", &"person", "Bram", PackedStringArray(), true)
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(1)
	runtime.trace.enabled = true
	return runtime


func _provider(text: String, ok: bool, hold: bool) -> WyrdFakeAIText:
	var provider := WyrdFakeAIText.new()
	provider.text = text
	provider.ok = ok
	provider.hold = hold
	return provider


func _result(ok: bool, text: String) -> WyrdAIResult:
	var result := WyrdAIResult.new()
	result.ok = ok
	result.text = text
	return result


func _rows(runtime: WyrdRuntime, kind: String) -> Array:
	var rows: Array = []
	for event in runtime.trace.events:
		if str(event.get("kind", "")) == kind:
			rows.append(event)
	return rows


func _index(runtime: WyrdRuntime, kind: String) -> int:
	var at := -1
	var i := 0
	for event in runtime.trace.events:
		if str(event.get("kind", "")) == kind:
			at = i
		i += 1
	return at
