extends GutTest


func test_assign_refusals_status_history_and_host_assign() -> void:
	var opened := _boot(_TINY)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	_people(host)
	runtime.trace.enabled = true
	assert_false(runtime.roles.assign_from_content(&"missing", &"ada"))
	assert_push_error("unknown role \"missing\"")
	assert_eq(_reasons(runtime, "role_assign").size(), 0)
	runtime.roles.define(&"keeper", "none", false, -1, "", "", &"", "abolish")
	runtime.roles.assign(&"keeper", &"ada")
	runtime.roles.vacate(&"keeper", &"left")
	assert_true(runtime.roles.abolished(&"keeper"))
	assert_false(runtime.roles.assign_from_content(&"keeper", &"bea"))
	assert_eq(_reasons(runtime, "role_assign"), PackedStringArray(["abolished"]))
	assert_push_warning("assign_from_content: \"keeper\" is abolished")
	runtime.roles.define(&"vote", "host_decides")
	runtime.roles.assign(&"vote", &"ada")
	assert_true(runtime.roles.vacate_from_content(&"vote"))
	host.world.add_entity(&"bea", &"person", "Bea", PackedStringArray(), false)
	assert_false(runtime.roles.assign_from_content(&"vote", &"bea"))
	assert_eq(_last(runtime, "role_assign")["reason"], "contested")
	assert_push_warning("assign_from_content: \"vote\" is contested")
	runtime.roles.define(&"tagged", "none", false, -1, "", "has_tag(candidate, local)")
	assert_false(runtime.roles.assign_from_content(&"tagged", &"nobody"))
	assert_eq(_last(runtime, "role_assign")["reason"], "no_entity")
	assert_false(runtime.roles.assign_from_content(&"tagged", &"cy"))
	assert_eq(_last(runtime, "role_assign")["reason"], "ineligible")
	assert_push_warning("has no living entity")
	assert_push_warning("is ineligible")
	assert_true(runtime.roles.assign_from_content(&"tagged", &"ada"))
	assert_eq(String(runtime.roles.binding_status(&"tagged")), "successor")
	assert_eq(runtime.deeds.count_matching(&"ada", &"role_changed", &"ada"), 0)
	var before := runtime.deeds.size()
	assert_false(runtime.roles.assign_from_content(&"tagged", &"ada"))
	assert_eq(_last(runtime, "role_assign")["reason"], "same_holder")
	assert_eq(_last(runtime, "role_assign")["ok"], "false")
	assert_eq(runtime.deeds.size(), before)
	host.world.add_entity(&"bea", &"person", "Bea", PackedStringArray(["local"]), true)
	assert_true(runtime.roles.assign_from_content(&"tagged", &"bea"))
	assert_push_warning_count(4)
	assert_eq(String(runtime.roles.holder(&"tagged")), "bea")
	assert_eq(String(runtime.roles.binding_status(&"tagged")), "successor")
	var history: Array = runtime.roles.export_state()["bindings"]["tagged"]["history"]
	var prior: Dictionary = history[history.size() - 1]
	assert_eq(str(prior["holder"]), "ada")
	assert_eq(str(prior["reason"]), "assign")
	var deed: Dictionary = runtime.deeds.row_at(runtime.deeds.size() - 1)
	assert_eq(String(deed["verb"]), "role_changed")
	assert_eq(String(deed["actor"]), "ada")
	assert_eq(String(deed["target"]), "bea")
	assert_eq(String(deed["visibility"]), "public")
	runtime.roles.define(&"clerk", "none", false, -1, "", "", &"ada")
	assert_eq(String(runtime.roles.binding_status(&"clerk")), "default")
	runtime.roles.vacate_from_content(&"clerk")
	assert_true(runtime.roles.assign_from_content(&"clerk", &"ada"))
	assert_eq(String(runtime.roles.binding_status(&"clerk")), "default")
	assert_true(runtime.roles.assign_from_content(&"clerk", &"cy"))
	assert_eq(String(runtime.roles.binding_status(&"clerk")), "successor")
	assert_eq(String(runtime.roles.holder(&"tagged")), "bea")
	runtime.trace.clear()
	runtime.roles.assign(&"clerk", &"ada")
	assert_eq(String(runtime.roles.binding_status(&"clerk")), "default")
	assert_eq(_reasons(runtime, "role_assign").size(), 0)


