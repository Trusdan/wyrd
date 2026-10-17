extends GutTest

## Per-hop rumor mutations. The deed row stays. believed/ holds the copy.


const _PLAIN := """
language 1
facts
  harbor.toll_fate : symbol stored
quest harbor_guild "The Harbor Guild"
  stage post
"""


func test_a_kept_roll_matches_the_hash_and_the_deed_stays() -> void:
	var first := _spread(11, 0.5, Callable(self, &"_waive"))
	var second := _spread(11, 0.5, Callable(self, &"_waive"))
	assert_eq(JSON.stringify(_mutate_state(first)), JSON.stringify(_mutate_state(second)))
	var kept := _manual(11, "line_fisher", "dock_hand", 1, "harbor.toll_fate", 0, 0.5, 0)
	var lines := _rows(first, "rumor_mutate")
	assert_eq(lines.size(), 1)
	assert_eq(String(lines[0]["who"]), "dock_hand")
	assert_eq(String(lines[0]["listener"]), "dock_hand")
	assert_eq(String(lines[0]["speaker"]), "line_fisher")
	assert_eq(String(lines[0]["path"]), "harbor_toll")
	assert_eq(String(lines[0]["key"]), "harbor.toll_fate")
	assert_eq(String(lines[0]["field"]), "harbor.toll_fate")
	assert_eq(int(lines[0]["hop"]), 1)
	assert_eq(String(lines[0]["kept"]), "true" if kept else "false")
	assert_eq(String(lines[0]["result"]), "keep" if kept else "mutate")
	assert_eq(String(lines[0]["value"]), "stolen" if kept else "waived")
	assert_eq(first.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"), &"stolen" if kept else &"waived")
	assert_null(first.facts.get_in(&"harbor.toll_fate", &"known/dock_hand"))
	assert_eq(first.facts.get(&"harbor.toll_fate"), &"lost_at_sea")
	_assert_deed(first)
	var other := _spread(29, 0.5, Callable(self, &"_waive"))
	var other_kept := _manual(29, "line_fisher", "dock_hand", 1, "harbor.toll_fate", 0, 0.5, 0)
	assert_eq(String(_rows(other, "rumor_mutate")[0]["kept"]), "true" if other_kept else "false")


func test_the_next_hop_hears_the_mutated_copy() -> void:
	var runtime := _boot(4)
	_policy(runtime, 2, 1.0, [_change("harbor.toll_fate", Callable(self, &"_retell"), Callable(self, &"_keep_none"))])
	_link(runtime, "line_fisher", "dock_hand")
	_link(runtime, "dock_hand", "ferry_master")
	runtime.trace.enabled = true
	_whisper(runtime)
	runtime.tick(0)
	assert_eq(runtime.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"), &"waived")
	assert_eq(runtime.facts.get_in(&"harbor.toll_fate", &"believed/ferry_master"), &"paid")
	assert_null(runtime.facts.get_in(&"harbor.toll_fate", &"known/dock_hand"))
	assert_null(runtime.facts.get_in(&"harbor.toll_fate", &"known/ferry_master"))
	assert_eq(runtime.facts.get(&"harbor.toll_fate"), &"lost_at_sea")
	_assert_deed(runtime)
	var hops: Array = []
	for row in _rows(runtime, "rumor_mutate"):
		hops.append(int(row["hop"]))
	assert_eq(hops, [1, 2])
	assert_eq(String(_rows(runtime, "rumor_mutate")[1]["speaker"]), "dock_hand")
	assert_eq(String(_rows(runtime, "rumor_mutate")[1]["value"]), "paid")


func test_a_drop_does_not_write_or_continue() -> void:
	var runtime := _boot(4)
	_policy(runtime, 2, 1.0, [_change("harbor.toll_fate", "drop", Callable(self, &"_keep_none"))])
	_link(runtime, "line_fisher", "dock_hand")
	_link(runtime, "dock_hand", "ferry_master")
	runtime.trace.enabled = true
	_whisper(runtime)
	runtime.tick(0)
	assert_null(runtime.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"))
	assert_null(runtime.facts.get_in(&"harbor.toll_fate", &"believed/ferry_master"))
	assert_null(runtime.facts.get_in(&"harbor.toll_fate", &"known/dock_hand"))
	assert_eq(runtime.facts.get(&"harbor.toll_fate"), &"lost_at_sea")
	assert_eq(runtime.scheduler().carry("rumor"), 0)
	var lines := _rows(runtime, "rumor_mutate")
	assert_eq(lines.size(), 1)
	assert_eq(String(lines[0]["result"]), "drop")
	assert_eq(String(lines[0]["kept"]), "false")
	assert_eq(String(lines[0]["value"]), "")
	assert_eq(String(_rows(runtime, "rumor_adopt")[0]["accepted"]), "false")
	_assert_deed(runtime)


func test_two_mutations_run_in_order_on_the_copy() -> void:
	var runtime := _boot(4)
	var steps: Array = [
		_change("harbor.toll_fate", Callable(self, &"_retell"), Callable(self, &"_keep_none")),
		_change("harbor.toll_fate", Callable(self, &"_retell"), Callable(self, &"_keep_none")),
	]
	_policy(runtime, 1, 1.0, steps)
	_link(runtime, "line_fisher", "dock_hand")
	runtime.trace.enabled = true
	_whisper(runtime)
	runtime.tick(0)
	assert_eq(runtime.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"), &"paid")
	var lines := _rows(runtime, "rumor_mutate")
	assert_eq(lines.size(), 2)
	assert_eq(String(lines[0]["value"]), "waived")
	assert_eq(String(lines[1]["value"]), "paid")
	assert_eq(String(lines[0]["result"]), "mutate")
	assert_eq(runtime.facts.get(&"harbor.toll_fate"), &"lost_at_sea")
	_assert_deed(runtime)


func test_a_full_keep_and_a_foreign_field_leave_the_claim() -> void:
	var kept := _boot(4)
	_policy(kept, 1, 1.0, [_change("harbor.toll_fate", Callable(self, &"_waive"), Callable(self, &"_keep_all"))])
	_link(kept, "line_fisher", "dock_hand")
	kept.trace.enabled = true
	_whisper(kept)
	kept.tick(0)
	assert_eq(kept.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"), &"stolen")
	assert_eq(String(_rows(kept, "rumor_mutate")[0]["result"]), "keep")
	assert_eq(String(_rows(kept, "rumor_mutate")[0]["kept"]), "true")

	var skipped := _boot(4)
	_policy(skipped, 1, 1.0, [_change("ferry.toll_coins", Callable(self, &"_waive"), Callable(self, &"_keep_none"))])
	_link(skipped, "line_fisher", "dock_hand")
	skipped.trace.enabled = true
	_whisper(skipped)
	skipped.tick(0)
	assert_eq(skipped.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"), &"stolen")
	assert_eq(_rows(skipped, "rumor_mutate").size(), 0)
	assert_eq(skipped.facts.get(&"harbor.toll_fate"), &"lost_at_sea")


func test_a_rejected_hop_and_a_coarse_listener_do_not_mutate() -> void:
	var cold := _boot(4)
	_policy(cold, 2, 1.0, [_change("harbor.toll_fate", Callable(self, &"_waive"), Callable(self, &"_keep_none"))])
	_link(cold, "line_fisher", "dock_hand")
	_link(cold, "dock_hand", "ferry_master")
	cold.social.set_baseline(&"dock_hand", &"line_fisher", &"affinity", -1000.0)
	cold.trace.enabled = true
	_whisper(cold)
	cold.tick(0)
	assert_eq(_rows(cold, "rumor_mutate").size(), 0)
	assert_null(cold.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"))
	assert_null(cold.facts.get_in(&"harbor.toll_fate", &"believed/ferry_master"))
	assert_eq(String(_rows(cold, "rumor_adopt")[0]["accepted"]), "false")

	var mixed := _boot(4)
	_policy(mixed, 2, 1.0, [_change("harbor.toll_fate", Callable(self, &"_waive"), Callable(self, &"_keep_none"))])
	_link(mixed, "line_fisher", "dock_hand")
	_link(mixed, "line_fisher", "net_mender")
	_link(mixed, "dock_hand", "ferry_master")
	var host := _host(mixed)
	host.spatial.set_place(&"dock_hand", &"harbor_bar")
	host.spatial.set_precision(&"harbor_bar", &"coarse")
	mixed.trace.enabled = true
	_whisper(mixed)
	mixed.tick(0)
	assert_null(mixed.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"))
	assert_null(mixed.facts.get_in(&"harbor.toll_fate", &"believed/ferry_master"))
	assert_eq(mixed.facts.get_in(&"harbor.toll_fate", &"believed/net_mender"), &"waived")
	var heard: Array = []
	for row in _rows(mixed, "rumor_mutate"):
		heard.append(String(row["who"]))
	assert_eq(heard, ["net_mender"])


func test_thirty_and_one_forty_four_fps_match() -> void:
	var slow := _over(30)
	var fast := _over(144)
	var whole := _over(0)
	var flushed := _over(-1)
	assert_eq(slow.now_minutes(), 60)
	assert_eq(fast.now_minutes(), 60)
	assert_eq(whole.now_minutes(), 60)
	assert_eq(flushed.now_minutes(), 0)
	assert_eq(JSON.stringify(_mutate_state(slow)), JSON.stringify(_mutate_state(fast)))
	assert_eq(JSON.stringify(_mutate_state(slow)), JSON.stringify(_mutate_state(whole)))
	assert_eq(JSON.stringify(_rows(slow, "rumor_mutate")), JSON.stringify(_rows(flushed, "rumor_mutate")))
	assert_eq(
		slow.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"),
		flushed.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand")
	)
	assert_null(slow.facts.get_in(&"harbor.toll_fate", &"known/dock_hand"))
	assert_eq(slow.facts.get(&"harbor.toll_fate"), &"lost_at_sea")
	_assert_deed(slow)


func test_materialize_uses_the_reach_level_as_the_hop() -> void:
	var runtime := _coarse(_boot(4))
	_policy(runtime, 1, 1.0, [_change("harbor.toll_fate", Callable(self, &"_waive"), Callable(self, &"_keep_half"))])
	runtime.trace.enabled = true
	_whisper(runtime)
	for _minute in WyrdRumor.REACH_FULL * 60:
		runtime.tick(1)
	assert_eq(runtime.rumors.reach_level("1", &"gullhaven"), WyrdRumor.REACH_FULL)
	_ask(runtime, "dock_hand")
	var kept := _manual(4, "gullhaven", "dock_hand", WyrdRumor.REACH_FULL, "harbor.toll_fate", 0, 0.5, 240)
	var lines := _rows(runtime, "rumor_mutate")
	assert_eq(lines.size(), 1)
	assert_eq(int(lines[0]["hop"]), WyrdRumor.REACH_FULL)
	assert_eq(String(lines[0]["speaker"]), "gullhaven")
	assert_eq(String(lines[0]["who"]), "dock_hand")
	assert_eq(String(lines[0]["path"]), "harbor_toll")
	assert_eq(String(lines[0]["kept"]), "true" if kept else "false")
	assert_eq(runtime.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"), &"stolen" if kept else &"waived")
	assert_null(runtime.facts.get_in(&"harbor.toll_fate", &"known/dock_hand"))
	assert_eq(runtime.facts.get(&"harbor.toll_fate"), &"lost_at_sea")
	_assert_deed(runtime)
	_ask(runtime, "dock_hand")
	assert_eq(_rows(runtime, "rumor_mutate").size(), 1)


func test_aggregate_frames_match_and_a_drop_is_once() -> void:
	var slow := _coarse_over(30)
	var fast := _coarse_over(144)
	var whole := _coarse_over(0)
	_ask(slow, "dock_hand")
	_ask(fast, "dock_hand")
	_ask(whole, "dock_hand")
	assert_eq(JSON.stringify(_rows(slow, "rumor_mutate")), JSON.stringify(_rows(fast, "rumor_mutate")))
	assert_eq(JSON.stringify(_rows(slow, "rumor_mutate")), JSON.stringify(_rows(whole, "rumor_mutate")))
	assert_eq(
		slow.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"),
		fast.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand")
	)
	assert_eq(slow.facts.get(&"harbor.toll_fate"), &"lost_at_sea")

	var dropped := _coarse(_boot(4))
	_policy(dropped, 1, 1.0, [_change("harbor.toll_fate", "drop", Callable(self, &"_keep_none"))])
	dropped.trace.enabled = true
	_whisper(dropped)
	for _minute in WyrdRumor.REACH_FULL * 60:
		dropped.tick(1)
	_ask(dropped, "dock_hand")
	assert_null(dropped.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"))
	assert_eq(String(_rows(dropped, "rumor_mutate")[0]["result"]), "drop")
	assert_eq(String(_rows(dropped, "rumor_mutate")[0]["speaker"]), "gullhaven")
	assert_eq(int(_rows(dropped, "rumor_mutate")[0]["hop"]), WyrdRumor.REACH_FULL)
	assert_eq(String(_rows(dropped, "rumor_materialize")[0]["accepted"]), "false")
	_ask(dropped, "dock_hand")
	assert_eq(_rows(dropped, "rumor_mutate").size(), 1)
	assert_eq(dropped.facts.get(&"harbor.toll_fate"), &"lost_at_sea")
	_assert_deed(dropped)


func test_trace_lines_filter_and_stay_quiet_when_off() -> void:
	var quiet := _boot(4)
	_policy(quiet, 1, 1.0, [_change("harbor.toll_fate", Callable(self, &"_waive"), Callable(self, &"_keep_none"))])
	_link(quiet, "line_fisher", "dock_hand")
	_whisper(quiet)
	quiet.tick(0)
	assert_eq(quiet.trace.events.size(), 0)
	assert_eq(quiet.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"), &"waived")

	var runtime := _boot(4)
	_policy(runtime, 1, 1.0, [_change("harbor.toll_fate", Callable(self, &"_waive"), Callable(self, &"_keep_none"))])
	_link(runtime, "line_fisher", "dock_hand")
	_link(runtime, "line_fisher", "ferry_master")
	runtime.trace.enabled = true
	runtime.trace.prefix = "dock_hand"
	_whisper(runtime)
	runtime.tick(0)
	var lines := _rows(runtime, "rumor_mutate")
	assert_eq(lines.size(), 1)
	assert_eq(String(lines[0]["who"]), "dock_hand")
	for row in runtime.trace.events:
		if String(row.get("kind", "")) != "rumor_mutate":
			continue
		assert_eq(String(row["who"]), "dock_hand")

	var policy := _boot(4)
	_policy(policy, 1, 1.0, [_change("harbor.toll_fate", Callable(self, &"_waive"), Callable(self, &"_keep_none"))])
	_link(policy, "line_fisher", "dock_hand")
	policy.trace.enabled = true
	policy.trace.prefix = "harbor_toll"
	_whisper(policy)
	policy.tick(0)
	assert_eq(_rows(policy, "rumor_mutate").size(), 1)
	assert_eq(String(_rows(policy, "rumor_mutate")[0]["path"]), "harbor_toll")


func test_load_keeps_the_copy_and_continues() -> void:
	var runtime := _boot(4)
	_one_unit(runtime)
	_policy(runtime, 1, 1.0, [_change("harbor.toll_fate", Callable(self, &"_waive"), Callable(self, &"_keep_none"))])
	_link(runtime, "line_fisher", "dock_hand")
	_link(runtime, "line_fisher", "ferry_master")
	runtime.trace.enabled = true
	_whisper(runtime)
	runtime.tick(0)
	assert_eq(runtime.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"), &"waived")
	assert_gt(runtime.scheduler().carry("rumor"), 0)
	var saved := runtime.save_state()
	assert_eq(int(saved["schema_version"]), 3)
	assert_false(saved.has("mutations"))
	assert_eq(JSON.stringify(saved).find("mutate\t"), -1)
	var raw := JSON.stringify(saved)
	assert_true(raw.contains("\"t\":\"symbol\""))
	assert_true(raw.contains("\"v\":\"waived\""))
	var loaded := _boot(1)
	_policy(loaded, 1, 1.0, [_change("harbor.toll_fate", Callable(self, &"_waive"), Callable(self, &"_keep_none"))])
	loaded.trace.enabled = true
	var report := loaded.load_state(JSON.parse_string(raw))
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(_rows(loaded, "rumor_mutate").size(), 0)
	assert_eq(loaded.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"), &"waived")
	assert_null(loaded.facts.get_in(&"harbor.toll_fate", &"believed/ferry_master"))
	loaded.tick(0)
	assert_eq(loaded.facts.get_in(&"harbor.toll_fate", &"believed/ferry_master"), &"waived")
	assert_eq(_rows(loaded, "rumor_mutate").size(), 1)
	assert_eq(String(_rows(loaded, "rumor_mutate")[0]["listener"]), "ferry_master")
	assert_eq(String(_rows(loaded, "rumor_mutate")[0]["result"]), "mutate")
	assert_eq(loaded.facts.get(&"harbor.toll_fate"), &"lost_at_sea")
	_assert_deed(loaded)


func test_the_registered_mutation_is_a_copy() -> void:
	var runtime := _boot(4)
	var spec := _change("harbor.toll_fate", Callable(self, &"_waive"), Callable(self, &"_keep_none"))
	_policy(runtime, 1, 1.0, [spec])
	spec["to"] = "drop"
	_link(runtime, "line_fisher", "dock_hand")
	_whisper(runtime)
	runtime.tick(0)
	assert_eq(runtime.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"), &"waived")
	assert_eq(runtime.facts.get(&"harbor.toll_fate"), &"lost_at_sea")


func _spread(seed_value: int, chance: float, change: Callable) -> WyrdRuntime:
	var runtime := _boot(seed_value)
	_policy(runtime, 1, 1.0, [_change("harbor.toll_fate", change, _keep_fixed(chance))])
	_link(runtime, "line_fisher", "dock_hand")
	runtime.trace.enabled = true
	_whisper(runtime)
	runtime.tick(0)
	return runtime


func _over(fps: int) -> WyrdRuntime:
	var runtime := _boot(11)
	_policy(runtime, 1, 1.0, [_change("harbor.toll_fate", Callable(self, &"_waive"), Callable(self, &"_keep_half"))])
	_link(runtime, "line_fisher", "dock_hand")
	runtime.trace.enabled = true
	_whisper(runtime)
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


func _coarse_over(fps: int) -> WyrdRuntime:
	var runtime := _coarse(_boot(11))
	_policy(runtime, 1, 1.0, [_change("harbor.toll_fate", Callable(self, &"_waive"), Callable(self, &"_keep_none"))])
	runtime.trace.enabled = true
	_whisper(runtime)
	runtime.trace.clear()
	if fps == 0:
		runtime.tick(60)
	else:
		for _frame in 60 * fps:
			runtime.tick(1.0 / float(fps))
	return runtime


func _coarse(runtime: WyrdRuntime) -> WyrdRuntime:
	var host := _host(runtime)
	host.spatial.set_precision(&"gullhaven", &"coarse")
	host.spatial.set_place(&"dock_hand", &"gullhaven")
	return runtime


func _policy(runtime: WyrdRuntime, hops: int, chance: float, mutations: Array) -> void:
	var policy := WyrdRumorPolicy.new()
	policy.id = &"harbor_toll"
	policy.kinds = PackedStringArray(["friend"])
	policy.max_hops = hops
	policy.pass_chance = chance
	policy.mutations = mutations
	runtime.register_rumor_policy(policy)


func _change(field: String, to: Variant, keep: Callable) -> Dictionary:
	return {"field": field, "keep_chance_fn": keep, "to": to}


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
	var path := "user://wyrd_m8_mutate_%d.wyrd" % _PLAIN.hash()
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


func _ask(runtime: WyrdRuntime, person: String) -> void:
	runtime.eval_bool(_compile(runtime, "believes(%s, harbor.toll_fate)" % person))


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


func _assert_deed(runtime: WyrdRuntime) -> void:
	assert_eq(runtime.deeds.size(), 1)
	var row := runtime.deeds.row_at(0)
	assert_eq(row["verb"], &"whispered")
	assert_eq(row["actor"], &"line_fisher")
	assert_eq(row["place"], &"gullhaven")


func _manual(
	seed_value: int,
	from_who: String,
	to_who: String,
	hop_n: int,
	field: String,
	index: int,
	chance: float,
	bucket: int
) -> bool:
	var key := StringName("mutate\t1\t%s\t%s\t%d\t%s\t%d" % [from_who, to_who, hop_n, field, index])
	return WyrdRng.for_decision(seed_value, &"rumor", key, bucket).randf() < chance


func _mutate_state(runtime: WyrdRuntime) -> Dictionary:
	return {
		"belief": runtime.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"),
		"known": runtime.facts.get_in(&"harbor.toll_fate", &"known/dock_hand"),
		"lines": _rows(runtime, "rumor_mutate"),
		"world": String(runtime.facts.get(&"harbor.toll_fate")),
	}


func _rows(runtime: WyrdRuntime, kind: String) -> Array:
	var rows: Array = []
	for row in runtime.trace.events:
		if String(row.get("kind", "")) == kind:
			rows.append(row)
	return rows


func _keep_fixed(chance: float) -> Callable:
	_fixed_chance = chance
	return Callable(self, &"_keep_fixed_value")


func _keep_fixed_value(value: Variant, hop: int) -> float:
	if hop < 0 or value == null:
		return 1.0
	return _fixed_chance


func _keep_none(value: Variant, hop: int) -> float:
	if hop < 0 or value == null:
		return 1.0
	return 0.0


func _keep_all(value: Variant, hop: int) -> float:
	if hop < 0 or value == null:
		return 0.0
	return 1.0


func _keep_half(value: Variant, hop: int) -> float:
	if hop < 0 or value == null:
		return 0.0
	return 0.5


func _waive(value: Variant, hop: int) -> StringName:
	if hop < 0:
		return value
	return &"waived"


func _retell(value: Variant, hop: int) -> StringName:
	if hop < 1:
		return value
	if String(value) == "stolen":
		return &"waived"
	return &"paid"


var _fixed_chance: float = 1.0
