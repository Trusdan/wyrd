extends GutTest

## WFR9 group-position conflicts. The condition is conflicted, not the M4 slot state.


const _FACTS := """
language 1
events
  groups_changed()
facts
  world.storm_heard : bool stored
  player.coins : int stored
  harbor.toll_tale : symbol stored
"""


func test_disagreement_is_conflicted_and_own_belief_is_not() -> void:
	var runtime := _boot(_FACTS + _IDLE)
	var host: WyrdFakeHost = _host(runtime)
	assert_false(_eval(runtime, "conflicted(player, world.storm_heard)"))
	runtime.facts.set(&"world.storm_heard", true)
	runtime.facts.set_in(&"world.storm_heard", true, &"known/player")
	runtime.facts.set_in(&"world.storm_heard", true, &"believed/player")
	assert_false(_eval(runtime, "conflicted(player, world.storm_heard)"))
	assert_true(_eval(runtime, "believes(player, world.storm_heard)"))
	host.world.set_groups(&"player", PackedStringArray([&"harbor_guild"]))
	runtime.invalidate_groups()
	runtime.facts.set_in(&"world.storm_heard", false, &"held/harbor_guild")
	assert_false(_eval(runtime, "conflicted(player, world.storm_heard)"))
	assert_true(_eval(runtime, "believes(player, world.storm_heard)"))
	runtime.facts.clear_in(&"world.storm_heard", &"believed/player")
	assert_false(_eval(runtime, "conflicted(player, world.storm_heard)"))
	assert_false(_eval(runtime, "believes(player, world.storm_heard)"))
	host.world.set_groups(&"player", PackedStringArray([&"harbor_guild", &"faction.harbor"]))
	runtime.invalidate_groups()
	runtime.facts.set_in(&"world.storm_heard", false, &"held/faction.harbor")
	assert_false(_eval(runtime, "conflicted(player, world.storm_heard)"))
	runtime.facts.set_in(&"world.storm_heard", true, &"held/faction.harbor")
	assert_true(_eval(runtime, "conflicted(player, world.storm_heard)"))
	assert_true(_eval(runtime, "conflicted(player, world.storm_heard) == true"))
	assert_false(_eval(runtime, "believes(player, world.storm_heard)"))
	assert_true(_eval(runtime, "believes(player, world.storm_heard) == false"))
	assert_eq(runtime.facts.get(&"world.storm_heard"), true)
	assert_true(_eval(runtime, "knows(player, world.storm_heard)"))
	runtime.facts.set_in(&"world.storm_heard", true, &"believed/player")
	assert_true(_eval(runtime, "conflicted(player, world.storm_heard)"))
	assert_true(_eval(runtime, "believes(player, world.storm_heard)"))


func test_absence_is_not_a_position_and_values_compare_by_type() -> void:
	var runtime := _boot(_FACTS + _IDLE)
	var host: WyrdFakeHost = _host(runtime)
	host.world.set_groups(&"ferry_master", PackedStringArray([&"harbor_guild", &"faction.harbor"]))
	runtime.facts.set_in(&"world.storm_heard", false, &"held/harbor_guild")
	assert_false(_eval(runtime, "conflicted(ferry_master, world.storm_heard)"))
	runtime.facts.set_in(&"player.coins", 0, &"held/harbor_guild")
	runtime.facts.set_in(&"player.coins", 4, &"held/faction.harbor")
	assert_true(_eval(runtime, "conflicted(ferry_master, player.coins)"))
	runtime.facts.set_in(&"player.coins", 4, &"held/harbor_guild")
	assert_false(_eval(runtime, "conflicted(ferry_master, player.coins)"))
	runtime.facts.set_in(&"harbor.toll_tale", &"stolen", &"held/harbor_guild")
	runtime.facts.set_in(&"harbor.toll_tale", &"lost", &"held/faction.harbor")
	assert_true(_eval(runtime, "conflicted(ferry_master, harbor.toll_tale)"))
	runtime.facts.set_in(&"harbor.toll_tale", &"stolen", &"held/faction.harbor")
	assert_false(_eval(runtime, "conflicted(ferry_master, harbor.toll_tale)"))
	runtime.facts.set_in(&"world.storm_heard", false, &"held/faction.harbor")
	assert_false(_eval(runtime, "conflicted(ferry_master, world.storm_heard)"))


