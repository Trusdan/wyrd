extends GutTest


func test_replay_shows_the_same_bark() -> void:
	var recorded_runtime := _boot(true)
	var recorded := recorded_runtime.trace.snapshot()
	var again_runtime := _boot(false)
	WyrdTrace.replay(again_runtime, recorded)
	assert_eq(WyrdTrace.diff(recorded, again_runtime.trace.snapshot()), PackedStringArray())
	var first := _bark(recorded_runtime)
	var second := _bark(again_runtime)
	assert_eq(second.text, first.text)
	assert_eq(second.text, "The gate stays shut.")
	assert_eq(str(second.text_source), "ai")
	var row: Dictionary = _first(recorded, "ai_deliver")
	assert_eq(int(row["id"]), 1)
	assert_eq(bool(row["ok"]), true)
	assert_eq(str(row["text"]), "The gate stays shut.")
	assert_eq(str(row["error"]), "")


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
	var authored := _bark(again)
	assert_eq(authored.text, "The gate is shut.")
	assert_eq(str(authored.text_source), "authored")


func _bark(runtime: WyrdRuntime) -> WyrdLineView:
	var heard: Array = []
	runtime.bark_ready.connect(func(line): heard.append(line))
	runtime.director.query("bark", "", "ferry_master")
	assert_eq(heard.size(), 1)
	return heard[0]


func _boot(answer: bool) -> WyrdRuntime:
	var path := "user://wyrd_m10_bark_replay.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(_BODY)
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = "m10barkreplay"
	manifest.files = PackedStringArray([path])
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	host.world.add_entity(&"player", &"person", "traveler", PackedStringArray(), true)
	host.world.add_entity(&"ferry_master", &"person", "Bram", PackedStringArray(), true)
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(1)
	if answer:
		runtime.register_adapter(WyrdAIProvider, _Later.new())
	else:
		runtime.register_adapter(WyrdAIProvider, _Silent.new())
	runtime.trace.enabled = true
	runtime.trace.clear()
	if answer:
		runtime.tick(0)
		var provider := runtime.ai.provider() as _Later
		provider.answer(0, true, "The gate stays shut.")
	return runtime


func _first(events: Array, kind: String) -> Dictionary:
	for row in events:
		if str(row.get("kind", "")) == kind:
			return row
	return {}


class _Later extends WyrdAIProvider:
	var waiting: Array[WyrdAIRequest] = []

	func id() -> StringName:
		return &"bark-replay"

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
		return &"bark-replay"

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

storylet gate.bell
  scope: bark
  speaker: ferry_master
  - The gate is shut. #tag:ai #line:gate_bark
"""