func test_vacate_runs_each_strategy_and_refuses() -> void:
	var opened := _boot(_TINY)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	_people(host)
	runtime.social.set_kind(&"ada", &"bea", &"apprentice")
	runtime.roles.define(&"related", "relation(apprentice)")
	runtime.roles.assign(&"related", &"ada")
	runtime.trace.enabled = true
	assert_true(runtime.roles.vacate_from_content(&"related"))
	assert_eq(String(runtime.roles.holder(&"related")), "bea")
	assert_eq(String(runtime.roles.binding_status(&"related")), "successor")
	assert_eq(_last(runtime, "role_vacate")["reason"], "vacated")
	assert_eq(_last(runtime, "role_vacate")["to"], "bea")
	assert_eq(_last(runtime, "role_vacate")["ok"], "true")
	host.world.add_member(&"faction.harbor", &"cy")
	runtime.roles.set_faction_rank(func(_faction: StringName, _entity: StringName) -> int:
		return 1
	)
	runtime.roles.define(&"factor", "faction_assigns(faction.harbor)")
	runtime.roles.assign(&"factor", &"ada")
	assert_true(runtime.roles.vacate_from_content(&"factor"))
	assert_eq(String(runtime.roles.holder(&"factor")), "cy")
	assert_eq(String(runtime.roles.binding_status(&"factor")), "successor")
	var elected: Array = []
	runtime.roles.election_needed.connect(func(role: StringName, _departed: StringName) -> void:
		elected.append(String(role))
	)
	runtime.roles.define(&"reeve", "election")
	runtime.roles.assign(&"reeve", &"ada")
	assert_true(runtime.roles.vacate_from_content(&"reeve"))
	assert_eq(elected, ["reeve"])
	assert_eq(String(runtime.roles.binding_status(&"reeve")), "contested")
	assert_eq(_last(runtime, "role_vacate")["reason"], "vacated")
	assert_eq(_last(runtime, "role_vacate")["to"], "")
	var asked: Array = []
	runtime.roles.succession_requested.connect(func(role: StringName, _departed: StringName) -> void:
		asked.append(String(role))
	)
	runtime.roles.define(&"asked_role", "host_decides")
	runtime.roles.assign(&"asked_role", &"ada")
	assert_true(runtime.roles.vacate_from_content(&"asked_role"))
	assert_eq(asked, ["asked_role"])
	assert_eq(String(runtime.roles.binding_status(&"asked_role")), "contested")
	runtime.roles.define(&"held", "none")
	runtime.roles.assign(&"held", &"ada")
	assert_true(runtime.roles.vacate_from_content(&"held"))
	assert_eq(String(runtime.roles.holder(&"held")), "")
	assert_eq(String(runtime.roles.binding_status(&"held")), "empty")
	assert_eq(_last(runtime, "role_vacate")["to"], "")
	runtime.roles.define(&"ended", "none", false, -1, "", "", &"", "abolish")
	runtime.roles.assign(&"ended", &"ada")
	assert_true(runtime.roles.vacate_from_content(&"ended"))
	assert_true(runtime.roles.abolished(&"ended"))
	assert_eq(String(runtime.roles.holder(&"ended")), "")
	assert_eq(_last(runtime, "role_vacate")["reason"], "vacated")
	assert_false(runtime.roles.vacate_from_content(&"missing"))
	assert_push_error("unknown role \"missing\"")
	assert_false(runtime.roles.vacate_from_content(&"ended"))
	assert_eq(_last(runtime, "role_vacate")["reason"], "abolished")
	assert_false(runtime.roles.vacate_from_content(&"reeve"))
	assert_eq(_last(runtime, "role_vacate")["reason"], "contested")
	assert_false(runtime.roles.vacate_from_content(&"held"))
	assert_eq(_last(runtime, "role_vacate")["reason"], "empty")
	assert_push_warning("vacate_from_content: \"ended\" is abolished")
	assert_push_warning("vacate_from_content: \"reeve\" is contested")
	assert_push_warning("vacate_from_content: \"held\" is empty")


