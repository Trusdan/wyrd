extends GutTest


func test_succession_chain_none_and_secret() -> void:
	var opened := _open()
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	for id in ["ada", "bea", "cy"]:
		host.world.add_entity(StringName(id), &"person", id, PackedStringArray(), true)
	runtime.roles.define(&"dock_keeper", "relation(apprentice|kin)")
	runtime.roles.define(&"ferry_master", "none", true)
	runtime.social.set_kind(&"ada", &"bea", &"apprentice")
	runtime.social.set_kind(&"ada", &"cy", &"kin")
	runtime.social.set_kind(&"bea", &"cy", &"apprentice")
	host.world.add_entity(&"bea", &"person", "bea", PackedStringArray(), false)
	runtime.roles.assign(&"dock_keeper", &"ada")
	assert_eq(runtime.roles.binding_status(&"dock_keeper"), &"default")
	var changed: Array = []
	var vacant: Array = []
	runtime.roles.role_holder_changed.connect(func(role: StringName, old_h: StringName, new_h: StringName) -> void:
		changed.append([String(role), String(old_h), String(new_h)])
	)
	runtime.roles.role_vacant.connect(func(role: StringName) -> void: vacant.append(String(role)))
	runtime.roles.vacate(&"dock_keeper", &"died")
	assert_eq(runtime.roles.holder(&"dock_keeper"), &"cy")
	assert_eq(runtime.roles.binding_status(&"dock_keeper"), &"successor")
	assert_eq(runtime.roles.history(&"dock_keeper").size(), 1)
	assert_eq(runtime.roles.history(&"dock_keeper")[0]["reason"], &"died")
	assert_eq(runtime.deeds.count_matching(&"ada", &"role_changed", &"cy"), 1)
	host.world.add_entity(&"cy", &"person", "cy", PackedStringArray(), true)
	runtime.roles.vacate(&"dock_keeper", &"quit")
	assert_eq(runtime.roles.holder(&"dock_keeper"), &"")
	assert_eq(vacant, ["dock_keeper"])
	runtime.roles.vacate(&"dock_keeper", &"again")
	assert_eq(vacant.size(), 1)
	runtime.roles.assign(&"ferry_master", &"ada")
	assert_false(runtime.roles.revealed(&"player", &"role.ferry_master.holder"))
	assert_null(runtime.facts.get_in(&"role.ferry_master.holder", &"known/player"))
	runtime.roles.tell(&"ferry_master", &"player")
	assert_true(runtime.roles.revealed(&"player", &"role.ferry_master.holder"))
	assert_false(runtime.roles.revealed(&"clerk", &"role.ferry_master.holder"))
	assert_eq(runtime.facts.get_in(&"role.ferry_master.holder", &"known/player"), &"ada")
	runtime.roles.vacate(&"ferry_master", &"exposed")
	assert_eq(runtime.facts.get_in(&"role.ferry_master.holder", &"known/player"), &"")
	assert_true(runtime.roles.revealed(&"player", &"role.ferry_master.holder"))
	runtime.roles.define(&"watcher", "public")
	assert_push_error("not a role succession")
	assert_eq(changed[0][2], "cy")
	runtime.social.set_kind(&"ada", &"bea", &"apprentice")
	host.world.add_entity(&"bea", &"person", "bea", PackedStringArray(), true)
	host.world.add_entity(&"cy", &"person", "cy", PackedStringArray(), true)
	runtime.roles.assign(&"dock_keeper", &"ada")
	runtime.roles.vacate(&"dock_keeper", &"died")
	assert_eq(runtime.roles.holder(&"dock_keeper"), &"bea")


