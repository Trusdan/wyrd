extends GutTest

## WFR4 statement deeds. The score is disposition / 100, or a host override.


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

const _CLAIM := """
quest harbor_guild "The Harbor Guild"
  stage post
    ~ record deed paid(actor: ferry_master, place: gullhaven, witnesses: [dock_apprentice], reveals: world.storm_heard, claim: true, statement: true)
"""


func test_statement_compiles_and_rejects_a_bad_type() -> void:
	var effects: Array = _quest(_FACTS + """
quest harbor_guild "The Harbor Guild"
  stage post
    ~ record deed paid(actor: ferry_master, witnesses: [dock_apprentice], reveals: world.storm_heard, claim: true, statement: true)
    ~ record deed arrived(actor: player, statement: false)
""").stages[0].effects
	assert_eq(effects.size(), 2)
	assert_eq(_arg_names(effects[0]), ["actor", "witnesses", "statement"])
	assert_eq(String(effects[0].args[2]["text"]), "true")
	assert_eq(effects[0].fact_key, "world.storm_heard")
	assert_eq(_arg_names(effects[1]), ["actor", "statement"])
	assert_eq(String(effects[1].args[1]["text"]), "false")
	var file := _file(_FACTS + """
quest harbor_guild "The Harbor Guild"
  stage post
    ~ record deed arrived(actor: player, statement: 1)
    ~ record deed paid(actor: ferry_master, statement: true, statement: false)
    ~ record deed arrived(statement: true)
""")
	assert_eq(file.codes, ["E_NOT_BOOL", "E_ARG_TYPE", "E_ARG_NAME", "E_ARG_TYPE"], str(file.messages))
	assert_eq(WyrdConfig.new().credibility_threshold, 0.5)


func test_default_score_accepts_and_skips_perception_writes() -> void:
	var runtime := _boot(_FACTS + _CLAIM)
	var host := _host(runtime)
	host.world.set_groups(&"dock_apprentice", PackedStringArray([&"harbor_guild"]))
	host.spatial.set_perception(&"dock_apprentice", &"saw")
	runtime.trace.enabled = true
	runtime.tick(0)
	assert_null(runtime.facts.get(&"world.storm_heard"))
	assert_null(runtime.facts.get_in(&"world.storm_heard", &"known/dock_apprentice"))
	assert_eq(runtime.facts.get_in(&"world.storm_heard", &"believed/dock_apprentice"), true)
	assert_null(runtime.facts.get_in(&"world.storm_heard", &"known/ferry_master"))
	assert_null(runtime.facts.get_in(&"world.storm_heard", &"believed/ferry_master"))
	assert_null(runtime.facts.get_in(&"world.storm_heard", &"believed/player"))
	assert_null(runtime.facts.get_in(&"world.storm_heard", &"held/harbor_guild"))
	assert_true(_eval(runtime, "believes(dock_apprentice, world.storm_heard)"))
	assert_false(_eval(runtime, "knows(dock_apprentice, world.storm_heard)"))
	assert_false(_eval(runtime, "knows(ferry_master, world.storm_heard)"))
	assert_eq(runtime.deeds.mode_of(&"dock_apprentice", &"paid"), &"saw")
	var lines := _rows(runtime, "credibility")
	assert_eq(lines.size(), 1)
	assert_eq(String(lines[0]["listener"]), "dock_apprentice")
	assert_eq(String(lines[0]["speaker"]), "ferry_master")
	assert_eq(String(lines[0]["who"]), "dock_apprentice")
	assert_eq(String(lines[0]["verb"]), "paid")
	assert_eq(String(lines[0]["key"]), "world.storm_heard")
	assert_eq(String(lines[0]["value"]), "true")
	assert_eq(String(lines[0]["score"]), "0.5000")
	assert_eq(String(lines[0]["accepted"]), "true")
	assert_eq(_ops(runtime, "belief"), ["believe"])
	assert_eq(_ops(runtime, "knowledge"), [])
	assert_eq(_rows(runtime, "perception").size(), 1)


