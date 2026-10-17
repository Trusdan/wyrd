extends GutTest

## Coarse reach: one rumor unit per game hour, one seeded draw per NPC.


const _PLAIN := """
language 1
facts
  harbor.toll_fate : symbol stored
quest harbor_guild "The Harbor Guild"
  stage post
"""


func test_defaults_are_one_hour_and_four_ticks() -> void:
	var runtime := _boot(4)
	assert_eq(runtime.config().rumor_coarse_minutes, 60)
	assert_eq(WyrdRumor.REACH_FULL, 4)


func test_level_zero_does_not_draw_and_one_hour_matches_the_roll() -> void:
	var seed_value := _seed_for(true)
	var runtime := _arm(_boot(seed_value))
	runtime.trace.enabled = true
	_whisper(runtime)
	runtime.tick(0)
	assert_eq(runtime.now_minutes(), 0)
	assert_eq(runtime.rumors.reach_level("1", &"gullhaven"), 0)
	assert_eq(runtime.scheduler().carry("rumor"), 0)
	assert_eq(_rows(runtime, "rumor_hop").size(), 0)
	assert_eq(_rows(runtime, "rumor_reach").size(), 0)
	assert_null(_belief(runtime, "dock_hand"))
	assert_eq(_rows(runtime, "rumor_materialize").size(), 0)
	runtime.tick(60)
	assert_eq(runtime.now_minutes(), 60)
	assert_eq(runtime.rumors.reach_level("1", &"gullhaven"), 1)
	assert_eq(runtime.scheduler().carry("rumor"), 0)
	var rises := _rows(runtime, "rumor_reach")
	assert_eq(rises.size(), 1)
	assert_eq(String(rises[0]["deed"]), "1")
	assert_eq(String(rises[0]["place"]), "gullhaven")
	assert_eq(String(rises[0]["who"]), "gullhaven")
	assert_eq(String(rises[0]["path"]), "harbor_toll")
	assert_eq(String(rises[0]["key"]), "harbor.toll_fate")
	assert_eq(int(rises[0]["level"]), 1)
	assert_null(runtime.facts.get_in(&"harbor.toll_fate", &"known/dock_hand"))
	assert_null(_belief(runtime, "line_fisher"))
	assert_eq(_rows(runtime, "rumor_materialize").size(), 0)
	var expected := _manual(seed_value, "1", "dock_hand", 1, 60)
	var heard: Variant = _belief(runtime, "dock_hand")
	if expected:
		assert_eq(heard, &"stolen")
		assert_true(_believes(runtime, "dock_hand"))
	else:
		assert_null(heard)
		assert_false(_believes(runtime, "dock_hand"))
	var drawn := _rows(runtime, "rumor_materialize")
	assert_eq(drawn.size(), 1)
	assert_eq(String(drawn[0]["listener"]), "dock_hand")
	assert_eq(String(drawn[0]["who"]), "dock_hand")
	assert_eq(String(drawn[0]["place"]), "gullhaven")
	assert_eq(String(drawn[0]["path"]), "harbor_toll")
	assert_eq(String(drawn[0]["key"]), "harbor.toll_fate")
	assert_eq(String(drawn[0]["deed"]), "1")
	assert_eq(int(drawn[0]["level"]), 1)
	assert_eq(String(drawn[0]["chance"]), "0.2500")
	assert_eq(String(drawn[0]["accepted"]), "true" if expected else "false")
	_belief(runtime, "dock_hand")
	assert_eq(_rows(runtime, "rumor_materialize").size(), 1)
	assert_null(runtime.facts.get_in(&"harbor.toll_fate", &"known/dock_hand"))
	assert_eq(runtime.facts.get(&"harbor.toll_fate"), &"lost_at_sea")


func test_a_reject_is_once_and_the_next_deed_can_roll() -> void:
	var seed_value := _seed_for(false)
	var runtime := _arm(_boot(seed_value))
	runtime.trace.enabled = true
	_whisper(runtime)
	_whisper(runtime)
	runtime.tick(60)
	assert_eq(runtime.rumors.reach_level("1", &"gullhaven"), 1)
	assert_eq(runtime.rumors.reach_level("2", &"gullhaven"), 1)
	assert_null(_belief(runtime, "dock_hand"))
	var first := _rows(runtime, "rumor_materialize")
	assert_eq(first.size(), 1)
	assert_eq(String(first[0]["deed"]), "1")
	assert_eq(String(first[0]["accepted"]), "false")
	assert_eq(String(first[0]["chance"]), "0.2500")
	var second_taken := _manual(seed_value, "2", "dock_hand", 1, 60)
	var heard: Variant = _belief(runtime, "dock_hand")
	if second_taken:
		assert_eq(heard, &"stolen")
	else:
		assert_null(heard)
	var both := _rows(runtime, "rumor_materialize")
	assert_eq(both.size(), 2)
	assert_eq(String(both[1]["deed"]), "2")
	assert_eq(String(both[1]["accepted"]), "true" if second_taken else "false")
	_belief(runtime, "dock_hand")
	assert_eq(_rows(runtime, "rumor_materialize").size(), 2)
	assert_null(runtime.facts.get_in(&"harbor.toll_fate", &"known/dock_hand"))
	assert_eq(runtime.facts.get(&"harbor.toll_fate"), &"lost_at_sea")


