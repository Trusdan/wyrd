extends GutTest


func test_a_later_host_role_change_aborts_after_a_choice() -> void:
	var opened := _boot(_ROOM, "user://wyrd_choice_bug.wyrd")
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.world.add_entity(&"ada", &"person", "Ada", PackedStringArray(), true)
	host.world.add_entity(&"bea", &"person", "Bea", PackedStringArray(), true)
	runtime.roles.assign(&"keeper", &"ada")
	runtime.quests.start("gate")
	runtime.dialogue.open_scene("room")
	runtime.dialogue.choose(0)
	assert_true(runtime.dialogue.is_open())
	assert_eq(runtime.dialogue.line().id, "still")
	runtime.trace.enabled = true
	runtime.trace.clear()
	runtime.roles.assign(&"keeper", &"bea")
	assert_false(runtime.dialogue.is_open())
	assert_eq(_abort_reason(runtime), "holder_left")


func test_a_compiled_disabled_condition_greys_and_a_false_condition_hides() -> void:
	var runtime: WyrdRuntime = _boot(_PACK, "user://wyrd_choices.wyrd")["runtime"]
	runtime.facts.set(&"player.coins", 0)
	runtime.dialogue.open_scene("grey")
	var views := runtime.dialogue.choices()
	assert_eq(views.size(), 2)
	assert_eq(views[0].id, "c_pay")
	assert_false(views[0].enabled)
	assert_eq(views[0].reason, "short on coins")
	assert_eq(views[1].id, "c_plain")
	assert_true(views[1].enabled)
	assert_eq(views[1].reason, "")
	runtime.dialogue.abort(&"host")
	runtime.facts.set(&"player.coins", 5)
	runtime.dialogue.open_scene("grey")
	views = runtime.dialogue.choices()
	assert_eq(views.size(), 2)
	assert_eq(views[0].id, "c_pay")
	assert_true(views[0].enabled)
	assert_eq(views[0].reason, "")
	runtime.dialogue.abort(&"host")
	runtime.facts.set(&"player.coins", -1)
	runtime.dialogue.open_scene("grey")
	views = runtime.dialogue.choices()
	assert_eq(views[0].id, "c_gone")
	assert_false(views[0].enabled)
	assert_eq(views[0].reason, "nope")


func test_chance_in_a_disabled_condition_follows_the_seed_and_bucket() -> void:
	var first: WyrdRuntime = _boot(_PACK, "user://wyrd_choices.wyrd", 11)["runtime"]
	var second: WyrdRuntime = _boot(_PACK, "user://wyrd_choices_b.wyrd", 11)["runtime"]
	first.dialogue.open_scene("maybe")
	second.dialogue.open_scene("maybe")
	assert_eq(first.dialogue.choices()[0].enabled, second.dialogue.choices()[0].enabled)
	assert_eq(first.dialogue.choices()[0].enabled, not _chance_hit(first, 0.5))
	first.dialogue.abort(&"host")
	first.tick(20)
	first.dialogue.open_scene("maybe")
	assert_eq(first.now_minutes(), 20)
	assert_eq(first.dialogue.choices()[0].enabled, not _chance_hit(first, 0.5))
	assert_eq(first.dialogue.choices()[0].enabled, second.dialogue.choices()[0].enabled)
	first.dialogue.abort(&"host")
	first.tick(60)
	first.dialogue.open_scene("maybe")
	assert_eq(first.dialogue.choices()[0].enabled, not _chance_hit(first, 0.5))


