extends GutTest

## Belief conditions, precedence, and the M4 reads that use them.


const _FACTS := """
language 1
events
  groups_changed()
facts
  world.storm_heard : bool stored
  player.coins : int stored
  harbor.toll_tale : symbol stored
  role.ferry_master.holder : symbol stored
  npc.{id}.alive : bool source: world.is_alive invalidate: on_event(groups_changed)
"""


func test_precedence_stops_on_false_and_ignores_known() -> void:
	var runtime := _boot(_FACTS + _IDLE)
	var host: WyrdFakeHost = _host(runtime)
	host.world.set_groups(&"ferry_master", PackedStringArray([&"harbor_guild", &"faction.harbor"]))
	runtime.facts.set(&"world.storm_heard", true)
	runtime.facts.set_in(&"world.storm_heard", true, &"known/ferry_master")
	assert_false(_eval(runtime, "believes(ferry_master, world.storm_heard)"))
	assert_false(_eval(runtime, "believes(ferry_master, world.storm_heard) == true"))
	assert_false(_eval(runtime, "believes(ferry_master, world.storm_heard) == false"))
	assert_true(_eval(runtime, "knows(ferry_master, world.storm_heard)"))
	assert_eq(runtime.facts.get(&"world.storm_heard"), true)
	runtime.facts.set_in(&"world.storm_heard", false, &"held/harbor_guild")
	runtime.facts.set_in(&"world.storm_heard", true, &"held/faction.harbor")
	assert_false(_eval(runtime, "believes(ferry_master, world.storm_heard)"))
	assert_true(_eval(runtime, "believes(ferry_master, world.storm_heard) == false"))
	runtime.facts.set_in(&"world.storm_heard", false, &"believed/ferry_master")
	assert_false(_eval(runtime, "believes(ferry_master, world.storm_heard)"))
	assert_true(_eval(runtime, "believes(ferry_master, world.storm_heard) == false"))
	assert_false(_eval(runtime, "held(harbor_guild, world.storm_heard)"))
	assert_true(_eval(runtime, "held(faction.harbor, world.storm_heard)"))
	runtime.facts.clear_in(&"world.storm_heard", &"believed/ferry_master")
	assert_false(_eval(runtime, "believes(ferry_master, world.storm_heard)"))
	assert_eq(_lookup(runtime, "ferry_master", "world.storm_heard")["source"], "group harbor_guild")
	var calls := [0]
	runtime.register_group_precedence(func(_agent: StringName, groups: PackedStringArray) -> PackedStringArray:
		calls[0] += 1
		var flipped := PackedStringArray()
		for i in range(groups.size() - 1, -1, -1):
			flipped.append(groups[i])
		return flipped
	)
	assert_true(_eval(runtime, "believes(ferry_master, world.storm_heard)"))
	assert_gt(calls[0], 0)
	runtime.facts.set_in(&"world.storm_heard", true, &"believed/ferry_master")
	var before := int(calls[0])
	assert_true(_eval(runtime, "believes(ferry_master, world.storm_heard)"))
	assert_eq(calls[0], before)
	var bare := WyrdWorldAdapter.new()
	assert_eq(bare.groups_of(&"player").size(), 0)


func test_value_read_types_and_zero_stops_the_walk() -> void:
	var runtime := _boot(_FACTS + _IDLE)
	var host: WyrdFakeHost = _host(runtime)
	host.world.set_groups(&"player", PackedStringArray([&"harbor_guild"]))
	runtime.facts.set_in(&"player.coins", 4, &"held/harbor_guild")
	runtime.facts.set_in(&"player.coins", 0, &"believed/player")
	assert_false(_eval(runtime, "believes(player, player.coins)"))
	assert_true(_eval(runtime, "belief(player, player.coins) == 0"))
	assert_false(_eval(runtime, "believes(player, player.coins) == 4"))
	runtime.facts.clear_in(&"player.coins", &"believed/player")
	assert_true(_eval(runtime, "belief(player, player.coins) == 4"))
	runtime.facts.set_in(&"harbor.toll_tale", &"stolen", &"believed/player")
	assert_true(_eval(runtime, "believes(player, harbor.toll_tale)"))
	assert_true(_eval(runtime, "belief(player, harbor.toll_tale) == stolen"))
	var compared := _compile(runtime, "believes(player, world.storm_heard) == true")
	assert_true(_names(compared).has("belief"))
	assert_false(_names(compared).has("believes"))
	var flag := _compile(runtime, "believes(player, world.storm_heard)")
	assert_true(_names(flag).has("believes"))
	assert_true(flag.reads.has(&"world.storm_heard"))
	assert_true(flag.reads.has(&"group.membership"))
	var direct := _compile(runtime, "held(harbor_guild, world.storm_heard)")
	assert_false(direct.reads.has(&"group.membership"))
	var knows := _compile(runtime, "knows(player, world.storm_heard)")
	assert_false(knows.reads.has(&"group.membership"))
	var dynamic := _compile_text("belief(player, npc.{holder(ferry)}.alive) == true")
	assert_true(dynamic.has("E_OP_TYPE"), str(dynamic))


