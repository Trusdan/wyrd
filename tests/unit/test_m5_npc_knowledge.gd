extends GutTest

## NPC knowledge and WFR3 perception. No rumour spread.


const _FACTS := """
language 1
events
  season_changed()
facts
  world.storm_heard : bool stored
  player.coins : int stored
  harbor.toll_tale : symbol stored
  world.season : symbol source: time.season invalidate: on_event(season_changed)
"""


func test_learn_and_forget_compile() -> void:
	var effects: Array = _quest(_FACTS + """
quest harbor_guild "The Harbor Guild"
  stage post
    ~ learn dock_apprentice world.storm_heard = true
    ~ forget ferry_master player.coins
    ~ learn player harbor.toll_tale = stolen
""").stages[0].effects
	assert_eq(effects.size(), 3)
	assert_eq(String(effects[0].kind), "learn")
	assert_eq(effects[0].agent, "dock_apprentice")
	assert_eq(effects[0].fact_key, "world.storm_heard")
	assert_eq(String(effects[1].kind), "forget")
	assert_eq(effects[1].agent, "ferry_master")
	assert_eq(effects[1].fact_key, "player.coins")
	assert_eq(String(effects[2].kind), "learn")
	assert_eq(effects[2].fact_key, "harbor.toll_tale")


func test_learn_and_reveals_reject_bad_facts() -> void:
	var file := _file(_FACTS + """
quest harbor_guild "The Harbor Guild"
  stage post
    ~ learn player world.season = storm
    ~ learn dock_apprentice player.coins = true
    ~ learn ferry_master missing.coins = 1
    ~ learn
    ~ forget player player.coins = 1
    ~ record deed arrived(actor: player, reveals: world.storm_heard)
    ~ record deed arrived(actor: player, claim: true)
    ~ record deed arrived(actor: player, reveals: world.season, claim: storm)
    ~ record deed arrived(actor: player, reveals: player.coins, claim: true)
    ~ record deed arrived(actor: player, reveals: missing.coins, claim: 1)
""")
	assert_eq(file.codes, [
		"E_WRITE_RESOLVED",
		"E_WRITE_TYPE",
		"E_UNKNOWN_FACT",
		"E_STMT_UNKNOWN",
		"E_STMT_UNKNOWN",
		"E_ARG_TYPE",
		"E_ARG_TYPE",
		"E_WRITE_RESOLVED",
		"E_WRITE_TYPE",
		"E_UNKNOWN_FACT",
	], str(file.messages))


func test_learn_and_forget_stay_reserved() -> void:
	var learn := _file("language 1\nquest learn \"The Harbor Guild\"\n")
	assert_true(learn.codes.has("E_RESERVED_WORD"), str(learn.messages))
	var forget := _file("language 1\nquest forget \"The Harbor Guild\"\n")
	assert_true(forget.codes.has("E_RESERVED_WORD"), str(forget.messages))


