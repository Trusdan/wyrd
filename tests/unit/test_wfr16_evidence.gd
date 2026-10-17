extends GutTest

## WFR16: event witnesses and decaying world evidence.


func test_saw_heard_and_inferred_write_by_mode() -> void:
	var opened := _boot(_PACK)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.trace.enabled = true
	_pour(runtime, [
		{"id": &"ferry_master", "mode": &"saw"},
		{"id": &"dock_hand", "mode": "heard"},
		{"id": &"dock_apprentice", "mode": "inferred"},
		{"id": &"player", "mode": ""},
	])
	assert_eq(runtime.facts.get(&"harbor.deck_wet"), true)
	assert_eq(runtime.facts.get_in(&"harbor.deck_wet", &"known/ferry_master"), true)
	assert_null(runtime.facts.get_in(&"harbor.deck_wet", &"believed/ferry_master"))
	assert_eq(runtime.facts.get_in(&"harbor.deck_wet", &"believed/dock_hand"), true)
	assert_null(runtime.facts.get_in(&"harbor.deck_wet", &"known/dock_hand"))
	assert_eq(runtime.facts.get_in(&"harbor.deck_wet", &"believed/dock_apprentice"), true)
	assert_null(runtime.facts.get_in(&"harbor.deck_wet", &"known/player"))
	assert_null(runtime.facts.get_in(&"harbor.deck_wet", &"believed/player"))
	var witnesses := _rows(runtime, "event_witness")
	assert_eq(witnesses.size(), 3)
	assert_eq(String(witnesses[0]["agent"]), "ferry_master")
	assert_eq(String(witnesses[0]["mode"]), "saw")
	assert_eq(String(witnesses[0]["event"]), "bucket_poured")
	assert_eq(String(witnesses[0]["key"]), "harbor.deck_wet")
	assert_eq(String(witnesses[0]["value"]), "true")
	assert_eq(String(witnesses[1]["mode"]), "heard")
	assert_eq(String(witnesses[2]["agent"]), "dock_apprentice")
	assert_eq(String(witnesses[2]["mode"]), "inferred")
	var evidence := _rows(runtime, "evidence")
	assert_eq(evidence.size(), 1)
	assert_eq(String(evidence[0]["event"]), "bucket_poured")
	assert_eq(String(evidence[0]["key"]), "harbor.deck_wet")
	assert_eq(String(evidence[0]["value"]), "true")
	assert_eq(String(evidence[0]["until"]), "60")
	var event := runtime.content().events["bucket_poured"] as WyrdEventDef
	assert_eq(event.leaves_key, "harbor.deck_wet")
	assert_eq(event.decays_minutes, 60)
	assert_eq(event.leaves_value, true)


func test_trace_prefix_keeps_the_matching_witness() -> void:
	var opened := _boot(_PACK)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.trace.enabled = true
	runtime.trace.prefix = "dock_hand"
	_pour(runtime, [
		{"id": "ferry_master", "mode": "saw"},
		{"id": "dock_hand", "mode": "heard"},
	])
	var witnesses := _rows(runtime, "event_witness")
	assert_eq(witnesses.size(), 1)
	assert_eq(String(witnesses[0]["who"]), "dock_hand")
	assert_eq(_rows(runtime, "evidence").size(), 0)
	assert_eq(runtime.facts.get_in(&"harbor.deck_wet", &"known/ferry_master"), true)


func test_auto_witnesses_follow_the_spatial_adapter() -> void:
	var opened := _boot(_PACK)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.spatial.set_witnesses(
		&"harbor",
		PackedStringArray([&"ferry_master", &"dock_hand", &"dock_apprentice"])
	)
	host.spatial.set_perception(&"dock_hand", &"heard", &"harbor")
	host.spatial.set_perception(&"dock_apprentice", &"", &"harbor")
	runtime.trace.enabled = true
	runtime.events.emit(&"bucket_poured", {
		"actor": &"player",
		"place": &"harbor",
		"witnesses": "auto",
	})
	assert_eq(runtime.facts.get(&"harbor.deck_wet"), true)
	assert_eq(runtime.facts.get_in(&"harbor.deck_wet", &"known/ferry_master"), true)
	assert_eq(runtime.facts.get_in(&"harbor.deck_wet", &"believed/dock_hand"), true)
	assert_null(runtime.facts.get_in(&"harbor.deck_wet", &"known/dock_apprentice"))
	assert_null(runtime.facts.get_in(&"harbor.deck_wet", &"believed/dock_apprentice"))
	var witnesses := _rows(runtime, "event_witness")
	assert_eq(witnesses.size(), 2)
	assert_eq(String(witnesses[0]["agent"]), "ferry_master")
	assert_eq(String(witnesses[0]["mode"]), "saw")
	assert_eq(String(witnesses[1]["mode"]), "heard")
	var rows: Array = runtime.facts.evidence_rows()
	assert_eq(rows.size(), 1)
	assert_eq(String(rows[0]["place"]), "harbor")
	assert_eq(String(rows[0]["actor"]), "player")


