extends GutTest

const _Harness := preload("res://tests/scenario/s2c_harness.gd")


func test_default_provider_is_null() -> void:
	var runtime := WyrdRuntime.new()
	runtime.trace.enabled = true
	assert_true(runtime.ai.provider() is WyrdNullAIProvider)
	assert_eq(String(runtime.ai.provider_id()), "null")
	assert_false(runtime.ai.is_active())
	assert_true(runtime.ai.is_enabled())
	assert_eq(runtime.ai.provider().prompt_version(), 0)
	assert_eq(runtime.ai.provider().locales(), PackedStringArray())
	assert_eq(runtime.adapter(WyrdAIProvider), runtime.ai.provider())
	assert_eq(_rows(runtime, "ai_provider").size(), 0)
	assert_eq(_rows(runtime, "ai_request").size(), 0)
	var facade = load("res://addons/wyrd/runtime/wyrd.gd").new()
	assert_true(facade.ai is WyrdAI)
	assert_true(facade.ai.provider() is WyrdNullAIProvider)
	facade.free()


func test_null_request_keeps_no_pending_state() -> void:
	var runtime := WyrdRuntime.new()
	runtime.trace.enabled = true
	var id := runtime.ai.request(&"bark_paraphrase", {"text": "hello"})
	assert_eq(id, 0)
	assert_eq(runtime.ai.pending_count(), 0)
	var row: Dictionary = _rows(runtime, "ai_request")[0]
	assert_eq(int(row["id"]), 0)
	assert_eq(str(row["slot_kind"]), "bark_paraphrase")
	assert_eq(str(row["path"]), "")
	assert_eq(str(row["state"]), "refused")
	assert_eq(str(row["reason"]), "null")


func test_gullhaven_trace_has_no_ai_lines() -> void:
	var opened := _Harness.new().boot_gullhaven()
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.trace.enabled = true
	runtime.start_new_game(1)
	runtime.tick(1)
	runtime.deeds.record(&"arrived", &"player", &"", &"gullhaven")
	var hits := 0
	for row in runtime.trace.events:
		if str(row.get("kind", "")).begins_with("ai_"):
			hits += 1
	assert_eq(hits, 0)


func test_unknown_kind_is_refused() -> void:
	var runtime := _with_later()
	runtime.trace.enabled = true
	assert_eq(runtime.ai.request(&"poem", {"text": "x"}, {}, &"bad.line"), 0)
	assert_push_warning("unknown kind")
	assert_eq(runtime.ai.pending_count(), 0)
	var row: Dictionary = _rows(runtime, "ai_request")[0]
	assert_eq(str(row["reason"]), "kind")
	assert_eq(str(row["state"]), "refused")
	assert_eq(str(row["slot_kind"]), "poem")
	assert_eq(str(row["path"]), "bad.line")


func test_disabled_refuses_and_cancels_once() -> void:
	var runtime := WyrdRuntime.new()
	var later := WyrdFakeAI.EchoLater.new()
	runtime.register_adapter(WyrdAIProvider, later)
	runtime.trace.enabled = true
	var id := runtime.ai.request(&"gossip", {"text": "pending"}, {}, &"dock.line")
	assert_gt(id, 0)
	runtime.trace.clear()
	runtime.ai.set_enabled(false)
	assert_false(runtime.ai.is_enabled())
	assert_eq(runtime.ai.pending_count(), 0)
	assert_eq(later.cancelled.size(), 1)
	assert_eq(later.cancelled[0], id)
	var providers := _rows(runtime, "ai_provider")
	assert_eq(providers.size(), 1)
	assert_eq(str(providers[0]["id"]), "echo-later")
	assert_eq(str(providers[0]["state"]), "off")
	var cancelled: Dictionary = _rows(runtime, "ai_cancel")[0]
	assert_eq(int(cancelled["id"]), id)
	assert_eq(str(cancelled["slot_kind"]), "gossip")
	assert_eq(str(cancelled["reason"]), "off")
	assert_eq(runtime.ai.request(&"gossip", {}, {}, &"dock.line"), 0)
	var refused: Dictionary = _rows(runtime, "ai_request")[0]
	assert_eq(str(refused["reason"]), "off")
	assert_eq(str(refused["state"]), "refused")
	var before := runtime.trace.events.size()
	runtime.ai.set_enabled(false)
	assert_eq(runtime.trace.events.size(), before)


