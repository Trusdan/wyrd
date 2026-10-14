extends GutTest


func test_slot_mode_live() -> void:
	var slot := _quest("""
language 1
quest ferry_toll "The Ferry Toll"
  slot tavern = tavern_owner mode: live
  stage pay
""").slots[0]
	assert_eq(slot.name, "tavern")
	assert_eq(slot.role, "tavern_owner")
	assert_eq(String(slot.mode), "live")
	assert_eq(slot.locked_stage, "")
	assert_null(slot.cast_when)


func test_slot_mode_locked_at() -> void:
	var slot := _quest("""
language 1
quest ferry_toll "The Ferry Toll"
  slot ferry = ferry_master mode: locked_at(pay)
  stage pay
""").slots[0]
	assert_eq(String(slot.mode), "locked_at")
	assert_eq(slot.locked_stage, "pay")
	assert_null(slot.cast_when)


func test_slot_mode_cast() -> void:
	var slot := _quest("""
language 1
facts
  player.coins : int stored
quest ferry_toll "The Ferry Toll"
  slot gate = keeper mode: cast(player.coins > 0)
  stage pay
""").slots[0]
	assert_eq(String(slot.mode), "cast")
	assert_eq(slot.cast_text, "player.coins > 0")
	assert_not_null(slot.cast_when)
	assert_true(slot.reads.has(&"player.coins"))
	assert_eq(slot.locked_stage, "")


func test_on_empty_wait() -> void:
	var quest := _quest("""
language 1
quest ferry_toll "The Ferry Toll"
  on_empty: wait
  stage pay
""")
	assert_eq(quest.on_empty, "wait")


func test_start_when_stores_the_wait_condition() -> void:
	var quest := _quest("""
language 1
facts
  player.coins : int stored
quest ferry_toll "The Ferry Toll"
  start when player.coins > 0
  stage pay
""")
	assert_eq(quest.start_text, "player.coins > 0")
	assert_not_null(quest.start_when)
	assert_false(quest.start_when.uses_chance)
	assert_true(quest.reads.has(&"player.coins"))


func test_start_when_rejects_chance() -> void:
	var file := _file("""
language 1
quest ferry_toll "The Ferry Toll"
  start when chance(0.5)
  stage pay
""")
	assert_eq(file.codes, ["E_CHANCE_CONTEXT"])
	var quest: WyrdQuestDef = file.unit.quests[0]
	assert_true(quest.start_when.uses_chance)


func test_waits_until_stores_the_wait_condition() -> void:
	var stage: WyrdStageDef = _quest("""
language 1
facts
  season : symbol stored
quest ferry_toll "The Ferry Toll"
  stage pay
    waits_until season == spring
""").stages[0]
	assert_eq(stage.waits_text, "season == spring")
	assert_not_null(stage.waits_until)
	assert_false(stage.waits_until.uses_chance)
	assert_true(stage.reads.has(&"season"))


func test_waits_until_rejects_chance() -> void:
	var file := _file("""
language 1
quest ferry_toll "The Ferry Toll"
  stage pay
    waits_until chance(0.2)
""")
	assert_eq(file.codes, ["E_CHANCE_CONTEXT"])
	assert_true(file.unit.quests[0].stages[0].waits_until.uses_chance)


func test_waits_until_rejects_per_query_facts() -> void:
	var file := _file("""
language 1
facts
  world.weather : symbol source: world.weather invalidate: per_query
quest ferry_toll "The Ferry Toll"
  stage pay
    waits_until world.weather == calm
""")
	assert_eq(file.codes, ["E_RESOLVER_INVALIDATION"])
	assert_true(file.unit.quests[0].stages[0].reads.has(&"world.weather"))


func test_unconditional_stage_transition() -> void:
	var stage: WyrdStageDef = _quest("""
language 1
quest ferry_toll "The Ferry Toll"
  stage gossip
    -> pay
  stage pay
""").stages[0]
	assert_eq(stage.transitions.size(), 1)
	assert_eq(stage.transitions[0]["target"], "pay")
	assert_eq(stage.transitions[0]["expr"], "")
	assert_null(stage.transitions[0]["when"])


func test_conditional_stage_transition() -> void:
	var stage: WyrdStageDef = _quest("""
language 1
facts
  player.coins : int stored
quest ferry_toll "The Ferry Toll"
  stage pay
    -> gossip when player.coins >= 2
  stage gossip
""").stages[0]
	assert_eq(stage.transitions[0]["target"], "gossip")
	assert_eq(stage.transitions[0]["expr"], "player.coins >= 2")
	assert_not_null(stage.transitions[0]["when"])
	assert_true(stage.reads.has(&"player.coins"))


func test_variant_default() -> void:
	_assert_bare_state("default")


func test_variant_successor() -> void:
	_assert_bare_state("successor")


func test_variant_empty() -> void:
	_assert_bare_state("empty")


func test_variant_hostile() -> void:
	_assert_bare_state("hostile")


func test_variant_locked_gone() -> void:
	_assert_bare_state("locked_gone")


