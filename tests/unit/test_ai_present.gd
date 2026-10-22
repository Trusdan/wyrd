extends GutTest

## Opted-in lines show cached text. A plain line stays authored.


func test_hit_replaces_text_only() -> void:
	var plain := _show(_provider("en", true), false)
	var hit := _show(_provider("en", false), true)
	assert_eq(hit["gate"].text, "The gate is shut.!")
	assert_eq(str(hit["gate"].text_source), "ai")
	assert_eq(str(_use(hit["runtime"], "gate")["reason"]), "hit")
	assert_eq(str(_use(hit["runtime"], "gate")["source"]), "ai")
	assert_eq(hit["gate"].id, plain["gate"].id)
	assert_eq(hit["gate"].tags, plain["gate"].tags)
	assert_eq(hit["gate"].audio, plain["gate"].audio)
	assert_eq(hit["gate"].speaker, plain["gate"].speaker)
	assert_eq(hit["plain"].text, plain["plain"].text)
	assert_eq(str(hit["plain"].text_source), "authored")
	assert_eq(_uses(hit["runtime"], "plain").size(), 0)
	assert_eq(hit["choices"], plain["choices"])


func test_miss_when_prefetch_is_off() -> void:
	var runtime := _boot()
	runtime.config().ai_max_inflight = 0
	runtime.register_adapter(WyrdAIProvider, _provider("en", true))
	runtime.trace.clear()
	runtime.dialogue.open_scene("gate")
	var view := runtime.dialogue.line()
	assert_eq(view.text, "The gate is shut.")
	assert_eq(str(view.text_source), "authored")
	assert_eq(str(_use(runtime, "gate")["reason"]), "miss")
	assert_eq(_rows(runtime, "ai_prefetch").size(), 0)
	assert_eq(runtime.ai.pending_count(), 0)


func test_waiting_while_unanswered() -> void:
	var runtime := _boot()
	var provider := _provider("en", true)
	runtime.register_adapter(WyrdAIProvider, provider)
	runtime.trace.clear()
	runtime.dialogue.open_scene("gate")
	var view := runtime.dialogue.line()
	assert_eq(view.text, "The gate is shut.")
	assert_eq(str(view.text_source), "authored")
	assert_eq(str(_use(runtime, "gate")["reason"]), "waiting")
	assert_eq(str(_use(runtime, "gate")["key"]), provider.waiting[0].key)
	assert_gt(provider.calls, 0)


func test_rejected_then_a_later_hit() -> void:
	var runtime := _boot()
	var provider := _provider("en", false)
	provider.bad = true
	runtime.register_adapter(WyrdAIProvider, provider)
	runtime.trace.clear()
	runtime.dialogue.open_scene("gate")
	var view := runtime.dialogue.line()
	assert_eq(view.text, "The gate is shut.")
	assert_eq(str(view.text_source), "authored")
	assert_eq(str(_use(runtime, "gate")["reason"]), "rejected")
	provider.bad = false
	var packet := runtime.ai.packet_for_line("gate", &"bark_paraphrase", &"")
	runtime.ai.request(&"bark_paraphrase", packet, {}, &"gate")
	var again := WyrdLineView.new()
	again.id = "gate"
	again.speaker = &"narrator"
	again.text = "The gate is shut."
	runtime.trace.clear()
	runtime.ai.present(again, "gate")
	assert_eq(again.text, "The gate is shut.!")
	assert_eq(str(again.text_source), "ai")
	assert_eq(str(_use(runtime, "gate")["reason"]), "hit")
	assert_eq(view.text, "The gate is shut.")


