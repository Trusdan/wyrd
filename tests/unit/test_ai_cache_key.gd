extends GutTest

## Cache key stability and the [code]key=[/code] field on existing AI trace lines.


func test_key_is_stable_and_changes_with_inputs() -> void:
	var left := _runtime("fixed-text", 1)
	var right := _runtime("fixed-text", 1)
	var packet := {"text": "The gate is shut.", "v": 1}
	var kind := &"bark_paraphrase"
	var first := left.ai.cache_key(kind, packet, &"en")
	assert_eq(first.length(), 16)
	assert_eq(first, first.to_lower())
	assert_eq(first, left.ai.cache_key(kind, packet, &"en"))
	assert_eq(first, right.ai.cache_key(kind, packet, &"en"))
	assert_ne(first, left.ai.cache_key(&"gossip", packet, &"en"))
	assert_ne(first, left.ai.cache_key(kind, {"text": "The lane is quiet.", "v": 1}, &"en"))
	assert_ne(first, _runtime("other-text", 1).ai.cache_key(kind, packet, &"en"))
	assert_ne(first, _runtime("fixed-text", 2).ai.cache_key(kind, packet, &"en"))
	assert_ne(first, left.ai.cache_key(kind, packet, &"fr"))
	var previous := TranslationServer.get_locale()
	TranslationServer.set_locale("fr")
	var from_server := left.ai.cache_key(kind, packet)
	TranslationServer.set_locale(previous)
	assert_eq(from_server, left.ai.cache_key(kind, packet, &"fr"))


func test_constraints_and_insertion_order_do_not_change_the_key() -> void:
	var runtime := _runtime("fixed-text", 1)
	var kind := &"bark_paraphrase"
	var forward := {"b": 1, "a": {"z": true, "y": "no"}}
	var backward := {"a": {"y": "no", "z": true}, "b": 1}
	assert_eq(runtime.ai.cache_key(kind, forward, &"en"), runtime.ai.cache_key(kind, backward, &"en"))
	var provider: _Hold = runtime.ai.provider()
	var id := runtime.ai.request(kind, forward, {"max_chars": 40}, &"toll.keeper")
	var again := runtime.ai.request(kind, backward, {"note": "other"}, &"toll.keeper")
	assert_gt(id, 0)
	assert_gt(again, 0)
	assert_eq(provider.waiting[0].key, provider.waiting[1].key)
	assert_eq(provider.waiting[0].key, runtime.ai.cache_key(kind, forward, provider.waiting[0].locale))


func test_sent_request_carries_the_key_and_refused_uses_dash() -> void:
	var runtime := _runtime("fixed-text", 1)
	runtime.trace.enabled = true
	var packet := {"text": "The gate is shut."}
	var id := runtime.ai.request(&"bark_paraphrase", packet, {}, &"toll.keeper")
	var provider: _Hold = runtime.ai.provider()
	var sent: Dictionary = _rows(runtime, "ai_request")[0]
	assert_eq(str(sent["state"]), "sent")
	assert_eq(str(sent["reason"]), "-")
	assert_eq(str(sent["slot_kind"]), "bark_paraphrase")
	assert_eq(str(sent["path"]), "toll.keeper")
	assert_eq(int(sent["id"]), id)
	assert_eq(str(sent["key"]), provider.waiting[0].key)
	assert_eq(provider.waiting[0].key, runtime.ai.cache_key(&"bark_paraphrase", packet, provider.waiting[0].locale))
	runtime.trace.clear()
	assert_eq(runtime.ai.request(&"not_a_kind", packet), 0)
	assert_push_warning("unknown kind")
	assert_eq(str(_rows(runtime, "ai_request")[0]["key"]), "-")
	assert_eq(str(_rows(runtime, "ai_request")[0]["reason"]), "kind")
	runtime.ai.set_enabled(false)
	runtime.trace.clear()
	assert_eq(runtime.ai.request(&"gossip", packet), 0)
	assert_eq(str(_rows(runtime, "ai_request")[0]["key"]), "-")
	assert_eq(str(_rows(runtime, "ai_request")[0]["state"]), "refused")


func test_result_validate_and_cancel_rows_carry_the_key() -> void:
	var runtime := _runtime("fixed-text", 1)
	runtime.trace.enabled = true
	var packet := {"text": "The gate is shut."}
	var id := runtime.ai.request(&"bark_paraphrase", packet, {}, &"toll.keeper")
	var provider: _Hold = runtime.ai.provider()
	var key := provider.waiting[0].key
	assert_true(runtime.ai.cancel(id))
	var cancelled: Dictionary = _rows(runtime, "ai_cancel")[0]
	assert_eq(str(cancelled["reason"]), "host")
	assert_eq(str(cancelled["slot_kind"]), "bark_paraphrase")
	assert_eq(str(cancelled["path"]), "toll.keeper")
	assert_eq(int(cancelled["id"]), id)
	assert_eq(str(cancelled["key"]), key)
	provider.waiting.clear()
	runtime.trace.clear()
	id = runtime.ai.request(&"bark_paraphrase", packet, {}, &"toll.keeper")
	key = provider.waiting[0].key
	assert_true(provider.answer("The gate is shut tonight.", true))
	var result: Dictionary = _rows(runtime, "ai_result")[0]
	assert_eq(str(result["rule"]), "-")
	assert_eq(str(result["ok"]), "true")
	assert_eq(str(result["slot_kind"]), "bark_paraphrase")
	assert_eq(str(result["path"]), "toll.keeper")
	assert_eq(int(result["id"]), id)
	assert_eq(str(result["key"]), key)
	var check: Dictionary = _rows(runtime, "ai_validate")[0]
	assert_eq(str(check["rule"]), "-")
	assert_eq(str(check["ok"]), "true")
	assert_eq(str(check["key"]), key)
	assert_gt(_index(runtime, "ai_validate"), _index(runtime, "ai_result"))
	runtime.trace.clear()
	assert_false(runtime.ai.deliver(404, _result(true, "missing")))
	var unknown: Dictionary = _rows(runtime, "ai_result")[0]
	assert_eq(str(unknown["rule"]), "unknown_request")
	assert_eq(str(unknown["key"]), "-")
	assert_eq(_rows(runtime, "ai_validate").size(), 0)


class _Hold extends WyrdAIProvider:
	var provider_id: StringName = &"fixed-text"
	var version: int = 1
	var waiting: Array[WyrdAIRequest] = []

	func id() -> StringName:
		return provider_id

	func prompt_version() -> int:
		return version

	func locales() -> PackedStringArray:
		return PackedStringArray(["en"])

	func request(req: WyrdAIRequest) -> void:
		waiting.append(req)

	func cancel(_request_id: int) -> void:
		pass

	func answer(text: String, ok: bool) -> bool:
		var req := waiting.pop_front() as WyrdAIRequest
		var result := WyrdAIResult.new()
		result.ok = ok
		result.text = text
		return req.reply(result)


func _runtime(provider_id: String, version: int) -> WyrdRuntime:
	var runtime := WyrdRuntime.new()
	var provider := _Hold.new()
	provider.provider_id = StringName(provider_id)
	provider.version = version
	runtime.register_adapter(WyrdAIProvider, provider)
	return runtime


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