func test_learn_writes_known_and_leaves_beliefs() -> void:
	var runtime := _boot(_FACTS + """
quest harbor_guild "The Harbor Guild"
  stage post
    ~ believe dock_apprentice world.storm_heard = true
    ~ learn dock_apprentice world.storm_heard = false
    ~ learn dock_apprentice world.storm_heard = false
    ~ forget ferry_master player.coins
    ~ learn ferry_master harbor.toll_tale = stolen
    ~ forget ferry_master harbor.toll_tale
""")
	runtime.trace.enabled = true
	runtime.tick(0)
	assert_null(runtime.facts.get(&"world.storm_heard"))
	assert_eq(runtime.facts.get_in(&"world.storm_heard", &"believed/dock_apprentice"), true)
	assert_eq(runtime.facts.get_in(&"world.storm_heard", &"known/dock_apprentice"), false)
	assert_true(_eval(runtime, "knows(dock_apprentice, world.storm_heard)"))
	assert_true(_eval(runtime, "believes(dock_apprentice, world.storm_heard)"))
	assert_null(runtime.facts.get_in(&"world.storm_heard", &"known/ferry_master"))
	assert_null(runtime.facts.get_in(&"harbor.toll_tale", &"known/ferry_master"))
	assert_null(runtime.facts.get_in(&"player.coins", &"known/player"))
	var ops := _ops(runtime, "knowledge")
	assert_eq(ops, ["learn", "learn", "forget"])
	assert_eq(String(_rows(runtime, "knowledge")[0]["who"]), "dock_apprentice")
	assert_eq(String(_rows(runtime, "knowledge")[0]["value"]), "false")
	assert_eq(String(_rows(runtime, "knowledge")[0]["perspective"]), "known")
	assert_eq(String(_rows(runtime, "knowledge")[2]["who"]), "ferry_master")
	assert_eq(String(_rows(runtime, "knowledge")[2]["value"]), "")
	runtime.roles.define(&"ferry_master", "none", true)
	runtime.roles.assign(&"ferry_master", &"ferry_master")
	runtime.roles.tell(&"ferry_master", &"dock_apprentice")
	var told := _rows(runtime, "knowledge")
	assert_eq(told.size(), 4)
	assert_eq(String(told[3]["op"]), "learn")
	assert_eq(String(told[3]["who"]), "dock_apprentice")
	assert_eq(String(told[3]["key"]), "role.ferry_master.holder")
	runtime.trace.prefix = "ferry_master"
	var before := _rows(runtime, "knowledge").size()
	runtime.facts.set_in(&"player.coins", 4, &"known/dock_apprentice")
	assert_eq(_rows(runtime, "knowledge").size(), before)
	runtime.trace.prefix = ""
	runtime.trace.enabled = false
	runtime.trace.events.clear()
	runtime.facts.set_in(&"player.coins", 1, &"known/player")
	assert_eq(runtime.trace.events.size(), 0)


func test_perception_writes_by_mode_and_does_not_spread() -> void:
	var runtime := _boot(_FACTS + """
quest harbor_guild "The Harbor Guild"
  stage post
    ~ record deed arrived(actor: player, place: gullhaven, witnesses: auto, reveals: world.storm_heard, claim: true)
    ~ record deed paid(actor: ferry_master, place: gullhaven, witnesses: [dock_apprentice], reveals: harbor.toll_tale, claim: stolen)
""")
	var host := _host(runtime)
	host.world.set_groups(&"player", PackedStringArray([&"harbor_guild"]))
	host.spatial.set_witnesses(&"gullhaven", PackedStringArray([&"ferry_master", &"dock_apprentice"]))
	host.spatial.set_perception(&"ferry_master", &"saw")
	host.spatial.set_perception(&"dock_apprentice", &"heard", &"gullhaven")
	runtime.trace.enabled = true
	runtime.tick(0)
	assert_null(runtime.facts.get(&"world.storm_heard"))
	assert_eq(runtime.facts.get_in(&"world.storm_heard", &"known/ferry_master"), true)
	assert_null(runtime.facts.get_in(&"world.storm_heard", &"believed/ferry_master"))
	assert_null(runtime.facts.get_in(&"world.storm_heard", &"known/dock_apprentice"))
	assert_eq(runtime.facts.get_in(&"world.storm_heard", &"believed/dock_apprentice"), true)
	assert_null(runtime.facts.get_in(&"world.storm_heard", &"known/player"))
	assert_null(runtime.facts.get_in(&"world.storm_heard", &"believed/player"))
	assert_null(runtime.facts.get_in(&"world.storm_heard", &"held/harbor_guild"))
	assert_false(_eval(runtime, "believes(player, world.storm_heard)"))
	assert_true(_eval(runtime, "knows(ferry_master, world.storm_heard)"))
	assert_false(_eval(runtime, "knows(dock_apprentice, world.storm_heard)"))
	assert_true(_eval(runtime, "believes(dock_apprentice, world.storm_heard)"))
	assert_eq(runtime.facts.get_in(&"harbor.toll_tale", &"believed/dock_apprentice"), &"stolen")
	assert_null(runtime.facts.get_in(&"harbor.toll_tale", &"known/dock_apprentice"))
	assert_null(runtime.facts.get_in(&"harbor.toll_tale", &"known/ferry_master"))
	var arrived := runtime.deeds.row_at(0)
	assert_eq(arrived["witnesses"], PackedStringArray(["dock_apprentice", "ferry_master"]))
	assert_eq(arrived["perception"], PackedStringArray(["heard", "saw"]))
	assert_true(_eval(runtime, "perceived(ferry_master, arrived) == saw"))
	assert_true(_eval(runtime, "perceived(dock_apprentice, arrived) == heard"))
	assert_false(_eval(runtime, "perceived(player, arrived) == saw"))
	assert_false(_eval(runtime, "perceived(player, arrived) == heard"))
	assert_true(_eval(runtime, "perceived(dock_apprentice, paid) == heard"))
	var perception := _rows(runtime, "perception")
	assert_eq(perception.size(), 3)
	assert_eq(String(perception[0]["agent"]), "dock_apprentice")
	assert_eq(String(perception[0]["mode"]), "heard")
	assert_eq(String(perception[0]["verb"]), "arrived")
	assert_eq(String(perception[0]["key"]), "world.storm_heard")
	assert_eq(String(perception[0]["value"]), "true")
	assert_eq(String(perception[1]["mode"]), "saw")
	assert_eq(_ops(runtime, "knowledge"), ["learn"])
	assert_eq(String(_rows(runtime, "knowledge")[0]["who"]), "ferry_master")
	assert_eq(_ops(runtime, "belief"), ["believe", "believe"])
	assert_eq(String(_rows(runtime, "belief")[0]["who"]), "dock_apprentice")
	assert_eq(String(_rows(runtime, "belief")[0]["key"]), "world.storm_heard")
	assert_eq(String(_rows(runtime, "belief")[1]["key"]), "harbor.toll_tale")
	var bare := WyrdSpatialAdapter.new()
	assert_eq(bare.perceive(&"player", &"ferry_master", &"", &"gullhaven"), &"saw")