func test_off_and_null_stay_authored() -> void:
	var runtime := _boot()
	runtime.ai.set_enabled(false)
	runtime.trace.clear()
	runtime.dialogue.open_scene("gate")
	assert_eq(str(runtime.dialogue.line().text_source), "authored")
	assert_eq(str(_use(runtime, "gate")["reason"]), "off")
	assert_eq(str(_use(runtime, "gate")["key"]), "-")
	assert_eq(_rows(runtime, "ai_prefetch").size(), 0)
	assert_eq(runtime.ai.pending_count(), 0)
	var quiet := _boot()
	quiet.trace.clear()
	quiet.dialogue.open_scene("gate")
	assert_eq(str(quiet.dialogue.line().text_source), "authored")
	assert_eq(str(_use(quiet, "gate")["reason"]), "off")
	assert_eq(_rows(quiet, "ai_prefetch").size(), 0)
	assert_eq(_rows(quiet, "ai_request").size(), 0)


func test_locale_gate_and_language_part() -> void:
	var runtime := _boot()
	runtime.register_adapter(WyrdAIProvider, _provider("de", true))
	runtime.trace.clear()
	runtime.dialogue.open_scene("gate")
	assert_eq(str(runtime.dialogue.line().text_source), "authored")
	assert_eq(str(_use(runtime, "gate")["reason"]), "locale")
	assert_eq(str(_use(runtime, "gate")["key"]), "-")
	var prefetch: Dictionary = _rows(runtime, "ai_prefetch")[0]
	assert_eq(int(prefetch["locale"]), int(prefetch["lines"]))
	assert_eq(int(prefetch["sent"]), 0)
	var previous := TranslationServer.get_locale()
	TranslationServer.set_locale("en_US")
	var wider := _boot()
	wider.register_adapter(WyrdAIProvider, _provider("en", true))
	wider.trace.clear()
	wider.dialogue.open_scene("gate")
	TranslationServer.set_locale(previous)
	assert_eq(str(_use(wider, "gate")["reason"]), "waiting")
	assert_eq(int(_rows(wider, "ai_prefetch")[0]["locale"]), 0)
	assert_eq(int(_rows(wider, "ai_prefetch")[0]["sent"]), 1)


func test_topic_and_bark_hit_and_miss() -> void:
	var hit := _boot()
	hit.register_adapter(WyrdAIProvider, _provider("en", false))
	hit.topics.unlock(&"harbor_toll")
	hit.trace.clear()
	var topics: Array = []
	hit.dialogue.topic_answered.connect(func(_npc, _topic, line): topics.append(line))
	assert_eq(hit.dialogue.open("ferry_master"), PackedStringArray(["harbor_toll"]))
	hit.dialogue.ask_topic("ferry_master", "harbor_toll")
	assert_eq(topics.size(), 1)
	assert_eq(topics[0].text, "The harbor has news.!")
	assert_eq(str(topics[0].text_source), "ai")
	assert_eq(str(_use(hit, "news")["reason"]), "hit")
	var missed := _boot()
	missed.config().ai_max_inflight = 0
	missed.register_adapter(WyrdAIProvider, _provider("en", true))
	missed.topics.unlock(&"harbor_toll")
	missed.trace.clear()
	var quiet: Array = []
	missed.dialogue.topic_answered.connect(func(_npc, _topic, line): quiet.append(line))
	missed.dialogue.open("ferry_master")
	missed.dialogue.ask_topic("ferry_master", "harbor_toll")
	assert_eq(quiet[0].text, "The harbor has news.")
	assert_eq(str(quiet[0].text_source), "authored")
	assert_eq(str(_use(missed, "news")["reason"]), "miss")
	var bark := _boot()
	var provider := _provider("en", false)
	bark.register_adapter(WyrdAIProvider, provider)
	var packet := bark.ai.packet_for_line("bell", &"bark_paraphrase", &"ferry_master")
	bark.ai.request(&"bark_paraphrase", packet, {}, &"bell")
	bark.trace.clear()
	var heard: Array = []
	bark.bark_ready.connect(func(line): heard.append(line))
	var story := bark.content().storylets["harbor.bark"] as WyrdStoryletDef
	bark.present_bark(story, {"line_id": "bell"})
	assert_eq(heard.size(), 1)
	assert_eq(heard[0].text, "The bell is still.!")
	assert_eq(str(heard[0].text_source), "ai")
	assert_eq(str(_use(bark, "bell")["reason"]), "hit")
	var bare := _boot()
	bare.register_adapter(WyrdAIProvider, _provider("en", true))
	bare.trace.clear()
	var none: Array = []
	bare.bark_ready.connect(func(line): none.append(line))
	bare.present_bark(bare.content().storylets["harbor.bark"], {"line_id": "bell"})
	assert_eq(none[0].text, "The bell is still.")
	assert_eq(str(none[0].text_source), "authored")
	assert_eq(str(_use(bare, "bell")["reason"]), "miss")