func test_variant_unwilling() -> void:
	var variant := _variant("ferry.unwilling(player.coins < 1):")
	assert_eq(String(variant.state), "unwilling")
	assert_eq(variant.condition_text, "player.coins < 1")
	assert_not_null(variant.condition)
	assert_true(variant.reads.has(&"player.coins"))


func test_variant_barred() -> void:
	var variant := _variant("ferry.barred(not has(player, pass)):")
	assert_eq(String(variant.state), "barred")
	assert_eq(variant.condition_text, "not has(player, pass)")
	assert_not_null(variant.condition)
	assert_eq(variant.redirects.size(), 0)


func test_redirect_beat_is_parsed_only() -> void:
	var file := _variant_file("""ferry.successor:
      redirect beat greet to nobody""")
	assert_eq(file.codes, [])
	var redirect: Dictionary = file.unit.quests[0].stages[0].variants[0].redirects[0]
	assert_eq(redirect["beat"], "greet")
	assert_eq(redirect["slot"], "nobody")


func test_requires_is_parsed_only() -> void:
	var quest := _quest("""
language 1
quest ferry_toll "The Ferry Toll"
  requires: [pack.harbor, pack.roads]
  stage pay
""")
	assert_eq(quest.requires.size(), 2)
	assert_eq(quest.requires[0], "pack.harbor")
	assert_eq(quest.requires[1], "pack.roads")


func test_set_on_a_stored_fact() -> void:
	var effect: WyrdEffectDef = _quest("""
language 1
facts
  player.coins : int stored
quest ferry_toll "The Ferry Toll"
  stage pay
    ~ set player.coins = player.coins - 2
""").stages[0].effects[0]
	assert_eq(String(effect.kind), "set")
	assert_eq(effect.fact_key, "player.coins")
	assert_eq(effect.target_text, "player.coins")
	assert_true(effect.reads.has(&"player.coins"))


func test_set_on_a_pattern() -> void:
	var effect: WyrdEffectDef = _quest("""
language 1
facts
  npc.{id}.met : bool stored
quest ferry_toll "The Ferry Toll"
  stage pay
    ~ set npc.{id}.met = true
""").stages[0].effects[0]
	assert_eq(effect.fact_key, "npc.{id}.met")
	assert_true(effect.reads.has(&"npc.{id}.met"))


func test_inc_on_stored_facts_and_patterns() -> void:
	var effects: Array[WyrdEffectDef] = _quest("""
language 1
facts
  player.coins : int stored
  ferry.toll_coins : float stored
  npc.{id}.coins : int stored
quest ferry_toll "The Ferry Toll"
  stage pay
    ~ inc player.coins by 2
    ~ inc ferry.toll_coins by 1
    ~ inc npc.{id}.coins by 1
""").stages[0].effects
	assert_eq(effects.size(), 3)
	assert_eq(String(effects[0].kind), "inc")
	assert_eq(effects[0].fact_key, "player.coins")
	assert_eq(effects[1].fact_key, "ferry.toll_coins")
	assert_eq(effects[2].fact_key, "npc.{id}.coins")
	assert_true(effects[2].reads.has(&"npc.{id}.coins"))


func test_set_rejects_a_resolved_fact() -> void:
	var file := _file("""
language 1
facts
  world.weather : symbol source: world.weather invalidate: on_event(weather_changed)
quest ferry_toll "The Ferry Toll"
  stage pay
    ~ set world.weather = calm
""")
	assert_eq(file.codes, ["E_WRITE_RESOLVED"])
	assert_eq(file.unit.quests[0].stages[0].effects[0].fact_key, "world.weather")


func test_inc_rejects_a_type_mismatch() -> void:
	var file := _file("""
language 1
facts
  season : symbol stored
  player.coins : int stored
quest ferry_toll "The Ferry Toll"
  stage pay
    ~ inc season by 1
    ~ set player.coins = true
""")
	assert_eq(file.codes, ["E_WRITE_TYPE", "E_WRITE_TYPE"])


func test_record_deed_checks_arguments() -> void:
	var kept: WyrdEffectDef = _quest("""
language 1
quest ferry_toll "The Ferry Toll"
  stage pay
    ~ record deed paid(actor: player, target: ferry, witnesses: auto, memorable: true)
""").stages[0].effects[0]
	assert_eq(String(kept.kind), "record_deed")
	assert_eq(kept.verb, "paid")
	assert_eq(kept.args.size(), 4)
	assert_eq(kept.args[0]["name"], "actor")
	assert_eq(kept.args[2]["text"], "auto")
	var file := _file("""
language 1
quest ferry_toll "The Ferry Toll"
  stage pay
    ~ record deed paid(player)
    ~ record deed paid(actor: player, nope: 1)
    ~ record deed paid(actor: player, magnitude: true)
""")
	assert_eq(file.codes, ["E_ARG_NAME", "E_ARG_TYPE", "E_ARG_NAME", "E_ARG_TYPE"])


