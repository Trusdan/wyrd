extends GutTest


class Poll extends WyrdElectionAdapter:
	var heard: Array = []

	func start_election(role: StringName, departed: StringName) -> void:
		heard.append([String(role), String(departed)])


func test_election_calls_the_adapter_until_assign() -> void:
	var opened := _boot(_BOTH)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	_people(host)
	var poll := Poll.new()
	runtime.register_adapter(WyrdElectionAdapter, poll)
	var heard: Array = []
	runtime.roles.election_needed.connect(func(role: StringName, departed: StringName) -> void:
		heard.append([String(role), String(departed)])
	)
	runtime.roles.define(&"dock_keeper", "election", false, -1, "", "", &"", "abolish")
	runtime.roles.assign(&"dock_keeper", &"ada")
	runtime.trace.enabled = true
	runtime.tick(0)
	assert_eq(runtime.quests.variant_of("gate"), "keeper.default")
	runtime.roles.vacate(&"dock_keeper", &"left")
	assert_eq(heard, [["dock_keeper", "ada"]])
	assert_eq(poll.heard, [["dock_keeper", "ada"]])
	assert_eq(runtime.roles.holder(&"dock_keeper"), &"")
	assert_eq(runtime.roles.binding_status(&"dock_keeper"), &"contested")
	assert_eq(runtime.roles.departed(&"dock_keeper"), &"ada")
	assert_false(runtime.roles.abolished(&"dock_keeper"))
	runtime.tick(0)
	assert_eq(runtime.roles.slot_state(&"keeper", "gate"), &"contested")
	assert_eq(runtime.quests.variant_of("gate"), "keeper.contested")
	assert_eq(runtime.quests.journal("gate")[1]["id"], "j_vote")
	var row := _slot_event(runtime, "keeper")
	assert_eq(String(row["state"]), "contested")
	assert_eq(String(row["reason"]), "contested")
	var step := _succession_event(runtime)
	assert_eq(String(step["strategy"]), "election")
	assert_eq(String(step["reason"]), "contested")
	assert_eq(String(step["from"]), "ada")
	assert_eq(String(step["to"]), "")
	runtime.roles.assign(&"dock_keeper", &"ada")
	assert_push_error("must differ")
	assert_eq(runtime.roles.binding_status(&"dock_keeper"), &"contested")
	runtime.roles.assign(&"dock_keeper", &"bea")
	assert_eq(runtime.roles.holder(&"dock_keeper"), &"bea")
	assert_eq(runtime.roles.binding_status(&"dock_keeper"), &"default")
	assert_eq(runtime.roles.departed(&"dock_keeper"), &"")
	assert_eq(runtime.deeds.count_matching(&"ada", &"role_changed", &"bea"), 1)
	runtime.tick(0)
	assert_eq(runtime.roles.slot_state(&"keeper", "gate"), &"default")


func test_missing_contested_variant_uses_empty() -> void:
	var opened := _boot(_EMPTY_ONLY)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	_people(host)
	runtime.register_adapter(WyrdElectionAdapter, Poll.new())
	runtime.roles.define(&"dock_keeper", "election")
	runtime.roles.assign(&"dock_keeper", &"ada")
	runtime.trace.enabled = true
	runtime.tick(0)
	runtime.roles.vacate(&"dock_keeper", &"died")
	runtime.tick(0)
	assert_eq(runtime.roles.slot_state(&"keeper", "gate"), &"contested")
	assert_eq(runtime.quests.variant_of("gate"), "keeper.empty")
	assert_eq(runtime.quests.journal("gate")[1]["id"], "j_empty")
	var row := _slot_event(runtime, "keeper")
	assert_eq(String(row["state"]), "contested")
	assert_eq(String(row["reason"]), "fallback_empty")


func test_locked_gone_beats_contested() -> void:
	var opened := _boot(_LOCK)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	_people(host)
	runtime.register_adapter(WyrdElectionAdapter, Poll.new())
	runtime.roles.define(&"ferry_master", "election")
	runtime.roles.assign(&"ferry_master", &"ada")
	runtime.tick(0)
	assert_eq(runtime.roles.slot_state(&"ferry", "gate"), &"default")
	runtime.roles.vacate(&"ferry_master", &"left")
	assert_eq(runtime.roles.binding_status(&"ferry_master"), &"contested")
	runtime.tick(0)
	assert_eq(runtime.roles.slot_holder("gate", &"ferry"), &"ada")
	assert_eq(runtime.roles.slot_state(&"ferry", "gate"), &"locked_gone")
	assert_eq(runtime.quests.variant_of("gate"), "ferry.locked_gone")


func test_contest_with_no_variant_holds_on_empty() -> void:
	var opened := _boot(_HOLD)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	_people(host)
	runtime.register_adapter(WyrdElectionAdapter, Poll.new())
	runtime.roles.define(&"dock_keeper", "host_decides")
	runtime.roles.set_host_decides(func(_role: StringName, _departed: StringName) -> void:
		pass
	)
	runtime.roles.assign(&"dock_keeper", &"ada")
	runtime.tick(0)
	runtime.roles.vacate(&"dock_keeper", &"left")
	runtime.tick(0)
	assert_eq(runtime.roles.slot_state(&"keeper", "gate"), &"contested")
	assert_eq(runtime.quests.variant_of("gate"), "")
	assert_eq(runtime.quests.waiting_reason("gate"), "on_empty")


func test_missing_election_adapter_is_a_startup_error() -> void:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	runtime.roles.define(&"ferry_master", "election")
	runtime.start_new_game(2)
	assert_push_error("election has no adapter")
	runtime.roles.election_needed.connect(func(_role: StringName, _departed: StringName) -> void:
		pass
	)
	runtime.start_new_game(3)


