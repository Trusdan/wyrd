extends GutTest

const _Provider := preload("res://example/ai/wyrd_local_provider.gd")
const _Transport := preload("res://example/ai/wyrd_local_transport.gd")

var _servers: Array[WyrdFakeLocalServer] = []


func before_each() -> void:
	for _i in 3:
		await get_tree().process_frame


func after_each() -> void:
	for server in _servers:
		if is_instance_valid(server):
			server.stop()
	_servers.clear()


func test_replay_shows_the_cached_line_and_sends_nothing() -> void:
	var server := _listen()
	server.auto_text = "The gate stays shut."
	var recorded_runtime := _boot()
	_attach(recorded_runtime, server)
	recorded_runtime.trace.enabled = true
	recorded_runtime.trace.clear()
	recorded_runtime.dialogue.open_scene("gate")
	assert_true(await _until(func() -> bool: return _rows(recorded_runtime, "ai_result").size() >= 1, 2.0))
	recorded_runtime.dialogue.advance()
	recorded_runtime.dialogue.open_scene("gate")
	var shown: WyrdLineView = recorded_runtime.dialogue.line()
	assert_eq(shown.text, "The gate stays shut.")
	assert_eq(shown.text_source, &"ai")
	var seen := server.requests.size()
	assert_gt(seen, 0)
	var recorded: Array = []
	for row in recorded_runtime.trace.snapshot():
		if str(row.get("kind", "")) == "ai_local":
			continue
		recorded.append(row)
	var again := _boot()
	again.register_adapter(WyrdAIProvider, _Silent.new())
	again.trace.enabled = true
	again.trace.clear()
	WyrdTrace.replay(again, recorded)
	assert_eq(WyrdTrace.diff(recorded, again.trace.snapshot()), PackedStringArray())
	var replayed: WyrdLineView = again.dialogue.line()
	assert_eq(replayed.text, shown.text)
	assert_eq(replayed.text_source, &"ai")
	assert_eq(server.requests.size(), seen)


func _listen() -> WyrdFakeLocalServer:
	var server := WyrdFakeLocalServer.new()
	add_child_autofree(server)
	var port := server.start()
	assert_gt(port, 0)
	_servers.append(server)
	return server


func _attach(runtime: WyrdRuntime, server: WyrdFakeLocalServer) -> void:
	var transport = _Transport.new()
	add_child_autofree(transport)
	var provider = _Provider.new()
	provider.timeout_s = 0.5
	assert_true(provider.set_base_url("http://127.0.0.1:%d" % server.port))
	provider.attach(transport)
	provider.bind_trace(runtime)
	runtime.register_adapter(WyrdAIProvider, provider)


func _boot() -> WyrdRuntime:
	var path := "user://wyrd_m10_local_replay.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(_BODY)
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = "m10localreplay"
	manifest.files = PackedStringArray([path])
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	host.world.add_entity(&"player", &"person", "Traveler", PackedStringArray(), true)
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(1)
	runtime.tick(0)
	return runtime


func _rows(runtime: WyrdRuntime, kind: String) -> Array:
	var rows: Array = []
	for event in runtime.trace.events:
		if str(event.get("kind", "")) == kind:
			rows.append(event)
	return rows


func _until(done: Callable, seconds: float) -> bool:
	var start := Time.get_ticks_msec()
	while not bool(done.call()):
		if Time.get_ticks_msec() - start > int(seconds * 1000.0):
			return false
		await get_tree().process_frame
	return true


class _Silent extends WyrdAIProvider:
	func id() -> StringName:
		return &"local:smollm2-360m-instruct-q4_k_m"

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

scene gate
  narrator: The gate is shut. #tag:ai #line:gate
  -> end
"""