func test_precedence_names_the_first_present_group() -> void:
	var runtime := _boot(_FACTS + _IDLE)
	var host: WyrdFakeHost = _host(runtime)
	host.world.set_groups(&"player", PackedStringArray([&"harbor_guild", &"faction.harbor"]))
	runtime.facts.set_in(&"world.storm_heard", false, &"held/harbor_guild")
	runtime.facts.set_in(&"world.storm_heard", true, &"held/faction.harbor")
	runtime.trace.enabled = true
	assert_true(_eval(runtime, "conflicted(player, world.storm_heard)"))
	var first := _conflicts(runtime)
	assert_eq(first.size(), 1)
	assert_eq(String(first[0]["source"]), "group harbor_guild")
	assert_eq(String(first[0]["value"]), "false")
	assert_eq(String(first[0]["against"]), "faction.harbor")
	assert_eq(String(first[0]["conflicted"]), "true")
	runtime.register_group_precedence(func(_agent: StringName, groups: PackedStringArray) -> PackedStringArray:
		var flipped := PackedStringArray()
		for i in range(groups.size() - 1, -1, -1):
			flipped.append(groups[i])
		return flipped
	)
	assert_true(_eval(runtime, "conflicted(player, world.storm_heard)"))
	assert_true(_eval(runtime, "believes(player, world.storm_heard)"))
	var flipped_row := _conflicts(runtime)
	assert_eq(String(flipped_row[flipped_row.size() - 1]["source"]), "group faction.harbor")
	assert_eq(String(flipped_row[flipped_row.size() - 1]["value"]), "true")
	assert_eq(String(flipped_row[flipped_row.size() - 1]["against"]), "harbor_guild")


func test_conflict_trace_is_one_line_and_filterable() -> void:
	var runtime := _boot(_FACTS + _IDLE)
	var host: WyrdFakeHost = _host(runtime)
	runtime.trace.enabled = true
	assert_false(_eval(runtime, "conflicted(player, world.storm_heard)"))
	var none := _conflicts(runtime)
	assert_eq(none.size(), 1)
	assert_eq(String(none[0]["agent"]), "player")
	assert_eq(String(none[0]["key"]), "world.storm_heard")
	assert_eq(String(none[0]["conflicted"]), "false")
	assert_eq(String(none[0]["source"]), "none")
	assert_eq(String(none[0]["value"]), "")
	assert_eq(String(none[0]["against"]), "")
	host.world.set_groups(&"player", PackedStringArray([&"harbor_guild", &"faction.harbor"]))
	runtime.invalidate_groups()
	runtime.facts.set_in(&"world.storm_heard", false, &"held/harbor_guild")
	runtime.facts.set_in(&"world.storm_heard", false, &"held/faction.harbor")
	assert_false(_eval(runtime, "conflicted(player, world.storm_heard)"))
	var agreed := _conflicts(runtime)
	assert_eq(agreed.size(), 2)
	assert_eq(String(agreed[1]["source"]), "group harbor_guild")
	assert_eq(String(agreed[1]["conflicted"]), "false")
	assert_eq(String(agreed[1]["against"]), "")
	var before := agreed.size()
	assert_false(_eval(runtime, "held(harbor_guild, world.storm_heard)"))
	assert_false(_eval(runtime, "believes(player, world.storm_heard)"))
	assert_eq(_conflicts(runtime).size(), before)
	runtime.trace.prefix = "other"
	assert_false(_eval(runtime, "conflicted(player, world.storm_heard) or conflicted(ferry_master, player.coins)"))
	assert_eq(_conflicts(runtime).size(), before)
	runtime.trace.prefix = "player"
	assert_false(_eval(runtime, "conflicted(ferry_master, world.storm_heard) or conflicted(player, player.coins)"))
	var filtered := _conflicts(runtime)
	assert_gt(filtered.size(), before)
	for row in filtered.slice(before):
		assert_true(String(row["agent"]) == "player" or String(row["key"]).begins_with("player"))
	runtime.trace.prefix = "world.storm"
	var marked := _conflicts(runtime).size()
	assert_false(_eval(runtime, "conflicted(ferry_master, world.storm_heard)"))
	assert_eq(_conflicts(runtime).size(), marked + 1)
	runtime.trace.enabled = false
	runtime.trace.prefix = ""
	runtime.trace.events.clear()
	assert_false(_eval(runtime, "conflicted(player, world.storm_heard)"))
	assert_eq(runtime.trace.events.size(), 0)
	var direct := _boot(_FACTS + _IDLE)
	direct.trace.enabled = true
	var fn: Callable = direct.function_table()[&"conflicted"]
	assert_false(fn.call([null, &"world.storm_heard"]))
	assert_eq(_conflicts(direct).size(), 0)
	assert_false(fn.call([&"player", 4]))
	var blank := _conflicts(direct)
	assert_eq(blank.size(), 1)
	assert_eq(String(blank[0]["key"]), "")
	assert_eq(String(blank[0]["source"]), "none")
	assert_eq(String(blank[0]["conflicted"]), "false")