func test_slots_rebind_and_locked_assign_stays_usable() -> void:
	var opened := _boot(_SLOTS)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	_people(host)
	runtime.roles.assign(&"dock_keeper", &"ada")
	runtime.roles.assign(&"ferry_master", &"ada")
	runtime.quests.start("liveq")
	runtime.tick(0)
	assert_eq(String(runtime.roles.slot_holder("liveq", &"keeper")), "ada")
	assert_true(runtime.roles.assign_from_content(&"dock_keeper", &"bea"))
	assert_eq(String(runtime.roles.slot_holder("liveq", &"keeper")), "bea")
	runtime.tick(0)
	assert_eq(runtime.quests.variant_of("liveq"), "keeper.successor")
	runtime.quests.start("lockq")
	assert_eq(String(runtime.roles.slot_holder("lockq", &"ferry")), "ada")
	runtime.roles.assign(&"ferry_master", &"bea")
	assert_eq(String(runtime.roles.slot_holder("lockq", &"ferry")), "ada")
	assert_eq(String(runtime.roles.slot_state(&"ferry", "lockq")), "default")
	assert_true(runtime.roles.assign_from_content(&"ferry_master", &"cy"))
	assert_eq(String(runtime.roles.slot_holder("lockq", &"ferry")), "ada")
	assert_ne(String(runtime.roles.slot_state(&"ferry", "lockq")), "locked_gone")
	runtime.tick(0)
	assert_eq(runtime.quests.variant_of("lockq"), "ferry.default")
	var vacated := _boot(_SLOTS)
	var other: WyrdRuntime = vacated["runtime"]
	_people(vacated["host"])
	other.roles.assign(&"ferry_master", &"ada")
	other.quests.start("lockq")
	assert_true(other.roles.vacate_from_content(&"ferry_master"))
	assert_eq(String(other.roles.slot_holder("lockq", &"ferry")), "ada")
	assert_eq(String(other.roles.slot_state(&"ferry", "lockq")), "locked_gone")
	other.tick(0)
	assert_eq(other.quests.variant_of("lockq"), "ferry.locked_gone")
	runtime.quests.start("castq")
	var frozen := String(runtime.roles.slot_holder("castq", &"look"))
	assert_false(frozen.is_empty())
	var replacement := &"bea" if frozen != "bea" else &"cy"
	assert_true(runtime.roles.assign_from_content(&"watcher", replacement))
	assert_eq(String(runtime.roles.slot_holder("castq", &"look")), frozen)
	runtime.roles.define(&"empty_role", "none")
	runtime.roles.assign(&"empty_role", &"ada")
	runtime.quests.start("emptyq")
	runtime.tick(0)
	assert_eq(runtime.quests.variant_of("emptyq"), "seat.default")
	assert_true(runtime.roles.vacate_from_content(&"empty_role"))
	runtime.tick(0)
	assert_eq(String(runtime.roles.slot_state(&"seat", "emptyq")), "empty")
	assert_eq(runtime.quests.variant_of("emptyq"), "seat.empty")
	var heard: Array = []
	runtime.roles.election_needed.connect(func(role: StringName, _departed: StringName) -> void:
		heard.append(String(role))
	)
	runtime.roles.define(&"vote_role", "election")
	runtime.roles.assign(&"vote_role", &"ada")
	runtime.quests.start("voteq")
	runtime.tick(0)
	assert_true(runtime.roles.vacate_from_content(&"vote_role"))
	assert_eq(heard, ["vote_role"])
	runtime.tick(0)
	assert_eq(String(runtime.roles.slot_state(&"seat", "voteq")), "contested")
	assert_eq(runtime.quests.variant_of("voteq"), "seat.contested")


