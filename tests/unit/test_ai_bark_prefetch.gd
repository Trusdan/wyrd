extends GutTest

const _Harness := preload("res://tests/scenario/s2c_harness.gd")


func test_a_tick_sends_holding_barks_and_a_query_shows_the_cache() -> void:
	var runtime := _boot()
	runtime.config().ai_max_inflight = 8
	var provider := _hold()
	runtime.register_adapter(WyrdAIProvider, provider)
	runtime.roles.assign(&"lookout", &"nia")
	runtime.trace.clear()
	runtime.tick(0)
	var arm: Dictionary = _row(runtime, "ai_sweep")
	assert_eq(str(arm["op"]), "arm")
	assert_eq(str(arm["reason"]), "start")
	assert_eq(int(arm["count"]), 5)
	assert_eq(provider.paths(), PackedStringArray(["gate_bark", "tide", "m1", "m2"]))
	assert_eq(provider.owners(), PackedStringArray(["bark:a.gate", "bark:c.held", "bark:e.set", "bark:e.set"]))
	assert_eq(_prefetch_paths(runtime), PackedStringArray(["a.gate", "c.held", "e.set"]))
	assert_eq(_noise(runtime), PackedStringArray())
	var tide := provider.waiting[1]
	assert_eq(tide.key, _shown_key(runtime, "c.held", "tide"))
	for index in provider.waiting.size():
		assert_true(provider.answer(index, true, str(provider.waiting[index].packet.get("text", "")) + "."))
	var heard: Array = []
	runtime.bark_ready.connect(func(line): heard.append(line))
	var won: Dictionary = runtime.director.query("bark", "", "ferry_master")
	assert_eq(str(won["id"]), "a.gate")
	assert_eq(heard.size(), 1)
	assert_eq(heard[0].text, "The gate is shut..")
	assert_eq(str(heard[0].text_source), "ai")
	assert_eq(str(_use(runtime, "gate_bark")["reason"]), "hit")


func test_a_fact_change_rearms_and_the_floor_waits_sixty_minutes() -> void:
	var changed := _boot()
	changed.config().ai_max_inflight = 8
	changed.register_adapter(WyrdAIProvider, _hold())
	changed.roles.assign(&"lookout", &"nia")
	changed.tick(0)
	changed.facts.set(&"player.coins", 1)
	changed.trace.clear()
	changed.tick(0)
	assert_eq(str(_row(changed, "ai_sweep")["reason"]), "change")
	assert_true(_prefetch_paths(changed).has("b.closed"))
	var floor := _boot()
	floor.config().ai_max_inflight = 8
	floor.register_adapter(WyrdAIProvider, _hold())
	floor.roles.assign(&"lookout", &"nia")
	floor.tick(0)
	floor.trace.clear()
	floor.tick(59)
	assert_eq(_rows(floor, "ai_sweep").size(), 0)
	floor.trace.clear()
	floor.tick(1)
	assert_eq(floor.now_minutes(), 60)
	assert_eq(str(_row(floor, "ai_sweep")["reason"]), "floor")


func test_bark_cap_leaves_one_slot_and_one_sends_nothing() -> void:
	var runtime := _boot()
	runtime.config().ai_max_inflight = 4
	var provider := _hold()
	runtime.register_adapter(WyrdAIProvider, provider)
	runtime.roles.assign(&"lookout", &"nia")
	runtime.trace.clear()
	runtime.tick(0)
	var bark_open := 0
	for req in provider.waiting:
		if req.owner.begins_with("bark:"):
			bark_open += 1
	assert_eq(bark_open, 3)
	runtime.dialogue.open_scene("gate")
	assert_eq(provider.waiting.size(), 4)
	assert_eq(provider.waiting[3].owner, "scene:gate")
	var tight := _boot()
	tight.config().ai_max_inflight = 1
	var quiet := _hold()
	tight.register_adapter(WyrdAIProvider, quiet)
	tight.roles.assign(&"lookout", &"nia")
	tight.trace.clear()
	tight.tick(0)
	assert_eq(quiet.waiting.size(), 0)
	assert_eq(_rows(tight, "ai_sweep").size(), 0)
	assert_eq(_prefetch_paths(tight).size(), 0)


func test_a_bark_request_expires_after_sixty_minutes() -> void:
	var runtime := _boot()
	runtime.config().ai_max_inflight = 8
	var provider := _hold()
	runtime.register_adapter(WyrdAIProvider, provider)
	runtime.roles.assign(&"lookout", &"nia")
	runtime.tick(0)
	var request_id := provider.waiting[0].id
	var key := provider.waiting[0].key
	runtime.trace.clear()
	runtime.tick(60)
	var expired := false
	for event in _rows(runtime, "ai_cancel"):
		if int(event.get("id", 0)) == request_id and str(event.get("reason", "")) == "expired":
			expired = true
	assert_true(expired)
	assert_true(provider.answer(0, true, "The gate stays shut."))
	assert_eq(str(_rows(runtime, "ai_result")[-1]["rule"]), "late")
	assert_eq(runtime.ai.cached_text(key), "The gate stays shut.")