func test_unlock_do_and_outcome() -> void:
	var effects: Array[WyrdEffectDef] = _quest("""
language 1
facts
  player.coins : int stored
quest ferry_toll "The Ferry Toll"
  stage pay
    ~ unlock topic harbor_toll
    ~ do take_coin(amount: player.coins) on_fail -> nowhere
    outcome crossing = route_closed
""").stages[0].effects
	assert_eq(String(effects[0].kind), "unlock_topic")
	assert_eq(effects[0].topic, "harbor_toll")
	assert_eq(String(effects[1].kind), "do")
	assert_eq(effects[1].command, "take_coin")
	assert_eq(effects[1].on_fail, "nowhere")
	assert_eq(effects[1].args[0]["name"], "amount")
	assert_true(effects[1].reads.has(&"player.coins"))
	assert_eq(String(effects[2].kind), "outcome")
	assert_eq(effects[2].branch, "crossing")
	assert_eq(effects[2].outcome, "route_closed")


func test_rejects_out_of_slice_effects_and_set_disposition() -> void:
	var file := _file("""
language 1
quest ferry_toll "The Ferry Toll"
  stage pay
    ~ lock topic harbor_toll
    ~ start quest other
    ~ advance
    ~ assign role ferry
    ~ vacate role ferry
    ~ adjust baseline player
    ~ set_disposition player ferry
""")
	assert_eq(file.codes, [
		"E_EFFECT_NOT_IN_SLICE",
		"E_EFFECT_NOT_IN_SLICE",
		"E_EFFECT_NOT_IN_SLICE",
		"E_EFFECT_NOT_IN_SLICE",
		"E_EFFECT_NOT_IN_SLICE",
		"E_EFFECT_NOT_IN_SLICE",
		"E_NO_SET_DISPOSITION",
	])
	assert_eq(file.messages[6], "record deeds or use adjust baseline (§2.5)")
	assert_eq(file.unit.quests[0].stages[0].effects.size(), 0)


func test_journal_line_id_is_stored() -> void:
	var journal: WyrdLineDef = _quest("""
language 1
quest ferry_toll "The Ferry Toll"
  stage pay
    journal: The toll is paid. #line:j_paid
""").stages[0].journals[0]
	assert_eq(journal.line_id, "j_paid")
	assert_eq(String(journal.kind), "journal")
	assert_eq(journal.scene_id, "")


func test_quest_reads_are_the_union() -> void:
	var quest := _quest("""
language 1
facts
  player.coins : int stored
  season : symbol stored
  npc.{id}.alive : bool source: world.is_alive invalidate: on_event(npc_died)
quest ferry_toll "The Ferry Toll"
  start when player.coins > 0
  stage pay
    waits_until season == spring
    journal: Alive {fact(npc, holder(ferry), alive)}. #line:j1
    -> next when player.coins >= 2
  stage next
""")
	var stage := quest.stages[0]
	assert_true(quest.start_when.reads.has(&"player.coins"))
	assert_true(stage.waits_until.reads.has(&"season"))
	assert_true(stage.journals[0].reads.has(&"npc.{id}.alive"))
	assert_true(stage.reads.has(&"player.coins"))
	assert_true(stage.reads.has(&"season"))
	assert_true(stage.reads.has(&"npc.{id}.alive"))
	assert_true(quest.reads.has(&"player.coins"))
	assert_true(quest.reads.has(&"season"))
	assert_true(quest.reads.has(&"npc.{id}.alive"))


func test_deep_effect_span_points_at_its_line() -> void:
	var effect: WyrdEffectDef = _quest("""
language 1
facts
  player.coins : int stored
quest ferry_toll "The Ferry Toll"
  slot ferry = ferry_master mode: live
  stage pay
    variant ferry.default:
      ~ set player.coins = 2
""").stages[0].variants[0].body.effects[0]
	assert_eq(effect.line, 9)
	assert_eq(effect.col, 7)
	assert_eq(effect.end_line, 9)
	assert_gt(effect.end_col, effect.col)


func _assert_bare_state(state: String) -> void:
	var variant := _variant("ferry.%s:" % state)
	assert_eq(String(variant.state), state)
	assert_null(variant.condition)
	assert_eq(variant.condition_text, "")
	assert_not_null(variant.body)


func _variant(head: String) -> WyrdVariantDef:
	var file := _variant_file(head)
	assert_eq(file.codes, [], head)
	return file.unit.quests[0].stages[0].variants[0]


func _variant_file(head: String) -> Dictionary:
	return _file("""
language 1
facts
  player.coins : int stored
quest ferry_toll "The Ferry Toll"
  slot ferry = ferry_master mode: live
  stage pay
    variant %s
""" % head)


func _quest(text: String) -> WyrdQuestDef:
	var file := _file(text)
	assert_eq(file.codes, [], text)
	return file.unit.quests[0]


func _file(text: String) -> Dictionary:
	var source := WyrdSource.new("sample.wyrd", text)
	var diagnostics := WyrdDiagnostics.new()
	var tree := WyrdParser.new().parse(source, diagnostics)
	var unit := WyrdStatements.new().compile(source, tree, diagnostics)
	var codes: Array = []
	var messages: Array = []
	for item in diagnostics.items:
		codes.append(String(item.code))
		messages.append(item.message)
	return {"codes": codes, "messages": messages, "unit": unit}