func test_a_choice_keeps_its_speaker_and_another_scene_aborts() -> void:
	var opened := _boot(_SCENES)
	var runtime: WyrdRuntime = opened["runtime"]
	_people(opened["host"])
	runtime.roles.assign(&"dock_keeper", &"ada")
	runtime.quests.start("speakq")
	runtime.dialogue.open_scene("room")
	var hello := runtime.dialogue.line()
	assert_eq(String(hello.speaker), "ada")
	assert_eq(hello.display_name, "Ada")
	runtime.dialogue.advance()
	runtime.dialogue.choose(0)
	assert_true(runtime.dialogue.is_open())
	assert_eq(String(runtime.roles.holder(&"dock_keeper")), "bea")
	var still := runtime.dialogue.line()
	assert_eq(String(still.speaker), "ada")
	assert_eq(still.display_name, "Ada")
	assert_eq(still.text, "Still here.")
	runtime.dialogue.advance()
	assert_false(runtime.dialogue.is_open())
	runtime.roles.assign(&"dock_keeper", &"ada")
	runtime.quests.start("outerq")
	runtime.trace.enabled = true
	runtime.trace.clear()
	runtime.dialogue.open_scene("outer")
	runtime.dialogue.advance()
	runtime.dialogue.advance()
	runtime.dialogue.choose(0)
	assert_false(runtime.dialogue.is_open())
	assert_eq(String(_last(runtime, "abort")["reason"]), "holder_left")
	assert_eq(String(runtime.roles.holder(&"dock_keeper")), "bea")


func test_baseline_values_refusals_and_hostile_recheck() -> void:
	var opened := _boot(_HOSTILE)
	var runtime: WyrdRuntime = opened["runtime"]
	_people(opened["host"])
	runtime.roles.assign(&"dock_keeper", &"ada")
	runtime.quests.start("gate")
	runtime.tick(0)
	assert_eq(runtime.quests.variant_of("gate"), "keeper.default")
	assert_true(runtime.social.adjust_baseline(&"ada", &"player", &"affinity", -2.5))
	assert_eq(_baseline(runtime, "ada", "player", "affinity"), -2.5)
	assert_true(runtime.social.adjust_baseline(&"ada", &"player", &"affinity", 1.25))
	assert_eq(_baseline(runtime, "ada", "player", "affinity"), -1.25)
	var entries := runtime.social.cache_entries()
	var queued := runtime.scheduler().carry("cache_refresh")
	assert_false(runtime.social.adjust_baseline(&"ada", &"player", &"affinity", 0.0))
	assert_eq(runtime.social.cache_entries(), entries)
	assert_eq(runtime.scheduler().carry("cache_refresh"), queued)
	assert_eq(_baseline(runtime, "ada", "player", "affinity"), -1.25)
	assert_false(runtime.social.adjust_baseline(&"ada", &"ada", &"affinity", 3.0))
	assert_false(_has_edge(runtime, "ada", "ada", "affinity"))
	assert_false(runtime.social.adjust_baseline(&"", &"player", &"affinity", 1.0))
	assert_push_warning("zero")
	assert_push_warning("self edge")
	assert_push_warning("missing entity")
	runtime.config().set_kind_scale(&"apprentice", &"affinity", 2.0)
	runtime.social.set_kind(&"player", &"ada", &"apprentice")
	assert_true(runtime.social.adjust_baseline(&"player", &"ada", &"affinity", 5.0))
	assert_eq(runtime.social.axis(&"player", &"ada", &"affinity"), 5.0)
	assert_eq(_baseline(runtime, "player", "ada", "affinity"), 5.0)
	var deeds := runtime.deeds.size()
	assert_true(runtime.social.adjust_baseline(&"ada", &"player", &"affinity", -100.0))
	assert_eq(runtime.deeds.size(), deeds)
	assert_eq(runtime.social.cache_entries(), 0)
	assert_gt(runtime.scheduler().carry("cache_refresh"), 0)
	assert_lt(runtime.social.disposition(&"ada", &"player"), 20)
	runtime.tick(0)
	assert_eq(String(runtime.roles.slot_state(&"keeper", "gate")), "hostile")
	assert_eq(runtime.quests.variant_of("gate"), "keeper.hostile")


