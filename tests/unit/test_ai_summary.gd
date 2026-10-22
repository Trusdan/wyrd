extends GutTest

## Journal summary returns at once and never writes the journal.


func test_null_provider_joins_entries_and_an_empty_journal_is_silent() -> void:
	var runtime := _boot()
	runtime.trace.clear()
	assert_eq(runtime.quests.summary("toll"), "")
	assert_eq(_rows(runtime, "ai_use").size(), 0)
	assert_eq(_rows(runtime, "ai_request").size(), 0)
	assert_eq(_rows(runtime, "ai_prefetch").size(), 0)
	assert_eq(_rows(runtime, "quest_summary").size(), 1)
	runtime.tick(0)
	runtime.trace.clear()
	var joined := "Bram shut the gate.\nNia heard the bell."
	assert_eq(runtime.quests.summary("toll"), joined)
	assert_eq(str(_rows(runtime, "ai_use")[0]["reason"]), "off")
	assert_eq(str(_rows(runtime, "ai_use")[0]["slot_kind"]), "journal_summary")
	assert_eq(str(_rows(runtime, "ai_use")[0]["path"]), "summary:toll")
	assert_eq(str(_rows(runtime, "ai_use")[0]["key"]), "-")
	assert_eq(_rows(runtime, "ai_request").size(), 0)
	assert_eq(_rows(runtime, "ai_prefetch").size(), 0)
	assert_eq(String(runtime.quests.summary_source("toll")), "authored")
	runtime.trace.clear()
	assert_eq(runtime.quests.summary("missing"), "")
	assert_eq(_rows(runtime, "ai_use").size(), 0)
	assert_eq(_rows(runtime, "ai_request").size(), 0)
	assert_eq(_rows(runtime, "ai_prefetch").size(), 0)


func test_a_miss_sends_one_request_then_a_hit_or_a_rejection() -> void:
	var runtime := _started()
	var provider := _Hold.new()
	runtime.register_adapter(WyrdAIProvider, provider)
	runtime.trace.clear()
	var joined := "Bram shut the gate.\nNia heard the bell."
	assert_eq(runtime.quests.summary("toll"), joined)
	assert_eq(str(_use(runtime)["reason"]), "miss")
	assert_eq(str(_use(runtime)["path"]), "summary:toll")
	assert_eq(str(_use(runtime)["slot_kind"]), "journal_summary")
	assert_eq(provider.waiting.size(), 1)
	assert_eq(String(provider.waiting[0].kind), "journal_summary")
	assert_eq(provider.waiting[0].owner, "summary:toll")
	assert_eq(String(provider.waiting[0].path), "summary:toll")
	assert_eq(str(_rows(runtime, "ai_prefetch")[0]["source"]), "summary")
	assert_eq(str(_rows(runtime, "ai_prefetch")[0]["path"]), "toll")
	assert_eq(int(_rows(runtime, "ai_prefetch")[0]["lines"]), 1)
	assert_eq(int(_rows(runtime, "ai_prefetch")[0]["sent"]), 1)
	var packet: Dictionary = provider.waiting[0].packet
	assert_eq(packet["line_ids"], ["j1", "j3"])
	assert_eq(packet["entries"], ["Bram shut the gate.", "Nia heard the bell."])
	assert_eq(str(packet["text"]), joined)
	var names: Array = []
	for row in packet["entities"]:
		names.append(str(row["id"]))
	assert_eq(names, ["bram", "nia"])
	assert_false(str(packet).contains("sealed"))
	runtime.trace.clear()
	assert_eq(runtime.quests.summary("toll"), joined)
	assert_eq(str(_use(runtime)["reason"]), "waiting")
	assert_eq(provider.waiting.size(), 1)
	assert_eq(_rows(runtime, "ai_prefetch").size(), 0)
	assert_true(provider.answer(0, true, "The gate stayed shut."))
	assert_eq(runtime.quests.summary("toll"), "The gate stayed shut.")
	assert_eq(String(runtime.quests.summary_source("toll")), "ai")
	assert_eq(str(_use(runtime)["reason"]), "hit")
	assert_eq(str(_use(runtime)["source"]), "ai")
	var rejected := _started()
	var later := _Hold.new()
	rejected.register_adapter(WyrdAIProvider, later)
	rejected.quests.summary("toll")
	assert_true(later.answer(0, true, "{"))
	rejected.trace.clear()
	assert_eq(rejected.quests.summary("toll"), joined)
	assert_eq(str(_use(rejected)["reason"]), "rejected")
	assert_eq(later.waiting.size(), 1)


func test_a_longer_journal_supersedes_the_open_summary() -> void:
	var runtime := _started()
	var provider := _Hold.new()
	runtime.register_adapter(WyrdAIProvider, provider)
	var first := runtime.quests.summary("toll")
	var old_id := provider.waiting[0].id
	var old_key := provider.waiting[0].key
	runtime.facts.set(&"player.step", 1)
	runtime.tick(0)
	assert_eq(runtime.quests.journal("toll").size(), 3)
	runtime.trace.clear()
	var again := runtime.quests.summary("toll")
	assert_eq(first, "Bram shut the gate.\nNia heard the bell.")
	assert_eq(again, first + "\nThe lane is quiet.")
	assert_eq(provider.waiting.size(), 2)
	assert_ne(provider.waiting[1].key, old_key)
	assert_eq(provider.waiting[1].owner, "summary:toll")
	var cancelled := false
	for event in _rows(runtime, "ai_cancel"):
		if int(event.get("id", 0)) == old_id and str(event.get("reason", "")) == "superseded":
			cancelled = true
			assert_eq(str(event.get("path", "")), "summary:toll")
			assert_eq(str(event.get("slot_kind", "")), "journal_summary")
	assert_true(cancelled)
	assert_eq(int(_rows(runtime, "ai_prefetch")[0]["sent"]), 1)


