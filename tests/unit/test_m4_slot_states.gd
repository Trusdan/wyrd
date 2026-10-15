extends GutTest


func test_precedence_unwilling_and_barred() -> void:
	var opened := _boot(_BODY)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	_people(host)
	runtime.roles.define(&"dock_keeper", "relation(apprentice)")
	runtime.social.set_kind(&"ada", &"bea", &"apprentice")
	runtime.roles.assign(&"dock_keeper", &"ada")
	runtime.facts.set(&"player.coins", 0)
	runtime.trace.enabled = true
	runtime.tick(0)
	assert_eq(runtime.quests.variant_of("gate"), "keeper.barred")
	assert_eq(runtime.roles.slot_state(&"keeper", "gate"), &"barred")
	assert_eq(runtime.quests.journal("gate")[0]["id"], "j_barred")
	var barred: Dictionary = _slot_event(runtime, "keeper")
	assert_eq(String(barred["state"]), "barred")
	assert_eq(String(barred["reason"]), "barred")
	assert_eq(String(barred["role"]), "dock_keeper")
	runtime.facts.set(&"player.coins", 4)
	runtime.social.set_baseline(&"ada", &"player", &"affinity", -80.0)
	runtime.tick(0)
	assert_eq(runtime.roles.slot_state(&"keeper", "gate"), &"hostile")
	assert_eq(runtime.quests.variant_of("gate"), "keeper.hostile")
	assert_eq(runtime.quests.journal("gate")[1]["id"], "j_hostile")
	runtime.social.set_baseline(&"ada", &"player", &"affinity", 0.0)
	runtime.facts.set(&"player.coins", 1)
	runtime.tick(0)
	assert_eq(runtime.roles.slot_state(&"keeper", "gate"), &"unwilling")
	assert_eq(runtime.quests.variant_of("gate"), "keeper.unwilling")
	assert_eq(runtime.quests.journal("gate")[2]["id"], "j_unwilling")
	runtime.facts.set(&"player.coins", 9)
	runtime.tick(0)
	assert_eq(runtime.roles.slot_state(&"keeper", "gate"), &"default")
	assert_eq(runtime.quests.variant_of("gate"), "keeper.default")
	runtime.roles.vacate(&"dock_keeper", &"left")
	runtime.tick(0)
	assert_eq(runtime.roles.holder(&"dock_keeper"), &"bea")
	assert_eq(runtime.roles.slot_state(&"keeper", "gate"), &"successor")
	assert_eq(runtime.quests.variant_of("gate"), "keeper.successor")


func test_first_declared_variant_and_fallthrough() -> void:
	var opened := _boot(_FALL)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	_people(host)
	runtime.roles.define(&"dock_keeper", "none")
	runtime.roles.assign(&"dock_keeper", &"ada")
	runtime.trace.enabled = true
	runtime.facts.set(&"player.coins", 2)
	runtime.tick(0)
	assert_eq(runtime.quests.variant_of("gate"), "keeper.unwilling")
	assert_eq(runtime.quests.journal("gate")[0]["id"], "j_first")
	runtime.facts.set(&"player.coins", 0)
	runtime.social.set_baseline(&"ada", &"player", &"affinity", -80.0)
	runtime.tick(0)
	assert_eq(runtime.roles.slot_state(&"keeper", "gate"), &"default")
	assert_eq(runtime.quests.variant_of("gate"), "keeper.default")
	var row: Dictionary = _slot_event(runtime, "keeper")
	assert_eq(String(row["state"]), "default")
	assert_eq(String(row["reason"]), "fallthrough")


func test_locked_gone_ignores_the_successor() -> void:
	var opened := _boot(_LOCK)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	_people(host)
	runtime.roles.define(&"ferry_master", "relation(apprentice)")
	runtime.social.set_kind(&"ada", &"bea", &"apprentice")
	runtime.roles.assign(&"ferry_master", &"ada")
	runtime.trace.enabled = true
	runtime.tick(0)
	assert_eq(runtime.quests.stage("gate"), "pay")
	assert_eq(runtime.roles.slot_holder("gate", &"ferry"), &"ada")
	assert_eq(runtime.roles.slot_state(&"ferry", "gate"), &"default")
	runtime.roles.vacate(&"ferry_master", &"died")
	assert_eq(runtime.roles.holder(&"ferry_master"), &"bea")
	assert_eq(runtime.roles.slot_holder("gate", &"ferry"), &"ada")
	assert_eq(runtime.roles.slot_state(&"ferry", "gate"), &"locked_gone")
	assert_eq(runtime.quests.variant_of("gate"), "")
	runtime.tick(0)
	assert_eq(runtime.quests.variant_of("gate"), "ferry.locked_gone")
	assert_eq(runtime.quests.journal("gate")[0]["id"], "j_gone")
	var gone: Dictionary = _slot_event(runtime, "ferry")
	assert_eq(String(gone["state"]), "locked_gone")
	assert_eq(String(gone["reason"]), "frozen_vacated")
	runtime.roles.assign(&"ferry_master", &"ada")
	host.world.add_entity(&"ada", &"person", "Ada", PackedStringArray(["local"]), false)
	assert_eq(runtime.roles.slot_state(&"ferry", "gate"), &"locked_gone")
	runtime.tick(0)
	gone = _slot_event(runtime, "ferry")
	assert_eq(String(gone["reason"]), "frozen_dead")


func test_route_closed_stays_open_and_is_readable() -> void:
	var opened := _boot(_ROUTE)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.tick(0)
	assert_eq(runtime.quests.status("gate"), &"active")
	assert_eq(runtime.quests.outcome("gate", "crossing"), "route_closed")
	assert_eq(runtime.quests.stage("gate"), "shut")
	runtime.facts.set(&"player.coins", 3)
	runtime.tick(0)
	assert_eq(runtime.quests.stage("gate"), "done")
	assert_eq(runtime.quests.outcome("gate", "crossing"), "done")
	assert_eq(runtime.quests.status("gate"), &"completed")


