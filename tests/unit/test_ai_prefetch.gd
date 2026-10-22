extends GutTest


func test_scene_open_sends_in_source_order_and_a_divert_keeps_the_root() -> void:
	var runtime := _boot()
	var provider := _hold(true)
	runtime.register_adapter(WyrdAIProvider, provider)
	runtime.trace.clear()
	runtime.dialogue.open_scene("root")
	assert_eq(provider.waiting.size(), 1)
	assert_eq(String(provider.waiting[0].path), "gate")
	assert_eq(provider.waiting[0].owner, "scene:root")
	var first: Dictionary = _rows(runtime, "ai_prefetch")[0]
	assert_eq(str(first["source"]), "scene")
	assert_eq(str(first["path"]), "root")
	assert_eq(int(first["lines"]), 1)
	assert_eq(int(first["sent"]), 1)
	assert_eq(int(first["cached"]) + int(first["open"]) + int(first["capped"]) + int(first["locale"]), 0)
	var shown := runtime.dialogue.line()
	assert_eq(str(_row(runtime, "ai_use")["key"]), provider.waiting[0].key)
	runtime.dialogue.advance()
	assert_eq(provider.waiting.size(), 2)
	assert_eq(String(provider.waiting[1].path), "lane")
	assert_eq(provider.waiting[1].owner, "scene:root")
	var second: Dictionary = _rows(runtime, "ai_prefetch")[1]
	assert_eq(str(second["path"]), "root")
	assert_eq(int(second["lines"]), 1)
	assert_eq(int(second["sent"]), 1)
	assert_eq(shown.text, "The gate is shut.")


func test_cap_cached_and_open_keys() -> void:
	var runtime := _boot()
	runtime.config().ai_max_inflight = 0
	runtime.register_adapter(WyrdAIProvider, _hold(true))
	runtime.trace.clear()
	runtime.dialogue.open_scene("root")
	assert_eq(runtime.ai.pending_count(), 0)
	assert_eq(_rows(runtime, "ai_prefetch").size(), 0)
	runtime.dialogue.advance()
	runtime.dialogue.advance()
	var capped := _boot()
	capped.config().ai_max_inflight = 1
	var provider := _hold(true)
	capped.register_adapter(WyrdAIProvider, provider)
	var host_packet := {"text": "HOST-ONLY-TOKEN"}
	var host_id := capped.ai.request(&"bark_paraphrase", host_packet, {}, &"host-line")
	assert_gt(host_id, 0)
	capped.trace.clear()
	capped.dialogue.open_scene("root")
	var row: Dictionary = _rows(capped, "ai_prefetch")[0]
	assert_eq(int(row["sent"]), 0)
	assert_eq(int(row["capped"]), 1)
	assert_eq(capped.ai.pending_count(), 1)
	var filled := _boot()
	var answering := _hold(false)
	filled.register_adapter(WyrdAIProvider, answering)
	var packet := filled.ai.packet_for_line("gate", &"bark_paraphrase", &"")
	filled.ai.request(&"bark_paraphrase", packet, {}, &"gate")
	filled.trace.clear()
	filled.dialogue.open_scene("root")
	var cached: Dictionary = _rows(filled, "ai_prefetch")[0]
	assert_eq(int(cached["cached"]), 1)
	assert_eq(int(cached["sent"]), 0)
	var again := _boot()
	var held := _hold(true)
	again.register_adapter(WyrdAIProvider, held)
	again.ai.request(&"bark_paraphrase", again.ai.packet_for_line("gate", &"bark_paraphrase", &""), {}, &"gate")
	again.trace.clear()
	again.dialogue.open_scene("root")
	var open_row: Dictionary = _rows(again, "ai_prefetch")[0]
	assert_eq(int(open_row["open"]), 1)
	assert_eq(int(open_row["sent"]), 0)
	assert_eq(again.ai.pending_count(), 1)