func test_traces_keep_every_reason_and_filter() -> void:
	var opened := _boot(_TINY)
	var runtime: WyrdRuntime = opened["runtime"]
	_people(opened["host"])
	runtime.roles.define(&"keeper", "none")
	runtime.trace.enabled = true
	runtime.trace.prefix = "other"
	assert_true(runtime.roles.assign_from_content(&"keeper", &"ada"))
	assert_true(runtime.social.adjust_baseline(&"ada", &"bea", &"affinity", 2.0))
	assert_eq(_reasons(runtime, "role_assign").size(), 0)
	assert_eq(_reasons(runtime, "baseline_adjust").size(), 0)
	runtime.trace.prefix = "keeper"
	runtime.trace.clear()
	assert_false(runtime.roles.assign_from_content(&"keeper", &"ada"))
	assert_eq(_reasons(runtime, "role_assign"), PackedStringArray(["same_holder"]))
	assert_eq(str(_last(runtime, "role_assign")["role"]), "keeper")
	runtime.trace.prefix = "ada"
	runtime.trace.clear()
	assert_true(runtime.social.adjust_baseline(&"ada", &"bea", &"affinity", -1.0))
	assert_eq(_reasons(runtime, "baseline_adjust"), PackedStringArray(["adjusted"]))
	assert_eq(str(_last(runtime, "baseline_adjust")["who"]), "ada")
	assert_eq(_reasons(runtime, "role_assign").size(), 0)
	runtime.trace.prefix = ""
	runtime.trace.clear()
	assert_true(runtime.roles.assign_from_content(&"keeper", &"bea"))
	assert_false(runtime.roles.assign_from_content(&"keeper", &"bea"))
	assert_true(runtime.social.adjust_baseline(&"ada", &"bea", &"affinity", 1.0))
	runtime.roles.define(&"bare", "none")
	assert_false(runtime.roles.vacate_from_content(&"bare"))
	runtime.roles.define(&"ended", "none", false, -1, "", "", &"", "abolish")
	runtime.roles.assign(&"ended", &"ada")
	runtime.roles.vacate_from_content(&"ended")
	runtime.roles.assign_from_content(&"ended", &"bea")
	runtime.roles.vacate_from_content(&"ended")
	runtime.roles.define(&"vote", "host_decides")
	runtime.roles.assign(&"vote", &"ada")
	runtime.roles.vacate_from_content(&"vote")
	runtime.roles.assign_from_content(&"vote", &"bea")
	runtime.roles.vacate_from_content(&"vote")
	runtime.roles.assign_from_content(&"keeper", &"nobody")
	runtime.roles.define(&"tagged", "none", false, -1, "", "has_tag(candidate, local)")
	runtime.roles.assign_from_content(&"tagged", &"cy")
	runtime.social.adjust_baseline(&"ada", &"bea", &"affinity", 0.0)
	runtime.social.adjust_baseline(&"ada", &"ada", &"affinity", 1.0)
	runtime.social.adjust_baseline(&"", &"bea", &"affinity", 1.0)
	assert_true(_has_reason(runtime, "role_assign", "assigned"))
	assert_true(_has_reason(runtime, "role_assign", "abolished"))
	assert_true(_has_reason(runtime, "role_assign", "contested"))
	assert_true(_has_reason(runtime, "role_assign", "no_entity"))
	assert_true(_has_reason(runtime, "role_assign", "ineligible"))
	assert_true(_has_reason(runtime, "role_assign", "same_holder"))
	assert_true(_has_reason(runtime, "role_vacate", "vacated"))
	assert_true(_has_reason(runtime, "role_vacate", "abolished"))
	assert_true(_has_reason(runtime, "role_vacate", "contested"))
	assert_true(_has_reason(runtime, "role_vacate", "empty"))
	assert_true(_has_reason(runtime, "baseline_adjust", "adjusted"))
	assert_true(_has_reason(runtime, "baseline_adjust", "zero"))
	assert_true(_has_reason(runtime, "baseline_adjust", "self_edge"))
	assert_true(_has_reason(runtime, "baseline_adjust", "no_entity"))