func test_deliver_once_then_unknown() -> void:
	var runtime := WyrdRuntime.new()
	var later := WyrdFakeAI.EchoLater.new()
	runtime.register_adapter(WyrdAIProvider, later)
	runtime.trace.enabled = true
	var id := runtime.ai.request(&"journal_summary", {"text": "day"}, {}, &"journal.1")
	assert_eq(runtime.ai.pending_count(), 1)
	assert_true(later.answer(0, true, "ai-text-not-stored"))
	assert_eq(runtime.ai.pending_count(), 0)
	var row: Dictionary = _rows(runtime, "ai_result")[0]
	assert_eq(int(row["id"]), id)
	assert_eq(str(row["slot_kind"]), "journal_summary")
	assert_eq(str(row["ok"]), "true")
	assert_eq(str(row["rule"]), "-")
	assert_eq(str(row["path"]), "journal.1")
	assert_false(JSON.stringify(runtime.save_state()).contains("ai-text-not-stored"))
	assert_false(later.answer(0, true, "again"))
	var second: Dictionary = _rows(runtime, "ai_result")[1]
	assert_eq(str(second["rule"]), "unknown_request")
	assert_eq(str(second["slot_kind"]), "-")


func test_synchronous_reply_was_pending_first() -> void:
	var runtime := WyrdRuntime.new()
	var now := WyrdFakeAI.EchoNow.new()
	now.host = runtime
	runtime.register_adapter(WyrdAIProvider, now)
	runtime.trace.enabled = true
	var id := runtime.ai.request(&"tts_prep", {"text": "hello"}, {}, &"voice.1")
	assert_gt(id, 0)
	assert_eq(now.seen_pending, 1)
	assert_eq(runtime.ai.pending_count(), 0)
	assert_eq(now.texts[0], "hello")
	var sent: Dictionary = _rows(runtime, "ai_request")[0]
	assert_eq(str(sent["state"]), "sent")
	assert_eq(str(sent["reason"]), "-")
	assert_eq(int(sent["id"]), id)
	var result: Dictionary = _rows(runtime, "ai_result")[0]
	assert_eq(str(result["ok"]), "true")
	assert_eq(str(result["rule"]), "-")
	assert_false(runtime.ai.deliver(id, _result(true, "again")))
	assert_eq(str(_rows(runtime, "ai_result")[1]["rule"]), "unknown_request")


func test_cancel_notifies_the_provider() -> void:
	var runtime := WyrdRuntime.new()
	var later := WyrdFakeAI.EchoLater.new()
	runtime.register_adapter(WyrdAIProvider, later)
	runtime.trace.enabled = true
	var id := runtime.ai.request(&"bark_paraphrase", {"text": "a"}, {}, &"line.a")
	assert_true(runtime.ai.cancel(id))
	assert_eq(later.cancelled.size(), 1)
	assert_eq(later.cancelled[0], id)
	assert_eq(runtime.ai.pending_count(), 0)
	var row: Dictionary = _rows(runtime, "ai_cancel")[0]
	assert_eq(str(row["reason"]), "host")
	assert_eq(str(row["slot_kind"]), "bark_paraphrase")
	assert_eq(str(row["path"]), "line.a")
	assert_false(runtime.ai.cancel(id))
	assert_eq(later.cancelled.size(), 1)
	assert_false(runtime.ai.deliver(id, _result(false, "")))
	assert_eq(str(_rows(runtime, "ai_result")[0]["rule"]), "unknown_request")