func test_contested_variant_does_not_cover_empty() -> void:
	var diagnostics := WyrdDiagnostics.new()
	var path := "user://wyrd_m4_election_lint.wyrd"
	_write(path, _LINT)
	WyrdPack.compile(PackedStringArray([path]), "harbor", 1, null, diagnostics, path, true)
	var text := diagnostics.format()
	assert_false(text.contains("unknown slot state \"contested\""))
	assert_true(text.contains("W_EMPTY_UNCOVERED"))
	assert_true(text.contains("slot \"keeper\" can become empty"))
	assert_false(text.contains("slot \"clerk\" can become empty"))
	assert_true(text.contains("does not take a condition"))


func test_pending_status_loads_as_contested() -> void:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	host.world.add_entity(&"ada", &"person", "Ada", PackedStringArray(["local"]), true)
	host.world.add_entity(&"bea", &"person", "Bea", PackedStringArray(["local"]), true)
	assert_true(_load_header(runtime).ok)
	runtime.start_new_game(4)
	runtime.roles.set_host_decides(func(_role: StringName, _departed: StringName) -> void:
		pass
	)
	runtime.roles.define(&"dock_keeper", "host_decides")
	runtime.roles.assign(&"dock_keeper", &"ada")
	runtime.roles.vacate(&"dock_keeper", &"left")
	var saved := runtime.save_state()
	assert_eq(int(saved["schema_version"]), 3)
	var roles: Dictionary = saved["roles"]
	assert_true((roles["pending"] as Dictionary).has("dock_keeper"))
	assert_eq(String((roles["bindings"] as Dictionary)["dock_keeper"]["status"]), "contested")
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(saved))
	((parsed["roles"] as Dictionary)["bindings"] as Dictionary)["dock_keeper"]["status"] = "pending"
	var fresh := WyrdRuntime.new()
	var next := WyrdFakeHost.new()
	next.register_into(fresh)
	next.world.add_entity(&"ada", &"person", "Ada", PackedStringArray(["local"]), true)
	next.world.add_entity(&"bea", &"person", "Bea", PackedStringArray(["local"]), true)
	assert_true(_load_header(fresh).ok)
	fresh.roles.set_host_decides(func(_role: StringName, _departed: StringName) -> void:
		pass
	)
	fresh.start_new_game(9)
	var report := fresh.load_state(parsed)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(fresh.roles.binding_status(&"dock_keeper"), &"contested")
	assert_eq(fresh.roles.departed(&"dock_keeper"), &"ada")
	assert_eq(fresh.roles.slot_state(&"dock_keeper"), &"contested")


const _BOTH := """
language 1
quest gate "Gate"
  slot keeper = dock_keeper mode: live
  stage arrive
    variant keeper.contested:
      journal: Vote. #line:j_vote
      waits_until false
    variant keeper.empty:
      journal: Empty. #line:j_empty
      waits_until false
    variant keeper.default:
      journal: Here. #line:j_here
      waits_until false
"""

const _EMPTY_ONLY := """
language 1
quest gate "Gate"
  slot keeper = dock_keeper mode: live
  stage arrive
    variant keeper.empty:
      journal: Empty. #line:j_empty
      waits_until false
    variant keeper.default:
      journal: Here. #line:j_here
      waits_until false
"""

const _LOCK := """
language 1
quest gate "Gate"
  slot ferry = ferry_master mode: locked_at(arrive)
  stage arrive
    variant ferry.contested:
      journal: Vote. #line:j_vote
      waits_until false
    variant ferry.locked_gone:
      journal: Gone. #line:j_gone
      waits_until false
    variant ferry.default:
      journal: Here. #line:j_here
      waits_until false
"""

const _HOLD := """
language 1
quest gate "Gate"
  on_empty: wait
  slot keeper = dock_keeper mode: live
  stage arrive
    waits_until false
"""

const _LINT := """
language 1
quest gate "Gate"
  slot keeper = dock_keeper mode: live
  slot clerk = dock_clerk mode: live
  stage arrive
    scene room with keeper
    variant keeper.contested:
      -> done
    variant keeper.contested(true):
      -> done
  stage done
    variant clerk.empty:
      waits_until false
scene room
  keeper: Here. #line:room
  -> end
"""


func _boot(body: String) -> Dictionary:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var path := "user://wyrd_m4_elections.wyrd"
	_write(path, body)
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(4)
	return {"host": host, "runtime": runtime}


func _people(host: WyrdFakeHost) -> void:
	host.world.add_entity(&"ada", &"person", "Ada", PackedStringArray(["local"]), true)
	host.world.add_entity(&"bea", &"person", "Bea", PackedStringArray(["local"]), true)
	host.world.add_entity(&"player", &"person", "traveler", PackedStringArray(), true)


func _slot_event(runtime: WyrdRuntime, slot_name: String) -> Dictionary:
	var found := {}
	for row in runtime.trace.events:
		if String(row.get("kind", "")) == "slot_state" and String(row.get("slot", "")) == slot_name:
			found = row
	return found


func _succession_event(runtime: WyrdRuntime) -> Dictionary:
	var found := {}
	for row in runtime.trace.events:
		if String(row.get("kind", "")) == "succession":
			found = row
	return found


func _load_header(runtime: WyrdRuntime) -> WyrdLoadReport:
	var path := "user://wyrd_m4_election_header.wyrd"
	_write(path, "language 1\n")
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	return runtime.load_content(manifest)


func _write(path: String, body: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(body)
	file.close()