func test_inferred_empty_and_bad_modes() -> void:
	var runtime := _boot(_FACTS + """
quest idle "Idle"
  stage post
    waits_until false
""")
	var host := _host(runtime)
	host.spatial.set_perception(&"dock_apprentice", &"inferred")
	host.spatial.set_perception(&"ferry_master", &"")
	runtime.deeds.record(
		&"arrived",
		&"player",
		&"",
		&"gullhaven",
		PackedStringArray(),
		1.0,
		PackedStringArray([&"ferry_master", &"dock_apprentice"])
	)
	var row := runtime.deeds.row_at(0)
	assert_eq(row["witnesses"], PackedStringArray(["dock_apprentice"]))
	assert_eq(row["perception"], PackedStringArray(["inferred"]))
	assert_eq(runtime.deeds.mode_of(&"dock_apprentice", &"arrived"), &"inferred")
	assert_eq(runtime.deeds.mode_of(&"ferry_master", &"arrived"), &"")
	host.spatial.set_perception(&"ferry_master", &"public")
	runtime.deeds.record(&"paid", &"player", &"", &"gullhaven", PackedStringArray(), 1.0, PackedStringArray([&"ferry_master"]))
	assert_push_error("perception")
	assert_eq(runtime.deeds.mode_of(&"ferry_master", &"paid"), &"saw")
	runtime.trace.enabled = true
	runtime.deeds.record(&"arrived", &"ferry_master", &"player", &"gullhaven", PackedStringArray(), 1.0, PackedStringArray([&"dock_apprentice"]))
	assert_eq(runtime.deeds.mode_of(&"dock_apprentice", &"arrived"), &"inferred")
	var lines := _rows(runtime, "perception")
	assert_eq(lines.size(), 1)
	assert_eq(String(lines[0]["mode"]), "inferred")
	assert_eq(String(lines[0]["key"]), "")
	assert_eq(String(lines[0]["value"]), "")
	assert_null(runtime.facts.get_in(&"world.storm_heard", &"known/dock_apprentice"))
	assert_null(runtime.facts.get_in(&"world.storm_heard", &"believed/dock_apprentice"))