func test_registering_a_provider_cancels_the_previous() -> void:
	var runtime := WyrdRuntime.new()
	var first := WyrdFakeAI.EchoLater.new()
	runtime.register_adapter(WyrdAIProvider, first)
	var id := runtime.ai.request(&"epilogue_stitch", {}, {}, &"end.1")
	var second := WyrdFakeAI.EchoNow.new()
	runtime.trace.enabled = true
	runtime.trace.clear()
	runtime.register_adapter(WyrdAIProvider, second)
	assert_eq(first.cancelled.size(), 1)
	assert_eq(first.cancelled[0], id)
	assert_eq(runtime.ai.pending_count(), 0)
	assert_true(runtime.ai.is_active())
	assert_eq(String(runtime.ai.provider_id()), "echo-now")
	var cancelled: Dictionary = _rows(runtime, "ai_cancel")[0]
	assert_eq(str(cancelled["reason"]), "provider")
	assert_eq(str(cancelled["slot_kind"]), "epilogue_stitch")
	var registered: Dictionary = _rows(runtime, "ai_provider")[0]
	assert_eq(str(registered["id"]), "echo-now")
	assert_eq(str(registered["state"]), "on")
	runtime.trace.clear()
	runtime.register_adapter(WyrdAIProvider, WyrdNullAIProvider.new())
	assert_true(runtime.ai.provider() is WyrdNullAIProvider)
	assert_false(runtime.ai.is_active())
	assert_eq(runtime.adapter(WyrdAIProvider), runtime.ai.provider())
	assert_eq(runtime.ai.request(&"gossip", {}), 0)
	var restored: Dictionary = _rows(runtime, "ai_provider")[0]
	assert_eq(str(restored["id"]), "null")
	assert_eq(str(restored["state"]), "off")
	assert_eq(str(_rows(runtime, "ai_request")[0]["reason"]), "null")


func test_new_game_and_load_reset_ids_and_save_ignores_requests() -> void:
	var harness := _Harness.new()
	var left: WyrdRuntime = harness.open_pack(_Harness.SAMPLE)["runtime"]
	var right: WyrdRuntime = harness.open_pack(_Harness.SAMPLE)["runtime"]
	left.start_new_game(3)
	right.start_new_game(3)
	var plain := JSON.stringify(left.save_state(), "", true)
	var later := WyrdFakeAI.EchoLater.new()
	right.register_adapter(WyrdAIProvider, later)
	assert_eq(JSON.stringify(right.save_state(), "", true), plain)
	var id := right.ai.request(&"gossip", {"text": "ai-text-not-stored"}, {}, &"dock.line")
	assert_gt(id, 0)
	assert_eq(JSON.stringify(right.save_state(), "", true), plain)
	right.trace.enabled = true
	right.trace.clear()
	var loaded := right.load_state(right.save_state())
	assert_true(loaded.ok, loaded.diagnostics.format())
	assert_eq(right.ai.pending_count(), 0)
	var load_cancel: Dictionary = _rows(right, "ai_cancel")[0]
	assert_eq(int(load_cancel["id"]), id)
	assert_eq(str(load_cancel["reason"]), "load")
	var reopened := right.ai.request(&"gossip", {}, {}, &"dock.line")
	assert_eq(reopened, 1)
	right.trace.clear()
	right.start_new_game(3)
	assert_eq(right.ai.pending_count(), 0)
	var game_cancel: Dictionary = _rows(right, "ai_cancel")[0]
	assert_eq(int(game_cancel["id"]), reopened)
	assert_eq(str(game_cancel["reason"]), "new_game")
	assert_eq(right.ai.request(&"bark_paraphrase", {}), 1)
	assert_eq(JSON.stringify(right.save_state(), "", true), JSON.stringify(left.save_state(), "", true))


