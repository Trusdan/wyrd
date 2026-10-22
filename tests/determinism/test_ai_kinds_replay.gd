extends GutTest


func test_replay_keeps_request_ids_and_shown_text() -> void:
	var recorded_runtime := _boot(true)
	var recorded := recorded_runtime.trace.snapshot()
	var again_runtime := _boot(false)
	WyrdTrace.replay(again_runtime, recorded)
	assert_eq(WyrdTrace.diff(recorded, again_runtime.trace.snapshot()), PackedStringArray())
	assert_eq(_deliver_ids(recorded), [1, 2, 3])
	assert_eq(_deliver_ids(again_runtime.trace.snapshot()), [1, 2, 3])
	assert_eq(recorded_runtime.quests.summary("toll"), "Noted.")
	assert_eq(again_runtime.quests.summary("toll"), "Noted.")
	var first := _present(recorded_runtime)
	var second := _present(again_runtime)
	assert_eq(first.text, "The gate stays shut.")
	assert_eq(second.text, first.text)
	assert_eq(str(first.text_source), "ai")
	assert_eq(str(second.text_source), "ai")


func test_replay_without_deliveries_keeps_gameplay() -> void:
	var recorded_runtime := _boot(true)
	var recorded := recorded_runtime.trace.snapshot()
	var stripped: Array = []
	for row in recorded:
		if str(row.get("kind", "")) == "ai_deliver":
			continue
		stripped.append(row)
	var again := _boot(false)
	WyrdTrace.replay(again, stripped)
	recorded_runtime.config().ai_save_cache = false
	again.config().ai_save_cache = false
	assert_eq(JSON.stringify(again.save_state(), "", true), JSON.stringify(recorded_runtime.save_state(), "", true))
	assert_eq(again.quests.summary("toll"), "Bram shut the gate.")
	var authored := _present(again)
	assert_eq(authored.text, "The gate is shut.")
	assert_eq(str(authored.text_source), "authored")


func _present(runtime: WyrdRuntime) -> WyrdLineView:
	var view := WyrdLineView.new()
	view.id = "rumor"
	view.text = "The gate is shut."
	view.speaker = &"narrator"
	runtime.ai.present(view, "rumor")
	return view


func _deliver_ids(events: Array) -> Array:
	var ids: Array = []
	for row in events:
		if str(row.get("kind", "")) == "ai_deliver":
			ids.append(int(row.get("id", 0)))
	return ids


func _boot(answer: bool) -> WyrdRuntime:
	var path := "user://wyrd_m10_kinds_replay.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(_BODY)
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = "m10kindsreplay"
	manifest.files = PackedStringArray([path])
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	host.world.add_entity(&"player", &"person", "Traveler", PackedStringArray(), true)
	host.world.add_entity(&"bram", &"person", "Bram", PackedStringArray(), true)
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(1)
	runtime.tick(0)
	if answer:
		runtime.register_adapter(WyrdAIProvider, _Later.new())
	else:
		runtime.register_adapter(WyrdAIProvider, _Silent.new())
	runtime.trace.enabled = true
	runtime.trace.clear()
	if answer:
		runtime.dialogue.open_scene("rumor")
		runtime.dialogue.advance()
		runtime.ai.request(&"epilogue_stitch", _host_packet(), {}, &"end")
		runtime.quests.summary("toll")
		runtime.quests.summary("toll")
		var provider := runtime.ai.provider() as _Later
		provider.answer(0, true, "The gate stays shut.")
		provider.answer(1, true, "The harbor slept.")
		provider.answer(2, true, "Noted.")
	return runtime


func _host_packet() -> Dictionary:
	return {
		"entities": [],
		"facts": {},
		"kind": "epilogue_stitch",
		"line_ids": [],
		"text": "The harbor slept.",
		"v": 1,
	}


class _Later extends WyrdAIProvider:
	var waiting: Array[WyrdAIRequest] = []

	func id() -> StringName:
		return &"kinds-replay"

	func prompt_version() -> int:
		return 1

	func locales() -> PackedStringArray:
		return PackedStringArray(["en"])

	func request(req: WyrdAIRequest) -> void:
		waiting.append(req)

	func cancel(_request_id: int) -> void:
		pass

	func answer(index: int, ok: bool, text: String) -> bool:
		var result := WyrdAIResult.new()
		result.ok = ok
		result.text = text
		return waiting[index].reply(result)


class _Silent extends WyrdAIProvider:
	func id() -> StringName:
		return &"kinds-replay"

	func prompt_version() -> int:
		return 1

	func locales() -> PackedStringArray:
		return PackedStringArray(["en"])

	func request(_req: WyrdAIRequest) -> void:
		pass

	func cancel(_request_id: int) -> void:
		pass


const _BODY := """// [EXAMPLE CONTENT]
language 1

facts
  player.clearance : symbol stored

quest toll "The Toll"
  start when true
  stage one
    journal: Bram shut the gate. #line:j1
    waits_until false

scene rumor
  narrator: The gate is shut. #tag:ai #tag:gossip #line:rumor
  -> end
"""
