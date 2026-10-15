extends GutTest

## Perspective store, belief effects, and the schema 2 save migration.


const _PLAY := """
language 1
events
  season_changed()
facts
  world.storm_heard : bool stored
  player.coins : int stored
  world.season : symbol source: time.season invalidate: on_event(season_changed)
quest harbor_guild "The Harbor Guild"
  stage post
    ~ believe player world.storm_heard = true
    ~ declare harbor_guild world.storm_heard = false
    ~ set player.coins = 3
    ~ unbelieve player world.storm_heard
    ~ believe ferry_master world.storm_heard = true
    ~ retract harbor_guild world.storm_heard
    ~ believe ferry_master world.storm_heard = true
"""

const _ONE := """
language 1
facts
  world.storm_heard : bool stored
quest harbor_guild "The Harbor Guild"
  stage post
    ~ believe ferry_master world.storm_heard = true
"""


func test_belief_effects_compile() -> void:
	var effects: Array = _quest("""
language 1
facts
  world.storm_heard : bool stored
  player.coins : int stored
quest harbor_guild "The Harbor Guild"
  stage post
    ~ believe player world.storm_heard = true
    ~ declare harbor_guild player.coins = 2
    ~ unbelieve ferry_master world.storm_heard
    ~ retract harbor_guild player.coins
""").stages[0].effects
	assert_eq(effects.size(), 4)
	assert_eq(String(effects[0].kind), "believe")
	assert_eq(effects[0].agent, "player")
	assert_eq(effects[0].fact_key, "world.storm_heard")
	assert_eq(String(effects[1].kind), "declare")
	assert_eq(effects[1].agent, "harbor_guild")
	assert_eq(effects[1].fact_key, "player.coins")
	assert_eq(String(effects[2].kind), "unbelieve")
	assert_eq(effects[2].agent, "ferry_master")
	assert_eq(effects[2].fact_key, "world.storm_heard")
	assert_eq(String(effects[3].kind), "retract")
	assert_eq(effects[3].agent, "harbor_guild")
	assert_eq(effects[3].fact_key, "player.coins")


func test_belief_effects_reject_bad_facts() -> void:
	var file := _file("""
language 1
events
  season_changed()
facts
  player.coins : int stored
  world.season : symbol source: time.season invalidate: on_event(season_changed)
quest harbor_guild "The Harbor Guild"
  stage post
    ~ believe player world.season = storm
    ~ declare harbor_guild player.coins = true
    ~ believe player missing.coins = 1
    ~ believe
    ~ unbelieve player player.coins = 1
    ~ retract
""")
	assert_eq(file.codes, [
		"E_WRITE_RESOLVED",
		"E_WRITE_TYPE",
		"E_UNKNOWN_FACT",
		"E_STMT_UNKNOWN",
		"E_STMT_UNKNOWN",
		"E_STMT_UNKNOWN",
	], str(file.messages))


func test_belief_words_stay_reserved_as_identifiers() -> void:
	var file := _file("""
language 1
quest believe "The Harbor Guild"
""")
	assert_true(file.codes.has("E_RESERVED_WORD"), str(file.messages))