func test_known_is_removed_and_knows_reads() -> void:
	var removed_runtime := _boot(_FACTS + _IDLE)
	var removed_diagnostics := WyrdDiagnostics.new()
	WyrdCondition.new().compile("known(player, world.storm_heard)", removed_runtime.content().schema, removed_diagnostics, "sample.wyrd", 1, 1)
	assert_true(_codes(removed_diagnostics).has("E_KNOWN_REMOVED"), removed_diagnostics.format())
	assert_true(removed_diagnostics.format().contains("knows"), removed_diagnostics.format())
	var runtime := _boot(_FACTS + _IDLE)
	assert_false(_eval(runtime, "knows(player, world.storm_heard)"))
	runtime.facts.set_in(&"world.storm_heard", true, &"known/player")
	assert_true(_eval(runtime, "knows(player, world.storm_heard)"))
	assert_false(_eval(runtime, "believes(player, world.storm_heard)"))
	runtime.roles.define(&"ferry_master", "none")
	runtime.roles.assign(&"ferry_master", &"ferry_master")
	assert_true(_eval(runtime, "knows(player, role.ferry_master.holder)"))
	assert_true(_eval(runtime, "knows(dock_apprentice, role.ferry_master.holder)"))


func test_lookup_trace_is_one_line_and_filterable() -> void:
	var runtime := _boot(_FACTS + _IDLE)
	runtime.trace.enabled = true
	assert_false(_eval(runtime, "believes(player, world.storm_heard)"))
	var first := _lookups(runtime)
	assert_eq(first.size(), 1)
	assert_eq(String(first[0]["agent"]), "player")
	assert_eq(String(first[0]["key"]), "world.storm_heard")
	assert_eq(String(first[0]["source"]), "none")
	assert_eq(String(first[0]["value"]), "")
	runtime.facts.set_in(&"world.storm_heard", true, &"believed/player")
	assert_true(_eval(runtime, "belief(player, world.storm_heard) == true"))
	var own := _lookups(runtime)
	assert_eq(String(own[own.size() - 1]["source"]), "own")
	assert_eq(String(own[own.size() - 1]["value"]), "true")
	runtime.facts.clear_in(&"world.storm_heard", &"believed/player")
	runtime.facts.set_in(&"world.storm_heard", false, &"held/harbor_guild")
	_host(runtime).world.set_groups(&"player", PackedStringArray([&"harbor_guild"]))
	runtime.invalidate_groups()
	assert_false(_eval(runtime, "believes(player, world.storm_heard)"))
	var grouped := _lookups(runtime)
	assert_eq(String(grouped[grouped.size() - 1]["source"]), "group harbor_guild")
	assert_eq(String(grouped[grouped.size() - 1]["value"]), "false")
	var before := _lookups(runtime).size()
	assert_false(_eval(runtime, "held(harbor_guild, world.storm_heard)"))
	assert_eq(_lookups(runtime).size(), before)
	runtime.trace.prefix = "other"
	assert_false(_eval(runtime, "believes(ferry_master, world.storm_heard) or believes(player, world.storm_heard)"))
	assert_eq(_lookups(runtime).size(), before)
	runtime.trace.prefix = "player"
	assert_false(_eval(runtime, "believes(ferry_master, world.storm_heard) or believes(player, player.coins)"))
	var filtered := _lookups(runtime)
	assert_gt(filtered.size(), before)
	for row in filtered.slice(before):
		assert_true(String(row["agent"]) == "player" or String(row["key"]).begins_with("player"))
	runtime.trace.enabled = false
	runtime.trace.events.clear()
	assert_false(_eval(runtime, "believes(player, world.storm_heard)"))
	assert_eq(runtime.trace.events.size(), 0)