func test_topic_prefetch_reuses_eligible_storylets() -> void:
	var on := _boot()
	var provider := _hold(true)
	on.register_adapter(WyrdAIProvider, provider)
	on.topics.unlock(&"harbor_toll")
	on.topics.unlock(&"tavern_talk")
	on.trace.clear()
	on.dialogue.open("ferry_master")
	assert_eq(provider.paths(), PackedStringArray(["alpha", "m1", "m2", "zeta"]))
	for req in provider.waiting:
		assert_eq(req.owner, "topic:ferry_master")
	var prefetch: Dictionary = _rows(on, "ai_prefetch")[0]
	assert_eq(str(prefetch["source"]), "topic")
	assert_eq(str(prefetch["path"]), "ferry_master")
	assert_eq(int(prefetch["lines"]), 4)
	assert_eq(int(prefetch["sent"]), 4)
	var off := _boot()
	off.ai.set_enabled(false)
	off.topics.unlock(&"harbor_toll")
	off.topics.unlock(&"tavern_talk")
	off.trace.clear()
	off.dialogue.open("ferry_master")
	assert_eq(_rows(on, "director").size(), _rows(off, "director").size())
	assert_eq(_rows(on, "storylet_index").size(), _rows(off, "storylet_index").size())
	on.dialogue.open("tavern_owner")
	var cancelled := 0
	for req in provider.waiting:
		if req.owner == "topic:ferry_master":
			cancelled += 1
	assert_eq(cancelled, 4)
	var reasons: PackedStringArray = PackedStringArray()
	for event in _rows(on, "ai_cancel"):
		reasons.append(str(event.get("reason", "")))
	assert_eq(reasons, PackedStringArray(["superseded", "superseded", "superseded", "superseded"]))
	assert_eq(provider.paths(), PackedStringArray(["alpha", "m1", "m2", "zeta", "stew"]))
	assert_eq(provider.waiting[4].owner, "topic:tavern_owner")


func test_scene_end_keeps_host_requests_and_a_late_result_is_cached() -> void:
	var ended := _finish_scene("advance")
	_assert_scene_end(ended)
	var aborted := _finish_scene("abort")
	_assert_scene_end(aborted)
	var forced := _finish_scene("force")
	_assert_scene_end(forced)
	var runtime: WyrdRuntime = ended["runtime"]
	var provider: _Hold = ended["provider"]
	var view: WyrdLineView = ended["view"]
	assert_eq(view.text, "The gate is shut.")
	assert_true(provider.answer(1, true, "The gate stays shut."))
	assert_eq(view.text, "The gate is shut.")
	assert_eq(str(_row(runtime, "ai_result")["rule"]), "late")
	assert_eq(runtime.ai.cached_text(provider.waiting[1].key), "The gate stays shut.")
	runtime.dialogue.open_scene("root")
	assert_eq(runtime.dialogue.line().text, "The gate stays shut.")
	assert_eq(str(runtime.dialogue.line().text_source), "ai")
	var bad := _finish_scene("advance")
	var bad_runtime: WyrdRuntime = bad["runtime"]
	var bad_provider: _Hold = bad["provider"]
	assert_true(bad_provider.answer(1, true, "{"))
	assert_eq(bad_runtime.ai.cache_size(), 0)
	assert_eq(str(_rows(bad_runtime, "ai_result")[-1]["rule"]), "late")


func test_late_list_forgets_and_host_cancel_stays_unknown() -> void:
	var runtime := _boot()
	runtime.config().ai_max_inflight = 2
	var provider := _hold(true)
	runtime.register_adapter(WyrdAIProvider, provider)
	runtime.trace.clear()
	runtime.dialogue.open_scene("pair")
	assert_eq(provider.waiting.size(), 2)
	runtime.config().ai_max_inflight = 1
	runtime.dialogue.advance()
	runtime.dialogue.advance()
	var forgot: Dictionary = _row_where(runtime, "ai_late", "cap")
	assert_eq(int(forgot["id"]), provider.waiting[0].id)
	assert_eq(str(forgot["path"]), "gate2")
	assert_false(runtime.ai.deliver(provider.waiting[0].id, _result(true, "The gate stays shut.")))
	assert_eq(str(_rows(runtime, "ai_result")[-1]["rule"]), "unknown_request")
	assert_true(provider.answer(1, true, "The lane stays quiet."))
	assert_eq(str(_rows(runtime, "ai_result")[-1]["rule"]), "late")
	var off := _finish_scene("advance")
	off["runtime"].ai.set_enabled(false)
	assert_eq(str(_row_where(off["runtime"], "ai_late", "off")["reason"]), "off")
	var swapped := _finish_scene("advance")
	swapped["runtime"].ai.set_provider(_hold(true))
	assert_eq(str(_row_where(swapped["runtime"], "ai_late", "provider")["reason"]), "provider")
	var fresh := _finish_scene("advance")
	fresh["runtime"].start_new_game(1)
	assert_eq(str(_row_where(fresh["runtime"], "ai_late", "new_game")["reason"]), "new_game")
	var loaded := _finish_scene("advance")
	var loaded_runtime: WyrdRuntime = loaded["runtime"]
	loaded_runtime.config().ai_save_cache = false
	var report := loaded_runtime.load_state(loaded_runtime.save_state())
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(str(_row_where(loaded_runtime, "ai_late", "load")["reason"]), "load")
	var host := _boot()
	var later := _hold(true)
	host.register_adapter(WyrdAIProvider, later)
	var request_id := host.ai.request(&"bark_paraphrase", {"text": "hello"}, {}, &"host-line")
	assert_true(host.ai.cancel(request_id))
	assert_false(later.answer(0, true, "hello"))
	assert_eq(str(_rows(host, "ai_result")[-1]["rule"]), "unknown_request")


