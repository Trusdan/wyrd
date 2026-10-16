extends GutTest

const _Harness := preload("res://tests/scenario/s2c_harness.gd")

## Each belief-backed unwilling and barred condition flips on a write and a retract.
const MATRIX_SIZE := 6

const _FATE := &"harbor.toll_fate"


func test_matrix_size_is_each_condition_and_direction() -> void:
	var cases := _cases()
	assert_eq(cases.size(), MATRIX_SIZE)
	var seen := {}
	for case in cases:
		var key := "%s|%s" % [case["slot"], case["direction"]]
		assert_false(seen.has(key), key)
		seen[key] = true
	assert_eq(seen.size(), MATRIX_SIZE)


func test_each_condition_flips_when_the_belief_is_written_or_retracted() -> void:
	for case in _cases():
		if not _run_case(case):
			return


func test_heard_witness_and_rejected_statement_leave_the_world_unset() -> void:
	var opened := _boot(false)
	var runtime: WyrdRuntime = opened["runtime"]
	_ask(runtime)
	assert_eq(runtime.quests.stage("toll_tale"), "hearing")
	assert_null(runtime.facts.get(_FATE))
	assert_eq(runtime.facts.get_in(_FATE, &"believed/line_fisher"), &"stolen")
	assert_null(runtime.facts.get_in(_FATE, &"known/line_fisher"))
	assert_eq(runtime.facts.get_in(_FATE, &"held/harbor_council"), &"lost_at_sea")
	assert_eq(runtime.facts.get_in(_FATE, &"believed/dock_apprentice"), &"stolen")
	assert_null(runtime.facts.get_in(_FATE, &"known/dock_apprentice"))
	assert_eq(runtime.deeds.mode_of(&"dock_apprentice", &"whispered"), &"heard")
	assert_null(runtime.facts.get_in(_FATE, &"believed/ferry_master"))
	assert_null(runtime.facts.get_in(_FATE, &"known/ferry_master"))
	assert_eq(runtime.quests.variant_of("toll_tale"), "council.default")
	runtime.dialogue.open_scene("toll.tale")
	var rows: Array = _Harness.new().line_rows(runtime)
	assert_eq(rows.size(), 1)
	assert_eq(String(rows[0]["id"]), "tale_claim")
	assert_true(String(rows[0]["text"]).contains("stolen"), String(rows[0]["text"]))


func test_inherited_line_save_round_trips() -> void:
	var opened := _boot(true)
	var runtime: WyrdRuntime = opened["runtime"]
	_ask(runtime)
	assert_eq(runtime.quests.variant_of("toll_tale"), "council.unwilling")
	assert_null(runtime.facts.get_in(_FATE, &"believed/dock_hand"))
	assert_true(_eval(runtime, "belief(dock_hand, harbor.toll_fate) == lost_at_sea"))
	var saved := runtime.save_state()
	var parsed: Variant = JSON.parse_string(JSON.stringify(saved))
	assert_true(parsed is Dictionary)
	var fresh_open := _Harness.new().open_pack(_Harness.HARBOR)
	var fresh: WyrdRuntime = fresh_open["runtime"]
	_people(fresh_open["host"], true)
	fresh.invalidate_groups()
	var report := fresh.load_state(parsed)
	assert_true(report.ok, report.diagnostics.format())
	assert_true(_same(saved, fresh.save_state()))
	assert_eq(fresh.quests.variant_of("toll_tale"), "council.unwilling")
	assert_eq(String(fresh.roles.slot_state(&"council", "toll_tale")), "unwilling")


func _run_case(case: Dictionary) -> bool:
	var label := "%s %s" % [case["slot"], case["direction"]]
	var member := str(case["source"]) == "group"
	var opened := _boot(member)
	var runtime: WyrdRuntime = opened["runtime"]
	_ask(runtime)
	if str(case["source"]) == "own":
		runtime.facts.set_in(_FATE, &"lost_at_sea", &"believed/dock_hand")
		runtime.tick(0)
	elif str(case["slot"]) == "barred":
		runtime.facts.set_in(_FATE, &"stolen", &"believed/player")
		runtime.tick(0)
	if not assert_eq(runtime.quests.variant_of("toll_tale"), str(case["written"]), label + " written"):
		return false
	if not assert_eq(String(runtime.roles.slot_state(&"council", "toll_tale")), str(case["state"]), label + " state"):
		return false
	if str(case["direction"]) == "write":
		return true
	if str(case["source"]) == "group":
		runtime.facts.clear_in(_FATE, &"held/harbor_council")
	elif str(case["source"]) == "own":
		runtime.facts.clear_in(_FATE, &"believed/dock_hand")
	else:
		runtime.facts.clear_in(_FATE, &"believed/player")
	runtime.tick(0)
	if not assert_eq(runtime.quests.variant_of("toll_tale"), "council.default", label + " retracted"):
		return false
	if not assert_eq(String(runtime.roles.slot_state(&"council", "toll_tale")), "default", label + " open"):
		return false
	return true


func _cases() -> Array:
	return [
		{"direction": "write", "slot": "unwilling_group", "source": "group", "state": "unwilling", "written": "council.unwilling"},
		{"direction": "retract", "slot": "unwilling_group", "source": "group", "state": "unwilling", "written": "council.unwilling"},
		{"direction": "write", "slot": "unwilling_own", "source": "own", "state": "unwilling", "written": "council.unwilling"},
		{"direction": "retract", "slot": "unwilling_own", "source": "own", "state": "unwilling", "written": "council.unwilling"},
		{"direction": "write", "slot": "barred", "source": "player", "state": "barred", "written": "council.barred"},
		{"direction": "retract", "slot": "barred", "source": "player", "state": "barred", "written": "council.barred"},
	]


func _boot(member: bool) -> Dictionary:
	var opened := _Harness.new().open_pack(_Harness.HARBOR)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	_people(host, member)
	runtime.start_new_game(4)
	host.spatial.set_perception(&"dock_apprentice", &"heard")
	runtime.social.set_baseline(&"ferry_master", &"line_fisher", &"affinity", -100.0)
	runtime.invalidate_groups()
	return opened


func _people(host: WyrdFakeHost, member: bool) -> void:
	host.world.add_entity(&"player", &"person", "traveler", PackedStringArray(), true)
	host.world.add_entity(&"dock_hand", &"person", "hand", PackedStringArray(), true)
	host.world.add_entity(&"line_fisher", &"person", "fisher", PackedStringArray(), true)
	host.world.add_entity(&"dock_apprentice", &"person", "apprentice", PackedStringArray(), true)
	host.world.add_entity(&"ferry_master", &"person", "master", PackedStringArray(), true)
	if member:
		host.world.set_groups(&"dock_hand", PackedStringArray([&"harbor_council"]))


func _ask(runtime: WyrdRuntime) -> void:
	runtime.deeds.record(&"asked_council", &"player", &"", &"gullhaven")
	runtime.tick(0)


func _eval(runtime: WyrdRuntime, text: String) -> bool:
	var diagnostics := WyrdDiagnostics.new()
	var schema := runtime.content().schema if runtime.content() != null else null
	var compiled := WyrdCondition.new().compile(text, schema, diagnostics, "", 1, 1)
	if diagnostics.has_errors():
		return false
	return runtime.eval_bool(compiled)


func _same(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):
		return false
	if left is Dictionary:
		if left.size() != right.size():
			return false
		for key in left.keys():
			if not right.has(key) or not _same(left[key], right[key]):
				return false
		return true
	if left is Array:
		if left.size() != right.size():
			return false
		for i in left.size():
			if not _same(left[i], right[i]):
				return false
		return true
	return left == right
