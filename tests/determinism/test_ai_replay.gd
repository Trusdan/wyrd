extends GutTest

const _Harness := preload("res://tests/scenario/s2c_harness.gd")


func test_replay_shows_the_same_text() -> void:
	var recorded := _events(true)
	var again := _events(false, recorded)
	assert_eq(WyrdTrace.diff(recorded, again), PackedStringArray())
	var lines := _line_text(recorded)
	assert_eq(_line_text(again), lines)
	assert_eq(lines[0], "The lane is quiet.")
	assert_eq(lines[1], "The gate stays shut.")
	assert_true(_has(recorded, "ai_deliver"))
	var row: Dictionary = _first(recorded, "ai_deliver")
	assert_eq(int(row["id"]), 1)
	assert_eq(bool(row["ok"]), true)
	assert_eq(str(row["text"]), "The gate stays shut.")
	assert_eq(str(row["error"]), "")


func test_replay_without_deliveries_keeps_gameplay() -> void:
	var recorded := _events(true)
	var stripped: Array = []
	for row in recorded:
		if str(row.get("kind", "")) == "ai_deliver":
			continue
		stripped.append(row)
	assert_eq(_line_text(_events(false, stripped)), PackedStringArray(["The lane is quiet.", "The gate is shut."]))
	assert_eq(_save(true), _save(false, stripped))


func test_gullhaven_default_provider_logs_no_ai() -> void:
	var opened := _Harness.new().boot_gullhaven()
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.trace.enabled = true
	runtime.trace.clear()
	runtime.tick(1)
	runtime.dialogue.open_scene("toll.offer_room")
	runtime.dialogue.force_close()
	var hits := 0
	for row in runtime.trace.events:
		var kind := str(row.get("kind", ""))
		if kind.begins_with("ai_") or kind == "ai_deliver":
			hits += 1
	assert_eq(hits, 0)
	assert_false(runtime.save_state().has("ai"))


func _events(answer: bool, recorded: Array = []) -> Array:
	return _run(answer, true, recorded).trace.snapshot()


func _save(answer: bool, recorded: Array = []) -> String:
	var runtime := _run(answer, false, recorded)
	return JSON.stringify(runtime.save_state(), "", true)


func _run(answer: bool, keep_cache: bool, recorded: Array) -> WyrdRuntime:
	var runtime := _boot()
	runtime.config().ai_save_cache = keep_cache
	if answer:
		runtime.register_adapter(WyrdAIProvider, _Later.new())
	else:
		runtime.register_adapter(WyrdAIProvider, _Silent.new())
	runtime.trace.enabled = true
	runtime.trace.clear()
	if recorded.is_empty():
		runtime.dialogue.open_scene("gate")
		var provider := runtime.ai.provider() as _Later
		provider.answer(0, true, "The gate stays shut.")
		runtime.dialogue.advance()
		runtime.dialogue.advance()
	else:
		WyrdTrace.replay(runtime, recorded)
	return runtime


func _boot() -> WyrdRuntime:
	var path := "user://wyrd_m10_replay.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(_BODY)
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = "m10replay"
	manifest.files = PackedStringArray([path])
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	host.world.add_entity(&"player", &"person", "traveler", PackedStringArray(), true)
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(1)
	return runtime


func _line_text(events: Array) -> PackedStringArray:
	var lines := PackedStringArray()
	for row in events:
		if str(row.get("kind", "")) == "line":
			lines.append(str(row.get("text", "")))
	return lines


func _has(events: Array, kind: String) -> bool:
	return not _first(events, kind).is_empty()


func _first(events: Array, kind: String) -> Dictionary:
	for row in events:
		if str(row.get("kind", "")) == kind:
			return row
	return {}


class _Later extends WyrdAIProvider:
	var waiting: Array[WyrdAIRequest] = []

	func id() -> StringName:
		return &"replay-ai"

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
		return &"replay-ai"

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
  player.coins : int stored

scene gate
  narrator: The lane is quiet. #line:plain
  narrator: The gate is shut. #tag:ai #line:gate
  -> end
"""