func _show(provider: _Hold, answer: bool) -> Dictionary:
	var runtime := _boot()
	if not answer:
		runtime.ai.set_enabled(false)
	else:
		runtime.register_adapter(WyrdAIProvider, provider)
	runtime.trace.clear()
	runtime.dialogue.open_scene("gate")
	var gate := runtime.dialogue.line()
	runtime.dialogue.advance()
	var plain := runtime.dialogue.line()
	runtime.dialogue.advance()
	var choices: Array = []
	for view in runtime.dialogue.choices():
		choices.append({"enabled": view.enabled, "id": view.id, "text": view.text})
	return {"choices": choices, "gate": gate, "plain": plain, "runtime": runtime}


func _boot() -> WyrdRuntime:
	var path := "user://wyrd_m10_present.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(_BODY)
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = "m10present"
	manifest.files = PackedStringArray([path])
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	host.world.add_entity(&"player", &"person", "traveler", PackedStringArray(), true)
	host.world.add_entity(&"ferry_master", &"person", "Bram", PackedStringArray(), true)
	host.world.add_entity(&"tavern_owner", &"person", "Innkeeper", PackedStringArray(), true)
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(1)
	runtime.trace.enabled = true
	return runtime


func _provider(locale: String, hold: bool) -> _Hold:
	var provider := _Hold.new()
	provider.locale_name = locale
	provider.hold = hold
	return provider


func _use(runtime: WyrdRuntime, line_id: String) -> Dictionary:
	var rows := _uses(runtime, line_id)
	if rows.is_empty():
		return {}
	return rows[rows.size() - 1]


func _uses(runtime: WyrdRuntime, line_id: String) -> Array:
	var rows: Array = []
	for event in _rows(runtime, "ai_use"):
		if str(event.get("path", "")) == line_id:
			rows.append(event)
	return rows


func _rows(runtime: WyrdRuntime, kind: String) -> Array:
	var rows: Array = []
	for event in runtime.trace.events:
		if str(event.get("kind", "")) == kind:
			rows.append(event)
	return rows


class _Hold extends WyrdAIProvider:
	var locale_name: String = "en"
	var hold: bool = false
	var bad: bool = false
	var calls: int = 0
	var waiting: Array[WyrdAIRequest] = []

	func id() -> StringName:
		return &"present-text"

	func prompt_version() -> int:
		return 1

	func locales() -> PackedStringArray:
		return PackedStringArray([locale_name])

	func request(req: WyrdAIRequest) -> void:
		calls += 1
		waiting.append(req)
		if hold:
			return
		var result := WyrdAIResult.new()
		result.ok = true
		result.text = "{" if bad else str(req.packet.get("text", "")) + "!"
		req.reply(result)

	func cancel(_request_id: int) -> void:
		pass


const _BODY := """// [EXAMPLE CONTENT]
language 1

facts
  player.coins : int stored

scene gate
  narrator: The gate is shut. #tag:ai #tag:toll #line:gate
  narrator: The lane is quiet. #line:plain
  * [Leave] -> end #line:leave
  -> end

scene inner
  narrator: The bell is still. #line:inner
  -> end

storylet harbor.news
  scope: topic harbor_toll
  speaker: ferry_master
  - The harbor has news. #tag:ai #line:news

storylet harbor.bark
  scope: bark
  speaker: ferry_master
  - The bell is still. #tag:ai #line:bell
"""
