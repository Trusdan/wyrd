extends GutTest

const _ELIGIBILITY := "alive(candidate) and has_tag(candidate, local)"
const _SUCCESSION := "relation(apprentice|kin)"


func test_define_matches_role_block() -> void:
	var opened := _boot()
	var runtime: WyrdRuntime = opened["runtime"]
	var compiled := _compile(_role_body())
	assert_eq(compiled["diagnostics"].format(), "")
	var file: WyrdFileDef = compiled["file"]
	assert_eq(file.roles.size(), 1)
	runtime.roles.install(file.roles[0])
	var from_block: Dictionary = runtime.roles.definition(&"ferry_master")
	assert_eq(runtime.roles.holder(&"ferry_master"), &"ada")
	assert_true(runtime.roles.eligible(&"ferry_master", &"ada"))
	assert_false(runtime.roles.eligible(&"ferry_master", &"bea"))
	runtime.roles.define(
		&"ferry_master",
		_SUCCESSION,
		false,
		-1,
		"place(gullhaven)",
		_ELIGIBILITY,
		&"ada",
		"hold",
		"public"
	)
	assert_eq(runtime.roles.definition(&"ferry_master"), from_block)
	assert_eq(runtime.roles.holder(&"ferry_master"), &"ada")
	assert_true(runtime.roles.eligible(&"ferry_master", &"ada"))
	assert_false(runtime.roles.eligible(&"ferry_master", &"bea"))
	assert_false(runtime.roles.eligible(&"ferry_master", &"cy"))


func test_succession_skips_ineligible_and_dead() -> void:
	var opened := _boot()
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.world.add_entity(&"cy", &"person", "Cy", PackedStringArray(["local"]), true)
	runtime.roles.define(&"dock_keeper", "relation(apprentice)", false, -1, "", "has_tag(candidate, local)")
	runtime.social.set_kind(&"ada", &"bea", &"apprentice")
	runtime.social.set_kind(&"ada", &"cy", &"apprentice")
	runtime.roles.assign(&"dock_keeper", &"ada")
	runtime.roles.vacate(&"dock_keeper", &"died")
	assert_eq(runtime.roles.holder(&"dock_keeper"), &"cy")
	assert_eq(runtime.roles.binding_status(&"dock_keeper"), &"successor")
	host.world.add_entity(&"cy", &"person", "Cy", PackedStringArray(["local"]), false)
	runtime.roles.define(&"ferry_master", "relation(apprentice)", false, -1, "", "has_tag(candidate, local)")
	runtime.social.set_kind(&"ada", &"bea", &"apprentice")
	runtime.roles.assign(&"ferry_master", &"ada")
	runtime.roles.vacate(&"ferry_master", &"died")
	assert_eq(runtime.roles.holder(&"ferry_master"), &"")
	assert_eq(runtime.roles.binding_status(&"ferry_master"), &"empty")
	assert_true(runtime.roles.eligible(&"ferry_master", &"cy"))


func test_election_stays_stored_until_a_later_pr() -> void:
	var opened := _boot()
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.roles.define(&"storm_watcher", "faction_assigns(faction.harbor)", false, -1, "", "", &"", "abolish")
	assert_eq(runtime.roles.definition(&"storm_watcher")["strategy"], "faction_assigns")
	assert_eq(runtime.roles.definition(&"storm_watcher")["succession_arg"], "faction.harbor")
	assert_eq(runtime.roles.definition(&"storm_watcher")["vacancy"], "abolish")
	runtime.roles.assign(&"storm_watcher", &"ada")
	runtime.roles.vacate(&"storm_watcher", &"left")
	assert_eq(runtime.roles.holder(&"storm_watcher"), &"")
	assert_true(runtime.roles.abolished(&"storm_watcher"))
	assert_eq(runtime.deeds.count_matching(&"ada", &"role_abolished", &"storm_watcher"), 1)
	runtime.roles.define(&"tavern_owner", "election")
	runtime.roles.define(&"watcher", "host_decides")
	runtime.roles.assign(&"tavern_owner", &"bea")
	runtime.roles.assign(&"watcher", &"ada")
	runtime.roles.vacate(&"tavern_owner", &"left")
	runtime.roles.vacate(&"watcher", &"left")
	assert_eq(runtime.roles.holder(&"tavern_owner"), &"")
	assert_false(runtime.roles.abolished(&"tavern_owner"))
	assert_eq(runtime.roles.holder(&"watcher"), &"")
	assert_eq(runtime.roles.binding_status(&"watcher"), &"pending")


func test_eligibility_trace_is_one_line() -> void:
	var opened := _boot()
	var runtime: WyrdRuntime = opened["runtime"]
	var parts := PackedStringArray()
	var lines := PackedStringArray()
	for i in 120:
		var key := "gullhaven.n%03d" % i
		lines.append("  %s : int stored" % key)
		parts.append("%s > 0" % key)
	var body := "language 1\nfacts\n%s\nrole dock_keeper\n  eligibility: %s\n" % ["\n".join(lines), " and ".join(parts)]
	var compiled := _compile(body)
	assert_eq(compiled["diagnostics"].format(), "")
	var file: WyrdFileDef = compiled["file"]
	runtime.facts.bind_schema(compiled["schema"])
	runtime.roles.install(file.roles[0])
	assert_gt(file.roles[0].eligibility.reads.size(), 100)
	for i in 120:
		runtime.facts.set(&"gullhaven.n%03d" % i, 1)
	runtime.trace.enabled = true
	runtime.trace.clear()
	assert_true(runtime.roles.eligible(&"dock_keeper", &"ada"))
	assert_eq(runtime.trace.events.size(), 1)
	var row: Dictionary = runtime.trace.events[0]
	assert_eq(String(row["kind"]), "eligible")
	assert_eq(String(row["role"]), "dock_keeper")
	assert_eq(String(row["entity"]), "ada")
	assert_eq(bool(row["ok"]), true)
	assert_eq(row.size(), 4)
	assert_false(JSON.stringify(row).contains("gullhaven.n"))
	runtime.facts.set(&"gullhaven.n000", 0)
	assert_false(runtime.roles.eligible(&"dock_keeper", &"ada"))
	assert_eq(runtime.trace.events.size(), 2)
	runtime.roles.define(&"watcher", "none")
	assert_true(runtime.roles.eligible(&"watcher", &"ada"))
	assert_eq(runtime.trace.events.size(), 2)