func test_evidence_decays_on_tick_and_a_changed_value_stays() -> void:
	var opened := _boot(_PACK)
	var runtime: WyrdRuntime = opened["runtime"]
	_pour(runtime, [])
	runtime.tick(59)
	assert_eq(runtime.facts.get(&"harbor.deck_wet"), true)
	runtime.tick(1)
	assert_null(runtime.facts.get(&"harbor.deck_wet"))
	assert_eq(runtime.facts.evidence_rows().size(), 0)

	var again := _boot(_PACK)
	var refreshed: WyrdRuntime = again["runtime"]
	_pour(refreshed, [])
	refreshed.tick(59)
	_pour(refreshed, [])
	refreshed.tick(59)
	assert_eq(refreshed.facts.get(&"harbor.deck_wet"), true)
	refreshed.tick(1)
	assert_null(refreshed.facts.get(&"harbor.deck_wet"))

	var kept := _boot(_PACK)
	var host_owned: WyrdRuntime = kept["runtime"]
	_pour(host_owned, [])
	host_owned.facts.set(&"harbor.deck_wet", false)
	host_owned.tick(60)
	assert_eq(host_owned.facts.get(&"harbor.deck_wet"), false)
	assert_eq(host_owned.facts.evidence_rows().size(), 0)
	host_owned.facts.set(&"harbor.deck_wet", true)
	host_owned.tick(60)
	assert_eq(host_owned.facts.get(&"harbor.deck_wet"), true)

	var steady := _boot(_PACK)
	var bell: WyrdRuntime = steady["runtime"]
	bell.events.emit(&"bell_note", {"actor": &"player"})
	bell.tick(500)
	assert_eq(bell.facts.get(&"harbor.bell_struck"), true)
	assert_eq(int(bell.facts.evidence_rows()[0]["until"]), -1)


func test_save_and_load_keep_the_deadline() -> void:
	var opened := _boot(_PACK)
	var runtime: WyrdRuntime = opened["runtime"]
	_pour(runtime, [{"id": "ferry_master", "mode": "saw"}])
	var saved := runtime.save_state()
	assert_eq(int(saved["schema_version"]), 3)
	var facts: Dictionary = saved["facts"]
	assert_true(facts.has("evidence"))
	var listed: Array = facts["evidence"]
	assert_eq(listed.size(), 1)
	assert_eq(String(listed[0]["key"]), "harbor.deck_wet")
	assert_eq(int(listed[0]["until"]), 60)
	assert_eq(listed[0]["value"], true)
	runtime.tick(60)
	assert_null(runtime.facts.get(&"harbor.deck_wet"))

	var restored := _boot(_PACK)
	var loaded: WyrdRuntime = restored["runtime"]
	var report := loaded.load_state(saved)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(loaded.facts.get(&"harbor.deck_wet"), true)
	assert_eq(loaded.facts.get_in(&"harbor.deck_wet", &"known/ferry_master"), true)
	assert_eq(int(loaded.facts.evidence_rows()[0]["until"]), 60)
	loaded.tick(59)
	assert_eq(loaded.facts.get(&"harbor.deck_wet"), true)
	loaded.tick(1)
	assert_null(loaded.facts.get(&"harbor.deck_wet"))
	assert_eq(loaded.facts.get_in(&"harbor.deck_wet", &"known/ferry_master"), true)

	var parsed: Variant = JSON.parse_string(JSON.stringify(saved))
	assert_true(parsed is Dictionary)
	var from_json := _boot(_PACK)
	var round: WyrdRuntime = from_json["runtime"]
	var json_report := round.load_state(parsed)
	assert_true(json_report.ok, json_report.diagnostics.format())
	assert_eq(round.facts.get(&"harbor.deck_wet"), true)
	assert_eq(int(round.facts.evidence_rows()[0]["until"]), 60)
	round.tick(60)
	assert_null(round.facts.get(&"harbor.deck_wet"))


func test_notice_turns_evidence_into_a_belief() -> void:
	var opened := _boot(_PACK)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.spatial.set_perception(&"ferry_master", &"heard", &"harbor")
	runtime.trace.enabled = true
	runtime.events.emit(&"bucket_poured", {"actor": &"player", "place": &"harbor"})
	assert_null(runtime.facts.get_in(&"harbor.deck_wet", &"known/ferry_master"))
	runtime.notice_evidence(&"ferry_master", &"harbor")
	assert_eq(runtime.facts.get_in(&"harbor.deck_wet", &"believed/ferry_master"), true)
	assert_null(runtime.facts.get_in(&"harbor.deck_wet", &"known/ferry_master"))
	assert_eq(runtime.facts.get(&"harbor.deck_wet"), true)
	var witnesses := _rows(runtime, "event_witness")
	assert_eq(witnesses.size(), 1)
	assert_eq(String(witnesses[0]["mode"]), "heard")
	assert_eq(String(witnesses[0]["key"]), "harbor.deck_wet")
	runtime.tick(60)
	assert_null(runtime.facts.get(&"harbor.deck_wet"))
	assert_eq(runtime.facts.get_in(&"harbor.deck_wet", &"believed/ferry_master"), true)