func test_slot_trace_is_filterable() -> void:
	var opened := _boot(_BODY)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	_people(host)
	runtime.roles.define(&"dock_keeper", "none")
	runtime.roles.assign(&"dock_keeper", &"ada")
	runtime.facts.set(&"player.coins", 9)
	runtime.trace.prefix = "other"
	runtime.trace.enabled = true
	runtime.tick(0)
	assert_eq(_slot_count(runtime), 0)
	runtime.trace.prefix = "dock"
	runtime.facts.set(&"player.coins", 0)
	runtime.tick(0)
	assert_gt(_slot_count(runtime), 0)
	for row in runtime.trace.events:
		if String(row["kind"]) != "slot_state":
			continue
		assert_true(String(row["role"]).begins_with("dock") or String(row["quest"]).begins_with("dock") or String(row["slot"]).begins_with("dock"))
	var before := _slot_count(runtime)
	runtime.tick(0)
	assert_eq(_slot_count(runtime), before)


func test_coverage_and_constant_conditions() -> void:
	var diagnostics := WyrdDiagnostics.new()
	var path := "user://wyrd_m4_slot_lint.wyrd"
	_write(path, _LINT)
	WyrdPack.compile(PackedStringArray([path]), "harbor", 1, null, diagnostics, path, true)
	var text := diagnostics.format()
	assert_true(text.contains("W_EMPTY_UNCOVERED"))
	assert_true(text.contains("slot \"clerk\" can become empty"))
	assert_false(text.contains("slot \"spare\" can become empty"))
	assert_true(text.contains("W_LOCKED_GONE_UNCOVERED"))
	assert_true(text.contains("locked_at slot \"ferry\""))
	assert_true(text.contains("W_SLOT_COND_ALWAYS"))
	assert_true(text.contains("W_SLOT_COND_NEVER"))
	assert_true(text.contains("W_ROUTE_CLOSED"))
	assert_true(text.contains("branch \"crossing\""))
	assert_true(text.contains("\"$h\" is only valid in an unwilling condition"))


const _BODY := """
language 1
facts
  player.coins : int stored
quest gate "Gate"
  slot keeper = dock_keeper mode: live
  stage arrive
    variant keeper.barred(player.coins < 1):
      journal: Barred. #line:j_barred
      waits_until false
    variant keeper.hostile:
      journal: Hostile. #line:j_hostile
      waits_until false
    variant keeper.unwilling(player.coins < 5 and has_tag($h, local)):
      journal: Unwilling. #line:j_unwilling
      waits_until false
    variant keeper.successor:
      journal: Successor. #line:j_successor
      waits_until false
    variant keeper.default:
      journal: Default. #line:j_default
      waits_until false
"""

const _FALL := """
language 1
facts
  player.coins : int stored
quest gate "Gate"
  slot keeper = dock_keeper mode: live
  stage arrive
    variant keeper.unwilling(player.coins >= 2 and has_tag($h, local)):
      journal: First. #line:j_first
      waits_until false
    variant keeper.unwilling(player.coins >= 1 and has_tag($h, local)):
      journal: Second. #line:j_second
      waits_until false
    variant keeper.default:
      journal: Default. #line:j_default
      waits_until false
"""

const _LOCK := """
language 1
quest gate "Gate"
  slot ferry = ferry_master mode: locked_at(pay)
  stage arrive
    -> pay
  stage pay
    waits_until false
    variant ferry.locked_gone:
      journal: Gone. #line:j_gone
      waits_until false
"""

const _ROUTE := """
language 1
facts
  player.coins : int stored
quest gate "Gate"
  stage shut
    ~ outcome crossing = route_closed
    -> done when outcome(gate, crossing) == route_closed and player.coins >= 2
  stage done
    ~ outcome crossing = done
"""

const _LINT := """
language 1
facts
  player.coins : int stored
quest gate "Gate"
  slot keeper = dock_keeper mode: live
  slot clerk = dock_clerk mode: live
  slot spare = dock_spare mode: live
  slot ferry = ferry_master mode: locked_at(pay)
  stage arrive
    scene room with keeper, clerk
    variant keeper.empty:
      -> pay
    variant keeper.unwilling(true):
      -> pay
    variant keeper.barred(false):
      -> pay
    variant keeper.barred($h == ada):
      -> pay
    ~ outcome crossing = route_closed
    -> pay
  stage pay
  stage side
    scene room with spare
    ~ outcome crossing = done
scene room
  keeper: Here. #line:room
  -> end
"""


func _boot(body: String) -> Dictionary:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var path := "user://wyrd_m4_slot_states.wyrd"
	_write(path, body)
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(4)
	return {"host": host, "report": report, "runtime": runtime}


func _people(host: WyrdFakeHost) -> void:
	host.world.add_entity(&"ada", &"person", "Ada", PackedStringArray(["local"]), true)
	host.world.add_entity(&"bea", &"person", "Bea", PackedStringArray(["local"]), true)
	host.world.add_entity(&"player", &"person", "traveler", PackedStringArray(), true)


func _slot_count(runtime: WyrdRuntime) -> int:
	var count := 0
	for row in runtime.trace.events:
		if String(row.get("kind", "")) == "slot_state":
			count += 1
	return count


func _slot_event(runtime: WyrdRuntime, slot_name: String) -> Dictionary:
	var found := {}
	for row in runtime.trace.events:
		if String(row.get("kind", "")) == "slot_state" and String(row.get("slot", "")) == slot_name:
			found = row
	return found


func _write(path: String, body: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(body)
	file.close()