func test_a_summary_expires_after_sixty_minutes() -> void:
	var runtime := _started()
	var provider := _Hold.new()
	runtime.register_adapter(WyrdAIProvider, provider)
	runtime.quests.summary("toll")
	var request_id := provider.waiting[0].id
	runtime.trace.clear()
	runtime.tick(60)
	assert_eq(runtime.now_minutes(), 60)
	var expired := false
	for event in _rows(runtime, "ai_cancel"):
		if int(event.get("id", 0)) == request_id and str(event.get("reason", "")) == "expired":
			expired = true
	assert_true(expired)
	assert_eq(runtime.ai.pending_count(), 0)


func test_the_inflight_cap_sends_nothing() -> void:
	var runtime := _started()
	runtime.config().ai_max_inflight = 1
	var provider := _Hold.new()
	runtime.register_adapter(WyrdAIProvider, provider)
	var host_id := runtime.ai.request(&"epilogue_stitch", {"text": "The harbor slept.", "v": 1}, {}, &"end")
	assert_gt(host_id, 0)
	runtime.trace.clear()
	assert_eq(runtime.quests.summary("toll"), "Bram shut the gate.\nNia heard the bell.")
	assert_eq(str(_use(runtime)["reason"]), "miss")
	assert_eq(int(_rows(runtime, "ai_prefetch")[0]["capped"]), 1)
	assert_eq(int(_rows(runtime, "ai_prefetch")[0]["sent"]), 0)
	assert_eq(provider.waiting.size(), 1)
	assert_eq(runtime.ai.pending_count(), 1)


func test_summary_does_not_change_journal_facts_deeds_or_save() -> void:
	var runtime := _started()
	runtime.config().ai_save_cache = false
	var journal_before: Array = runtime.quests.journal("toll")
	var deeds_before := runtime.deeds.size()
	var saved := JSON.stringify(runtime.save_state(), "", true)
	runtime.quests.summary("toll")
	runtime.quests.summary_source("toll")
	assert_eq(runtime.quests.journal("toll"), journal_before)
	assert_eq(runtime.deeds.size(), deeds_before)
	assert_eq(JSON.stringify(runtime.save_state(), "", true), saved)
	var live := _started()
	var provider := _Hold.new()
	live.register_adapter(WyrdAIProvider, provider)
	live.config().ai_save_cache = false
	var before := JSON.stringify(live.save_state(), "", true)
	var written: Array = live.quests.journal("toll")
	live.quests.summary("toll")
	provider.answer(0, true, "The gate stayed shut.")
	live.quests.summary("toll")
	live.quests.summary_source("toll")
	assert_eq(live.quests.journal("toll"), written)
	assert_eq(live.deeds.size(), 0)
	assert_eq(JSON.stringify(live.save_state(), "", true), before)


func _started() -> WyrdRuntime:
	var runtime := _boot()
	runtime.config().secrecy_tiers = PackedStringArray(["open", "sealed"])
	runtime.tick(0)
	assert_eq(runtime.quests.journal("toll").size(), 2)
	return runtime


func _boot() -> WyrdRuntime:
	var path := "user://wyrd_m10_summary.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(_BODY)
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = "m10summary"
	manifest.files = PackedStringArray([path])
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	host.world.add_entity(&"player", &"person", "Traveler", PackedStringArray(), true)
	host.world.add_entity(&"bram", &"person", "Bram", PackedStringArray(), true)
	host.world.add_entity(&"nia", &"person", "Nia", PackedStringArray(), true)
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(1)
	runtime.config().secrecy_tiers = PackedStringArray(["open", "sealed"])
	runtime.trace.enabled = true
	return runtime


func _use(runtime: WyrdRuntime) -> Dictionary:
	var rows := _rows(runtime, "ai_use")
	if rows.is_empty():
		return {}
	return rows[rows.size() - 1]


func _rows(runtime: WyrdRuntime, kind: String) -> Array:
	var rows: Array = []
	for event in runtime.trace.events:
		if str(event.get("kind", "")) == kind:
			rows.append(event)
	return rows


class _Hold extends WyrdAIProvider:
	var waiting: Array[WyrdAIRequest] = []

	func id() -> StringName:
		return &"summary-text"

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


const _BODY := """// [EXAMPLE CONTENT]
language 1

facts
  player.step : int stored
  player.clearance : symbol stored

quest toll "The Toll"
  start when true
  stage one
    journal: Bram shut the gate. #line:j1
    journal: The sealed page. #secrecy:sealed #line:j2
    journal: Nia heard the bell. #line:j3
    waits_until player.step >= 1
    -> two
  stage two
    journal: The lane is quiet. #line:j4
    waits_until false
"""