func test_can_save_ignores_open_and_late_requests() -> void:
	var opened := _finish_scene("advance")
	var runtime: WyrdRuntime = opened["runtime"]
	assert_true(runtime.can_save())
	assert_eq(runtime.ai.pending_count(), 1)
	assert_false(JSON.stringify(runtime.save_state()).contains("HOST-ONLY-TOKEN"))


func _assert_scene_end(opened: Dictionary) -> void:
	var runtime: WyrdRuntime = opened["runtime"]
	var provider: _Hold = opened["provider"]
	assert_eq(runtime.ai.pending_count(), 1)
	assert_eq(String(provider.waiting[0].path), "host-line")
	var reasons: PackedStringArray = PackedStringArray()
	for event in _rows(runtime, "ai_cancel"):
		if str(event.get("path", "")) == "gate":
			reasons.append(str(event.get("reason", "")))
	assert_eq(reasons, PackedStringArray(["scene_end"]))


func _finish_scene(how: String) -> Dictionary:
	var runtime := _boot()
	var provider := _hold(true)
	runtime.register_adapter(WyrdAIProvider, provider)
	runtime.ai.request(&"bark_paraphrase", {"text": "HOST-ONLY-TOKEN"}, {}, &"host-line")
	runtime.trace.clear()
	runtime.dialogue.open_scene("root")
	var view := runtime.dialogue.line()
	if how == "abort":
		runtime.dialogue.abort(&"cut")
	elif how == "force":
		runtime.dialogue.force_close()
	else:
		runtime.dialogue.advance()
		runtime.dialogue.advance()
	return {"provider": provider, "runtime": runtime, "view": view}


func _boot() -> WyrdRuntime:
	var path := "user://wyrd_m10_prefetch.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(_BODY)
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = "m10prefetch"
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


func _hold(hold: bool) -> _Hold:
	var provider := _Hold.new()
	provider.hold = hold
	return provider


func _result(ok: bool, text: String) -> WyrdAIResult:
	var result := WyrdAIResult.new()
	result.ok = ok
	result.text = text
	return result


func _row(runtime: WyrdRuntime, kind: String) -> Dictionary:
	var rows := _rows(runtime, kind)
	if rows.is_empty():
		return {}
	return rows[rows.size() - 1]


func _row_where(runtime: WyrdRuntime, kind: String, reason: String) -> Dictionary:
	var found := {}
	for event in _rows(runtime, kind):
		if str(event.get("reason", "")) == reason:
			found = event
	return found


func _rows(runtime: WyrdRuntime, kind: String) -> Array:
	var rows: Array = []
	for event in runtime.trace.events:
		if str(event.get("kind", "")) == kind:
			rows.append(event)
	return rows


class _Hold extends WyrdAIProvider:
	var hold: bool = true
	var waiting: Array[WyrdAIRequest] = []

	func id() -> StringName:
		return &"prefetch-text"

	func prompt_version() -> int:
		return 1

	func locales() -> PackedStringArray:
		return PackedStringArray(["en"])

	func request(req: WyrdAIRequest) -> void:
		waiting.append(req)
		if hold:
			return
		var result := WyrdAIResult.new()
		result.ok = true
		result.text = str(req.packet.get("text", "")) + "!"
		req.reply(result)

	func cancel(_request_id: int) -> void:
		pass

	func answer(index: int, ok: bool, text: String) -> bool:
		var result := WyrdAIResult.new()
		result.ok = ok
		result.text = text
		return waiting[index].reply(result)

	func paths() -> PackedStringArray:
		var out := PackedStringArray()
		for req in waiting:
			out.append(String(req.path))
		return out


const _BODY := """// [EXAMPLE CONTENT]
language 1

facts
  player.coins : int stored

scene root
  narrator: The gate is shut. #tag:ai #line:gate
  -> scene inner
  -> end

scene inner
  narrator: The lane is quiet. #tag:ai #line:lane
  -> end

scene pair
  narrator: The gate is shut. #tag:ai #line:gate2
  narrator: The lane is quiet. #tag:ai #line:lane2
  -> end

storylet harbor.zeta
  scope: topic harbor_toll
  speaker: ferry_master
  - The tide turned early. #tag:ai #line:zeta

storylet harbor.alpha
  scope: topic harbor_toll
  speaker: ferry_master
  - The harbor has news. #tag:ai #line:alpha

storylet harbor.mid
  scope: topic harbor_toll
  speaker: ferry_master
  lines:
    - The ropes are wet. #tag:ai #line:m2
    - The lane is quiet. #tag:ai #line:m1

storylet harbor.visit
  scope: topic harbor_toll
  speaker: ferry_master
  -> scene inner

storylet tavern.note
  scope: topic tavern_talk
  speaker: tavern_owner
  - The stew is hot. #tag:ai #line:stew
"""
