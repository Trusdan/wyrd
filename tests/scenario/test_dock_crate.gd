extends GutTest

const _Harness := preload("res://tests/scenario/s2c_harness.gd")


func test_dock_crate_pass_fail_and_no_adapter() -> void:
	var passed := _play(true)
	var runtime: WyrdRuntime = passed["runtime"]
	var skills: WyrdFakeSkills = passed["skills"]
	assert_eq(passed["line"], "crate_lifted")
	assert_false(runtime.dialogue.is_open())
	assert_true(runtime.can_save())
	assert_eq(skills.requests.size(), 1)
	assert_eq(String(skills.requests[0].skill), "strength")
	assert_eq(skills.requests[0].args["weight"], 2)
	assert_eq(skills.requests[0].scene_id, "dock.crate_talk")
	assert_eq(skills.requests[0].choice_id, "c_crate_lift")
	assert_eq(runtime.quests.status("dock_crate"), &"active")
	var failed := _play(false)
	assert_eq(failed["line"], "crate_dropped")
	assert_eq((failed["skills"] as WyrdFakeSkills).requests.size(), 1)
	var bare: WyrdRuntime = _Harness.new().boot_gullhaven(false, 4)["runtime"]
	bare.quests.start("dock_crate")
	bare.dialogue.open_scene("dock.crate_talk")
	_Harness.new().line_rows(bare)
	_Harness.new().choose_text(bare, "Lift the crate")
	assert_push_error("no skill adapter")
	var dropped := _Harness.new().line_rows(bare)
	assert_eq(str(dropped[0]["id"]), "crate_dropped")
	var left := _play(true)
	var leaving: WyrdRuntime = left["runtime"]
	leaving.dialogue.open_scene("dock.crate_talk")
	_Harness.new().line_rows(leaving)
	var before := (left["skills"] as WyrdFakeSkills).requests.size()
	_Harness.new().choose_text(leaving, "Leave it")
	assert_false(leaving.dialogue.is_open())
	assert_eq((left["skills"] as WyrdFakeSkills).requests.size(), before)


func test_dock_crate_replay_and_save() -> void:
	var recorded := _traced(true)
	var again := _traced(true, recorded)
	assert_eq(WyrdTrace.diff(recorded, again), PackedStringArray())
	var changed := _traced(false, recorded)
	assert_true(" ".join(WyrdTrace.diff(recorded, changed)).contains("skill_check"))
	var opened := _play(true)
	var runtime: WyrdRuntime = opened["runtime"]
	assert_true(runtime.can_save())
	var saved := runtime.save_state()
	var fresh: WyrdRuntime = _Harness.new().boot_gullhaven(false, 4)["runtime"]
	var report := fresh.load_state(JSON.parse_string(JSON.stringify(saved)))
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(JSON.stringify(fresh.save_state()), JSON.stringify(saved))
	assert_false(fresh.dialogue.is_open())
	assert_eq(fresh.quests.status("dock_crate"), &"active")


func _play(passed: bool) -> Dictionary:
	var opened := _Harness.new().boot_gullhaven(false, 4)
	var runtime: WyrdRuntime = opened["runtime"]
	var skills := WyrdFakeSkills.new()
	if passed:
		skills.set_result(WyrdCommandResult.ok())
	else:
		skills.set_result_for(&"strength", WyrdCommandResult.failed(&"weak"))
	runtime.register_adapter(WyrdSkillAdapter, skills)
	runtime.quests.start("dock_crate")
	runtime.dialogue.open_scene("dock.crate_talk")
	var intro := _Harness.new().line_rows(runtime)
	assert_eq(str(intro[0]["id"]), "crate_line")
	assert_eq(str(intro[0]["speaker"]), "tavern_owner")
	assert_eq(str(intro[0]["name"]), "innkeeper")
	_Harness.new().choose_text(runtime, "Lift the crate")
	var rows := _Harness.new().line_rows(runtime)
	return {"line": str(rows[0]["id"]), "runtime": runtime, "skills": skills}


func _traced(passed: bool, recorded: Array = []) -> Array:
	var opened := _Harness.new().boot_gullhaven(false, 4)
	var runtime: WyrdRuntime = opened["runtime"]
	var skills := WyrdFakeSkills.new()
	if passed:
		skills.set_result(WyrdCommandResult.ok())
	else:
		skills.set_result(WyrdCommandResult.failed(&"weak"))
	runtime.register_adapter(WyrdSkillAdapter, skills)
	runtime.quests.start("dock_crate")
	runtime.trace.enabled = true
	runtime.trace.clear()
	if recorded.is_empty():
		runtime.dialogue.open_scene("dock.crate_talk")
		_Harness.new().line_rows(runtime)
		_Harness.new().choose_text(runtime, "Lift the crate")
		_Harness.new().line_rows(runtime)
	else:
		WyrdTrace.replay(runtime, recorded)
	return runtime.trace.snapshot()
