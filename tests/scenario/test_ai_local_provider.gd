extends GutTest

const _Provider := preload("res://example/ai/wyrd_local_provider.gd")
const _Transport := preload("res://example/ai/wyrd_local_transport.gd")
const _Prompts := preload("res://example/ai/wyrd_local_prompts.gd")

var _servers: Array[WyrdFakeLocalServer] = []


func before_each() -> void:
	# The first idle frame after a cold start can be longer than timeout_s.
	for _i in 3:
		await get_tree().process_frame


func after_each() -> void:
	for server in _servers:
		if is_instance_valid(server):
			server.stop()
	_servers.clear()


func test_round_trip_caches_and_shows_the_answer() -> void:
	var server := _listen()
	server.auto_text = "The gate stays shut."
	var opened := _boot(false)
	var runtime: WyrdRuntime = opened["runtime"]
	var wired: Dictionary = _attach(runtime, server)
	runtime.trace.enabled = true
	runtime.dialogue.open_scene("gate")
	assert_true(await _until(func() -> bool: return server.requests.size() >= 1, 2.0), "no request")
	var seen: Dictionary = server.requests[0]
	assert_eq(str(seen["method"]), "POST")
	assert_eq(str(seen["path"]), "/v1/chat/completions")
	var headers: Dictionary = seen["headers"]
	assert_eq(str(headers.get("content-type", "")), "application/json")
	assert_eq(str(headers.get("accept", "")), "application/json")
	assert_false(headers.has("authorization"))
	assert_false(headers.has("x-api-key"))
	var sent: Dictionary = _rows(runtime, "ai_request")[0]
	var req := WyrdAIRequest.new()
	req.kind = &"bark_paraphrase"
	req.packet = runtime.ai.packet_for_line("gate", &"bark_paraphrase")
	req.key = str(sent["key"])
	var expected := JSON.stringify(_Prompts.body(req, str(wired["provider"].model)), "", true)
	assert_eq(str(seen["body"]), expected)
	assert_true(await _until(func() -> bool: return _rows(runtime, "ai_result").size() >= 1, 2.0), "no result")
	assert_eq(str(_rows(runtime, "ai_result")[0]["ok"]), "true")
	assert_eq(str(_rows(runtime, "ai_validate")[0]["rule"]), "-")
	assert_eq(runtime.ai.cached_text(str(sent["key"])), "The gate stays shut.")
	runtime.dialogue.advance()
	assert_false(runtime.dialogue.is_open())
	runtime.dialogue.open_scene("gate")
	var line: WyrdLineView = runtime.dialogue.line()
	assert_eq(line.text, "The gate stays shut.")
	assert_eq(line.text_source, &"ai")


func test_host_kind_round_trips_into_host_text() -> void:
	var server := _listen()
	server.auto_text = "The harbor slept."
	var runtime: WyrdRuntime = _boot(false)["runtime"]
	_attach(runtime, server)
	runtime.trace.enabled = true
	var packet := {
		"entities": [],
		"facts": {},
		"kind": "tts_prep",
		"line_ids": [],
		"text": "The harbor slept.",
		"v": 1,
	}
	var id := runtime.ai.request(&"tts_prep", packet, {}, &"end")
	assert_gt(id, 0)
	assert_true(await _until(func() -> bool: return _rows(runtime, "ai_result").size() >= 1, 2.0))
	assert_eq(str(server.requests[0]["path"]), "/v1/chat/completions")
	assert_eq(runtime.ai.host_text(&"tts_prep", packet, "fallback"), "The harbor slept.")


func test_bad_replies_fall_back_to_the_authored_line() -> void:
	await _fallback({"body": "not-json", "mode": "reply", "status": 200}, "parse")
	await _fallback({"body": WyrdFakeLocalServer.chat_content("{\"nope\":1}"), "mode": "reply", "status": 200}, "schema")
	await _fallback({"body": "{}", "mode": "reply", "status": 500}, "http_500")
	await _fallback({"mode": "silent"}, "timeout", true)
	await _fallback({"mode": "close"}, "connect")
	await _fallback({"mode": "redirect"}, "redirect")
	await _fallback({"body": "x".repeat(70000), "mode": "reply", "status": 200}, "too_large")
	await _closed_port()