func test_a_passed_check_runs_effects_in_order_then_the_target() -> void:
	var opened := _open_lift(11, true)
	var runtime: WyrdRuntime = opened["runtime"]
	var skills: WyrdFakeSkills = opened["skills"]
	runtime.effects.quest_id = "preset-quest"
	runtime.effects.scene_id = "preset-scene"
	runtime.effects.choice_id = "preset-choice"
	runtime.trace.enabled = true
	runtime.trace.clear()
	runtime.dialogue.choose(1)
	assert_eq(runtime.dialogue.line().id, "lifted")
	assert_eq(runtime.facts.get(&"player.coins"), 3)
	var wrote := runtime.effects.provenance_of("player.coins")
	assert_eq(str(wrote["scene"]), "lift")
	assert_eq(str(wrote["choice"]), "c_lift")
	assert_eq(runtime.effects.quest_id, "preset-quest")
	assert_eq(runtime.effects.scene_id, "preset-scene")
	assert_eq(runtime.effects.choice_id, "preset-choice")
	assert_eq(skills.requests.size(), 1)
	assert_eq(_kinds(runtime, "draw").size(), 0)
	var request := skills.requests[0]
	assert_eq(String(request.skill), "strength")
	assert_eq(request.args["weight"], 4)
	assert_eq(request.scene_id, "lift")
	assert_eq(request.choice_id, "c_lift")
	assert_eq(request.roll, _roll(runtime, "lift", "c_lift", 0))
	var row: Dictionary = _kinds(runtime, "skill_check")[0]
	assert_eq(str(row["scene"]), "lift")
	assert_eq(str(row["choice"]), "c_lift")
	assert_eq(str(row["skill"]), "strength")
	assert_eq(str(row["key"]), "strength")
	assert_eq(str(row["path"]), "lift")
	assert_eq(str(row["ok"]), "true")
	assert_eq(str(row["reason"]), "-")
	assert_eq(str(row["roll"]), "%.4f" % request.roll)


func test_a_failed_check_skips_effects_and_uses_on_fail() -> void:
	var opened := _open_lift(3, false)
	var runtime: WyrdRuntime = opened["runtime"]
	var before := runtime.effects.provenance_of("player.coins")
	runtime.dialogue.choose(1)
	assert_eq(runtime.dialogue.line().id, "dropped")
	assert_eq(runtime.facts.get(&"player.coins"), 4)
	assert_eq(runtime.effects.provenance_of("player.coins"), before)
	runtime.dialogue.advance()
	assert_false(runtime.dialogue.is_open())
	var again := _open_lift(3, false)
	var stopping: WyrdRuntime = again["runtime"]
	stopping.dialogue.choose(3)
	assert_false(stopping.dialogue.is_open())
	assert_eq(stopping.facts.get(&"player.coins"), 4)
	assert_eq(stopping.effects.provenance_of("player.coins"), {})


func test_no_adapter_pushes_an_error_and_takes_the_failure_path() -> void:
	var runtime: WyrdRuntime = _boot(_PACK, "user://wyrd_choices.wyrd", 2)["runtime"]
	runtime.facts.set(&"player.coins", 4)
	runtime.trace.enabled = true
	runtime.dialogue.open_scene("lift")
	runtime.dialogue.choose(1)
	assert_push_error("no skill adapter")
	assert_eq(runtime.dialogue.line().id, "dropped")
	assert_eq(runtime.facts.get(&"player.coins"), 4)
	var row: Dictionary = _kinds(runtime, "skill_check")[0]
	assert_eq(str(row["ok"]), "false")
	assert_eq(str(row["reason"]), "no_adapter")


func test_rolls_match_for_one_seed_and_differ_by_choice_or_bucket() -> void:
	var same: WyrdRuntime = _open_lift(8, true)["runtime"]
	var other: WyrdRuntime = _open_lift(8, true, "user://wyrd_choices_b.wyrd")["runtime"]
	same.dialogue.choose(1)
	other.dialogue.choose(2)
	var lift_roll := _roll(same, "lift", "c_lift", 0)
	var other_roll := _roll(same, "lift", "c_other", 0)
	assert_eq(_request(same).roll, lift_roll)
	assert_eq(_request(other).roll, other_roll)
	assert_ne(lift_roll, other_roll)
	var later := _open_lift(8, true, "user://wyrd_choices_c.wyrd")
	var moved: WyrdRuntime = later["runtime"]
	moved.dialogue.abort(&"host")
	moved.tick(60)
	moved.dialogue.open_scene("lift")
	moved.dialogue.choose(1)
	assert_eq(moved.now_minutes(), 60)
	assert_eq(_request(moved).roll, _roll(moved, "lift", "c_lift", 1))
	assert_ne(_request(moved).roll, lift_roll)
	var frozen := _open_lift(8, true, "user://wyrd_choices_d.wyrd")
	var still: WyrdRuntime = frozen["runtime"]
	still.config().hour_bucket_minutes = 0
	still.dialogue.abort(&"host")
	still.tick(120)
	still.dialogue.open_scene("lift")
	still.dialogue.choose(1)
	assert_eq(still.now_minutes(), 120)
	assert_eq(_request(still).roll, _roll(still, "lift", "c_lift", 0))