func test_low_disposition_threshold_and_override_reject() -> void:
	var runtime := _boot(_FACTS + _CLAIM)
	_host(runtime).spatial.set_perception(&"dock_apprentice", &"heard")
	runtime.social.set_baseline(&"dock_apprentice", &"ferry_master", &"affinity", -1000.0)
	runtime.trace.enabled = true
	runtime.tick(0)
	_assert_rejected(runtime)
	assert_eq(String(_rows(runtime, "credibility")[0]["score"]), "0.0000")
	var raised := _boot(_FACTS + _CLAIM)
	raised.config().credibility_threshold = 0.9
	raised.trace.enabled = true
	raised.tick(0)
	_assert_rejected(raised)
	assert_eq(String(_rows(raised, "credibility")[0]["score"]), "0.5000")
	var calls: Array = [0]
	var overridden := _boot(_FACTS + _CLAIM)
	overridden.register_credibility(func(listener: StringName, speaker: StringName) -> float:
		calls[0] = int(calls[0]) + 1
		assert_eq(String(listener), "dock_apprentice")
		assert_eq(String(speaker), "ferry_master")
		return 0.0
	)
	overridden.social.set_baseline(&"dock_apprentice", &"ferry_master", &"affinity", 1000.0)
	overridden.trace.enabled = true
	overridden.tick(0)
	_assert_rejected(overridden)
	assert_eq(int(calls[0]), 1)
	assert_eq(String(_rows(overridden, "credibility")[0]["score"]), "0.0000")


func test_two_listeners_keep_witness_order() -> void:
	var body := _FACTS + """
quest harbor_guild "The Harbor Guild"
  stage post
    ~ record deed arrived(actor: player, place: gullhaven, witnesses: [ferry_master, dock_apprentice], reveals: world.storm_heard, claim: true, statement: true)
"""
	var runtime := _boot(body)
	var host := _host(runtime)
	host.spatial.set_perception(&"dock_apprentice", &"saw")
	host.spatial.set_perception(&"ferry_master", &"heard")
	runtime.social.set_baseline(&"ferry_master", &"player", &"affinity", -1000.0)
	runtime.trace.enabled = true
	runtime.tick(0)
	assert_eq(runtime.facts.get_in(&"world.storm_heard", &"believed/dock_apprentice"), true)
	assert_null(runtime.facts.get_in(&"world.storm_heard", &"known/dock_apprentice"))
	assert_null(runtime.facts.get_in(&"world.storm_heard", &"believed/ferry_master"))
	assert_null(runtime.facts.get_in(&"world.storm_heard", &"known/ferry_master"))
	assert_null(runtime.facts.get_in(&"world.storm_heard", &"believed/player"))
	var lines := _rows(runtime, "credibility")
	assert_eq(lines.size(), 2)
	assert_eq(String(lines[0]["listener"]), "dock_apprentice")
	assert_eq(String(lines[0]["accepted"]), "true")
	assert_eq(String(lines[1]["listener"]), "ferry_master")
	assert_eq(String(lines[1]["speaker"]), "player")
	assert_eq(String(lines[1]["accepted"]), "false")
	assert_eq(_ops(runtime, "belief"), ["believe"])
	assert_eq(String(_rows(runtime, "belief")[0]["who"]), "dock_apprentice")
	var filtered := _boot(body)
	_host(filtered).spatial.set_perception(&"dock_apprentice", &"saw")
	_host(filtered).spatial.set_perception(&"ferry_master", &"heard")
	filtered.social.set_baseline(&"ferry_master", &"player", &"affinity", -1000.0)
	filtered.trace.enabled = true
	filtered.trace.prefix = "dock_apprentice"
	filtered.tick(0)
	var kept := _rows(filtered, "credibility")
	assert_eq(kept.size(), 1)
	assert_eq(String(kept[0]["who"]), "dock_apprentice")
	assert_eq(_rows(filtered, "perception").size(), 1)
	assert_eq(String(_rows(filtered, "perception")[0]["agent"]), "dock_apprentice")