func test_slot_modes_and_states() -> void:
	var opened := _open(true)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.world.add_entity(&"ada", &"person", "Ada", PackedStringArray(), true)
	host.world.add_entity(&"bea", &"person", "Bea", PackedStringArray(), true)
	runtime.roles.define(&"dock_keeper", "relation(apprentice)")
	runtime.roles.define(&"ferry_master", "relation(apprentice)")
	runtime.roles.define(&"watcher", "none")
	runtime.social.set_kind(&"ada", &"bea", &"apprentice")
	assert_eq(runtime.roles.slot_state(&"keeper"), &"empty")
	assert_eq(_flag(runtime, "empty"), 1)
	runtime.roles.assign(&"dock_keeper", &"ada")
	runtime.tick(0)
	assert_eq(runtime.roles.slot_state(&"keeper"), &"default")
	assert_eq(runtime.roles.holder(&"keeper"), &"ada")
	runtime.social.set_baseline(&"ada", &"player", &"affinity", -60.0)
	assert_eq(runtime.social.disposition(&"ada", &"player"), 20)
	assert_eq(runtime.roles.slot_state(&"keeper"), &"default")
	runtime.social.set_baseline(&"ada", &"player", &"affinity", -62.0)
	assert_eq(runtime.social.disposition(&"ada", &"player"), 19)
	runtime.tick(0)
	assert_eq(runtime.roles.slot_state(&"keeper"), &"hostile")
	assert_eq(_flag(runtime, "hostile"), 1)
	assert_eq(_flag(runtime, "cold"), 1)
	runtime.config().hostile_threshold = 10
	assert_eq(runtime.roles.slot_state(&"keeper"), &"default")
	runtime.roles.define(&"dock_keeper", "relation(apprentice)", false, 100)
	assert_eq(runtime.roles.slot_state(&"keeper"), &"hostile")
	runtime.roles.define(&"dock_keeper", "relation(apprentice)")
	runtime.social.set_baseline(&"ada", &"player", &"affinity", 0.0)
	runtime.roles.vacate(&"dock_keeper", &"died")
	assert_eq(runtime.roles.slot_state(&"keeper"), &"successor")
	assert_eq(runtime.roles.holder(&"keeper"), &"bea")
	runtime.roles.enter_stage("gate", "arrive")
	assert_eq(runtime.roles.slot_holder("gate", &"ferry"), &"")
	runtime.roles.assign(&"ferry_master", &"ada")
	runtime.roles.enter_stage("gate", "pay")
	runtime.roles.vacate(&"ferry_master", &"died")
	assert_eq(runtime.roles.slot_holder("gate", &"ferry"), &"ada")
	assert_eq(runtime.roles.slot_state(&"ferry", "gate"), &"default")
	assert_eq(runtime.roles.holder(&"ferry_master"), &"bea")
	runtime.config().hostile_threshold = 20
	runtime.social.set_baseline(&"ada", &"player", &"affinity", -80.0)
	assert_eq(runtime.roles.slot_state(&"ferry", "gate"), &"hostile")
	runtime.roles.enter_stage("gate", "pay")
	assert_eq(runtime.roles.slot_holder("gate", &"ferry"), &"ada")
	runtime.roles.begin_quest("gate")
	assert_push_warning("casting is M4")
	assert_eq(runtime.roles.slot_holder("gate", &"lookout"), &"")
	runtime.roles.assign(&"watcher", &"ada")
	runtime.roles.begin_quest("gate")
	assert_eq(runtime.roles.slot_holder("gate", &"lookout"), &"")
	assert_eq(runtime.roles.slot_state(&"lookout", "gate"), &"empty")
	runtime.start_new_game(9)
	runtime.roles.assign(&"watcher", &"bea")
	runtime.roles.vacate(&"watcher", &"left")
	runtime.roles.begin_quest("gate")
	assert_push_warning("casting is M4")
	runtime.roles.assign(&"watcher", &"ada")
	assert_eq(runtime.roles.slot_holder("gate", &"lookout"), &"")
	runtime.start_new_game(9)
	runtime.roles.define(&"watcher", "relation(apprentice)")
	runtime.roles.assign(&"watcher", &"ada")
	runtime.social.set_kind(&"ada", &"bea", &"apprentice")
	runtime.roles.vacate(&"watcher", &"left")
	runtime.roles.begin_quest("gate")
	assert_push_warning("casting is M4")
	assert_eq(runtime.roles.slot_holder("gate", &"lookout"), &"bea")
	assert_eq(runtime.roles.slot_state(&"lookout", "gate"), &"successor")
	runtime.roles.assign(&"watcher", &"ada")
	assert_eq(runtime.roles.slot_holder("gate", &"lookout"), &"bea")