func test_membership_cache_and_groups_changed() -> void:
	var runtime := _boot(_FACTS + _SCENE)
	var host: WyrdFakeHost = _host(runtime)
	runtime.tick(0)
	assert_eq(runtime.quests.stage("rumour"), "hear")
	assert_eq(_flag(runtime, "believes"), 0)
	assert_false(_eval(runtime, "believes(player, world.storm_heard)"))
	runtime.facts.set_in(&"world.storm_heard", true, &"held/harbor_guild")
	host.world.set_groups(&"player", PackedStringArray([&"harbor_guild"]))
	assert_false(_eval(runtime, "believes(player, world.storm_heard)"))
	runtime.invalidate_groups()
	assert_true(_eval(runtime, "believes(player, world.storm_heard)"))
	runtime.tick(0)
	assert_eq(_flag(runtime, "believes"), 1)
	assert_eq(runtime.quests.stage("rumour"), "hear")
	host.world.set_groups(&"dock_apprentice", PackedStringArray([&"harbor_guild"]))
	runtime.events.emit(&"groups_changed", {})
	assert_eq(runtime.quests.stage("rumour"), "done")
	host.world.set_groups(&"player", PackedStringArray())
	runtime.events.emit(&"groups_changed", {})
	assert_eq(_flag(runtime, "believes"), 0)


func test_belief_rechecks_unwilling_and_barred() -> void:
	var runtime := _boot(_FACTS + _GATE)
	var host: WyrdFakeHost = _host(runtime)
	_people(host)
	runtime.roles.define(&"ferry_master", "none")
	runtime.roles.assign(&"ferry_master", &"ferry_master")
	runtime.tick(0)
	assert_eq(runtime.roles.slot_state(&"keeper", "gate"), &"default")
	assert_eq(runtime.quests.variant_of("gate"), "keeper.default")
	runtime.facts.set_in(&"world.storm_heard", true, &"believed/ferry_master")
	runtime.tick(0)
	assert_eq(runtime.roles.slot_state(&"keeper", "gate"), &"unwilling")
	assert_eq(runtime.quests.variant_of("gate"), "keeper.unwilling")
	runtime.facts.set_in(&"world.storm_heard", false, &"believed/ferry_master")
	runtime.tick(0)
	assert_eq(runtime.roles.slot_state(&"keeper", "gate"), &"default")
	runtime.facts.clear_in(&"world.storm_heard", &"believed/ferry_master")
	runtime.facts.set_in(&"world.storm_heard", true, &"held/harbor_guild")
	host.world.set_groups(&"ferry_master", PackedStringArray([&"harbor_guild"]))
	runtime.invalidate_groups()
	runtime.tick(0)
	assert_eq(runtime.roles.slot_state(&"keeper", "gate"), &"unwilling")
	runtime.facts.set_in(&"world.storm_heard", true, &"believed/player")
	runtime.tick(0)
	assert_eq(runtime.roles.slot_state(&"keeper", "gate"), &"barred")
	assert_eq(runtime.quests.variant_of("gate"), "keeper.barred")
	runtime.trace.enabled = true
	runtime.roles.define(&"dock_apprentice", "none")
	runtime.roles.assign(&"dock_apprentice", &"player")
	runtime.roles.vacate(&"dock_apprentice", &"left")
	assert_eq(_lookups(runtime).size(), 0)


func test_cast_and_eligibility_read_beliefs() -> void:
	var runtime := _boot(_FACTS + _CAST)
	var host: WyrdFakeHost = _host(runtime)
	_people(host)
	runtime.facts.set_in(&"world.storm_heard", true, &"believed/ferry_master")
	runtime.roles.begin_quest("watch")
	assert_eq(runtime.roles.slot_holder("watch", &"lookout"), &"ferry_master")
	runtime.roles.define(&"ferry_master", "none", false, -1, "", "believes(candidate, world.storm_heard)")
	assert_true(runtime.roles.eligible(&"ferry_master", &"ferry_master"))
	assert_false(runtime.roles.eligible(&"ferry_master", &"dock_apprentice"))
	runtime.facts.set_in(&"world.storm_heard", false, &"believed/ferry_master")
	assert_false(runtime.roles.eligible(&"ferry_master", &"ferry_master"))


