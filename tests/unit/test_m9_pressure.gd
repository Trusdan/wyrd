extends GutTest

const _PACK := "res://tests/support/m9_pressure.wyrdmanifest.tres"
const _TIERS := "res://tests/golden/link/template_pressure_tiers/pack.wyrd"


func test_offer_queues_replaces_and_keeps_fifo() -> void:
	var runtime := _runtime()
	runtime.config().pressure_tiers = PackedStringArray(["low", "mid", "high"])
	runtime.trace.enabled = true
	assert_true(runtime.generator.offer(&"guild", "toll", &"low", {"note": "first"}))
	assert_true(runtime.generator.offer(&"guild", "bell", &"mid", {}))
	assert_true(runtime.generator.offer(&"guild", "toll", &"high", {"note": "second", "count": 2}))
	var pending: Array = runtime.generator.pending()
	assert_eq(pending.size(), 2)
	assert_eq(str(pending[0]["key"]), "toll")
	assert_eq(String(pending[0]["tier"]), "high")
	assert_eq(str(pending[0]["origin"]), "host")
	assert_eq(str(pending[0]["template"]), "")
	assert_eq(String(pending[0]["source"]), "guild")
	var toll: Dictionary = pending[0]["payload"]
	assert_eq(str(toll["note"]), "second")
	assert_eq(int(toll["count"]), 2)
	assert_eq(str(pending[1]["key"]), "bell")
	assert_eq(String(pending[1]["tier"]), "mid")
	var offers := _offers(runtime)
	assert_eq(offers.size(), 3)
	assert_eq(str(offers[0]["replaced"]), "false")
	assert_eq(str(offers[0]["queued"]), "1")
	assert_eq(str(offers[2]["replaced"]), "true")
	assert_eq(str(offers[2]["queued"]), "2")
	assert_eq(str(offers[2]["key"]), "toll")
	assert_eq(str(offers[2]["origin"]), "host")


func test_offer_rejections_leave_the_queue() -> void:
	var runtime := _runtime()
	runtime.config().pressure_tiers = PackedStringArray(["low"])
	runtime.trace.enabled = true
	assert_true(runtime.generator.offer(&"guild", "toll", &"low", {"note": "kept"}))
	runtime.trace.clear()
	var before := JSON.stringify(runtime.generator.pending())
	assert_false(runtime.generator.offer(&"", "toll", &"low", {}))
	assert_push_error("source and key are required")
	assert_false(runtime.generator.offer(&"guild", "", &"low", {}))
	assert_push_error("source and key are required")
	assert_false(runtime.generator.offer(&"guild", "other", &"mythic", {}))
	assert_push_error("unknown pressure tier")
	runtime.config().pressure_tiers = PackedStringArray()
	assert_false(runtime.generator.offer(&"guild", "other", &"low", {}))
	assert_push_error("unknown pressure tier")
	runtime.config().pressure_tiers = PackedStringArray(["low"])
	assert_false(runtime.generator.offer(&"guild", "other", &"low", {"note": []}))
	assert_push_error("payload values")
	assert_false(runtime.generator.offer(&"guild", "other", &"low", {"note": RefCounted.new()}))
	assert_push_error("payload values")
	assert_eq(JSON.stringify(runtime.generator.pending()), before)
	assert_eq(_offers(runtime).size(), 0)


func test_queue_is_unsaved_and_cleared() -> void:
	var runtime := _boot()
	runtime.config().pressure_tiers = PackedStringArray(["low", "mid", "high"])
	runtime.start_new_game(4)
	var saved := runtime.save_state().duplicate(true)
	var before := JSON.stringify(saved)
	assert_true(runtime.generator.offer(&"guild", "toll", &"low", {"note": "pending"}))
	assert_eq(runtime.generator.pending_count(), 1)
	assert_eq(JSON.stringify(runtime.save_state()), before)
	runtime.start_new_game(4)
	assert_eq(runtime.generator.pending_count(), 0)
	assert_true(runtime.generator.offer(&"guild", "toll", &"low", {}))
	var reloaded := runtime.load_content(load(_PACK) as WyrdContentManifest)
	assert_true(reloaded.ok, reloaded.diagnostics.format())
	assert_eq(runtime.generator.pending_count(), 0)
	runtime.start_new_game(4)
	assert_true(runtime.generator.offer(&"guild", "toll", &"low", {}))
	var loaded := runtime.load_state(saved)
	assert_true(loaded.ok, loaded.diagnostics.format())
	assert_eq(runtime.generator.pending_count(), 0)


