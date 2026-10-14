extends GutTest


func test_line_speakers_are_slot_entity_or_narrator() -> void:
	var items: Array[WyrdSceneItem] = _scene("""
language 1
scene toll.gate
  ferry: Slot line. #line:a_slot
  ferry.master: Entity line. #line:a_entity
  narrator: Narrator line. #line:a_narrator
""").items
	assert_eq(items[0].line_def.speaker, "ferry")
	assert_eq(items[1].line_def.speaker, "ferry.master")
	assert_eq(items[2].line_def.speaker, "narrator")
	assert_eq(String(items[0].line_def.kind), "spoken")
	assert_eq(items[0].line_def.scene_id, "toll.gate")
	assert_eq(items[0].line_def.line_id, "a_slot")
	assert_eq(items[1].line_def.line_id, "a_entity")
	assert_eq(items[2].line_def.line_id, "a_narrator")


func test_line_condition() -> void:
	var line: WyrdLineDef = _scene("""
language 1
facts
  player.coins : int stored
scene toll.gate
  when player.coins >= 2: ferry: You can cross. #line:a1
""").items[0].line_def
	assert_eq(line.speaker, "ferry")
	assert_eq(line.condition_text, "player.coins >= 2")
	assert_not_null(line.condition)
	assert_true(line.reads.has(&"player.coins"))
	assert_eq(line.line_id, "a1")


func test_choice_without_a_condition() -> void:
	var choice: WyrdChoiceDef = _scene("""
language 1
scene toll.gate
  * [Stay] -> stay #line:c_stay
  - (stay)
""").items[0].choice
	assert_null(choice.condition)
	assert_eq(choice.condition_text, "")
	assert_eq(choice.target, "stay")
	assert_eq(choice.line_id, "c_stay")
	assert_eq(choice.effects.size(), 0)
	assert_not_null(choice.label)


func test_choice_with_a_condition() -> void:
	var choice: WyrdChoiceDef = _scene("""
language 1
facts
  player.coins : int stored
scene toll.gate
  * {player.coins >= 2} [Pay] -> paid #line:c_pay
  - (paid)
""").items[0].choice
	assert_eq(choice.condition_text, "player.coins >= 2")
	assert_not_null(choice.condition)
	assert_false(choice.condition.uses_chance)
	assert_true(choice.reads.has(&"player.coins"))
	assert_eq(choice.effects.size(), 0)


func test_choice_with_nested_effects() -> void:
	var choice: WyrdChoiceDef = _scene("""
language 1
facts
  player.coins : int stored
scene toll.gate
  * [Pay] -> paid #line:c_pay
    ~ set player.coins = 1
    ~ unlock topic harbor_toll
  - (paid)
""").items[0].choice
	assert_eq(choice.effects.size(), 2)
	assert_eq(String(choice.effects[0].kind), "set")
	assert_eq(choice.effects[0].fact_key, "player.coins")
	assert_eq(choice.effects[1].topic, "harbor_toll")
	assert_true(choice.reads.has(&"player.coins"))


func test_on_fail_names_a_label() -> void:
	var choice: WyrdChoiceDef = _scene("""
language 1
scene toll.gate
  * [Cross] -> cross #line:c1
    ~ do take_coin(amount: 1)
    on_fail -> broke
  - (cross)
  - (broke)
""").items[0].choice
	assert_eq(choice.effects.size(), 1)
	assert_eq(String(choice.effects[0].kind), "do")
	assert_eq(choice.effects[0].on_fail, "broke")
	assert_eq(choice.effects[0].command, "take_coin")


func test_labels_and_convergence() -> void:
	var items: Array[WyrdSceneItem] = _scene("""
language 1
scene toll.gate
  * [North] -> meet #line:c1
  * [South] -> meet #line:c2
  - (meet)
  narrator: Both roads meet. #line:a1
  -> end
""").items
	assert_eq(String(items[0].kind), "choice")
	assert_eq(items[0].choice.target, "meet")
	assert_eq(items[1].choice.target, "meet")
	assert_eq(String(items[2].kind), "label")
	assert_eq(items[2].label, "meet")
	assert_eq(String(items[3].kind), "line")
	assert_eq(String(items[4].kind), "divert")
	assert_eq(String(items[4].divert_kind), "end")