func test_content_load_assigns_secret_default_holder() -> void:
	var path := "user://wyrd_m4_role_block.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(_role_body().replace("visibility: public", "visibility: secret"))
	file.close()
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	_people(host)
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(4)
	assert_eq(runtime.roles.holder(&"ferry_master"), &"ada")
	assert_eq(runtime.roles.definition(&"ferry_master")["visibility"], "secret")
	assert_false(runtime.roles.revealed(&"player", &"role.ferry_master.holder"))
	runtime.roles.tell(&"ferry_master", &"player")
	assert_true(runtime.roles.revealed(&"player", &"role.ferry_master.holder"))


func test_save_keeps_eligibility() -> void:
	var opened := _boot()
	var runtime: WyrdRuntime = opened["runtime"]
	assert_true(_load_header(runtime).ok)
	runtime.start_new_game(4)
	runtime.roles.define(&"ferry_master", "none", false, -1, "world", _ELIGIBILITY, &"ada")
	assert_eq(runtime.roles.holder(&"ferry_master"), &"ada")
	var saved := runtime.save_state()
	assert_eq(int(saved["schema_version"]), 1)
	var parsed: Variant = JSON.parse_string(JSON.stringify(saved))
	var fresh := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(fresh)
	_people(host)
	assert_true(_load_header(fresh).ok)
	fresh.start_new_game(4)
	var loaded := fresh.load_state(parsed)
	assert_true(loaded.ok, loaded.diagnostics.format())
	assert_eq(fresh.roles.definition(&"ferry_master")["eligibility"], _ELIGIBILITY)
	assert_true(fresh.roles.eligible(&"ferry_master", &"ada"))
	assert_false(fresh.roles.eligible(&"ferry_master", &"bea"))
	assert_eq(fresh.roles.holder(&"ferry_master"), &"ada")


func test_duplicate_role_and_fact_read() -> void:
	var left := "user://wyrd_m4_role_a.wyrd"
	var right := "user://wyrd_m4_role_b.wyrd"
	_write(left, "language 1\n\nrole ferry_master\n  succession: none\n")
	_write(right, "language 1\n\nrole ferry_master\n  succession: election\n")
	var diagnostics := WyrdDiagnostics.new()
	WyrdPack.compile(PackedStringArray([left, right]), "harbor", 1, null, diagnostics, "", true)
	assert_true(diagnostics.format().contains("E_ROLE_DUPLICATE"))
	var read := "user://wyrd_m4_role_read.wyrd"
	_write(read, "language 1\n\nfacts\n  player.coins : int stored\nrole ferry_master\n  eligibility: player.coins >= 0\n")
	var used := WyrdDiagnostics.new()
	var pack := WyrdPack.compile(PackedStringArray([read]), "harbor", 1, null, used, "", true)
	var text := used.format()
	assert_false(text.contains("W_FACT_UNUSED"))
	assert_true(text.contains("W_FACT_NEVER_SET"))
	assert_true(text.contains("player.coins"))
	var exported: Array = WyrdExport.to_data(pack)["roles"]
	assert_eq(exported.size(), 1)
	assert_eq(String((exported[0] as Dictionary)["id"]), "ferry_master")


func test_define_rejects_a_bad_eligibility_condition() -> void:
	var opened := _boot()
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.roles.define(&"ferry_master", "none", false, -1, "", "chance(0.5)")
	assert_push_error("chance")
	assert_eq(runtime.roles.definition(&"ferry_master")["strategy"], "none")
	assert_eq(runtime.roles.definition(&"ferry_master")["eligibility"], "")


func _boot() -> Dictionary:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	_people(host)
	runtime.start_new_game(4)
	return {"host": host, "runtime": runtime}


func _people(host: WyrdFakeHost) -> void:
	host.world.add_entity(&"ada", &"person", "Ada", PackedStringArray(["local"]), true)
	host.world.add_entity(&"bea", &"person", "Bea", PackedStringArray(), true)
	host.world.add_entity(&"cy", &"person", "Cy", PackedStringArray(["local"]), false)
	host.world.add_entity(&"player", &"person", "traveler", PackedStringArray(), true)


func _role_body() -> String:
	return """language 1

role ferry_master
  scope: place(gullhaven)
  eligibility: %s
  default_holder: ada
  visibility: public
  succession: %s
  vacancy: hold
""" % [_ELIGIBILITY, _SUCCESSION]


func _compile(body: String) -> Dictionary:
	var source := WyrdSource.new("res://tests/unit/m4_role.wyrd", body)
	var diagnostics := WyrdDiagnostics.new()
	var tree := WyrdParser.new().parse(source, diagnostics)
	var file := WyrdStatements.new().compile(source, tree, diagnostics)
	return {"diagnostics": diagnostics, "file": file, "schema": tree.schema}


func _load_header(runtime: WyrdRuntime) -> WyrdLoadReport:
	var path := "user://wyrd_m4_role_header.wyrd"
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