func test_dropping_the_sweep_rearms_with_start() -> void:
	var off := _partial()
	off.ai.set_enabled(false)
	assert_eq(str(_row_where(off, "ai_sweep", "off")["op"]), "drop")
	off.ai.set_enabled(true)
	off.trace.clear()
	off.tick(0)
	assert_eq(str(_row(off, "ai_sweep")["reason"]), "start")
	var swapped := _partial()
	swapped.ai.set_provider(_hold())
	assert_eq(str(_row_where(swapped, "ai_sweep", "provider")["reason"]), "provider")
	swapped.trace.clear()
	swapped.tick(0)
	assert_eq(str(_row(swapped, "ai_sweep")["reason"]), "start")
	var fresh := _partial()
	fresh.start_new_game(1)
	fresh.register_adapter(WyrdAIProvider, _hold())
	fresh.roles.assign(&"lookout", &"nia")
	assert_eq(str(_row_where(fresh, "ai_sweep", "new_game")["reason"]), "new_game")
	fresh.tick(0)
	assert_eq(str(_rows(fresh, "ai_sweep")[-1]["reason"]), "start")
	var loaded := _partial()
	loaded.config().ai_save_cache = false
	var saved := loaded.save_state()
	loaded.load_state(saved)
	assert_eq(str(_row_where(loaded, "ai_sweep", "load")["reason"]), "load")
	loaded.register_adapter(WyrdAIProvider, _hold())
	loaded.roles.assign(&"lookout", &"nia")
	loaded.trace.clear()
	loaded.tick(0)
	assert_eq(str(_row(loaded, "ai_sweep")["reason"]), "start")


func test_null_and_off_log_nothing() -> void:
	var quiet := _boot()
	quiet.roles.assign(&"lookout", &"nia")
	quiet.trace.clear()
	quiet.tick(0)
	assert_eq(_rows(quiet, "ai_sweep").size(), 0)
	assert_eq(_rows(quiet, "ai_request").size(), 0)
	assert_eq(_queue_rows(quiet, "ai_prefetch").size(), 0)
	var off := _boot()
	off.register_adapter(WyrdAIProvider, _hold())
	off.ai.set_enabled(false)
	off.roles.assign(&"lookout", &"nia")
	off.trace.clear()
	off.tick(0)
	assert_eq(_rows(off, "ai_sweep").size(), 0)
	assert_eq(_rows(off, "ai_request").size(), 0)
	assert_eq(_queue_rows(off, "ai_prefetch").size(), 0)


func test_the_five_queue_split_stays_the_same_with_bark_work() -> void:
	var plain := _gullhaven(false)
	var busy := _gullhaven(true)
	assert_eq(_five(busy["runtime"]), _five(plain["runtime"]))
	assert_gt(_rows(busy["runtime"], "ai_sweep").size(), 0)
	assert_eq(_rows(plain["runtime"], "ai_sweep").size(), 0)
	assert_eq(_queue_rows(plain["runtime"], "ai_prefetch").size(), 0)
	plain["runtime"].config().ai_save_cache = false
	busy["runtime"].config().ai_save_cache = false
	assert_eq(JSON.stringify(busy["runtime"].save_state(), "", true), JSON.stringify(plain["runtime"].save_state(), "", true))


func _partial() -> WyrdRuntime:
	var runtime := _boot()
	runtime.config().scheduler_work_per_tick = 1
	runtime.config().ai_max_inflight = 8
	runtime.register_adapter(WyrdAIProvider, _hold())
	runtime.roles.assign(&"lookout", &"nia")
	runtime.trace.clear()
	runtime.tick(0)
	assert_gt(runtime.ai.prefetch_carry(), 0)
	return runtime


func _gullhaven(barks: bool) -> Dictionary:
	var opened := _Harness.new().boot_gullhaven()
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.config().ai_save_cache = false
	if barks:
		_add_barks(runtime)
		runtime.register_adapter(WyrdAIProvider, _hold())
	runtime.trace.enabled = true
	runtime.trace.clear()
	runtime.scheduler().push("rumor", "hop")
	runtime.scheduler().push("publish", "issue")
	runtime.tick(1)
	return {"runtime": runtime}


func _add_barks(runtime: WyrdRuntime) -> void:
	var path := "user://wyrd_m10_bark_extra.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("""// [EXAMPLE CONTENT]
language 1

storylet extra.bell
  scope: bark
  speaker: ferry_master
  - The bell is still. #tag:ai #line:extra_bell

storylet extra.lane
  scope: bark
  speaker: ferry_master
  - The lane is quiet. #tag:ai #line:extra_lane