func test_save_round_trip_keeps_the_effects_and_load_is_quiet() -> void:
	var opened := _boot(_TINY)
	var runtime: WyrdRuntime = opened["runtime"]
	_people(opened["host"])
	runtime.roles.define(&"keeper", "none", false, -1, "", "", &"ada")
	runtime.roles.vacate_from_content(&"keeper")
	assert_true(runtime.roles.assign_from_content(&"keeper", &"ada"))
	var assigned := _reload(opened)
	assert_eq(String(assigned.roles.holder(&"keeper")), "ada")
	assert_eq(String(assigned.roles.binding_status(&"keeper")), "default")
	assert_eq(_reasons(assigned, "role_assign").size(), 0)
	runtime.roles.define(&"vote", "election")
	runtime.roles.assign(&"vote", &"ada")
	assert_true(runtime.roles.vacate_from_content(&"vote"))
	var contested := _reload(opened)
	assert_eq(String(contested.roles.binding_status(&"vote")), "contested")
	assert_eq(String(contested.roles.departed(&"vote")), "ada")
	assert_eq(_reasons(contested, "role_vacate").size(), 0)
	assert_true(runtime.social.adjust_baseline(&"ada", &"bea", &"affinity", 3.5))
	var social := _reload(opened)
	assert_eq(_baseline(social, "ada", "bea", "affinity"), 3.5)
	assert_eq(_reasons(social, "baseline_adjust").size(), 0)
	assert_eq(int(social.save_state()["schema_version"]), 3)


func test_stage_effects_resolve_slots_holders_and_facts() -> void:
	var opened := _boot(_FLOW)
	var runtime: WyrdRuntime = opened["runtime"]
	_people(opened["host"])
	runtime.quests.start("flow")
	assert_eq(String(runtime.roles.holder(&"dock_keeper")), "ada")
	assert_eq(_baseline(runtime, "ada", "player", "affinity"), 4.0)
	runtime.facts.set(&"player.coins", 2)
	runtime.quests.advance("flow", "two")
	assert_eq(String(runtime.roles.holder(&"clerk")), "ada")
	assert_eq(String(runtime.roles.holder(&"watcher")), "ada")
	assert_eq(_baseline(runtime, "ada", "player", "affinity"), 6.0)
	assert_eq(runtime.facts.get(&"player.coins"), 2)


const _TINY := """
language 1
quest gate "Gate"
  start when false
  stage one
    waits_until false
"""


const _SLOTS := """
language 1
role dock_keeper
  succession: none
  vacancy: hold
role ferry_master
  succession: none
  vacancy: hold
role watcher
  succession: none
  vacancy: hold
quest liveq "Live"
  slot keeper = dock_keeper mode: live
  start when false
  stage arrive
    variant keeper.successor:
      journal: Next. #line:j_next
      waits_until false
    variant keeper.default:
      journal: Here. #line:j_here
      waits_until false
quest lockq "Lock"
  slot ferry = ferry_master mode: locked_at(pay)
  start when false
  stage arrive
    -> pay
  stage pay
    waits_until false
    variant ferry.locked_gone:
      journal: Gone. #line:j_gone
      waits_until false
    variant ferry.default:
      journal: Held. #line:j_held
      waits_until false
quest castq "Cast"
  slot look = watcher mode: cast(true)
  start when false
  stage arrive
    waits_until false
quest emptyq "Empty"
  slot seat = empty_role mode: live
  start when false
  stage arrive
    variant seat.empty:
      journal: Empty. #line:j_empty
      waits_until false
    variant seat.default:
      journal: Here. #line:j_seat
      waits_until false
quest voteq "Vote"
  slot seat = vote_role mode: live
  start when false
  stage arrive
    variant seat.contested:
      journal: Vote. #line:j_vote
      waits_until false
    variant seat.empty:
      journal: Empty. #line:j_vote_empty
      waits_until false
    variant seat.default:
      journal: Here. #line:j_vote_here
      waits_until false
"""