func test_tier_rank_and_tier_matches() -> void:
	var runtime := _runtime()
	var generator := runtime.generator
	runtime.config().pressure_tiers = PackedStringArray(["low", "mid", "high"])
	assert_eq(generator.tier_rank("low"), 0)
	assert_eq(generator.tier_rank("mid"), 1)
	assert_eq(generator.tier_rank("high"), 2)
	assert_eq(generator.tier_rank("mythic"), -1)
	assert_eq(generator.tier_rank(""), -1)
	var untiered := WyrdTemplateDef.new()
	assert_true(generator.tier_matches(&"", untiered))
	assert_true(generator.tier_matches(&"low", untiered))
	assert_true(generator.tier_matches(&"mythic", untiered))
	var single := WyrdTemplateDef.new()
	single.tier_low = "mid"
	assert_true(generator.tier_matches(&"", single))
	assert_true(generator.tier_matches(&"mid", single))
	assert_false(generator.tier_matches(&"low", single))
	assert_false(generator.tier_matches(&"high", single))
	assert_false(generator.tier_matches(&"mythic", single))
	var span := WyrdTemplateDef.new()
	span.tier_low = "low"
	span.tier_high = "mid"
	span.tier_range = true
	assert_true(generator.tier_matches(&"low", span))
	assert_true(generator.tier_matches(&"mid", span))
	assert_false(generator.tier_matches(&"high", span))
	assert_false(generator.tier_matches(&"mythic", span))
	runtime.config().pressure_tiers = PackedStringArray()
	assert_eq(generator.tier_rank("low"), -1)
	assert_false(generator.tier_matches(&"low", single))
	assert_true(generator.tier_matches(&"", single))
	assert_true(generator.tier_matches(&"low", untiered))


func test_deed_hooks_queue_matching_offers() -> void:
	var runtime := _boot()
	runtime.trace.enabled = true
	runtime.start_new_game(4)
	var matched := runtime.deeds.record(&"theft", &"bram", &"clerk", &"slip")
	assert_gt(matched, 0)
	assert_eq(runtime.generator.pending_count(), 1)
	var offer: Dictionary = runtime.generator.pending()[0]
	assert_eq(String(offer["source"]), "deed")
	assert_eq(str(offer["template"]), "theft_report")
	assert_eq(str(offer["origin"]), "deed")
	assert_eq(String(offer["tier"]), "")
	assert_eq(str(offer["key"]), "theft_report:%d" % matched)
	var payload: Dictionary = offer["payload"]
	assert_eq(int(payload["deed"]), matched)
	assert_eq(str(payload["verb"]), "theft")
	assert_eq(str(payload["actor"]), "bram")
	assert_eq(str(payload["target"]), "clerk")
	assert_eq(str(payload["place"]), "slip")
	assert_eq(str(_offers(runtime)[0]["replaced"]), "false")
	runtime.generator.clear()
	runtime.trace.clear()
	runtime.deeds.record(&"theft", &"bram", &"player")
	assert_eq(runtime.generator.pending_count(), 0)
	assert_eq(_offers(runtime).size(), 0)
	var again := runtime.deeds.record(&"theft", &"ada", &"clerk")
	assert_eq(runtime.generator.pending_count(), 1)
	runtime.deeds.deed_recorded.emit({
		"actor": &"ada",
		"id": again,
		"magnitude": 1.0,
		"place": &"",
		"target": &"clerk",
		"verb": &"theft",
	})
	assert_eq(runtime.generator.pending_count(), 1)
	assert_eq(str(runtime.generator.pending()[0]["key"]), "theft_report:%d" % again)
	assert_eq(str(_offers(runtime)[-1]["replaced"]), "true")
	runtime.generator.clear()
	var assault := runtime.deeds.record(&"assault", &"bram", &"player")
	assert_eq(runtime.generator.pending_count(), 1)
	assert_eq(str(runtime.generator.pending()[0]["template"]), "theft_report")
	assert_eq(str(runtime.generator.pending()[0]["key"]), "theft_report:%d" % assault)
	var saved := runtime.save_state()
	var fresh := _boot()
	fresh.start_new_game(4)
	var loaded := fresh.load_state(saved)
	assert_true(loaded.ok, loaded.diagnostics.format())
	assert_gt(fresh.deeds.size(), 0)
	assert_eq(fresh.generator.pending_count(), 0)


func test_hook_eval_restores_handler_locals() -> void:
	var runtime := _runtime()
	var path := "user://wyrd_m9_pressure_locals.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("""language 1

facts
  player.seen : int stored

events
  met(who: int)

quest watch "Watch"
  stage look
    on met where true:
      ~ record deed theft(actor: player, target: bram)
      ~ set player.seen = event.who
    waits_until false

template theft_report "Theft"
  on_deed theft where not deed.target == player
  stage work
    waits_until false