""")
	file.close()
	var diagnostics := WyrdDiagnostics.new()
	var pack := WyrdPack.compile(PackedStringArray([path]), "barkextra", 1, null, diagnostics, "", true)
	assert_false(diagnostics.has_errors(), diagnostics.format())
	var extra := WyrdContent.from_pack(pack)
	for story_id in extra.storylets.keys():
		runtime.content().storylets[story_id] = extra.storylets[story_id]
	for line_id in extra.lines.keys():
		runtime.content().lines[line_id] = extra.lines[line_id]
	for line_id in extra.ai_lines.keys():
		runtime.content().ai_lines[line_id] = extra.ai_lines[line_id]


func _shown_key(runtime: WyrdRuntime, story_id: String, line_id: String) -> String:
	var heard: Array = []
	runtime.bark_ready.connect(func(line): heard.append(line))
	runtime.present_bark(runtime.content().storylets[story_id], {"line_id": line_id})
	assert_eq(heard.size(), 1)
	return str(_use(runtime, line_id)["key"])


func _boot() -> WyrdRuntime:
	var path := "user://wyrd_m10_bark_prefetch.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(_BODY)
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = "m10bark"
	manifest.files = PackedStringArray([path])
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	host.world.add_entity(&"player", &"person", "traveler", PackedStringArray(), true)
	host.world.add_entity(&"ferry_master", &"person", "Bram", PackedStringArray(), true)
	host.world.add_entity(&"nia", &"person", "Nia", PackedStringArray(), true)
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(1)
	runtime.trace.enabled = true
	return runtime


func _hold() -> _Hold:
	return _Hold.new()


func _use(runtime: WyrdRuntime, line_id: String) -> Dictionary:
	var rows := _rows(runtime, "ai_use")
	for index in range(rows.size() - 1, -1, -1):
		if str(rows[index].get("path", "")) == line_id:
			return rows[index]
	return {}


func _prefetch_paths(runtime: WyrdRuntime) -> PackedStringArray:
	var paths := PackedStringArray()
	for event in _rows(runtime, "ai_prefetch"):
		if str(event.get("source", "")) != "bark":
			continue
		paths.append(str(event.get("path", "")))
	return paths


func _five(runtime: WyrdRuntime) -> Array:
	var rows: Array = []
	for event in _rows(runtime, "scheduler"):
		var queue := str(event.get("queue", ""))
		if queue == "ai_prefetch" or queue == "frame":
			continue
		rows.append(event)
	return rows


func _queue_rows(runtime: WyrdRuntime, queue: String) -> Array:
	var rows: Array = []
	for event in _rows(runtime, "scheduler"):
		if str(event.get("queue", "")) == queue:
			rows.append(event)
	return rows


func _noise(runtime: WyrdRuntime) -> PackedStringArray:
	var kinds := PackedStringArray()
	for event in runtime.trace.events:
		var kind := str(event.get("kind", ""))
		if kind == "tick" or kind == "scheduler" or kind.begins_with("ai_"):
			continue
		kinds.append(kind)
	return kinds


func _row(runtime: WyrdRuntime, kind: String) -> Dictionary:
	var rows := _rows(runtime, kind)
	if rows.is_empty():
		return {}
	return rows[0]


func _row_where(runtime: WyrdRuntime, kind: String, reason: String) -> Dictionary:
	for event in _rows(runtime, kind):
		if str(event.get("reason", "")) == reason:
			return event
	return {}


func _rows(runtime: WyrdRuntime, kind: String) -> Array:
	var rows: Array = []
	for event in runtime.trace.events:
		if str(event.get("kind", "")) == kind:
			rows.append(event)
	return rows


class _Hold extends WyrdAIProvider:
	var waiting: Array[WyrdAIRequest] = []

	func id() -> StringName:
		return &"bark-text"

	func prompt_version() -> int:
		return 1

	func locales() -> PackedStringArray:
		return PackedStringArray(["en"])

	func request(req: WyrdAIRequest) -> void:
		waiting.append(req)

	func cancel(_request_id: int) -> void:
		pass

	func answer(index: int, ok: bool, text: String) -> bool:
		if index < 0 or index >= waiting.size():
			return false
		var result := WyrdAIResult.new()
		result.ok = ok
		result.text = text
		return waiting[index].reply(result)

	func paths() -> PackedStringArray:
		var out := PackedStringArray()
		for req in waiting:
			out.append(String(req.path))
		return out

	func owners() -> PackedStringArray:
		var out := PackedStringArray()
		for req in waiting:
			out.append(req.owner)
		return out


const _BODY := """// [EXAMPLE CONTENT]
language 1

facts
  player.coins : int stored

// Storylet whens are not in the dep index. This start condition is, so a coins
// write marks the scheduler and the next tick arms with reason=change.
quest coins "Coins"
  start when player.coins >= 1
  stage hold
    waits_until player.coins >= 2

role lookout
  visibility: public

scene gate
  narrator: The gate is shut. #tag:ai #line:gate
  -> end

storylet a.gate
  scope: bark
  speaker: ferry_master
  priority: 5
  - The gate is shut. #tag:ai #line:gate_bark

storylet b.closed
  scope: bark
  speaker: ferry_master
  when: player.coins >= 1
  - The gate opens. #tag:ai #line:closed

storylet c.held
  scope: bark
  speaker: lookout
  - The tide is high. #tag:ai #line:tide

storylet d.wild
  scope: bark
  speaker: any
  - Anyone could say this. #tag:ai #line:wild

storylet e.set
  scope: bark
  speaker: ferry_master
  lines:
    - The second rope. #tag:ai #line:m2
    - The first rope. #tag:ai #line:m1
"""
