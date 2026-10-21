extends GutTest

## Precise rumor hops: one deed, one listener, believed only.


const _PLAIN := """
language 1
facts
  harbor.toll_fate : symbol stored
quest harbor_guild "The Harbor Guild"
  stage post
"""

const _REVEAL := """
language 1
facts
  harbor.toll_fate : symbol stored
quest harbor_guild "The Harbor Guild"
  stage post
    ~ record deed whispered(actor: line_fisher, place: gullhaven, witnesses: [dock_apprentice, net_mender], reveals: harbor.toll_fate, claim: stolen)
"""


func test_same_seed_matches_the_roll() -> void:
	var first := _one_listener(11, 0.5)
	var second := _one_listener(11, 0.5)
	assert_eq(JSON.stringify(_spread_state(first)), JSON.stringify(_spread_state(second)))
	var hops := _rows(first, "rumor_hop")
	assert_eq(hops.size(), 1)
	assert_eq(String(hops[0]["deed"]), "1")
	assert_eq(String(hops[0]["from"]), "line_fisher")
	assert_eq(String(hops[0]["to"]), "dock_hand")
	assert_eq(int(hops[0]["hop"]), 1)
	assert_eq(String(hops[0]["key"]), "harbor.toll_fate")
	assert_eq(String(hops[0]["path"]), "harbor_toll")
	var taken := WyrdRng.for_decision(11, &"rumor", &"1\tline_fisher\tdock_hand\t1", 0).randf() < 0.5
	assert_eq(String(hops[0]["taken"]), "true" if taken else "false")
	assert_eq(String(hops[0]["reason"]), "pass" if taken else "chance")
	if taken:
		assert_eq(first.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"), &"stolen")
		assert_eq(_rows(first, "rumor_adopt").size(), 1)
	else:
		assert_null(first.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"))
		assert_eq(_rows(first, "rumor_adopt").size(), 0)
	assert_null(first.facts.get_in(&"harbor.toll_fate", &"known/dock_hand"))
	assert_eq(first.facts.get(&"harbor.toll_fate"), &"lost_at_sea")
	var other := _one_listener(29, 0.5)
	var other_taken := WyrdRng.for_decision(29, &"rumor", &"1\tline_fisher\tdock_hand\t1", 0).randf() < 0.5
	assert_eq(String(_rows(other, "rumor_hop")[0]["taken"]), "true" if other_taken else "false")


func test_a_zero_chance_adopts_nobody() -> void:
	var runtime := _one_listener(11, 0.0)
	assert_eq(String(_rows(runtime, "rumor_hop")[0]["taken"]), "false")
	assert_eq(String(_rows(runtime, "rumor_hop")[0]["reason"]), "chance")
	assert_eq(_rows(runtime, "rumor_adopt").size(), 0)
	assert_null(runtime.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"))
	assert_eq(runtime.facts.get(&"harbor.toll_fate"), &"lost_at_sea")


func test_thirty_and_one_forty_four_fps_match() -> void:
	var slow := _spread_over(30)
	var fast := _spread_over(144)
	var whole := _spread_over(0)
	var flushed := _spread_over(-1)
	assert_eq(slow.now_minutes(), 60)
	assert_eq(fast.now_minutes(), 60)
	assert_eq(whole.now_minutes(), 60)
	assert_eq(flushed.now_minutes(), 0)
	assert_eq(JSON.stringify(_spread_state(slow)), JSON.stringify(_spread_state(fast)))
	assert_eq(JSON.stringify(_spread_state(slow)), JSON.stringify(_spread_state(whole)))
	assert_eq(JSON.stringify(_rows(slow, "rumor_hop")), JSON.stringify(_rows(flushed, "rumor_hop")))
	assert_eq(JSON.stringify(_rows(slow, "rumor_adopt")), JSON.stringify(_rows(flushed, "rumor_adopt")))
	assert_eq(_believers(slow), _believers(flushed))
	assert_eq(slow.scheduler().carry("rumor"), 0)
	assert_eq(fast.scheduler().carry("rumor"), 0)


func test_max_hops_stops_the_chain() -> void:
	var one := _chain_runtime(1)
	assert_eq(_believers(one), ["dock_hand"])
	assert_null(one.facts.get_in(&"harbor.toll_fate", &"known/dock_hand"))
	assert_eq(one.facts.get(&"harbor.toll_fate"), &"lost_at_sea")
	var two := _chain_runtime(2)
	assert_eq(_believers(two), ["dock_hand", "ferry_master"])
	assert_null(two.facts.get_in(&"harbor.toll_fate", &"believed/net_mender"))
	assert_null(two.facts.get_in(&"harbor.toll_fate", &"known/ferry_master"))
	var heard: Array[String] = []
	for row in _rows(two, "rumor_hop"):
		heard.append(String(row["to"]))
	assert_false(heard.has("net_mender"))


func test_adoption_matches_with_the_cache_off() -> void:
	var cached := _chain_runtime(2)
	var fresh := _boot(_PLAIN, 4)
	_policy(fresh, 2, 1.0)
	_chain(fresh)
	fresh.social.set_cache(false)
	_whisper(fresh, &"line_fisher")
	fresh.tick(0)
	assert_false(fresh.social.cache_enabled())
	assert_eq(_believers(cached), _believers(fresh))


func test_a_low_score_does_not_adopt_or_continue() -> void:
	var runtime := _boot(_PLAIN, 4)
	_policy(runtime, 3, 1.0)
	_chain(runtime)
	runtime.social.set_baseline(&"dock_hand", &"line_fisher", &"affinity", -1000.0)
	runtime.trace.enabled = true
	_whisper(runtime, &"line_fisher")
	runtime.tick(0)
	assert_null(runtime.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"))
	assert_null(runtime.facts.get_in(&"harbor.toll_fate", &"believed/ferry_master"))
	assert_null(runtime.facts.get_in(&"harbor.toll_fate", &"known/dock_hand"))
	assert_eq(runtime.facts.get(&"harbor.toll_fate"), &"lost_at_sea")
	var hops := _rows(runtime, "rumor_hop")
	assert_eq(hops.size(), 1)
	assert_eq(String(hops[0]["to"]), "dock_hand")
	assert_eq(String(hops[0]["taken"]), "true")
	assert_eq(String(hops[0]["reason"]), "pass")
	var adopted := _rows(runtime, "rumor_adopt")
	assert_eq(adopted.size(), 1)
	assert_eq(String(adopted[0]["accepted"]), "false")
	assert_eq(String(adopted[0]["listener"]), "dock_hand")
	assert_eq(String(adopted[0]["speaker"]), "line_fisher")
	assert_eq(String(adopted[0]["score"]), "0.0000")
	assert_eq(String(adopted[0]["key"]), "harbor.toll_fate")


func test_a_heard_rumor_believes_and_a_saw_witness_knows() -> void:
	var runtime := _boot(_REVEAL, 4)
	var host := _host(runtime)
	host.spatial.set_perception(&"dock_apprentice", &"saw")
	host.spatial.set_perception(&"net_mender", &"heard")
	_policy(runtime, 1, 1.0)
	_link(runtime, "line_fisher", "dock_hand")
	runtime.trace.enabled = true
	runtime.tick(0)
	assert_eq(runtime.facts.get(&"harbor.toll_fate"), &"lost_at_sea")
	assert_eq(runtime.facts.get_in(&"harbor.toll_fate", &"known/dock_apprentice"), &"stolen")
	assert_null(runtime.facts.get_in(&"harbor.toll_fate", &"believed/dock_apprentice"))
	assert_null(runtime.facts.get_in(&"harbor.toll_fate", &"known/net_mender"))
	assert_eq(runtime.facts.get_in(&"harbor.toll_fate", &"believed/net_mender"), &"stolen")
	assert_null(runtime.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"))
	assert_eq(runtime.deeds.witness_indexes(&"dock_apprentice").size(), 1)
	assert_eq(runtime.deeds.witness_indexes(&"net_mender").size(), 1)
	assert_eq(runtime.deeds.witness_indexes(&"dock_hand").size(), 0)
	assert_eq(runtime.scheduler().carry("rumor"), 1)
	runtime.tick(0)
	assert_eq(runtime.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"), &"stolen")
	assert_null(runtime.facts.get_in(&"harbor.toll_fate", &"known/dock_hand"))
	assert_eq(runtime.facts.get_in(&"harbor.toll_fate", &"known/dock_apprentice"), &"stolen")
	assert_null(runtime.facts.get_in(&"harbor.toll_fate", &"believed/line_fisher"))
	assert_null(runtime.facts.get_in(&"harbor.toll_fate", &"known/line_fisher"))
	assert_eq(runtime.facts.get(&"harbor.toll_fate"), &"lost_at_sea")
	var learned: Array[String] = []
	for row in _rows(runtime, "knowledge"):
		learned.append(String(row["who"]))
	assert_eq(learned, ["dock_apprentice"])
	var offered := _rows(runtime, "rumor_adopt")
	assert_eq(offered.size(), 1)
	assert_eq(String(offered[0]["listener"]), "dock_hand")
	assert_eq(String(offered[0]["speaker"]), "line_fisher")
	assert_eq(String(offered[0]["accepted"]), "true")
	assert_eq(String(offered[0]["path"]), "harbor_toll")


func test_in_flight_rumors_carry_in_order() -> void:
	var runtime := _boot(_PLAIN, 4)
	_one_unit(runtime)
	_policy(runtime, 1, 1.0)
	_link(runtime, "line_fisher", "net_mender")
	_link(runtime, "line_fisher", "ferry_master")
	_link(runtime, "line_fisher", "dock_hand")
	_whisper(runtime, &"line_fisher")
	assert_eq(runtime.scheduler().carry("rumor"), 3)
	var queued := runtime.scheduler().carry_tokens("rumor")
	assert_eq(_listener_of(queued[0]), "dock_hand")
	assert_eq(_listener_of(queued[1]), "ferry_master")
	assert_eq(_listener_of(queued[2]), "net_mender")
	runtime.tick(0)
	assert_eq(runtime.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"), &"stolen")
	assert_null(runtime.facts.get_in(&"harbor.toll_fate", &"believed/ferry_master"))
	assert_eq(runtime.scheduler().carry_tokens("rumor"), PackedStringArray([
		"1\tline_fisher\tferry_master\t1",
		"1\tline_fisher\tnet_mender\t1",
	]))
	runtime.tick(0)
	assert_eq(runtime.facts.get_in(&"harbor.toll_fate", &"believed/ferry_master"), &"stolen")
	assert_null(runtime.facts.get_in(&"harbor.toll_fate", &"believed/net_mender"))
	runtime.tick(0)
	assert_eq(runtime.facts.get_in(&"harbor.toll_fate", &"believed/net_mender"), &"stolen")
	assert_eq(runtime.scheduler().carry("rumor"), 0)
	assert_null(runtime.facts.get_in(&"harbor.toll_fate", &"known/net_mender"))


func test_load_keeps_the_in_flight_queue() -> void:
	var runtime := _boot(_PLAIN, 4)
	_one_unit(runtime)
	_policy(runtime, 1, 1.0)
	_link(runtime, "line_fisher", "dock_hand")
	_link(runtime, "line_fisher", "ferry_master")
	_whisper(runtime, &"line_fisher")
	runtime.tick(0)
	assert_eq(runtime.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"), &"stolen")
	assert_gt(runtime.scheduler().carry("rumor"), 0)
	var saved := runtime.save_state()
	assert_eq(int(saved["schema_version"]), 4)
	assert_false(saved.has("rumor"))
	assert_false(saved.has("rumors"))
	assert_true(_queue_has(saved, "rumor", "1\tline_fisher\tferry_master\t1"))
	var loaded := _boot(_PLAIN, 1)
	_policy(loaded, 1, 1.0)
	loaded.trace.enabled = true
	var parsed: Variant = JSON.parse_string(JSON.stringify(saved))
	var report := loaded.load_state(parsed)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(_rows(loaded, "rumor_hop").size(), 0)
	assert_eq(_rows(loaded, "rumor_adopt").size(), 0)
	assert_eq(loaded.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"), &"stolen")
	assert_null(loaded.facts.get_in(&"harbor.toll_fate", &"believed/ferry_master"))
	assert_true(_queue_has(loaded.save_state(), "rumor", "1\tline_fisher\tferry_master\t1"))
	loaded.tick(0)
	assert_eq(loaded.facts.get_in(&"harbor.toll_fate", &"believed/ferry_master"), &"stolen")
	assert_eq(_rows(loaded, "rumor_hop").size(), 1)
	assert_eq(String(_rows(loaded, "rumor_hop")[0]["to"]), "ferry_master")


func test_new_game_drops_flight_and_keeps_the_policy() -> void:
	var runtime := _boot(_PLAIN, 4)
	_policy(runtime, 1, 1.0)
	_link(runtime, "line_fisher", "dock_hand")
	_whisper(runtime, &"line_fisher")
	assert_eq(runtime.scheduler().carry("rumor"), 1)
	runtime.start_new_game(9)
	assert_eq(runtime.scheduler().carry("rumor"), 0)
	runtime.facts.set(&"harbor.toll_fate", &"lost_at_sea")
	_link(runtime, "line_fisher", "dock_hand")
	_whisper(runtime, &"line_fisher")
	runtime.tick(0)
	assert_eq(runtime.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"), &"stolen")
	assert_eq(runtime.facts.get(&"harbor.toll_fate"), &"lost_at_sea")


func test_coarse_places_do_not_spread() -> void:
	var blocked := _boot(_PLAIN, 4)
	_policy(blocked, 2, 1.0)
	_link(blocked, "line_fisher", "dock_hand")
	_host(blocked).spatial.set_precision(&"gullhaven", &"coarse")
	blocked.trace.enabled = true
	_whisper(blocked, &"line_fisher")
	blocked.tick(0)
	assert_eq(blocked.scheduler().carry("rumor"), 0)
	assert_eq(_rows(blocked, "rumor_hop").size(), 0)
	assert_null(blocked.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"))

	var mixed := _boot(_PLAIN, 4)
	_policy(mixed, 2, 1.0)
	_link(mixed, "line_fisher", "dock_hand")
	_link(mixed, "line_fisher", "net_mender")
	_link(mixed, "dock_hand", "ferry_master")
	var host := _host(mixed)
	host.spatial.set_place(&"dock_hand", &"harbor_bar")
	host.spatial.set_precision(&"harbor_bar", &"coarse")
	host.spatial.set_precision(&"gullhaven", &"precise")
	mixed.trace.enabled = true
	_whisper(mixed, &"line_fisher")
	mixed.tick(0)
	assert_null(mixed.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"))
	assert_null(mixed.facts.get_in(&"harbor.toll_fate", &"believed/ferry_master"))
	assert_eq(mixed.facts.get_in(&"harbor.toll_fate", &"believed/net_mender"), &"stolen")
	assert_null(mixed.facts.get_in(&"harbor.toll_fate", &"known/net_mender"))
	var reasons := {}
	for row in _rows(mixed, "rumor_hop"):
		reasons[String(row["to"])] = String(row["reason"])
	assert_eq(String(reasons["dock_hand"]), "coarse")
	assert_eq(String(reasons["net_mender"]), "pass")
	assert_false(reasons.has("ferry_master"))


func test_trace_lines_filter_and_stay_quiet_when_off() -> void:
	var quiet := _boot(_PLAIN, 4)
	_policy(quiet, 1, 1.0)
	_link(quiet, "line_fisher", "dock_hand")
	_whisper(quiet, &"line_fisher")
	quiet.tick(0)
	assert_eq(quiet.trace.events.size(), 0)
	assert_eq(quiet.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"), &"stolen")

	var runtime := _boot(_PLAIN, 4)
	_policy(runtime, 1, 1.0)
	_link(runtime, "line_fisher", "dock_hand")
	_link(runtime, "line_fisher", "ferry_master")
	runtime.trace.enabled = true
	runtime.trace.prefix = "dock_hand"
	_whisper(runtime, &"line_fisher")
	runtime.tick(0)
	var hops := _rows(runtime, "rumor_hop")
	assert_eq(hops.size(), 1)
	assert_eq(String(hops[0]["who"]), "dock_hand")
	assert_eq(String(hops[0]["speaker"]), "line_fisher")
	assert_eq(String(hops[0]["key"]), "harbor.toll_fate")
	for row in runtime.trace.events:
		var kind := String(row.get("kind", ""))
		if kind != "rumor_hop" and kind != "rumor_adopt":
			continue
		assert_eq(String(row["who"]), "dock_hand")


func test_the_first_policy_wins() -> void:
	var blocked := _boot(_PLAIN, 4)
	var stop := WyrdRumorPolicy.new()
	stop.id = &"stop"
	stop.kinds = PackedStringArray(["friend"])
	stop.max_hops = 0
	blocked.register_rumor_policy(stop)
	var later := WyrdRumorPolicy.new()
	later.id = &"later"
	later.kinds = PackedStringArray(["friend"])
	later.max_hops = 3
	blocked.register_rumor_policy(later)
	_link(blocked, "line_fisher", "dock_hand")
	_whisper(blocked, &"line_fisher")
	blocked.tick(0)
	assert_eq(blocked.scheduler().carry("rumor"), 0)
	assert_null(blocked.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"))

	var told := _boot(_PLAIN, 4)
	var only := WyrdRumorPolicy.new()
	only.id = &"told_only"
	only.kinds = PackedStringArray(["friend"])
	only.max_hops = 1
	only.verbs = PackedStringArray(["told"])
	told.register_rumor_policy(only)
	_link(told, "line_fisher", "dock_hand")
	_whisper(told, &"line_fisher")
	told.tick(0)
	assert_null(told.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"))
	told.perception_claim("harbor.toll_fate", &"stolen")
	told.deeds.record(&"told", &"line_fisher", &"", &"gullhaven")
	told.clear_perception_claim()
	told.tick(0)
	assert_eq(told.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"), &"stolen")


func test_no_policy_does_not_enqueue() -> void:
	var runtime := _boot(_PLAIN, 4)
	_link(runtime, "line_fisher", "dock_hand")
	_whisper(runtime, &"line_fisher")
	runtime.tick(0)
	assert_eq(runtime.scheduler().carry("rumor"), 0)
	assert_null(runtime.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"))
	assert_eq(runtime.facts.get(&"harbor.toll_fate"), &"lost_at_sea")


func test_a_listener_is_offered_once() -> void:
	var runtime := _boot(_PLAIN, 4)
	_policy(runtime, 1, 1.0)
	_link(runtime, "dock_apprentice", "dock_hand")
	_link(runtime, "line_fisher", "dock_hand")
	runtime.trace.enabled = true
	runtime.perception_claim("harbor.toll_fate", &"stolen")
	runtime.deeds.record(
		&"whispered",
		&"line_fisher",
		&"",
		&"gullhaven",
		PackedStringArray(),
		1.0,
		PackedStringArray(["dock_apprentice"])
	)
	runtime.clear_perception_claim()
	runtime.tick(0)
	var hops := _rows(runtime, "rumor_hop")
	assert_eq(hops.size(), 1)
	assert_eq(String(hops[0]["from"]), "dock_apprentice")
	assert_eq(String(hops[0]["to"]), "dock_hand")
	assert_eq(runtime.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"), &"stolen")
	assert_null(runtime.facts.get_in(&"harbor.toll_fate", &"believed/dock_apprentice"))
	assert_null(runtime.facts.get_in(&"harbor.toll_fate", &"known/dock_hand"))


func _one_listener(seed_value: int, chance: float) -> WyrdRuntime:
	var runtime := _boot(_PLAIN, seed_value)
	_policy(runtime, 1, chance)
	_link(runtime, "line_fisher", "dock_hand")
	runtime.trace.enabled = true
	_whisper(runtime, &"line_fisher")
	runtime.tick(0)
	return runtime


func _spread_over(fps: int) -> WyrdRuntime:
	var runtime := _boot(_PLAIN, 11)
	_policy(runtime, 2, 0.5)
	_link(runtime, "line_fisher", "dock_hand")
	_link(runtime, "line_fisher", "net_mender")
	_link(runtime, "dock_hand", "ferry_master")
	_link(runtime, "ferry_master", "dock_apprentice")
	runtime.trace.enabled = true
	_whisper(runtime, &"line_fisher")
	runtime.trace.clear()
	if fps < 0:
		runtime.tick(0)
	elif fps == 0:
		for _minute in 60:
			runtime.tick(1)
	else:
		for _frame in 60 * fps:
			runtime.tick(1.0 / float(fps))
	return runtime


func _chain_runtime(hops: int) -> WyrdRuntime:
	var runtime := _boot(_PLAIN, 4)
	_policy(runtime, hops, 1.0)
	_chain(runtime)
	runtime.trace.enabled = true
	_whisper(runtime, &"line_fisher")
	runtime.tick(0)
	return runtime


func _chain(runtime: WyrdRuntime) -> void:
	_link(runtime, "line_fisher", "dock_hand")
	_link(runtime, "dock_hand", "ferry_master")
	_link(runtime, "ferry_master", "net_mender")


func _policy(runtime: WyrdRuntime, hops: int, chance: float) -> void:
	var policy := WyrdRumorPolicy.new()
	policy.id = &"harbor_toll"
	policy.kinds = PackedStringArray(["friend"])
	policy.max_hops = hops
	policy.pass_chance = chance
	runtime.register_rumor_policy(policy)


func _link(runtime: WyrdRuntime, source: String, target: String) -> void:
	runtime.social.set_kind(StringName(source), StringName(target), &"friend")


func _whisper(runtime: WyrdRuntime, actor: StringName, place: StringName = &"gullhaven") -> void:
	runtime.perception_claim("harbor.toll_fate", &"stolen")
	runtime.deeds.record(&"whispered", actor, &"", place)
	runtime.clear_perception_claim()


func _one_unit(runtime: WyrdRuntime) -> void:
	runtime.config().scheduler_work_per_tick = 1
	runtime.config().scheduler_share_waits = 0
	runtime.config().scheduler_share_rumor = 1
	runtime.config().scheduler_share_publish = 0
	runtime.config().scheduler_share_cache = 0


func _boot(body: String, seed_value: int) -> WyrdRuntime:
	var path := "user://wyrd_m8_rumor_%d.wyrd" % body.hash()
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file)
	file.store_string(body)
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


func _people() -> PackedStringArray:
	return PackedStringArray([
		"dock_apprentice",
		"dock_hand",
		"ferry_master",
		"line_fisher",
		"net_mender",
	])


func _believers(runtime: WyrdRuntime) -> Array:
	var names: Array = []
	for person in _people():
		var value: Variant = runtime.facts.get_in(&"harbor.toll_fate", StringName("believed/%s" % person))
		if value != null:
			names.append(person)
	return names


func _layer(runtime: WyrdRuntime, layer: String) -> Dictionary:
	var out := {}
	for person in _people():
		var value: Variant = runtime.facts.get_in(&"harbor.toll_fate", StringName("%s/%s" % [layer, person]))
		if value != null:
			out[person] = String(value)
	return out


func _spread_state(runtime: WyrdRuntime) -> Dictionary:
	return {
		"adopts": _rows(runtime, "rumor_adopt"),
		"beliefs": _layer(runtime, "believed"),
		"carry": runtime.scheduler().carry_tokens("rumor"),
		"hops": _rows(runtime, "rumor_hop"),
		"known": _layer(runtime, "known"),
		"world": String(runtime.facts.get(&"harbor.toll_fate")),
	}


func _rows(runtime: WyrdRuntime, kind: String) -> Array:
	var rows: Array = []
	for row in runtime.trace.events:
		if String(row.get("kind", "")) == kind:
			rows.append(row)
	return rows


func _queue_has(data: Dictionary, queue: String, token: String) -> bool:
	var flight: Variant = data.get("flight", {})
	if not (flight is Dictionary):
		return false
	var scheduler: Variant = (flight as Dictionary).get("scheduler", {})
	if not (scheduler is Dictionary):
		return false
	var tokens: Variant = (scheduler as Dictionary).get(queue, [])
	return tokens is Array and (tokens as Array).has(token)


func _listener_of(token: String) -> String:
	var parts := token.split("\t")
	if parts.size() != 4:
		return ""
	return parts[2]
