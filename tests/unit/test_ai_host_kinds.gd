extends GutTest

## Host-called kinds, and an opted-in line on a generated instance.


func test_host_text_reads_cached_epilogue_and_tts() -> void:
	var runtime := _boot(_TINY)
	var provider := _Hold.new()
	runtime.register_adapter(WyrdAIProvider, provider)
	var epilogue := {"entities": [], "kind": "epilogue_stitch", "line_ids": [], "text": "The harbor slept.", "v": 1}
	var speech := {"entities": [], "kind": "tts_prep", "line_ids": [], "text": "The harbor slept.", "v": 1}
	assert_eq(runtime.ai.host_text(&"epilogue_stitch", epilogue, "fallback"), "fallback")
	var epilogue_id := runtime.ai.request(&"epilogue_stitch", epilogue, {}, &"end")
	var speech_id := runtime.ai.request(&"tts_prep", speech, {}, &"voice")
	assert_gt(epilogue_id, 0)
	assert_gt(speech_id, 0)
	assert_true(provider.answer(0, true, "The harbor slept."))
	assert_true(provider.answer(1, true, "The harbor slept."))
	assert_eq(runtime.ai.validate("The harbor slept.", &"epilogue_stitch", epilogue), &"")
	assert_eq(runtime.ai.validate("The harbor slept.", &"tts_prep", speech), &"")
	assert_eq(runtime.ai.host_text(&"epilogue_stitch", epilogue, "fallback"), "The harbor slept.")
	assert_eq(runtime.ai.host_text(&"tts_prep", speech, "fallback"), "The harbor slept.")
	assert_eq(runtime.ai.host_text(&"epilogue_stitch", {"text": "Other.", "v": 1}, "fallback"), "fallback")
	runtime.ai.set_enabled(false)
	assert_eq(runtime.ai.host_text(&"epilogue_stitch", epilogue, "fallback"), "fallback")
	runtime.ai.set_enabled(true)
	var french := _Hold.new()
	french.locale_name = "fr"
	runtime.register_adapter(WyrdAIProvider, french)
	assert_eq(runtime.ai.host_text(&"epilogue_stitch", epilogue, "fallback"), "fallback")


func test_ai_host_request_is_recorded_for_sent_and_refused_calls() -> void:
	var runtime := _boot(_TINY)
	runtime.trace.clear()
	assert_eq(runtime.ai.request(&"epilogue_stitch", {"text": "The harbor slept."}, {"max_chars": 40}, &"end"), 0)
	var refused: Dictionary = _rows(runtime, "ai_host_request")[0]
	assert_eq(str(refused["kind"]), "ai_host_request")
	assert_eq(str(refused["slot_kind"]), "epilogue_stitch")
	assert_eq(str(refused["path"]), "end")
	assert_eq(int((refused["constraints"] as Dictionary)["max_chars"]), 40)
	assert_eq(str((refused["packet"] as Dictionary)["text"]), "The harbor slept.")
	var provider := _Hold.new()
	runtime.register_adapter(WyrdAIProvider, provider)
	runtime.trace.clear()
	var sent := runtime.ai.request(&"tts_prep", {"text": "The harbor slept."}, {}, &"voice")
	assert_gt(sent, 0)
	var row: Dictionary = _rows(runtime, "ai_host_request")[0]
	assert_eq(str(row["slot_kind"]), "tts_prep")
	assert_eq(str(row["path"]), "voice")
	runtime.ai.set_enabled(false)
	runtime.trace.clear()
	assert_eq(runtime.ai.request(&"tts_prep", {"text": "x"}, {}, &"voice"), 0)
	assert_eq(str(_rows(runtime, "ai_host_request")[0]["slot_kind"]), "tts_prep")
	runtime.ai.set_enabled(true)
	runtime.trace.clear()
	assert_eq(runtime.ai.request(&"poem", {"text": "x"}, {}, &"bad"), 0)
	assert_eq(str(_rows(runtime, "ai_host_request")[0]["slot_kind"]), "poem")
	assert_eq(_rows(runtime, "ai_request")[0]["reason"], "kind")