func test_request_deep_copies_packet() -> void:
	var runtime := WyrdRuntime.new()
	var later := WyrdFakeAI.EchoLater.new()
	runtime.register_adapter(WyrdAIProvider, later)
	var packet := {"text": "hi", "nested": {"n": 1}}
	var constraints := {"limit": 2, "nested": {"n": 3}}
	var id := runtime.ai.request(&"journal_summary", packet, constraints, &"journal.1")
	assert_gt(id, 0)
	packet["text"] = "changed"
	packet["nested"]["n"] = 9
	constraints["limit"] = 8
	constraints["nested"]["n"] = 7
	var req := later.waiting[0]
	assert_eq(str(req.packet["text"]), "hi")
	assert_eq(int(req.packet["nested"]["n"]), 1)
	assert_eq(int(req.constraints["limit"]), 2)
	assert_eq(int(req.constraints["nested"]["n"]), 3)
	assert_eq(String(req.locale), TranslationServer.get_locale())
	assert_eq(String(req.path), "journal.1")
	assert_ne(req.packet, packet)


func test_kinds_are_the_five_names() -> void:
	var listed := WyrdRuntime.new().ai.kinds()
	assert_eq(listed.size(), 5)
	assert_eq(String(listed[0]), "bark_paraphrase")
	assert_eq(String(listed[1]), "gossip")
	assert_eq(String(listed[2]), "journal_summary")
	assert_eq(String(listed[3]), "epilogue_stitch")
	assert_eq(String(listed[4]), "tts_prep")
	listed.append(&"extra")
	assert_eq(WyrdRuntime.new().ai.kinds().size(), 5)


func test_prefix_keeps_the_matching_path() -> void:
	var runtime := _with_later()
	runtime.trace.enabled = true
	runtime.trace.prefix = "dock.keep"
	var kept := runtime.ai.request(&"gossip", {}, {}, &"dock.keep.1")
	var dropped := runtime.ai.request(&"gossip", {}, {}, &"other.line")
	assert_gt(kept, 0)
	assert_gt(dropped, 0)
	assert_eq(runtime.ai.pending_count(), 2)
	var rows := _rows(runtime, "ai_request")
	assert_eq(rows.size(), 1)
	assert_eq(str(rows[0]["path"]), "dock.keep.1")


func test_deliver_off_the_main_thread_is_refused() -> void:
	var runtime := _with_later()
	runtime.trace.enabled = true
	var id := runtime.ai.request(&"gossip", {"text": "hear"}, {}, &"dock.line")
	var worker := Thread.new()
	var box := {"returned": true}
	worker.start(func() -> void:
		box["returned"] = runtime.ai.deliver(id, _result(true, "nope"))
	)
	worker.wait_to_finish()
	assert_false(bool(box["returned"]))
	assert_push_error("main thread")
	assert_eq(runtime.ai.pending_count(), 1)
	var row: Dictionary = _rows(runtime, "ai_result")[0]
	assert_eq(str(row["rule"]), "thread")
	assert_eq(str(row["ok"]), "true")
	assert_eq(str(row["slot_kind"]), "gossip")
	assert_true(runtime.ai.deliver(id, _result(false, "")))
	assert_eq(runtime.ai.pending_count(), 0)


func test_null_result_counts_as_not_ok() -> void:
	var runtime := _with_later()
	runtime.trace.enabled = true
	var id := runtime.ai.request(&"gossip", {}, {}, &"dock.line")
	assert_true(runtime.ai.deliver(id, null))
	var row: Dictionary = _rows(runtime, "ai_result")[0]
	assert_eq(str(row["ok"]), "false")
	assert_eq(str(row["rule"]), "-")
	assert_eq(runtime.ai.pending_count(), 0)


func _with_later() -> WyrdRuntime:
	var runtime := WyrdRuntime.new()
	runtime.register_adapter(WyrdAIProvider, WyrdFakeAI.EchoLater.new())
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