func test_a_refused_url_or_cloud_model_never_connects() -> void:
	var server := _listen()
	var runtime: WyrdRuntime = _boot(false)["runtime"]
	var wired: Dictionary = _attach(runtime, server)
	wired["provider"].base_url = "http://example.com"
	runtime.trace.enabled = true
	runtime.dialogue.open_scene("gate")
	await _settled(runtime)
	assert_eq(server.connections, 0)
	assert_eq(str(_rows(runtime, "ai_local")[0]["op"]), "refused")
	assert_eq(str(_rows(runtime, "ai_local")[0]["reason"]), "not_loopback")
	assert_eq(str(_rows(runtime, "ai_deliver")[0]["error"]), "not_loopback")
	assert_eq(str(_rows(runtime, "ai_validate")[0]["rule"]), "provider")
	assert_eq(runtime.dialogue.line().text, "The gate is shut.")

	var again: WyrdRuntime = _boot(false)["runtime"]
	var cloud: Dictionary = _attach(again, server)
	cloud["provider"].model = "gemma3:cloud"
	again.trace.enabled = true
	var before := server.connections
	again.dialogue.open_scene("gate")
	await _settled(again)
	assert_eq(server.connections, before)
	assert_eq(str(_rows(again, "ai_local")[0]["reason"]), "cloud_model")
	assert_eq(str(_rows(again, "ai_deliver")[0]["error"]), "cloud_model")
	assert_eq(str(_rows(again, "ai_validate")[0]["rule"]), "provider")


func test_cancel_frees_the_request_and_a_provider_switch_cancels_the_rest() -> void:
	var server := _listen()
	server.replies.append({"mode": "silent"})
	var runtime: WyrdRuntime = _boot(false)["runtime"]
	var wired: Dictionary = _attach(runtime, server)
	var transport: Node = wired["transport"]
	runtime.trace.enabled = true
	runtime.dialogue.open_scene("gate")
	assert_true(await _until(func() -> bool: return server.requests.size() >= 1, 2.0))
	var id := int(_rows(runtime, "ai_request")[0]["id"])
	assert_eq(transport.get_child_count(), 1)
	assert_true(runtime.ai.cancel(id))
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(transport.get_child_count(), 0)
	assert_eq(_rows(runtime, "ai_result").size(), 0)
	assert_eq(server.live_connections(), 0)
	assert_eq(runtime.ai.pending_count(), 0)

	server.replies.append({"mode": "silent"})
	var second: WyrdRuntime = _boot(false)["runtime"]
	_attach(second, server)
	second.trace.enabled = true
	var seen := server.requests.size()
	second.dialogue.open_scene("gate")
	assert_true(await _until(func() -> bool: return server.requests.size() > seen, 2.0))
	second.register_adapter(WyrdAIProvider, WyrdNullAIProvider.new())
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_rows(second, "ai_result").size(), 0)
	assert_eq(server.live_connections(), 0)
	assert_eq(second.ai.pending_count(), 0)


func test_a_name_outside_the_packet_is_not_cached() -> void:
	var server := _listen()
	server.auto_text = "Zed shut it."
	var runtime: WyrdRuntime = _boot(true)["runtime"]
	_attach(runtime, server)
	runtime.trace.enabled = true
	runtime.dialogue.open_scene("gate")
	assert_true(await _until(func() -> bool: return _rows(runtime, "ai_validate").size() >= 1, 2.0))
	assert_eq(str(_rows(runtime, "ai_validate")[0]["rule"]), "names")
	var key := str(_rows(runtime, "ai_request")[0]["key"])
	assert_eq(runtime.ai.cached_text(key), "")
	runtime.dialogue.advance()
	runtime.dialogue.open_scene("gate")
	var line: WyrdLineView = runtime.dialogue.line()
	assert_eq(line.text, "The gate is shut.")
	assert_ne(line.text_source, &"ai")