func test_template_instances_prefetch_and_present_separately() -> void:
	var runtime := _boot(_TEMPLATE)
	var provider := _Cast.new()
	runtime.register_adapter(WyrdAIProvider, provider)
	var first := runtime.quests.create_instance("errand", {"courier": "ada"})
	var second := runtime.quests.create_instance("errand", {"courier": "bram"})
	assert_eq(first, "errand#1")
	assert_eq(second, "errand#2")
	runtime.trace.clear()
	runtime.dialogue.open_scene("gate")
	var ada := runtime.dialogue.line()
	assert_eq(ada.text, "The gate stays shut.")
	assert_eq(str(ada.text_source), "ai")
	assert_eq(provider.waiting[0].packet["speaker"]["id"], "ada")
	runtime.dialogue.advance()
	assert_false(runtime.dialogue.is_open())
	runtime.dialogue.open_scene("gate")
	var bram := runtime.dialogue.line()
	assert_eq(bram.text, "The gate stays shut!")
	assert_eq(str(bram.text_source), "ai")
	assert_eq(provider.waiting[1].packet["speaker"]["id"], "bram")
	assert_ne(provider.waiting[0].key, provider.waiting[1].key)
	assert_eq(str(_rows(runtime, "ai_request")[0]["slot_kind"]), "bark_paraphrase")
	assert_eq(str(_rows(runtime, "ai_request")[1]["slot_kind"]), "bark_paraphrase")


func _boot(body: String) -> WyrdRuntime:
	var path := "user://wyrd_m10_host_kinds.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(body)
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = "m10hostkinds"
	manifest.files = PackedStringArray([path])
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	host.world.add_entity(&"player", &"person", "Traveler", PackedStringArray(), true)
	host.world.add_entity(&"ada", &"person", "Ada", PackedStringArray(), true)
	host.world.add_entity(&"bram", &"person", "Bram", PackedStringArray(), true)
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(1)
	runtime.trace.enabled = true
	return runtime


func _rows(runtime: WyrdRuntime, kind: String) -> Array:
	var rows: Array = []
	for event in runtime.trace.events:
		if str(event.get("kind", "")) == kind:
			rows.append(event)
	return rows


class _Hold extends WyrdAIProvider:
	var locale_name: String = "en"
	var waiting: Array[WyrdAIRequest] = []

	func id() -> StringName:
		return &"host-kinds"

	func prompt_version() -> int:
		return 1

	func locales() -> PackedStringArray:
		return PackedStringArray([locale_name])

	func request(req: WyrdAIRequest) -> void:
		waiting.append(req)

	func cancel(_request_id: int) -> void:
		pass

	func answer(index: int, ok: bool, text: String) -> bool:
		var result := WyrdAIResult.new()
		result.ok = ok
		result.text = text
		return waiting[index].reply(result)


class _Cast extends WyrdAIProvider:
	var waiting: Array[WyrdAIRequest] = []

	func id() -> StringName:
		return &"host-cast"

	func prompt_version() -> int:
		return 1

	func locales() -> PackedStringArray:
		return PackedStringArray(["en"])

	func request(req: WyrdAIRequest) -> void:
		waiting.append(req)
		var speaker := ""
		var block: Variant = req.packet.get("speaker", {})
		if block is Dictionary:
			speaker = str((block as Dictionary).get("id", ""))
		var result := WyrdAIResult.new()
		result.ok = true
		result.text = "The gate stays shut." if speaker == "ada" else "The gate stays shut!"
		req.reply(result)

	func cancel(_request_id: int) -> void:
		pass


const _TINY := """// [EXAMPLE CONTENT]
language 1

scene gate
  narrator: Hello. #line:hi
  -> end
"""


const _TEMPLATE := """// [EXAMPLE CONTENT]
language 1

role messenger
  succession: none
  vacancy: hold

template errand "Errand"
  slot courier = messenger mode: cast(true)
  stage work
    scene gate with courier
    waits_until false

scene gate
  courier: The gate is shut. #tag:ai #line:gate
  -> end
"""