func test_explicit_false_and_statement_false() -> void:
	var runtime := _boot(_FACTS + """
quest harbor_guild "The Harbor Guild"
  stage post
    ~ record deed paid(actor: ferry_master, place: gullhaven, witnesses: [dock_apprentice], reveals: world.storm_heard, claim: false, statement: true)
    ~ record deed arrived(actor: player, place: gullhaven, witnesses: [ferry_master], reveals: world.storm_heard, claim: true, statement: false)
    ~ record deed paid(actor: player, place: gullhaven, witnesses: [dock_apprentice], reveals: harbor.toll_tale, claim: stolen, statement: false)
""")
	var host := _host(runtime)
	host.spatial.set_perception(&"dock_apprentice", &"heard")
	host.spatial.set_perception(&"ferry_master", &"saw")
	runtime.trace.enabled = true
	runtime.tick(0)
	assert_eq(runtime.facts.get_in(&"world.storm_heard", &"believed/dock_apprentice"), false)
	assert_null(runtime.facts.get_in(&"world.storm_heard", &"known/dock_apprentice"))
	assert_false(_eval(runtime, "believes(dock_apprentice, world.storm_heard)"))
	assert_true(_eval(runtime, "believes(dock_apprentice, world.storm_heard) == false"))
	assert_false(_eval(runtime, "knows(dock_apprentice, world.storm_heard)"))
	assert_eq(runtime.facts.get_in(&"world.storm_heard", &"known/ferry_master"), true)
	assert_null(runtime.facts.get_in(&"world.storm_heard", &"believed/ferry_master"))
	assert_eq(runtime.facts.get_in(&"harbor.toll_tale", &"believed/dock_apprentice"), &"stolen")
	assert_null(runtime.facts.get_in(&"harbor.toll_tale", &"known/dock_apprentice"))
	var lines := _rows(runtime, "credibility")
	assert_eq(lines.size(), 1)
	assert_eq(String(lines[0]["value"]), "false")
	assert_eq(String(lines[0]["accepted"]), "true")
	assert_eq(_ops(runtime, "knowledge"), ["learn"])
	assert_eq(_ops(runtime, "belief"), ["believe", "believe"])


func test_no_listeners_and_direct_record_make_no_decision() -> void:
	var runtime := _boot(_FACTS + """
quest harbor_guild "The Harbor Guild"
  stage post
    ~ record deed arrived(actor: player, reveals: world.storm_heard, claim: true, statement: true)
    ~ record deed paid(actor: ferry_master, witnesses: [dock_apprentice], statement: true)
""")
	runtime.trace.enabled = true
	runtime.tick(0)
	assert_eq(runtime.deeds.size(), 2)
	assert_eq(_rows(runtime, "credibility").size(), 0)
	assert_null(runtime.facts.get_in(&"world.storm_heard", &"believed/dock_apprentice"))
	assert_null(runtime.facts.get_in(&"world.storm_heard", &"known/player"))
	runtime.deeds.record(
		&"arrived",
		&"ferry_master",
		&"",
		&"gullhaven",
		PackedStringArray(),
		1.0,
		PackedStringArray([&"dock_apprentice"])
	)
	assert_eq(_rows(runtime, "credibility").size(), 0)
	assert_null(runtime.facts.get_in(&"world.storm_heard", &"believed/dock_apprentice"))
	assert_eq(runtime.deeds.mode_of(&"dock_apprentice", &"arrived"), &"saw")