func test_perception_save_and_scene_wake() -> void:
	var body := _FACTS + """
quest rumour "Rumour"
  stage hear
    ~ learn dock_apprentice world.storm_heard = false
    ~ record deed arrived(actor: player, place: gullhaven, witnesses: [dock_apprentice], reveals: world.storm_heard, claim: true)
    waits_until false
scene room
  when knows(dock_apprentice, world.storm_heard): narrator: Knows. #line:knows
  when perceived(dock_apprentice, arrived) == heard: narrator: Heard. #line:heard
  -> end
"""
	var runtime := _boot(body)
	var host := _host(runtime)
	host.spatial.set_perception(&"dock_apprentice", &"heard")
	runtime.tick(0)
	assert_eq(_flag(runtime, "knows"), 0)
	assert_eq(_flag(runtime, "heard"), 0)
	runtime.tick(0)
	assert_eq(_flag(runtime, "knows"), 1)
	assert_eq(_flag(runtime, "heard"), 1)
	assert_true(_eval(runtime, "knows(dock_apprentice, world.storm_heard)"))
	assert_true(_eval(runtime, "believes(dock_apprentice, world.storm_heard)"))
	var saved := runtime.save_state()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(saved))
	var fresh := _boot(body)
	fresh.trace.enabled = true
	assert_true(fresh.load_state(parsed).ok)
	assert_eq(fresh.trace.events.size(), 0)
	assert_eq(fresh.facts.get_in(&"world.storm_heard", &"known/dock_apprentice"), false)
	assert_eq(fresh.facts.get_in(&"world.storm_heard", &"believed/dock_apprentice"), true)
	assert_eq(fresh.deeds.mode_of(&"dock_apprentice", &"arrived"), &"heard")
	assert_true(_same(saved, fresh.save_state()))
	var again := _boot(body)
	_host(again).spatial.set_perception(&"dock_apprentice", &"heard")
	again.tick(0)
	assert_eq(again.deeds.mode_of(&"dock_apprentice", &"arrived"), runtime.deeds.mode_of(&"dock_apprentice", &"arrived"))
	assert_eq(again.facts.get_in(&"world.storm_heard", &"known/dock_apprentice"), false)
	assert_eq(again.facts.get_in(&"world.storm_heard", &"believed/dock_apprentice"), true)


func _quest(text: String) -> WyrdQuestDef:
	var file := _file(text)
	assert_eq(file.codes, [], str(file.messages))
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


func _boot(body: String) -> WyrdRuntime:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	runtime.set_meta(&"host", host)
	var path := "user://wyrd_m5_npc_knowledge.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(body)
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(4)
	return runtime


func _host(runtime: WyrdRuntime) -> WyrdFakeHost:
	return runtime.get_meta(&"host") as WyrdFakeHost


func _eval(runtime: WyrdRuntime, text: String) -> bool:
	var diagnostics := WyrdDiagnostics.new()
	var compiled := WyrdCondition.new().compile(text, runtime.content().schema, diagnostics, "sample.wyrd", 1, 1)
	assert_false(diagnostics.has_errors(), "%s %s" % [text, diagnostics.format()])
	return runtime.eval_bool(compiled)


func _rows(runtime: WyrdRuntime, kind: String) -> Array:
	var rows: Array = []
	for row in runtime.trace.events:
		if String(row.get("kind", "")) == kind:
			rows.append(row)
	return rows


func _ops(runtime: WyrdRuntime, kind: String) -> Array:
	var ops: Array = []
	for row in _rows(runtime, kind):
		ops.append(String(row.get("op", "")))
	return ops


func _flag(runtime: WyrdRuntime, record: String) -> int:
	var content := runtime.content()
	for i in content.conditions.size():
		if content.records[i] == record and content.sites[i] == "when":
			return int(runtime.condition_flags()[i])
	return -1


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