func test_choice_views_carry_the_check_and_hidden_or_disabled_choices_do_not_call_it() -> void:
	var opened := _open_lift(1, true)
	var runtime: WyrdRuntime = opened["runtime"]
	var skills: WyrdFakeSkills = opened["skills"]
	var views := runtime.dialogue.choices()
	assert_eq(views.size(), 5)
	assert_eq(views[0].id, "c_grey")
	assert_false(views[0].enabled)
	assert_eq(String(views[0].check), "strength")
	assert_eq(views[0].check_args["weight"], 2)
	assert_eq(views[1].id, "c_lift")
	assert_eq(String(views[1].check), "strength")
	assert_eq(views[1].check_args["weight"], 4)
	assert_eq(views[3].id, "c_stop")
	assert_eq(String(views[3].check), "strength")
	assert_eq(views[3].check_args, {})
	assert_eq(views[4].id, "c_plain_lift")
	assert_eq(String(views[4].check), "")
	assert_eq(views[4].check_args, {})
	assert_eq(skills.requests.size(), 0)
	runtime.trace.enabled = true
	runtime.trace.clear()
	runtime.dialogue.choose(0)
	assert_push_error("disabled")
	assert_eq(skills.requests.size(), 0)
	assert_eq(runtime.dialogue.choices().size(), 5)
	assert_eq(_kinds(runtime, "choose").size(), 0)
	assert_eq(_kinds(runtime, "skill_check").size(), 0)
	var rows: Array = _kinds(runtime, "choices")
	assert_eq(rows.size(), 0)
	runtime.dialogue.abort(&"host")
	runtime.trace.clear()
	runtime.dialogue.open_scene("lift")
	rows = _kinds(runtime, "choices")
	assert_eq(rows.size(), 1)
	var shown: Array = rows[0]["rows"]
	assert_eq(str(shown[0]["check"]), "strength")
	assert_false(shown[4].has("check"))
	assert_eq(str(shown[1]["check"]), "strength")
	assert_eq(skills.requests.size(), 0)


func test_a_role_change_inside_check_aborts_and_runs_no_effects() -> void:
	var opened := _boot(_PACK, "user://wyrd_choices.wyrd")
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	var skills := WyrdFakeSkills.new()
	skills.set_result(WyrdCommandResult.ok())
	runtime.register_adapter(WyrdSkillAdapter, skills)
	_people(host)
	runtime.roles.assign(&"keeper", &"ada")
	runtime.quests.start("abortq")
	runtime.facts.set(&"player.coins", 9)
	skills.before_result = func(_request) -> void:
		assert_false(runtime.can_save())
		runtime.roles.assign(&"keeper", &"bea")
	runtime.trace.enabled = true
	runtime.dialogue.open_scene("abort")
	runtime.dialogue.choose(0)
	assert_false(runtime.dialogue.is_open())
	assert_eq(_abort_reason(runtime), "holder_left")
	assert_eq(runtime.facts.get(&"player.coins"), 9)
	assert_eq(runtime.effects.provenance_of("player.coins"), {})
	assert_eq(skills.requests.size(), 1)
	assert_eq(String(runtime.roles.holder(&"keeper")), "bea")


func test_a_role_effect_in_the_choice_does_not_abort_its_scene() -> void:
	var opened := _boot(_PACK, "user://wyrd_choices.wyrd")
	var runtime: WyrdRuntime = opened["runtime"]
	_people(opened["host"])
	runtime.roles.assign(&"keeper", &"ada")
	runtime.quests.start("swapq")
	runtime.effects.quest_id = "preset-quest"
	runtime.effects.scene_id = "preset-scene"
	runtime.effects.choice_id = "preset-choice"
	runtime.dialogue.open_scene("swap")
	runtime.dialogue.choose(0)
	assert_true(runtime.dialogue.is_open())
	assert_eq(runtime.dialogue.line().id, "still_swap")
	assert_eq(String(runtime.roles.holder(&"keeper")), "bea")
	assert_eq(runtime.effects.quest_id, "preset-quest")
	assert_eq(runtime.effects.scene_id, "preset-scene")
	assert_eq(runtime.effects.choice_id, "preset-choice")
	runtime.dialogue.advance()
	assert_false(runtime.dialogue.is_open())
	runtime.roles.assign(&"keeper", &"ada")
	runtime.quests.start("abortq")
	var skills := WyrdFakeSkills.new()
	skills.set_result(WyrdCommandResult.ok())
	runtime.register_adapter(WyrdSkillAdapter, skills)
	runtime.facts.set(&"player.coins", 1)
	runtime.dialogue.open_scene("abort")
	runtime.dialogue.choose(0)
	assert_true(runtime.dialogue.is_open())
	assert_eq(runtime.dialogue.line().id, "held")
	assert_eq(runtime.facts.get(&"player.coins"), 4)
	assert_eq(String(runtime.roles.holder(&"keeper")), "bea")
	assert_eq(runtime.effects.quest_id, "preset-quest")
	assert_eq(runtime.effects.scene_id, "preset-scene")
	assert_eq(runtime.effects.choice_id, "preset-choice")


