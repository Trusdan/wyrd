extends GutTest


func test_faction_assigns_highest_rank_and_skips_the_departed() -> void:
	var opened := _boot()
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	_members(host)
	runtime.roles.set_faction_rank(func(faction: StringName, entity: StringName) -> int:
		assert_eq(String(faction), "faction.harbor")
		match String(entity):
			"bea":
				return 2
			"cy":
				return 9
			"dock_clerk":
				return 1
			_:
				return 0
	)
	runtime.roles.define(&"dock_keeper", "faction_assigns(faction.harbor)", false, -1, "", "has_tag(candidate, local)")
	runtime.roles.assign(&"dock_keeper", &"ada")
	runtime.roles.vacate(&"dock_keeper", &"died")
	assert_eq(runtime.roles.holder(&"dock_keeper"), &"cy")
	assert_eq(runtime.roles.binding_status(&"dock_keeper"), &"successor")
	assert_eq(runtime.deeds.count_matching(&"ada", &"role_changed", &"cy"), 1)
	assert_ne(runtime.roles.holder(&"dock_keeper"), &"ada")


func test_faction_tie_break_is_seeded() -> void:
	var first := _tied_pick(4)
	var again := _tied_pick(4)
	assert_eq(first, again)
	assert_true(first == "bea" or first == "cy")
	var other := ""
	for seed_value in range(1, 80):
		var pick := _tied_pick(seed_value)
		assert_true(pick == "bea" or pick == "cy")
		if pick != first:
			other = pick
			break
	assert_false(other.is_empty())


func test_host_decides_stays_contested_until_assign() -> void:
	var opened := _boot()
	var runtime: WyrdRuntime = opened["runtime"]
	var heard: Array = []
	runtime.roles.set_host_decides(func(role: StringName, departed: StringName) -> void:
		heard.append([String(role), String(departed)])
	)
	runtime.roles.define(&"dock_keeper", "host_decides")
	runtime.start_new_game(6)
	runtime.roles.define(&"dock_keeper", "host_decides")
	runtime.roles.assign(&"dock_keeper", &"ada")
	runtime.roles.vacate(&"dock_keeper", &"left")
	assert_eq(heard, [["dock_keeper", "ada"]])
	assert_eq(runtime.roles.holder(&"dock_keeper"), &"")
	assert_eq(runtime.roles.binding_status(&"dock_keeper"), &"contested")
	assert_eq(runtime.roles.slot_state(&"dock_keeper"), &"contested")
	assert_eq(runtime.roles.departed(&"dock_keeper"), &"ada")
	assert_false(runtime.roles.abolished(&"dock_keeper"))
	runtime.roles.assign(&"dock_keeper", &"ada")
	assert_push_error("must differ")
	assert_eq(runtime.roles.binding_status(&"dock_keeper"), &"contested")
	runtime.roles.assign(&"dock_keeper", &"bea")
	assert_eq(runtime.roles.holder(&"dock_keeper"), &"bea")
	assert_eq(runtime.roles.binding_status(&"dock_keeper"), &"default")
	assert_eq(runtime.roles.departed(&"dock_keeper"), &"")
	assert_eq(runtime.deeds.count_matching(&"ada", &"role_changed", &"bea"), 1)


func test_missing_host_callback_is_a_startup_error() -> void:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	_people(host)
	runtime.roles.define(&"ferry_master", "host_decides")
	runtime.start_new_game(2)
	assert_push_error("host_decides has no callback")
	runtime.roles.set_host_decides(func(_role: StringName, _departed: StringName) -> void:
		pass
	)
	runtime.start_new_game(2)