func test_contested_call_is_unknown_and_conflicted_reads_membership() -> void:
	var unknown := _compile_text("contested(player, world.storm_heard)")
	assert_true(unknown.has("E_UNKNOWN_FUNCTION"), str(unknown))
	var runtime := _boot(_FACTS + _IDLE)
	var compiled := _compile(runtime, "conflicted(player, world.storm_heard)")
	assert_true(compiled.reads.has(&"world.storm_heard"))
	assert_true(compiled.reads.has(&"group.membership"))
	var held := _compile(runtime, "held(harbor_guild, world.storm_heard)")
	assert_false(held.reads.has(&"group.membership"))


func test_scene_wakes_on_the_second_position_and_on_membership() -> void:
	var runtime := _boot(_FACTS + _SCENE)
	var host: WyrdFakeHost = _host(runtime)
	host.world.set_groups(&"player", PackedStringArray([&"harbor_guild", &"faction.harbor"]))
	runtime.tick(0)
	assert_eq(_flag(runtime, "conflicted"), 0)
	runtime.facts.set_in(&"world.storm_heard", false, &"held/harbor_guild")
	runtime.tick(0)
	assert_eq(_flag(runtime, "conflicted"), 0)
	runtime.facts.set_in(&"world.storm_heard", true, &"held/faction.harbor")
	runtime.tick(0)
	assert_eq(_flag(runtime, "conflicted"), 1)
	var cached := _boot(_FACTS + _SCENE)
	var cached_host: WyrdFakeHost = _host(cached)
	cached.tick(0)
	assert_false(_eval(cached, "conflicted(player, world.storm_heard)"))
	cached_host.world.set_groups(&"player", PackedStringArray([&"harbor_guild", &"faction.harbor"]))
	cached.facts.set_in(&"world.storm_heard", false, &"held/harbor_guild")
	cached.facts.set_in(&"world.storm_heard", true, &"held/faction.harbor")
	cached.tick(0)
	assert_eq(_flag(cached, "conflicted"), 0)
	cached.events.emit(&"groups_changed", {})
	cached.tick(0)
	assert_eq(_flag(cached, "conflicted"), 1)


const _IDLE := """
quest idle "Idle"
  stage post
    waits_until false
"""


const _SCENE := """
quest rumour "Rumour"
  stage hear
    waits_until false
scene room
  when conflicted(player, world.storm_heard): narrator: Conflicted. #line:conflicted
  -> end
"""


func _boot(body: String) -> WyrdRuntime:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	runtime.set_meta(&"host", host)
	var path := "user://wyrd_m5_conflicted.wyrd"
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


func _conflicts(runtime: WyrdRuntime) -> Array:
	var rows: Array = []
	for row in runtime.trace.events:
		if String(row.get("kind", "")) == "conflict":
			rows.append(row)
	return rows


func _flag(runtime: WyrdRuntime, record: String) -> int:
	var content := runtime.content()
	for i in content.conditions.size():
		if content.records[i] == record and content.sites[i] == "when":
			return int(runtime.condition_flags()[i])
	return -1