func test_conditions_read_deeds_and_known_player() -> void:
	var opened := _open(true)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.roles.define(&"dock_keeper", "none", true)
	runtime.roles.assign(&"dock_keeper", &"ada")
	runtime.facts.set(&"player.coins", 4)
	runtime.tick(0)
	assert_eq(_flag(runtime, "coins"), 0)
	assert_eq(_flag(runtime, "secret"), 0)
	assert_eq(_flag(runtime, "count"), 0)
	runtime.facts.set_in(&"player.coins", 4, &"known/player")
	runtime.tick(0)
	assert_eq(_flag(runtime, "coins"), 1)
	runtime.roles.tell(&"dock_keeper", &"player")
	runtime.tick(0)
	assert_eq(_flag(runtime, "secret"), 1)
	assert_false(runtime.roles.revealed(&"clerk", &"role.dock_keeper.holder"))
	runtime.deeds.record(&"gift", &"player", &"keeper")
	runtime.tick(0)
	assert_eq(_flag(runtime, "count"), 1)
	runtime.facts.set(&"player.coins", 0)
	var compiled := WyrdCondition.new().compile(
		"player.coins > 0",
		runtime.content().schema,
		WyrdDiagnostics.new(),
		"sample.wyrd",
		1,
		1
	)
	assert_eq(WyrdRpnEval.new().eval(compiled, {}, runtime.function_table()), false)
	assert_true(runtime.social.has_kind(&"ada", &"bea", &"apprentice") == false)
	runtime.social.set_kind(&"ada", &"bea", &"apprentice")
	assert_true(runtime.social.has_kind(&"ada", &"bea", &"apprentice"))
	assert_eq(runtime.roles.binding_since(&"dock_keeper"), 0)


func _open(with_content: bool = false) -> Dictionary:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	if with_content:
		var path := "user://wyrd_s2b_roles.wyrd"
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(_BODY)
		file.close()
		var manifest := WyrdContentManifest.new()
		manifest.pack_id = &"sample"
		manifest.language_version = 1
		manifest.files = PackedStringArray([path])
		var report := runtime.load_content(manifest)
		assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(8)
	if with_content:
		runtime.tick(0)
	return {"host": host, "runtime": runtime}


func _flag(runtime: WyrdRuntime, record: String) -> int:
	var content := runtime.content()
	for i in content.conditions.size():
		if content.records[i] == record and content.sites[i] == "when":
			return int(runtime.condition_flags()[i])
	return -1


const _BODY := """
language 1
facts
  player.coins : int stored
  role.dock_keeper.holder : symbol stored
quest gate "Gate"
  slot keeper = dock_keeper mode: live
  slot ferry = ferry_master mode: locked_at(pay)
  slot lookout = watcher mode: cast(player.coins >= 0)
  on_empty: wait
  stage arrive
    -> pay
  stage pay
    -> done
  stage done
scene room
  when deed_count(player, verb: gift, against: keeper) > 0: narrator: Count. #line:count
  when known(player, role.dock_keeper.holder): narrator: Secret. #line:secret
  when known(player, player.coins): narrator: Coins. #line:coins
  when slot_state(keeper) == empty: narrator: Empty. #line:empty
  when slot_state(keeper) == hostile: narrator: Hostile. #line:hostile
  when disposition(holder(keeper), player) < 20: narrator: Cold. #line:cold
  -> end
"""