func test_abolish_after_every_strategy_fails() -> void:
	var opened := _boot()
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.roles.define(&"dock_keeper", "faction_assigns(faction.harbor)", false, -1, "", "", &"", "abolish")
	runtime.roles.assign(&"dock_keeper", &"ada")
	runtime.roles.vacate(&"dock_keeper", &"died")
	assert_true(runtime.roles.abolished(&"dock_keeper"))
	assert_eq(runtime.roles.holder(&"dock_keeper"), &"")
	assert_eq(runtime.roles.binding_status(&"dock_keeper"), &"empty")
	assert_eq(runtime.deeds.count_matching(&"ada", &"role_abolished", &"dock_keeper"), 1)
	runtime.roles.assign(&"dock_keeper", &"bea")
	assert_push_error("is abolished")
	assert_eq(runtime.roles.holder(&"dock_keeper"), &"")
	runtime.roles.define(&"watcher", "host_decides", false, -1, "", "", &"", "abolish")
	runtime.roles.set_host_decides(func(_role: StringName, _departed: StringName) -> void:
		pass
	)
	runtime.roles.assign(&"watcher", &"bea")
	runtime.roles.vacate(&"watcher", &"left")
	assert_false(runtime.roles.abolished(&"watcher"))
	assert_eq(runtime.roles.binding_status(&"watcher"), &"contested")
	runtime.roles.define(&"ferry_master", "relation(apprentice)", false, -1, "", "", &"", "abolish")
	runtime.social.set_kind(&"ada", &"ada", &"apprentice")
	runtime.roles.assign(&"ferry_master", &"ada")
	runtime.roles.vacate(&"ferry_master", &"died")
	assert_true(runtime.roles.abolished(&"ferry_master"))
	assert_ne(runtime.roles.holder(&"ferry_master"), &"ada")


func test_succession_trace_is_one_line_and_filterable() -> void:
	var opened := _boot()
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	_members(host)
	runtime.roles.set_faction_rank(func(_faction: StringName, entity: StringName) -> int:
		return 3 if String(entity) == "bea" else 1
	)
	runtime.roles.define(&"dock_keeper", "faction_assigns(faction.harbor)", false, -1, "", "", &"", "abolish")
	runtime.roles.assign(&"dock_keeper", &"ada")
	runtime.trace.prefix = "other"
	runtime.trace.enabled = true
	runtime.roles.vacate(&"dock_keeper", &"died")
	assert_eq(_succession_count(runtime), 0)
	runtime.roles.define(&"dock_keeper", "faction_assigns(faction.harbor)")
	runtime.roles.assign(&"dock_keeper", &"ada")
	runtime.trace.prefix = "dock"
	runtime.roles.vacate(&"dock_keeper", &"died")
	assert_eq(_succession_count(runtime), 1)
	var row: Dictionary = _succession_event(runtime)
	assert_eq(String(row["role"]), "dock_keeper")
	assert_eq(String(row["strategy"]), "faction_assigns")
	assert_eq(String(row["from"]), "ada")
	assert_eq(String(row["to"]), "bea")
	assert_eq(String(row["reason"]), "picked")
	runtime.roles.define(&"storm_watcher", "none", false, -1, "", "", &"", "abolish")
	runtime.roles.assign(&"storm_watcher", &"cy")
	runtime.trace.prefix = ""
	runtime.roles.vacate(&"storm_watcher", &"left")
	var reasons: PackedStringArray = PackedStringArray()
	for event in runtime.trace.events:
		if String(event.get("kind", "")) != "succession" or String(event.get("role", "")) != "storm_watcher":
			continue
		reasons.append(String(event.get("reason", "")))
	assert_eq(reasons, PackedStringArray(["none", "abolished"]))


func test_pending_and_abolished_round_trip() -> void:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	_people(host)
	assert_true(_load_header(runtime).ok)
	runtime.start_new_game(4)
	runtime.roles.set_host_decides(func(_role: StringName, _departed: StringName) -> void:
		pass
	)
	runtime.roles.define(&"dock_keeper", "host_decides")
	runtime.roles.define(&"ferry_master", "none", false, -1, "", "", &"", "abolish")
	runtime.roles.assign(&"dock_keeper", &"ada")
	runtime.roles.assign(&"ferry_master", &"bea")
	runtime.roles.vacate(&"dock_keeper", &"left")
	runtime.roles.vacate(&"ferry_master", &"died")
	var saved := runtime.save_state()
	assert_eq(int(saved["schema_version"]), 1)
	var parsed: Variant = JSON.parse_string(JSON.stringify(saved))
	var fresh := WyrdRuntime.new()
	var next := WyrdFakeHost.new()
	next.register_into(fresh)
	_people(next)
	assert_true(_load_header(fresh).ok)
	fresh.roles.set_host_decides(func(_role: StringName, _departed: StringName) -> void:
		pass
	)
	fresh.start_new_game(9)
	var report := fresh.load_state(parsed)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(fresh.roles.binding_status(&"dock_keeper"), &"contested")
	assert_eq(fresh.roles.departed(&"dock_keeper"), &"ada")
	assert_true(fresh.roles.abolished(&"ferry_master"))
	fresh.roles.assign(&"ferry_master", &"cy")
	assert_push_error("is abolished")
	fresh.roles.assign(&"dock_keeper", &"cy")
	assert_eq(fresh.roles.holder(&"dock_keeper"), &"cy")