const _IDLE := """
quest idle "Idle"
  stage post
    waits_until false
"""


const _SCENE := """
quest rumour "Rumour"
  stage hear
    waits_until believes(dock_apprentice, world.storm_heard)
    -> done
  stage done
scene room
  when believes(player, world.storm_heard): narrator: Believes. #line:believes
  -> end
"""


const _GATE := """
quest gate "Gate"
  slot keeper = ferry_master mode: live
  stage arrive
    variant keeper.barred(believes(player, world.storm_heard)):
      journal: Barred. #line:j_barred
      waits_until false
    variant keeper.unwilling(believes($h, world.storm_heard)):
      journal: Unwilling. #line:j_unwilling
      waits_until false
    variant keeper.default:
      journal: Default. #line:j_default
      waits_until false
"""


const _CAST := """
quest watch "Watch"
  slot lookout = dock_apprentice mode: cast(believes(candidate, world.storm_heard))
  stage post
    waits_until false
"""


func _boot(body: String) -> WyrdRuntime:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	runtime.set_meta(&"host", host)
	var path := "user://wyrd_m5_belief_conditions.wyrd"
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


func _people(host: WyrdFakeHost) -> void:
	host.world.add_entity(&"player", &"person", "traveler", PackedStringArray(), true)
	host.world.add_entity(&"ferry_master", &"person", "ferry master", PackedStringArray([&"local"]), true)
	host.world.add_entity(&"dock_apprentice", &"person", "dock apprentice", PackedStringArray([&"local"]), true)


func _eval(runtime: WyrdRuntime, text: String) -> bool:
	var diagnostics := WyrdDiagnostics.new()
	var compiled := WyrdCondition.new().compile(
		text,
		runtime.content().schema,
		diagnostics,
		"sample.wyrd",
		1,
		1
	)
	assert_false(diagnostics.has_errors(), "%s %s" % [text, diagnostics.format()])
	return runtime.eval_bool(compiled)


func _compile(runtime: WyrdRuntime, text: String) -> WyrdCompiledCondition:
	var diagnostics := WyrdDiagnostics.new()
	var compiled := WyrdCondition.new().compile(
		text,
		runtime.content().schema,
		diagnostics,
		"sample.wyrd",
		1,
		1
	)
	assert_eq(_codes(diagnostics), [], "%s %s" % [text, diagnostics.format()])
	return compiled


func _compile_text(text: String) -> Array:
	var runtime := _boot(_FACTS + _IDLE)
	var diagnostics := WyrdDiagnostics.new()
	WyrdCondition.new().compile(text, runtime.content().schema, diagnostics, "sample.wyrd", 1, 1)
	return _codes(diagnostics)


func _codes(diagnostics: WyrdDiagnostics) -> Array:
	var codes: Array = []
	for item in diagnostics.items:
		codes.append(String(item.code))
	return codes


func _names(compiled: WyrdCompiledCondition) -> Array:
	var names: Array = []
	for item in compiled.consts:
		if item is StringName:
			names.append(String(item))
	return names


func _lookups(runtime: WyrdRuntime) -> Array:
	var rows: Array = []
	for row in runtime.trace.events:
		if String(row.get("kind", "")) == "belief_lookup":
			rows.append(row)
	return rows


func _lookup(runtime: WyrdRuntime, agent: String, key: String) -> Dictionary:
	runtime.trace.enabled = true
	var before := _lookups(runtime).size()
	_eval(runtime, "belief(%s, %s) == true" % [agent, key])
	var rows := _lookups(runtime)
	assert_gt(rows.size(), before)
	return rows[rows.size() - 1]


func _flag(runtime: WyrdRuntime, record: String) -> int:
	var content := runtime.content()
	for i in content.conditions.size():
		if content.records[i] == record and content.sites[i] == "when":
			return int(runtime.condition_flags()[i])
	return -1