func test_thirty_and_one_forty_four_fps_match() -> void:
	var slow := _over(30)
	var fast := _over(144)
	var whole := _over(0)
	var stepped := _over(1)
	var flushed := _over(-1)
	assert_eq(slow.now_minutes(), 60)
	assert_eq(fast.now_minutes(), 60)
	assert_eq(whole.now_minutes(), 60)
	assert_eq(stepped.now_minutes(), 60)
	assert_eq(flushed.now_minutes(), 0)
	assert_eq(flushed.rumors.reach_level("1", &"gullhaven"), 0)
	assert_eq(_rows(flushed, "rumor_reach").size(), 0)
	assert_null(_belief(flushed, "dock_hand"))
	for runtime in [slow, fast, whole, stepped]:
		assert_eq(runtime.rumors.reach_level("1", &"gullhaven"), 1)
		assert_eq(runtime.scheduler().carry("rumor"), 0)
		assert_eq(_rows(runtime, "rumor_hop").size(), 0)
	assert_eq(JSON.stringify(_rows(slow, "rumor_reach")), JSON.stringify(_rows(fast, "rumor_reach")))
	assert_eq(JSON.stringify(_rows(slow, "rumor_reach")), JSON.stringify(_rows(whole, "rumor_reach")))
	assert_eq(JSON.stringify(_rows(slow, "rumor_reach")), JSON.stringify(_rows(stepped, "rumor_reach")))
	_belief(slow, "dock_hand")
	_belief(fast, "dock_hand")
	_belief(whole, "dock_hand")
	_belief(stepped, "dock_hand")
	assert_eq(JSON.stringify(_rows(slow, "rumor_materialize")), JSON.stringify(_rows(fast, "rumor_materialize")))
	assert_eq(JSON.stringify(_rows(slow, "rumor_materialize")), JSON.stringify(_rows(whole, "rumor_materialize")))
	assert_eq(JSON.stringify(_rows(slow, "rumor_materialize")), JSON.stringify(_rows(stepped, "rumor_materialize")))
	var taken := _manual(11, "1", "dock_hand", 1, 60)
	var heard: Variant = _belief(slow, "dock_hand")
	if taken:
		assert_eq(heard, &"stolen")
	else:
		assert_null(heard)
	assert_eq(fast.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"), heard)
	assert_null(slow.facts.get_in(&"harbor.toll_fate", &"known/dock_hand"))
	assert_eq(slow.facts.get(&"harbor.toll_fate"), &"lost_at_sea")


func test_a_three_hour_jump_matches_minute_steps() -> void:
	var stepped := _arm(_boot(11))
	stepped.trace.enabled = true
	_whisper(stepped)
	for _minute in 180:
		stepped.tick(1)
	var jumped := _arm(_boot(11))
	jumped.config().scheduler_tick_minutes = 180
	jumped.trace.enabled = true
	_whisper(jumped)
	jumped.tick(180)
	assert_eq(stepped.now_minutes(), 180)
	assert_eq(jumped.now_minutes(), 180)
	assert_eq(stepped.rumors.reach_level("1", &"gullhaven"), 3)
	assert_eq(jumped.rumors.reach_level("1", &"gullhaven"), 3)
	assert_eq(JSON.stringify(_rows(stepped, "rumor_reach")), JSON.stringify(_rows(jumped, "rumor_reach")))
	assert_eq(_rows(stepped, "rumor_hop").size(), 0)
	assert_eq(_rows(jumped, "rumor_hop").size(), 0)


func test_reach_units_carry_in_order() -> void:
	var runtime := _arm(_boot(4))
	runtime.config().scheduler_tick_minutes = 180
	_one_unit(runtime)
	runtime.trace.enabled = true
	_whisper(runtime)
	runtime.tick(180)
	assert_eq(runtime.rumors.reach_level("1", &"gullhaven"), 1)
	assert_eq(runtime.scheduler().carry_tokens("rumor"), PackedStringArray([
		"reach\t1\tgullhaven\t2",
		"reach\t1\tgullhaven\t3",
	]))
	runtime.tick(0)
	assert_eq(runtime.rumors.reach_level("1", &"gullhaven"), 2)
	assert_eq(runtime.scheduler().carry_tokens("rumor"), PackedStringArray([
		"reach\t1\tgullhaven\t3",
	]))
	runtime.tick(0)
	assert_eq(runtime.rumors.reach_level("1", &"gullhaven"), 3)
	assert_eq(runtime.scheduler().carry("rumor"), 0)
	var levels: Array = []
	for row in _rows(runtime, "rumor_reach"):
		levels.append(int(row["level"]))
	assert_eq(levels, [1, 2, 3])
	assert_eq(_rows(runtime, "rumor_hop").size(), 0)


func test_a_place_read_as_precise_stops_new_rises() -> void:
	var runtime := _arm(_boot(4))
	runtime.config().scheduler_work_per_tick = 0
	runtime.config().scheduler_tick_minutes = 60
	_whisper(runtime)
	runtime.tick(60)
	assert_eq(runtime.now_minutes(), 60)
	assert_eq(runtime.rumors.reach_level("1", &"gullhaven"), 0)
	assert_eq(runtime.scheduler().carry_tokens("rumor"), PackedStringArray([
		"reach\t1\tgullhaven\t1",
	]))
	_host(runtime).spatial.set_precision(&"gullhaven", &"precise")
	_one_unit(runtime)
	runtime.config().scheduler_tick_minutes = 1
	runtime.trace.enabled = true
	runtime.tick(0)
	assert_eq(runtime.rumors.reach_level("1", &"gullhaven"), 1)
	runtime.tick(60)
	assert_eq(runtime.now_minutes(), 120)
	assert_eq(runtime.rumors.reach_level("1", &"gullhaven"), 1)
	assert_eq(runtime.scheduler().carry("rumor"), 0)
	assert_eq(_rows(runtime, "rumor_reach").size(), 1)


func test_zero_coarse_minutes_does_not_rise() -> void:
	var runtime := _arm(_boot(4))
	runtime.config().rumor_coarse_minutes = 0
	runtime.trace.enabled = true
	_whisper(runtime)
	runtime.tick(120)
	assert_eq(runtime.rumors.reach_level("1", &"gullhaven"), 0)
	assert_eq(runtime.scheduler().carry("rumor"), 0)
	assert_eq(_rows(runtime, "rumor_reach").size(), 0)
	assert_null(_belief(runtime, "dock_hand"))
	assert_eq(_rows(runtime, "rumor_materialize").size(), 0)


func test_precise_places_still_hop_and_a_coarse_listener_does_not() -> void:
	var precise := _boot(4)
	_policy(precise, 1, 1.0)
	_link(precise, "line_fisher", "dock_hand")
	_whisper(precise)
	precise.tick(0)
	assert_eq(precise.rumors.reach_level("1", &"gullhaven"), -1)
	assert_eq(precise.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"), &"stolen")
	assert_null(precise.facts.get_in(&"harbor.toll_fate", &"known/dock_hand"))

	var mixed := _boot(4)
	_policy(mixed, 2, 1.0)
	_link(mixed, "line_fisher", "dock_hand")
	_link(mixed, "line_fisher", "net_mender")
	_link(mixed, "dock_hand", "ferry_master")
	var host := _host(mixed)
	host.spatial.set_place(&"dock_hand", &"harbor_bar")
	host.spatial.set_precision(&"harbor_bar", &"coarse")
	mixed.trace.enabled = true
	_whisper(mixed)
	mixed.tick(0)
	assert_eq(mixed.rumors.reach_level("1", &"gullhaven"), -1)
	assert_eq(mixed.rumors.reach_level("1", &"harbor_bar"), -1)
	assert_null(mixed.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"))
	assert_null(mixed.facts.get_in(&"harbor.toll_fate", &"believed/ferry_master"))
	assert_eq(mixed.facts.get_in(&"harbor.toll_fate", &"believed/net_mender"), &"stolen")
	var reasons := {}
	for row in _rows(mixed, "rumor_hop"):
		reasons[String(row["to"])] = String(row["reason"])
	assert_eq(String(reasons["dock_hand"]), "coarse")
	assert_eq(String(reasons["net_mender"]), "pass")
	assert_false(reasons.has("ferry_master"))


func test_trace_lines_filter_and_stay_quiet_when_off() -> void:
	var quiet := _arm(_boot(4))
	_whisper(quiet)
	for _minute in WyrdRumor.REACH_FULL * 60:
		quiet.tick(1)
	assert_eq(quiet.trace.events.size(), 0)
	assert_eq(quiet.rumors.reach_level("1", &"gullhaven"), WyrdRumor.REACH_FULL)
	assert_eq(_belief(quiet, "dock_hand"), &"stolen")
	_belief(quiet, "dock_hand")
	assert_eq(quiet.trace.events.size(), 0)
	assert_null(quiet.facts.get_in(&"harbor.toll_fate", &"known/dock_hand"))

	var listener := _arm(_boot(4))
	listener.trace.enabled = true
	listener.trace.prefix = "dock_hand"
	_whisper(listener)
	listener.tick(60)
	_belief(listener, "dock_hand")
	assert_eq(_rows(listener, "rumor_reach").size(), 0)
	var heard := _rows(listener, "rumor_materialize")
	assert_gt(heard.size(), 0)
	for row in listener.trace.events:
		var kind := String(row.get("kind", ""))
		if kind != "rumor_materialize" and kind != "rumor_reach":
			continue
		assert_eq(String(row["who"]), "dock_hand")

	var place := _arm(_boot(4))
	place.trace.enabled = true
	place.trace.prefix = "gullhaven"
	_whisper(place)
	place.tick(60)
	_belief(place, "dock_hand")
	assert_eq(_rows(place, "rumor_materialize").size(), 0)
	var rose := _rows(place, "rumor_reach")
	assert_eq(rose.size(), 1)
	assert_eq(String(rose[0]["who"]), "gullhaven")
	assert_eq(String(rose[0]["path"]), "harbor_toll")

	var policy := _arm(_boot(4))
	policy.trace.enabled = true
	policy.trace.prefix = "harbor_toll"
	_whisper(policy)
	policy.tick(60)
	_belief(policy, "dock_hand")
	assert_eq(_rows(policy, "rumor_reach").size(), 1)
	assert_eq(_rows(policy, "rumor_materialize").size(), 1)
	assert_eq(String(_rows(policy, "rumor_reach")[0]["path"]), "harbor_toll")
	assert_eq(String(_rows(policy, "rumor_materialize")[0]["path"]), "harbor_toll")


func test_load_drops_reach_and_keeps_a_written_belief() -> void:
	var runtime := _arm(_boot(4))
	_host(runtime).spatial.set_place(&"ferry_master", &"gullhaven")
	runtime.trace.enabled = true
	_whisper(runtime)
	for _minute in WyrdRumor.REACH_FULL * 60:
		runtime.tick(1)
	assert_eq(_belief(runtime, "dock_hand"), &"stolen")
	assert_null(runtime.facts.get_in(&"harbor.toll_fate", &"believed/ferry_master"))
	var saved := runtime.save_state()
	assert_eq(int(saved["schema_version"]), 2)
	assert_false(saved.has("reach"))
	assert_false(saved.has("rumor"))
	assert_eq(JSON.stringify(saved).find("reach\t"), -1)
	var loaded := _boot(1)
	_policy(loaded, 1, 1.0)
	var host := _host(loaded)
	host.spatial.set_precision(&"gullhaven", &"coarse")
	host.spatial.set_place(&"dock_hand", &"gullhaven")
	host.spatial.set_place(&"ferry_master", &"gullhaven")
	loaded.trace.enabled = true
	var report := loaded.load_state(saved)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(loaded.rumors.reach_level("1", &"gullhaven"), -1)
	assert_eq(loaded.scheduler().carry("rumor"), 0)
	assert_eq(_rows(loaded, "rumor_reach").size(), 0)
	assert_eq(_rows(loaded, "rumor_materialize").size(), 0)
	assert_eq(loaded.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"), &"stolen")
	assert_null(_belief(loaded, "ferry_master"))
	assert_eq(_rows(loaded, "rumor_materialize").size(), 0)
	for _step in 5:
		loaded.tick(60)
	assert_eq(loaded.rumors.reach_level("1", &"gullhaven"), -1)
	assert_null(loaded.facts.get_in(&"harbor.toll_fate", &"believed/ferry_master"))
	assert_eq(_rows(loaded, "rumor_reach").size(), 0)
	assert_eq(_rows(loaded, "rumor_materialize").size(), 0)
	assert_eq(loaded.facts.get(&"harbor.toll_fate"), &"lost_at_sea")
	assert_null(loaded.facts.get_in(&"harbor.toll_fate", &"known/dock_hand"))


func test_new_game_drops_reach_and_keeps_the_policy() -> void:
	var runtime := _arm(_boot(4))
	_whisper(runtime)
	runtime.tick(60)
	assert_eq(runtime.rumors.reach_level("1", &"gullhaven"), 1)
	runtime.start_new_game(9)
	assert_eq(runtime.rumors.reach_level("1", &"gullhaven"), -1)
	assert_eq(runtime.scheduler().carry("rumor"), 0)
	runtime.facts.set(&"harbor.toll_fate", &"lost_at_sea")
	_whisper(runtime)
	runtime.tick(60)
	assert_eq(runtime.rumors.reach_level("1", &"gullhaven"), 1)
	assert_eq(runtime.facts.get(&"harbor.toll_fate"), &"lost_at_sea")


func _over(fps: int) -> WyrdRuntime:
	var runtime := _arm(_boot(11))
	runtime.trace.enabled = true
	_whisper(runtime)
	runtime.trace.clear()
	if fps < 0:
		runtime.tick(0)
	elif fps == 0:
		runtime.tick(60)
	else:
		for _frame in 60 * fps:
			runtime.tick(1.0 / float(fps))
	return runtime


func _arm(runtime: WyrdRuntime) -> WyrdRuntime:
	_policy(runtime, 1, 1.0)
	var host := _host(runtime)
	host.spatial.set_precision(&"gullhaven", &"coarse")
	host.spatial.set_place(&"dock_hand", &"gullhaven")
	return runtime


func _policy(runtime: WyrdRuntime, hops: int, chance: float) -> void:
	var policy := WyrdRumorPolicy.new()
	policy.id = &"harbor_toll"
	policy.kinds = PackedStringArray(["friend"])
	policy.max_hops = hops
	policy.pass_chance = chance
	runtime.register_rumor_policy(policy)


func _link(runtime: WyrdRuntime, source: String, target: String) -> void:
	runtime.social.set_kind(StringName(source), StringName(target), &"friend")


func _whisper(runtime: WyrdRuntime) -> void:
	runtime.perception_claim("harbor.toll_fate", &"stolen")
	runtime.deeds.record(&"whispered", &"line_fisher", &"", &"gullhaven")
	runtime.clear_perception_claim()


func _one_unit(runtime: WyrdRuntime) -> void:
	runtime.config().scheduler_work_per_tick = 1
	runtime.config().scheduler_share_waits = 0
	runtime.config().scheduler_share_rumor = 1
	runtime.config().scheduler_share_publish = 0
	runtime.config().scheduler_share_cache = 0


func _boot(seed_value: int) -> WyrdRuntime:
	var path := "user://wyrd_m8_aggregate_%d.wyrd" % _PLAIN.hash()
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file)
	file.store_string(_PLAIN)
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	runtime.set_meta(&"host", host)
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(seed_value)
	runtime.facts.set(&"harbor.toll_fate", &"lost_at_sea")
	return runtime


func _host(runtime: WyrdRuntime) -> WyrdFakeHost:
	return runtime.get_meta(&"host") as WyrdFakeHost


func _belief(runtime: WyrdRuntime, person: String) -> Variant:
	runtime.eval_bool(_compile(runtime, "belief(%s, harbor.toll_fate) == stolen" % person))
	return runtime.facts.get_in(&"harbor.toll_fate", StringName("believed/%s" % person))


func _believes(runtime: WyrdRuntime, person: String) -> bool:
	return runtime.eval_bool(_compile(runtime, "believes(%s, harbor.toll_fate)" % person))


func _compile(runtime: WyrdRuntime, text: String) -> WyrdCompiledCondition:
	var diagnostics := WyrdDiagnostics.new()
	var compiled := WyrdCondition.new().compile(
		text,
		runtime.content().schema,
		diagnostics,
		"sample.wyrd",
		1,
		1
	)
	assert_false(diagnostics.has_errors(), "%s %s" % [text, diagnostics.format()])
	return compiled


func _manual(seed_value: int, deed_id: String, person: String, level: int, bucket: int) -> bool:
	var chance := clampf(float(level) / float(WyrdRumor.REACH_FULL), 0.0, 1.0)
	var key := StringName("materialize\t%s\tgullhaven\t%s\t%d" % [deed_id, person, level])
	return WyrdRng.for_decision(seed_value, &"rumor", key, bucket).randf() < chance


func _seed_for(accept_first: bool) -> int:
	for seed_value in range(1, 400):
		if _manual(seed_value, "1", "dock_hand", 1, 60) == accept_first:
			return seed_value
	push_error("no seed in 1..399")
	return 1


func _rows(runtime: WyrdRuntime, kind: String) -> Array:
	var rows: Array = []
	for row in runtime.trace.events:
		if String(row.get("kind", "")) == kind:
			rows.append(row)
	return rows