func test_line_ready_carries_speaker_roles() -> void:
	var opened := _boot()
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	_write_quest(runtime)
	runtime.start_new_game(5)
	runtime.roles.assign(&"ferry_master", &"ada")
	runtime.roles.assign(&"dock_keeper", &"bea")
	runtime.tick(0)
	runtime.dialogue.open_scene("dock")
	var spoken := runtime.dialogue.line()
	assert_eq(spoken.speaker, &"ada")
	assert_eq(spoken.display_name, "Ada")
	assert_eq(spoken.roles, PackedStringArray(["ferry_master"]))
	runtime.dialogue.advance()
	var aside := runtime.dialogue.line()
	assert_eq(aside.speaker, &"narrator")
	assert_eq(aside.roles, PackedStringArray())
	host.world.add_entity(&"ada", &"person", "Ada", PackedStringArray(["local"]), true)


func _tied_pick(seed_value: int) -> String:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	_people(host)
	_members(host)
	runtime.start_new_game(seed_value)
	runtime.roles.set_faction_rank(func(_faction: StringName, entity: StringName) -> int:
		var name := String(entity)
		if name == "bea" or name == "cy":
			return 4
		return 1
	)
	runtime.roles.define(&"dock_keeper", "faction_assigns(faction.harbor)")
	runtime.roles.assign(&"dock_keeper", &"ada")
	runtime.roles.vacate(&"dock_keeper", &"died")
	return String(runtime.roles.holder(&"dock_keeper"))


func _succession_count(runtime: WyrdRuntime) -> int:
	var count := 0
	for row in runtime.trace.events:
		if String(row.get("kind", "")) == "succession":
			count += 1
	return count


func _succession_event(runtime: WyrdRuntime) -> Dictionary:
	var found := {}
	for row in runtime.trace.events:
		if String(row.get("kind", "")) == "succession":
			found = row
	return found


func _boot() -> Dictionary:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	_people(host)
	runtime.start_new_game(4)
	return {"host": host, "runtime": runtime}


func _people(host: WyrdFakeHost) -> void:
	host.world.add_entity(&"ada", &"person", "Ada", PackedStringArray(["local"]), true)
	host.world.add_entity(&"bea", &"person", "Bea", PackedStringArray(["local"]), true)
	host.world.add_entity(&"cy", &"person", "Cy", PackedStringArray(["local"]), true)
	host.world.add_entity(&"dock_clerk", &"person", "Clerk", PackedStringArray(), true)
	host.world.add_entity(&"player", &"person", "traveler", PackedStringArray(), true)


func _members(host: WyrdFakeHost) -> void:
	for id in ["ada", "bea", "cy", "dock_clerk"]:
		host.world.add_member(&"faction.harbor", StringName(id))


func _load_header(runtime: WyrdRuntime) -> WyrdLoadReport:
	var path := "user://wyrd_m4_succession_header.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("language 1\n")
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	return runtime.load_content(manifest)


func _write_quest(runtime: WyrdRuntime) -> void:
	var path := "user://wyrd_m4_succession_line.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("""language 1
quest gate "Gate"
  slot ferry = ferry_master mode: live
  slot keeper = dock_keeper mode: live
  stage arrive
    scene dock with ferry, keeper
    -> done
  stage done
scene dock
  ferry: The boat is ready. #line:hi
  narrator: Aside. #line:aside
  -> end
""")
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
