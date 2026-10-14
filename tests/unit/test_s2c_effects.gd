extends GutTest

const _Harness := preload("res://tests/scenario/s2c_harness.gd")


func test_six_effects_provenance_and_failure() -> void:
	var opened := _Harness.new().open_pack(_Harness.HARBOR)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	assert_true(opened["report"].ok, opened["report"].diagnostics.format())
	runtime.start_new_game(2)
	var topics: Array[String] = []
	var outcomes: Array[String] = []
	runtime.effects.topic_unlocked.connect(func(topic: StringName) -> void: topics.append(String(topic)))
	runtime.effects.outcome_changed.connect(func(quest_id: String, branch: StringName, value: StringName) -> void:
		outcomes.append("%s:%s=%s" % [quest_id, String(branch), String(value)])
	)
	runtime.effects.quest_id = "ferry_toll"
	runtime.effects.scene_id = "toll.offer_room"
	runtime.effects.choice_id = "c_room"
	var inc := WyrdEffectDef.new()
	inc.kind = &"inc"
	inc.fact_key = "tavern.stew_bowls"
	inc.value = _value(runtime, "4")
	assert_null(runtime.facts.get(&"tavern.stew_bowls"))
	assert_eq(runtime.effects.run_one(inc), "")
	assert_eq(runtime.facts.get(&"tavern.stew_bowls"), 4)
	var pay := _stage(runtime, "pay_toll")
	for effect in pay.effects:
		if effect.kind == &"do":
			continue
		assert_eq(runtime.effects.run_one(effect), "")
	assert_eq(runtime.facts.get(&"ferry.toll_coins"), 2)
	assert_eq(runtime.facts.get(&"tavern.stew_bowls"), 5)
	assert_eq(runtime.deeds.count_matching(&"player", &"paid", &"ferry", &"gullhaven"), 1)
	var paid := runtime.deeds.row_at(0)
	assert_eq(bool(paid["memorable"]), true)
	assert_eq(paid["tags"], PackedStringArray(["toll"]))
	assert_eq(paid["place"], &"gullhaven")
	assert_eq(topics, ["storm_rumour"])
	var wrote := runtime.effects.provenance_of("ferry.toll_coins")
	assert_eq(wrote["scene"], "toll.offer_room")
	assert_eq(wrote["choice"], "c_room")
	assert_eq(int(wrote["time"]), 0)
	host.actions.set_result(WyrdCommandResult.failed(&"refused"))
	var divert := ""
	for effect in pay.effects:
		if effect.kind == &"do":
			divert = runtime.effects.run_one(effect)
	assert_eq(divert, "gossip")
	assert_eq(host.actions.executed, [&"post_notice"])
	host.actions.set_result(WyrdCommandResult.ok())
	assert_eq(runtime.effects.run_one(pay.effects[pay.effects.size() - 1]), "")
	var cross := _stage(runtime, "cross")
	for effect in cross.effects:
		assert_eq(runtime.effects.run_one(effect), "")
	assert_eq(runtime.facts.get(&"world.storm_heard"), true)
	assert_eq(outcomes, ["ferry_toll:crossing=done"])
	assert_eq(runtime.effects.provenance_of("world.storm_heard")["time"], 0)
	var bad := WyrdEffectDef.new()
	bad.kind = &"set"
	bad.fact_key = "player.coins"
	bad.value = _value(runtime, "true")
	runtime.facts.set(&"player.coins", 3)
	runtime.effects.run_one(bad)
	assert_push_error("expected int")
	assert_eq(runtime.facts.get(&"player.coins"), 3)


func _stage(runtime: WyrdRuntime, stage_id: String) -> WyrdStageDef:
	var quest: WyrdQuestDef = runtime.content().quests["ferry_toll"]
	for stage in quest.stages:
		if stage.id == stage_id:
			return stage
	return null


func _value(runtime: WyrdRuntime, text: String) -> WyrdCompiledCondition:
	return WyrdCondition.new().compile(text, runtime.content().schema, WyrdDiagnostics.new(), "", 1, 1, WyrdCondition.CONTEXT_STORYLET, 1440, null, false)