func test_bad_witness_list_still_leaves_evidence() -> void:
	var opened := _boot(_PACK)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.events.emit(&"bucket_poured", {
		"actor": &"player",
		"place": &"harbor",
		"witnesses": 4,
	})
	assert_push_error("witnesses must")
	assert_eq(runtime.facts.get(&"harbor.deck_wet"), true)
	runtime.events.emit(&"bucket_poured", {
		"actor": &"player",
		"place": &"harbor",
		"witnesses": [
			{"id": "dock_hand", "mode": "guessed"},
			{"id": "ferry_master", "mode": "saw"},
		],
	})
	assert_push_error("unknown witness mode")
	assert_null(runtime.facts.get_in(&"harbor.deck_wet", &"believed/dock_hand"))
	assert_eq(runtime.facts.get_in(&"harbor.deck_wet", &"known/ferry_master"), true)


func test_leaves_diagnostics() -> void:
	var good := _diagnostics(_PACK)
	assert_false(good.has_errors(), good.format())
	assert_true(_diagnostics("""
		language 1
		events
		  bucket_poured(witnesses: symbol)
		""").format().contains("reserved for the emit payload"))
	assert_true(_diagnostics("""
		language 1
		events
		  bucket_poured() leaves: harbor.deck_wet = true decays 0
		""").format().contains("positive number of game minutes"))
	assert_true(_diagnostics("""
		language 1
		facts
		  harbor.deck_wet : bool stored
		events
		  bucket_poured() leaves: harbor.missing = true
		""").format().contains("E_UNKNOWN_FACT"))
	assert_true(_diagnostics("""
		language 1
		facts
		  world.season : symbol source: time.season invalidate: on_event(season_changed)
		events
		  season_changed() leaves: world.season = storm
		""").format().contains("E_WRITE_RESOLVED"))
	assert_true(_diagnostics("""
		language 1
		facts
		  harbor.deck_wet : bool stored
		events
		  bucket_poured() leaves: harbor.deck_wet = 1
		""").format().contains("E_WRITE_TYPE"))
	assert_true(_diagnostics("""
		language 1
		facts
		  npc.{id}.alive : bool source: world.is_alive invalidate: on_event(entity_alive_changed)
		events
		  entity_alive_changed(entity: symbol, alive: bool)
		  marked() leaves: npc.ferry_master.alive = true
		""").format().contains("must be a concrete key"))
	var depth := _diagnostics("""
		language 1
		facts
		  harbor.depth : float stored
		events
		  tide_rose() leaves: harbor.depth = 1.5
		""")
	assert_false(depth.has_errors(), depth.format())


func _pour(runtime: WyrdRuntime, witnesses: Array) -> void:
	var payload := {"actor": &"player", "place": &"harbor"}
	if not witnesses.is_empty():
		payload["witnesses"] = witnesses
	runtime.events.emit(&"bucket_poured", payload)


func _rows(runtime: WyrdRuntime, kind: String) -> Array:
	var found: Array = []
	for row in runtime.trace.snapshot():
		if str(row.get("kind", "")) == kind:
			found.append(row)
	return found


func _boot(body: String) -> Dictionary:
	var path := "user://wyrd_wfr16_%d.wyrd" % body.hash()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(body.strip_edges() + "\n")
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"gullhaven"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(5)
	return {"host": host, "runtime": runtime}


func _diagnostics(body: String) -> WyrdDiagnostics:
	var lines := PackedStringArray()
	for line in body.strip_edges().split("\n"):
		if line.begins_with("\t\t"):
			lines.append(line.substr(2))
		else:
			lines.append(line)
	var path := "user://wyrd_wfr16_diag_%d.wyrd" % body.hash()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	file.close()
	var diagnostics := WyrdDiagnostics.new()
	WyrdPack.compile(PackedStringArray([path]), "gullhaven", 1, null, diagnostics, path, true)
	return diagnostics


const _PACK := """
language 1
events
  bucket_poured(actor: symbol, place: symbol) leaves: harbor.deck_wet = true decays 60
  bell_note(actor: symbol) leaves: harbor.bell_struck = true
facts
  harbor.deck_wet : bool stored
  harbor.bell_struck : bool stored
scene deck
  narrator: The harbor deck. #line:deck
  when harbor.deck_wet: narrator: The deck is still wet from the bucket. #line:a_wet
  when harbor.bell_struck: narrator: The bell note is still here. #line:a_note
  -> end
"""