""")
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"m9_pressure_locals"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(4)
	runtime.quests.start("watch")
	assert_eq(runtime.quests.status("watch"), &"active")
	runtime.events.emit(&"met", {"who": 7})
	assert_eq(runtime.facts.get(&"player.seen"), 7)
	assert_eq(runtime.generator.pending_count(), 1)
	assert_eq(str(runtime.generator.pending()[0]["template"]), "theft_report")
	assert_eq(str(runtime.generator.pending()[0]["origin"]), "deed")


func test_pressure_tiers_without_a_list_do_not_warn() -> void:
	var diagnostics := WyrdDiagnostics.new()
	WyrdPack.compile(PackedStringArray([_TIERS]), "template_pressure_tiers", 1, null, diagnostics, "", true)
	for item in diagnostics.items:
		var row := item as WyrdDiagnostic
		assert_ne(String(row.code), "W_TEMPLATE_TIER_UNKNOWN")
		assert_ne(String(row.code), "W_TEMPLATE_TIER_ORDER")


func test_zero_generate_weight_matches_the_four_queue_split() -> void:
	var four := PackedInt32Array([40, 12, 8, 4])
	var five := PackedInt32Array([40, 12, 8, 4, 0])
	for budget in range(0, 257):
		var got := WyrdScheduler.apportion(five, budget)
		var old := _apportion4(four, budget)
		assert_eq(PackedInt32Array([got[0], got[1], got[2], got[3]]), old, "budget %d" % budget)
		assert_eq(int(got[4]), 0, "budget %d" % budget)


func test_generate_is_idle_without_a_handler() -> void:
	var runtime := _runtime()
	runtime.config().pressure_tiers = PackedStringArray(["low"])
	runtime.trace.enabled = true
	assert_true(runtime.generator.offer(&"guild", "toll", &"low", {"note": "waiting"}))
	runtime.trace.clear()
	runtime.tick(0)
	assert_eq(runtime.generator.pending_count(), 1)
	assert_eq(int(runtime.scheduler().carry("generate")), 0)
	for row in runtime.trace.events:
		if str(row.get("kind", "")) != "scheduler":
			continue
		assert_ne(str(row.get("queue", "")), "generate")


func test_generate_spill_and_share() -> void:
	var idle := WyrdScheduler.new()
	var fifo: Array[String] = []
	var waiting: Array[String] = ["toll", "bell", "rope"]
	idle.generate_has_work = func() -> bool: return not waiting.is_empty()
	idle.generate_unit = func() -> void:
		fifo.append(waiting[0])
		waiting.remove_at(0)
	idle.generate_pending = func() -> int: return waiting.size()
	var spilled: Dictionary = idle.run(3, PackedInt32Array([40, 12, 8, 4, 0]), func(_index: int) -> void: pass)
	assert_eq(fifo, ["toll", "bell", "rope"])
	assert_eq(int(spilled["generate_spent"]), 3)
	assert_eq(spilled["spent"], PackedInt32Array([0, 0, 0, 0]))
	var shared := WyrdScheduler.new()
	var calls := [0]
	var left := [40]
	shared.generate_has_work = func() -> bool: return int(left[0]) > 0
	shared.generate_unit = func() -> void:
		calls[0] = int(calls[0]) + 1
		left[0] = int(left[0]) - 1
	shared.generate_pending = func() -> int: return int(left[0])
	for index in 80:
		shared.watch(index)
	var weights := PackedInt32Array([40, 12, 8, 4, 16])
	var share := int(WyrdScheduler.apportion(weights, 80)[4])
	var report: Dictionary = shared.run(80, weights, func(_index: int) -> void: pass)
	assert_eq(int(calls[0]), share)
	assert_eq(int(report["generate_spent"]), share)
	assert_gt(share, 0)
	var spent: PackedInt32Array = report["spent"]
	assert_eq(int(spent[1]), 0)
	assert_eq(int(spent[2]), 0)
	assert_eq(int(spent[3]), 0)
	assert_eq(int(spent[0]) + int(report["generate_spent"]), 80)


func _runtime() -> WyrdRuntime:
	return WyrdRuntime.new()


func _boot() -> WyrdRuntime:
	var runtime := _runtime()
	var report := runtime.load_content(load(_PACK) as WyrdContentManifest)
	assert_true(report.ok, report.diagnostics.format())
	return runtime


func _offers(runtime: WyrdRuntime) -> Array:
	var rows: Array = []
	for row in runtime.trace.events:
		if str(row.get("kind", "")) == "gen_offer":
			rows.append(row)
	return rows


func _apportion4(weights: PackedInt32Array, budget: int) -> PackedInt32Array:
	var shares := PackedInt32Array()
	shares.resize(4)
	if budget <= 0:
		return shares
	var sum := 0
	for index in 4:
		sum += maxi(int(weights[index]), 0)
	if sum <= 0:
		shares[0] = budget
		return shares
	var frac: Array[float] = []
	var used := 0
	for index in 4:
		var weight := maxi(int(weights[index]), 0)
		var exact := float(weight) * float(budget) / float(sum)
		var whole := int(floor(exact))
		shares[index] = whole
		frac.append(exact - float(whole))
		used += whole
	var left := budget - used
	while left > 0:
		var best := 0
		var best_frac := -1.0
		for index in frac.size():
			if frac[index] > best_frac:
				best = index
				best_frac = frac[index]
		shares[best] = int(shares[best]) + 1
		frac[best] = -1.0
		left -= 1
	return shares