func test_divert_end() -> void:
	var item: WyrdSceneItem = _scene("""
language 1
scene toll.gate
  -> end
""").items[0]
	assert_eq(String(item.kind), "divert")
	assert_eq(String(item.divert_kind), "end")
	assert_eq(item.target, "end")


func test_divert_scene() -> void:
	var item: WyrdSceneItem = _scene("""
language 1
scene toll.gate
  -> scene toll.office
""").items[0]
	assert_eq(String(item.divert_kind), "scene")
	assert_eq(item.target, "toll.office")


func test_on_abort_stores_effects() -> void:
	var scene := _scene("""
language 1
scene toll.gate
  on_abort:
    ~ outcome crossing = failed
""")
	assert_eq(scene.on_abort.size(), 1)
	assert_eq(String(scene.on_abort[0].kind), "outcome")
	assert_eq(scene.on_abort[0].branch, "crossing")
	assert_eq(scene.on_abort[0].outcome, "failed")


func test_chance_is_allowed_on_a_choice() -> void:
	var choice: WyrdChoiceDef = _scene("""
language 1
scene toll.gate
  * {chance(1)} [Try the tide] -> next #line:c1
  - (next)
""").items[0].choice
	assert_true(choice.condition.uses_chance)
	assert_eq(choice.line_id, "c1")


func test_missing_line_id() -> void:
	var file := _file("""
language 1
scene toll.gate
  narrator: Missing too.
  * [Go] -> end
""")
	assert_eq(file.codes, ["E_LINE_ID_MISSING", "E_LINE_ID_MISSING"])
	assert_eq(file.messages[0], "missing #line: id; run tag-lines (S1d)")


func test_duplicate_line_id() -> void:
	var file := _file("""
language 1
scene toll.gate
  narrator: One. #line:same
  narrator: Two. #line:same
""")
	assert_eq(file.codes, ["E_LINE_ID_DUPLICATE"])
	assert_true(file.messages[0].begins_with("duplicate #line: id"))
	var scene: WyrdSceneDef = file.unit.scenes[0]
	assert_eq(scene.items[0].line_def.line_id, "same")
	assert_eq(scene.items[1].line_def.line_id, "same")


func test_scene_reads_are_the_union() -> void:
	var scene := _scene("""
language 1
facts
  player.coins : int stored
  season : symbol stored
scene toll.gate
  when player.coins > 0: narrator: Season {season}. #line:a1
  * {season == spring} [Pay {player.coins}] -> paid #line:c1
    ~ inc player.coins by 1
  - (paid)
""")
	var line := scene.items[0].line_def
	var choice := scene.items[1].choice
	assert_true(line.reads.has(&"player.coins"))
	assert_true(line.reads.has(&"season"))
	assert_true(choice.reads.has(&"season"))
	assert_true(choice.reads.has(&"player.coins"))
	assert_true(choice.effects[0].reads.has(&"player.coins"))
	assert_true(scene.reads.has(&"player.coins"))
	assert_true(scene.reads.has(&"season"))
	assert_eq(scene.reads.size(), 2)


func test_deep_choice_effect_span() -> void:
	var scene := _scene("""
language 1
facts
  player.coins : int stored
scene toll.gate
  * [Pay] -> paid #line:c1
    ~ set player.coins = 1
  - (paid)
""")
	var choice := scene.items[0].choice
	var effect := choice.effects[0]
	assert_eq(choice.line, 6)
	assert_eq(choice.col, 3)
	assert_eq(effect.line, 7)
	assert_eq(effect.col, 5)
	assert_eq(effect.end_line, 7)


func _scene(text: String) -> WyrdSceneDef:
	var file := _file(text)
	assert_eq(file.codes, [], text)
	return file.unit.scenes[0]


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
