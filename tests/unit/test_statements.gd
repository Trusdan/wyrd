extends GutTest


func test_writes_are_stored_and_typed() -> void:
	var file := _compile("""
language 1
facts
  player.coins : int stored
  ferry.toll_coins : float stored
  season : symbol stored
  npc.{id}.met : bool stored
  npc.{id}.alive : bool source: world.is_alive invalidate: on_event(npc_died)
  world.weather : symbol source: world.weather invalidate: per_query

quest ferry_toll "The Ferry Toll"
  stage pay
    ~ set player.coins = 1
    ~ set player.coins = true
    ~ set world.weather = calm
    ~ set npc.{id}.alive = false
    ~ set npc.{id}.met = true
    ~ set nope = 1
    ~ inc player.coins by 2
    ~ inc ferry.toll_coins by 1
    ~ inc ferry.toll_coins by 1.5
    ~ inc player.coins by 1.5
    ~ inc season by 1
""")
	assert_eq(file.codes, [
		"E_WRITE_TYPE",
		"E_WRITE_RESOLVED",
		"E_WRITE_RESOLVED",
		"E_UNKNOWN_FACT",
		"E_WRITE_TYPE",
		"E_WRITE_TYPE",
	])
	var effects: Array = file.unit.quests[0].stages[0].effects
	assert_eq(effects.size(), 11)
	assert_eq(effects[0].fact_key, "player.coins")
	assert_eq(effects[4].fact_key, "npc.{id}.met")
	assert_true(effects[4].reads.has(&"npc.{id}.met"))
	assert_eq(String(effects[6].kind), "inc")
	assert_eq(effects[7].fact_key, "ferry.toll_coins")


func test_line_ids_are_required_and_unique() -> void:
	var file := _compile("""
language 1
quest ferry_toll "The Ferry Toll"
  stage pay
    journal: Nobody tagged this.
    journal: Tagged. #line:same

scene toll.gate
  narrator: Missing too.
  narrator: Again. #line:same
  * [Go] -> end
  * -> end
  * [Stay] -> end #line:c_stay
""")
	assert_eq(file.codes, [
		"E_LINE_ID_MISSING",
		"E_LINE_ID_MISSING",
		"E_LINE_ID_DUPLICATE",
		"E_LINE_ID_MISSING",
	])
	assert_eq(file.messages[0], "missing #line: id; run tag-lines (S1d)")
	assert_true(file.messages[2].begins_with("duplicate #line: id"))
	var scene: WyrdSceneDef = file.unit.scenes[0]
	assert_eq(scene.items[3].choice.line_id, "")
	assert_eq(scene.items[4].choice.line_id, "c_stay")


func test_reads_union_conditions_and_prose() -> void:
	var file := _compile("""
language 1
facts
  player.coins : int stored
  season : symbol stored
  npc.{id}.alive : bool source: world.is_alive invalidate: on_event(npc_died)

quest ferry_toll "The Ferry Toll"
  start when player.coins > 0
  stage pay
    waits_until season == spring
    journal: {fact(npc, holder(ferry), alive)} still. #line:j1

scene toll.gate
  when player.coins > 0: narrator: Season {season}. #line:a1
  * {player.coins >= 2} [Pay] -> paid #line:c1
  - (paid)
""")
	assert_eq(file.codes, [])
	var quest: WyrdQuestDef = file.unit.quests[0]
	assert_true(quest.reads.has(&"player.coins"))
	assert_true(quest.stages[0].reads.has(&"season"))
	assert_true(quest.stages[0].journals[0].reads.has(&"npc.{id}.alive"))
	var line: WyrdLineDef = file.unit.scenes[0].items[0].line_def
	assert_true(line.reads.has(&"player.coins"))
	assert_true(line.reads.has(&"season"))
	var choice: WyrdChoiceDef = file.unit.scenes[0].items[1].choice
	assert_true(choice.reads.has(&"player.coins"))
	assert_eq(choice.label.kids[0].kind, &"text")


func test_chance_rejected_in_waits_and_allowed_on_choices() -> void:
	var file := _compile("""
language 1
facts
  player.coins : int stored
  world.weather : symbol source: world.weather invalidate: per_query
  world.season : symbol source: time.season invalidate: on_event(season_changed)

quest ferry_toll "The Ferry Toll"
  slot ferry = ferry_master mode: cast(chance(0.5))
  start when chance(0.5)
  stage pay
    waits_until chance(0.2)
  stage weather
    waits_until world.weather == calm
  stage later
    waits_until world.season == spring
    -> pay when chance(0.1)

scene toll.gate
  * {chance(1)} [Try the tide] -> next #line:c1
  - (next)
""")
	assert_true(file.codes.has("E_CHANCE_CONTEXT"))
	assert_eq(file.codes.count("E_CHANCE_CONTEXT"), 4)
	assert_true(file.codes.has("E_WAIT_RESOLVER_MODE"))
	var choice: WyrdChoiceDef = file.unit.scenes[0].items[0].choice
	assert_true(choice.condition.uses_chance)
	assert_false(file.unit.quests[0].stages[2].waits_until.uses_chance)


func test_disabled_when_is_type_checked() -> void:
	var file := _compile("""
language 1
scene toll.gate
  * [Stay] disabled_when {not_a_function(1)} "short on coins" -> stay #line:c1
  - (stay)
""")
	assert_true(file.codes.has("E_UNKNOWN_FUNCTION"))
	assert_true(file.codes.has("W_DISABLED_WHEN_DEPRECATED"))
	var choice: WyrdChoiceDef = file.unit.scenes[0].items[0].choice
	assert_eq(choice.disabled_when, "not_a_function(1)")
	assert_eq(choice.disabled_reason, "short on coins")
	assert_null(choice.condition)


func test_set_disposition_names_the_replacement() -> void:
	var file := _compile("""
language 1
quest ferry_toll "The Ferry Toll"
  stage pay
    ~ set_disposition player ferry
""")
	assert_eq(file.codes, ["E_NO_SET_DISPOSITION"])
	assert_eq(file.messages[0], "record deeds or use adjust baseline (§2.5)")
	assert_eq(file.unit.quests[0].stages[0].effects.size(), 0)


func test_journal_prose_interpolates_and_titles_do_not() -> void:
	var file := _compile("""
language 1
facts
  player.coins : int stored

quest ferry_toll "The {player.coins} Toll"
  stage pay
    journal "{player.coins} coins" #line:j_quoted
    journal: {player.coins} coins. #line:j_prose
""")
	assert_eq(file.codes, ["E_STMT_UNKNOWN"])
	assert_eq(file.messages[0], "journal text is prose after a colon")
	assert_eq(file.unit.quests[0].title, "The {player.coins} Toll")
	var journal: WyrdLineDef = file.unit.quests[0].stages[0].journals[0]
	assert_eq(journal.line_id, "j_prose")
	assert_eq(journal.prose.kids[0].kind, &"value")
	assert_true(journal.reads.has(&"player.coins"))


func test_malformed_effect_still_checks_children() -> void:
	var file := _compile("""
language 1
quest ferry_toll "The Ferry Toll"
  stage pay
    ~ set
      frobnicate
""")
	assert_eq(file.codes, ["E_STMT_UNKNOWN", "E_STMT_UNKNOWN"])
	assert_eq(file.messages[0], "set needs <fact> = <expr>")
	assert_eq(file.messages[1], "unknown statement \"frobnicate\"")


func _compile(text: String) -> Dictionary:
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