func test_repeat_logs_credibility_without_a_second_belief() -> void:
	var runtime := _boot(_FACTS + """
quest harbor_guild "The Harbor Guild"
  stage post
    ~ record deed paid(actor: ferry_master, witnesses: [dock_apprentice], reveals: world.storm_heard, claim: true, statement: true)
    ~ record deed paid(actor: ferry_master, witnesses: [dock_apprentice], reveals: world.storm_heard, claim: true, statement: true)
""")
	runtime.trace.enabled = true
	runtime.tick(0)
	var lines := _rows(runtime, "credibility")
	assert_eq(lines.size(), 2)
	assert_eq(String(lines[0]["accepted"]), "true")
	assert_eq(String(lines[1]["accepted"]), "true")
	assert_eq(_ops(runtime, "belief"), ["believe"])
	runtime.trace.enabled = false
	runtime.trace.events.clear()
	runtime.facts.set_in(&"world.storm_heard", false, &"believed/ferry_master")
	assert_eq(runtime.trace.events.size(), 0)


func test_save_stays_quiet_and_threshold_is_not_saved() -> void:
	var body := _FACTS + _CLAIM + """
    waits_until false
"""
	var runtime := _boot(body)
	runtime.config().credibility_threshold = 0.25
	runtime.trace.enabled = true
	runtime.tick(0)
	assert_eq(_rows(runtime, "credibility").size(), 1)
	var saved := runtime.save_state()
	assert_false(JSON.stringify(saved).contains("credibility"))
	var fresh := _boot(body)
	fresh.trace.enabled = true
	assert_true(fresh.load_state(saved).ok)
	assert_eq(fresh.trace.events.size(), 0)
	assert_eq(fresh.facts.get_in(&"world.storm_heard", &"believed/dock_apprentice"), true)
	assert_eq(fresh.config().credibility_threshold, 0.5)
	assert_true(_same(saved, fresh.save_state()))


func test_scene_wakes_after_accept_and_stays_down_after_reject() -> void:
	var accepted := _FACTS + _CLAIM + """
    waits_until false
scene room
  when believes(dock_apprentice, world.storm_heard): narrator: Believes. #line:believes
  -> end
"""
	var runtime := _boot(accepted)
	runtime.tick(0)
	assert_eq(_flag(runtime, "believes"), 0)
	runtime.tick(0)
	assert_eq(_flag(runtime, "believes"), 1)
	var rejected := _boot(accepted)
	rejected.social.set_baseline(&"dock_apprentice", &"ferry_master", &"affinity", -1000.0)
	rejected.tick(0)
	rejected.tick(0)
	assert_eq(_flag(rejected, "believes"), 0)
	assert_null(rejected.facts.get_in(&"world.storm_heard", &"believed/dock_apprentice"))


func test_seed_does_not_change_the_decision() -> void:
	var body := _FACTS + """
quest harbor_guild "The Harbor Guild"
  stage post
    ~ record deed arrived(actor: player, place: gullhaven, witnesses: [ferry_master, dock_apprentice], reveals: harbor.toll_tale, claim: stolen, statement: true)
"""
	var first := _played(body, 4)
	var second := _played(body, 11)
	assert_eq(first.facts.get_in(&"harbor.toll_tale", &"believed/dock_apprentice"), &"stolen")
	assert_null(first.facts.get_in(&"harbor.toll_tale", &"believed/ferry_master"))
	assert_null(first.facts.get_in(&"harbor.toll_tale", &"known/dock_apprentice"))
	assert_eq(second.facts.get_in(&"harbor.toll_tale", &"believed/dock_apprentice"), &"stolen")
	assert_null(second.facts.get_in(&"harbor.toll_tale", &"believed/ferry_master"))
	assert_eq(first.deeds.mode_of(&"dock_apprentice", &"arrived"), second.deeds.mode_of(&"dock_apprentice", &"arrived"))
	assert_eq(first.deeds.mode_of(&"ferry_master", &"arrived"), second.deeds.mode_of(&"ferry_master", &"arrived"))
	assert_eq(_rows(first, "credibility"), _rows(second, "credibility"))
	var open_gate := _played(body, 4)
	open_gate.config().credibility_threshold = 0.0
	open_gate.social.set_baseline(&"ferry_master", &"player", &"affinity", -1000.0)
	open_gate.trace.events.clear()
	open_gate.start_new_game(4)
	open_gate.config().credibility_threshold = 0.0
	open_gate.social.set_baseline(&"ferry_master", &"player", &"affinity", -1000.0)
	open_gate.trace.enabled = true
	open_gate.tick(0)
	assert_eq(open_gate.facts.get_in(&"harbor.toll_tale", &"believed/ferry_master"), &"stolen")
	assert_eq(String(_rows(open_gate, "credibility")[1]["listener"]), "ferry_master")
	assert_eq(String(_rows(open_gate, "credibility")[1]["accepted"]), "true")
	assert_eq(String(_rows(open_gate, "credibility")[1]["score"]), "0.0000")