func _fallback(reply: Dictionary, reason: String, pending_clear: bool = false) -> void:
	var server := _listen()
	server.replies.append(reply)
	var runtime: WyrdRuntime = _boot(false)["runtime"]
	_attach(runtime, server)
	runtime.trace.enabled = true
	var seen := server.requests.size()
	runtime.dialogue.open_scene("gate")
	assert_true(await _until(func() -> bool: return _rows(runtime, "ai_validate").size() >= 1, 3.0), reason)
	assert_eq(str(_rows(runtime, "ai_validate")[0]["rule"]), "provider", reason)
	assert_eq(str(_local(runtime, "error")["reason"]), reason, reason)
	assert_eq(runtime.dialogue.line().text, "The gate is shut.")
	assert_ne(runtime.dialogue.line().text_source, &"ai")
	if pending_clear:
		assert_eq(runtime.ai.pending_count(), 0)
	if reason == "redirect":
		await get_tree().create_timer(0.3).timeout
		assert_eq(server.requests.size(), seen + 1)


func _closed_port() -> void:
	var runtime: WyrdRuntime = _boot(false)["runtime"]
	var transport = _Transport.new()
	add_child_autofree(transport)
	var provider = _Provider.new()
	provider.timeout_s = 0.5
	provider.base_url = "http://127.0.0.1:59999"
	provider.attach(transport)
	provider.bind_trace(runtime)
	runtime.register_adapter(WyrdAIProvider, provider)
	runtime.trace.enabled = true
	runtime.dialogue.open_scene("gate")
	assert_true(await _until(func() -> bool: return _rows(runtime, "ai_validate").size() >= 1, 3.0), "closed")
	assert_eq(str(_rows(runtime, "ai_validate")[0]["rule"]), "provider")
	assert_eq(str(_local(runtime, "error")["reason"]), "connect")
	assert_eq(runtime.dialogue.line().text, "The gate is shut.")


func _settled(runtime: WyrdRuntime) -> void:
	assert_true(await _until(func() -> bool: return _rows(runtime, "ai_validate").size() >= 1, 2.0))


func _listen() -> WyrdFakeLocalServer:
	var server := WyrdFakeLocalServer.new()
	add_child_autofree(server)
	var port := server.start()
	assert_gt(port, 0)
	_servers.append(server)
	return server


func _attach(runtime: WyrdRuntime, server: WyrdFakeLocalServer) -> Dictionary:
	var transport = _Transport.new()
	add_child_autofree(transport)
	var provider = _Provider.new()
	provider.timeout_s = 0.5
	assert_true(provider.set_base_url("http://127.0.0.1:%d" % server.port))
	provider.attach(transport)
	provider.bind_trace(runtime)
	runtime.register_adapter(WyrdAIProvider, provider)
	return {"provider": provider, "transport": transport}


func _boot(with_zed: bool) -> Dictionary:
	var path := "user://wyrd_m10_local_provider.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(_BODY)
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = "m10local"
	manifest.files = PackedStringArray([path])
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	host.world.add_entity(&"player", &"person", "Traveler", PackedStringArray(), true)
	if with_zed:
		host.world.add_entity(&"zed", &"person", "Zed", PackedStringArray(), true)
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(1)
	return {"host": host, "runtime": runtime}


func _local(runtime: WyrdRuntime, op: String) -> Dictionary:
	for row in _rows(runtime, "ai_local"):
		if str(row.get("op", "")) == op:
			return row
	return {}


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


const _BODY := """// [EXAMPLE CONTENT]
language 1

scene gate
  narrator: The gate is shut. #tag:ai #line:gate
  -> end
"""