func test_skill_check_traces_filter_on_key_and_path() -> void:
	var opened := _open_lift(4, true)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.trace.enabled = true
	runtime.trace.prefix = "nope"
	runtime.trace.clear()
	runtime.dialogue.choose(1)
	assert_eq(_kinds(runtime, "skill_check").size(), 0)
	runtime.dialogue.abort(&"host")
	runtime.trace.prefix = "strength"
	runtime.trace.clear()
	runtime.dialogue.open_scene("lift")
	runtime.dialogue.choose(1)
	assert_eq(_kinds(runtime, "skill_check").size(), 1)
	assert_eq(str(_kinds(runtime, "skill_check")[0]["key"]), "strength")
	runtime.dialogue.abort(&"host")
	runtime.trace.prefix = "lift"
	runtime.trace.clear()
	runtime.dialogue.open_scene("lift")
	runtime.dialogue.choose(1)
	assert_eq(_kinds(runtime, "skill_check").size(), 1)
	assert_eq(str(_kinds(runtime, "skill_check")[0]["path"]), "lift")


func test_tracing_off_records_nothing() -> void:
	var opened := _open_lift(4, true)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.trace.enabled = false
	runtime.trace.clear()
	runtime.dialogue.choose(1)
	assert_eq(runtime.trace.events.size(), 0)
	assert_eq(runtime.dialogue.line().id, "lifted")


func test_replay_matches_and_a_changed_answer_shows_skill_check() -> void:
	var recorded := _replay(true)
	var again := _replay(true, recorded)
	assert_eq(WyrdTrace.diff(recorded, again), PackedStringArray())
	assert_true(_has(recorded, "skill_check"))
	assert_true(_has(recorded, "choose"))
	var changed := _replay(false, recorded)
	var found := WyrdTrace.diff(recorded, changed)
	assert_gt(found.size(), 0)
	assert_true(" ".join(found).contains("skill_check"))


func _replay(passed: bool, recorded: Array = []) -> Array:
	var opened := _boot(_PACK, "user://wyrd_choices_replay.wyrd", 6)
	var runtime: WyrdRuntime = opened["runtime"]
	var skills := WyrdFakeSkills.new()
	if passed:
		skills.set_result(WyrdCommandResult.ok())
	else:
		skills.set_result(WyrdCommandResult.failed(&"weak"))
	runtime.register_adapter(WyrdSkillAdapter, skills)
	runtime.facts.set(&"player.coins", 4)
	runtime.trace.enabled = true
	runtime.trace.clear()
	if recorded.is_empty():
		runtime.dialogue.open_scene("lift")
		runtime.dialogue.choose(1)
		runtime.dialogue.advance()
	else:
		WyrdTrace.replay(runtime, recorded)
	return runtime.trace.snapshot()


func _open_lift(seed_value: int, passed: bool, path: String = "user://wyrd_choices.wyrd") -> Dictionary:
	var opened := _boot(_PACK, path, seed_value)
	var runtime: WyrdRuntime = opened["runtime"]
	var skills := WyrdFakeSkills.new()
	if passed:
		skills.set_result(WyrdCommandResult.ok())
	else:
		skills.set_result_for(&"strength", WyrdCommandResult.failed(&"weak"))
	runtime.register_adapter(WyrdSkillAdapter, skills)
	runtime.facts.set(&"player.coins", 4)
	runtime.dialogue.open_scene("lift")
	opened["skills"] = skills
	return opened


func _request(runtime: WyrdRuntime) -> WyrdSkillCheck:
	var skills := runtime.adapter(WyrdSkillAdapter) as WyrdFakeSkills
	return skills.requests[0]