const _SCENES := """
language 1
role dock_keeper
  succession: none
  vacancy: hold
quest speakq "Speak"
  slot keeper = dock_keeper mode: live
  start when false
  stage arrive
    scene room with keeper
    waits_until false
quest outerq "Outer"
  slot keeper = dock_keeper mode: live
  start when false
  stage arrive
    scene outer with keeper
    waits_until false
scene room
  keeper: Hello. #line:hi
  * [Swap] -> after #line:c_swap
    ~ assign role dock_keeper to bea
  - (after)
  keeper: Still here. #line:still
  -> end
scene outer
  keeper: Outside. #line:out
  -> scene room
"""


const _HOSTILE := """
language 1
role dock_keeper
  succession: none
  vacancy: hold
quest gate "Gate"
  slot keeper = dock_keeper mode: live
  start when false
  stage arrive
    variant keeper.hostile:
      journal: Hostile. #line:j_hostile
      waits_until false
    variant keeper.default:
      journal: Here. #line:j_here
      waits_until false
"""


const _FLOW := """
language 1
facts
  player.coins : int stored
role dock_keeper
  succession: none
  vacancy: hold
role clerk
  succession: none
  vacancy: hold
role watcher
  succession: none
  vacancy: hold
quest flow "Flow"
  slot keeper = dock_keeper mode: live
  start when false
  stage one
    ~ assign role dock_keeper to ada
    ~ adjust baseline affinity(ada, player) by 4
    waits_until false
  stage two
    ~ assign role clerk to keeper
    ~ assign role watcher to holder(dock_keeper)
    ~ adjust baseline affinity(ada, player) by player.coins
    waits_until false
"""


func _boot(body: String) -> Dictionary:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var path := "user://wyrd_role_baseline.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(body)
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(1)
	return {"host": host, "path": path, "runtime": runtime}


func _people(host: WyrdFakeHost) -> void:
	host.world.add_entity(&"ada", &"person", "Ada", PackedStringArray(["local"]), true)
	host.world.add_entity(&"bea", &"person", "Bea", PackedStringArray(["local"]), true)
	host.world.add_entity(&"cy", &"person", "Cy", PackedStringArray(), true)
	host.world.add_entity(&"player", &"person", "traveler", PackedStringArray(), true)


func _reload(opened: Dictionary) -> WyrdRuntime:
	var runtime: WyrdRuntime = opened["runtime"]
	var saved := runtime.save_state()
	var fresh := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(fresh)
	_people(host)
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([str(opened["path"])])
	assert_true(fresh.load_content(manifest).ok)
	fresh.roles.set_host_decides(func(_role: StringName, _departed: StringName) -> void:
		pass
	)
	fresh.start_new_game(1)
	fresh.trace.enabled = true
	fresh.trace.clear()
	var report := fresh.load_state(saved)
	assert_true(report.ok, report.diagnostics.format())
	return fresh


func _reasons(runtime: WyrdRuntime, kind: String) -> PackedStringArray:
	var rows := PackedStringArray()
	for item in runtime.trace.events:
		if item is Dictionary and str((item as Dictionary).get("kind", "")) == kind:
			rows.append(str((item as Dictionary).get("reason", "")))
	return rows


func _last(runtime: WyrdRuntime, kind: String) -> Dictionary:
	var found := {}
	for item in runtime.trace.events:
		if item is Dictionary and str((item as Dictionary).get("kind", "")) == kind:
			found = item
	return found


func _has_reason(runtime: WyrdRuntime, kind: String, reason: String) -> bool:
	return _reasons(runtime, kind).has(reason)


func _baseline(runtime: WyrdRuntime, source: String, target: String, axis_name: String) -> float:
	for item in runtime.social.export_state()["baselines"]:
		var row: Dictionary = item
		if str(row["source"]) == source and str(row["target"]) == target and str(row["axis"]) == axis_name:
			return float(row["value"])
	return 0.0


func _has_edge(runtime: WyrdRuntime, source: String, target: String, axis_name: String) -> bool:
	for item in runtime.social.export_state()["baselines"]:
		var row: Dictionary = item
		if str(row["source"]) == source and str(row["target"]) == target and str(row["axis"]) == axis_name:
			return true
	return false