func test_override_can_split_listeners() -> void:
	var body := _FACTS + """
quest harbor_guild "The Harbor Guild"
  stage post
    ~ record deed paid(actor: ferry_master, witnesses: [player, dock_apprentice], reveals: world.storm_heard, claim: true, statement: true)
"""
	var calls: Array = [0]
	var runtime := _boot(body)
	runtime.register_credibility(func(listener: StringName, _speaker: StringName) -> float:
		calls[0] = int(calls[0]) + 1
		if String(listener) == "player":
			return 0.2
		return 0.8
	)
	runtime.trace.enabled = true
	runtime.tick(0)
	assert_eq(int(calls[0]), 2)
	assert_null(runtime.facts.get_in(&"world.storm_heard", &"believed/player"))
	assert_eq(runtime.facts.get_in(&"world.storm_heard", &"believed/dock_apprentice"), true)
	var lines := _rows(runtime, "credibility")
	assert_eq(String(lines[0]["listener"]), "dock_apprentice")
	assert_eq(String(lines[0]["score"]), "0.8000")
	assert_eq(String(lines[0]["accepted"]), "true")
	assert_eq(String(lines[1]["listener"]), "player")
	assert_eq(String(lines[1]["score"]), "0.2000")
	assert_eq(String(lines[1]["accepted"]), "false")


func _assert_rejected(runtime: WyrdRuntime) -> void:
	assert_null(runtime.facts.get(&"world.storm_heard"))
	assert_null(runtime.facts.get_in(&"world.storm_heard", &"believed/dock_apprentice"))
	assert_null(runtime.facts.get_in(&"world.storm_heard", &"known/dock_apprentice"))
	assert_null(runtime.facts.get_in(&"world.storm_heard", &"held/harbor_guild"))
	assert_false(_eval(runtime, "believes(dock_apprentice, world.storm_heard)"))
	assert_false(_eval(runtime, "knows(dock_apprentice, world.storm_heard)"))
	var lines := _rows(runtime, "credibility")
	assert_eq(lines.size(), 1)
	assert_eq(String(lines[0]["accepted"]), "false")
	assert_eq(String(lines[0]["listener"]), "dock_apprentice")
	assert_eq(String(lines[0]["speaker"]), "ferry_master")
	assert_eq(_ops(runtime, "belief"), [])
	assert_eq(_ops(runtime, "knowledge"), [])


func _played(body: String, seed_value: int) -> WyrdRuntime:
	var runtime := _boot(body)
	runtime.start_new_game(seed_value)
	var host := _host(runtime)
	host.spatial.set_perception(&"dock_apprentice", &"inferred")
	host.spatial.set_perception(&"ferry_master", &"heard")
	runtime.social.set_baseline(&"ferry_master", &"player", &"affinity", -1000.0)
	runtime.trace.enabled = true
	runtime.tick(0)
	return runtime


func _arg_names(effect: WyrdEffectDef) -> Array:
	var names: Array = []
	for arg in effect.args:
		names.append(String(arg["name"]))
	return names


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
	var path := "user://wyrd_m5_credibility.wyrd"
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