func _roll(runtime: WyrdRuntime, scene_id: String, choice_id: String, bucket: int) -> float:
	return WyrdRng.decision_unit(runtime.game_seed(), &"skill", StringName("%s:%s" % [scene_id, choice_id]), bucket)


func _chance_hit(runtime: WyrdRuntime, p: float) -> bool:
	var scene: WyrdSceneDef = runtime.content().scenes["maybe"]
	var choice := scene.items[0].choice
	var index := runtime.content().index_of(choice.disabled_condition)
	var record := ""
	var site := ""
	if index >= 0:
		record = runtime.content().records[index]
		site = runtime.content().sites[index]
	var bucket := 0
	var size := runtime.config().hour_bucket_minutes
	if size > 0:
		bucket = int(runtime.now_minutes() / float(size))
	var rng := WyrdRng.for_decision(runtime.game_seed(), &"chance", StringName("%s:%s" % [record, site]), bucket)
	return rng.randf() < p


func _people(host: WyrdFakeHost) -> void:
	host.world.add_entity(&"ada", &"person", "Ada", PackedStringArray(), true)
	host.world.add_entity(&"bea", &"person", "Bea", PackedStringArray(), true)


func _abort_reason(runtime: WyrdRuntime) -> String:
	for item in runtime.trace.events:
		if item is Dictionary and str((item as Dictionary).get("kind", "")) == "abort":
			return str((item as Dictionary).get("reason", ""))
	return ""


func _kinds(runtime: WyrdRuntime, kind: String) -> Array:
	var rows: Array = []
	for item in runtime.trace.events:
		if item is Dictionary and str((item as Dictionary).get("kind", "")) == kind:
			rows.append(item)
	return rows


func _has(events: Array, kind: String) -> bool:
	for item in events:
		if item is Dictionary and String((item as Dictionary).get("kind", "")) == kind:
			return true
	return false


func _boot(body: String, path: String, seed_value: int = 5) -> Dictionary:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(body.strip_edges() + "\n")
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(seed_value)
	return {"host": host, "runtime": runtime}


const _ROOM := """
language 1

role keeper
  succession: none
  vacancy: hold

quest gate "Gate"
  start when false
  on_empty: wait
  slot desk = keeper mode: live
  stage one
    scene room with desk
    waits_until false

scene room
  * [Stay] -> after #line:c_stay
  - (after)
  narrator: Still. #line:still
"""


const _PACK := """
language 1

facts
  player.coins : int stored

role keeper
  succession: none
  vacancy: hold

quest swapq "Swap"
  start when false
  on_empty: wait
  slot desk = keeper mode: live
  stage one
    scene swap with desk
    waits_until false

quest abortq "Abort"
  start when false
  on_empty: wait
  slot desk = keeper mode: live
  stage one
    scene abort with desk
    waits_until false

scene grey
  * {player.coins < 0} [Gone] show_disabled_when {true} "nope" -> end #line:c_gone
  * [Pay] show_disabled_when {player.coins < 2} "short on coins" -> end #line:c_pay
  * [Plain] -> end #line:c_plain

scene lift
  * {false} [Hidden] -> end #line:c_hide
    check strength(weight: 1) on_fail -> end
  * [Grey] show_disabled_when {true} "no" -> end #line:c_grey
    check strength(weight: 2) on_fail -> end
  * [Lift] -> lifted #line:c_lift
    check strength(weight: player.coins) on_fail -> dropped
    ~ set player.coins = 1
    ~ inc player.coins by 2
  * [Other] -> end #line:c_other
    check strength(weight: 3) on_fail -> end
  * [Stop] -> lifted #line:c_stop
    check strength() on_fail -> end
    ~ set player.coins = 7
  * [Plain] -> end #line:c_plain_lift
  - (lifted)
  narrator: Lifted. #line:lifted
  -> end
  - (dropped)
  narrator: Dropped. #line:dropped
  -> end

scene maybe
  * [Maybe] show_disabled_when {chance(0.5)} "maybe" -> end #line:c_maybe

scene swap
  * [Swap] -> after #line:c_swap
    ~ assign role keeper to bea
  - (after)
  narrator: Still. #line:still_swap

scene abort
  * [Swap] -> after #line:c_abort
    check strength() on_fail -> missed
    ~ set player.coins = 4
    ~ assign role keeper to bea
  - (after)
  narrator: Held. #line:held
  -> end
  - (missed)
  narrator: Missed. #line:missed
"""