func test_effects_write_beliefs_without_touching_world() -> void:
	var runtime := _boot(_PLAY)
	runtime.trace.enabled = true
	runtime.tick(0)
	assert_null(runtime.facts.get(&"world.storm_heard"))
	assert_eq(runtime.facts.get(&"player.coins"), 3)
	assert_null(runtime.facts.get_in(&"world.storm_heard", &"known/player"))
	assert_null(runtime.facts.get_in(&"world.storm_heard", &"believed/player"))
	assert_eq(runtime.facts.get_in(&"world.storm_heard", &"believed/ferry_master"), true)
	assert_null(runtime.facts.get_in(&"world.storm_heard", &"held/harbor_guild"))
	var facts: Dictionary = runtime.facts.export_state()
	assert_eq(facts["held"], {})
	var believed: Dictionary = facts["believed"]
	assert_eq(believed.keys(), ["ferry_master"])
	assert_eq((believed["ferry_master"] as Dictionary)["world.storm_heard"], true)
	var rows := _beliefs(runtime)
	assert_eq(_ops(runtime), ["believe", "declare", "unbelieve", "believe", "retract"])
	assert_eq(String(rows[0]["perspective"]), "believed")
	assert_eq(String(rows[1]["perspective"]), "held")
	assert_eq(String(rows[1]["value"]), "false")
	assert_eq(String(rows[4]["value"]), "")
	assert_true(runtime.facts.clear_in(&"world.storm_heard", &"held/harbor_guild"))
	assert_eq(_ops(runtime).size(), 5)
	assert_false(runtime.facts.set_in(&"world.season", &"storm", &"believed/ferry_master"))
	assert_push_error("not writable")
	assert_false(runtime.facts.set_in(&"npc.{id}.alive", true, &"believed/player"))
	assert_push_error("not a concrete")
	assert_eq(runtime.facts.get(&"player.coins"), 3)


func test_belief_trace_respects_prefix_and_stays_quiet_when_off() -> void:
	var quiet := _boot(_ONE)
	quiet.tick(0)
	assert_eq(quiet.trace.events.size(), 0)
	assert_eq(quiet.facts.get_in(&"world.storm_heard", &"believed/ferry_master"), true)
	var filtered := _boot(_ONE)
	filtered.trace.prefix = "tavern"
	filtered.trace.enabled = true
	filtered.tick(0)
	assert_eq(_beliefs(filtered).size(), 0)
	var kept := _boot(_ONE)
	kept.trace.prefix = "ferry_master"
	kept.trace.enabled = true
	kept.tick(0)
	var kept_rows := _beliefs(kept)
	assert_eq(kept_rows.size(), 1)
	assert_eq(String(kept_rows[0]["kind"]), "belief")
	assert_eq(String(kept_rows[0]["op"]), "believe")
	assert_eq(String(kept_rows[0]["who"]), "ferry_master")
	assert_eq(String(kept_rows[0]["key"]), "world.storm_heard")
	assert_eq(String(kept_rows[0]["value"]), "true")


func test_beliefs_round_trip_and_schema_1_fills_empty_bags() -> void:
	var runtime := _boot(_PLAY)
	runtime.tick(0)
	var saved := runtime.save_state()
	assert_eq(int(saved["schema_version"]), 2)
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(saved))
	var fresh := _boot(_PLAY)
	fresh.trace.enabled = true
	var report := fresh.load_state(parsed)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(fresh.trace.events.size(), 0)
	assert_eq(fresh.facts.get_in(&"world.storm_heard", &"believed/ferry_master"), true)
	assert_eq(fresh.facts.get(&"player.coins"), 3)
	assert_null(fresh.facts.get(&"world.storm_heard"))
	assert_true(_same(saved, fresh.save_state()))
	saved["schema_version"] = 1
	var old_facts: Dictionary = saved["facts"]
	old_facts.erase("believed")
	old_facts.erase("held")
	var migrated := _boot(_PLAY)
	var loaded := migrated.load_state(saved)
	assert_true(loaded.ok, loaded.diagnostics.format())
	assert_eq(migrated.facts.get(&"player.coins"), 3)
	assert_null(migrated.facts.get_in(&"world.storm_heard", &"believed/ferry_master"))
	var again := migrated.save_state()
	assert_eq(int(again["schema_version"]), 2)
	assert_eq((again["facts"] as Dictionary)["believed"], {})
	assert_eq((again["facts"] as Dictionary)["held"], {})


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
	var path := "user://wyrd_m5_beliefs.wyrd"
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


func _beliefs(runtime: WyrdRuntime) -> Array:
	var rows: Array = []
	for row in runtime.trace.events:
		if String(row.get("kind", "")) == "belief":
			rows.append(row)
	return rows


func _ops(runtime: WyrdRuntime) -> Array:
	var ops: Array = []
	for row in _beliefs(runtime):
		ops.append(String(row.get("op", "")))
	return ops


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
