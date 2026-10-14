extends GutTest


func test_stored_fact_lints_and_resolved_fact_is_not_never_set() -> void:
	var diagnostics := WyrdDiagnostics.new()
	var pack := _compile(diagnostics, """
		language 1
		facts
		  player.coins : int stored
		  world.season : symbol source: time.season invalidate: on_event(season_changed)
		quest gate "Gate"
		  stage arrive
		    waits_until world.season == storm and player.coins >= 0
		    ~ outcome route = done
		""")
	assert_false(diagnostics.has_errors(), diagnostics.format())
	assert_true(diagnostics.format().contains("warning[W_FACT_NEVER_SET]"))
	assert_true(diagnostics.format().contains("player.coins"))
	assert_false(diagnostics.format().contains("world.season"))
	assert_eq(pack.xref.events.size(), 1)
	assert_eq(str(pack.xref.events[0]["name"]), "season_changed")
	var season: Dictionary = _fact(pack, "world.season")
	assert_gt((season["readers"] as Array).size(), 0)
	assert_eq((season["writers"] as Array).size(), 0)


func test_pattern_read_matches_through_the_dependency_index() -> void:
	var diagnostics := WyrdDiagnostics.new()
	var pack := _compile(diagnostics, """
		language 1
		facts
		  npc.{id}.alive : bool source: world.is_alive
		scene room
		  when npc.ferry_master.alive: narrator: On the dock. #line:aa01
		  -> end
		""")
	var fact: Dictionary = _fact(pack, "npc.{id}.alive")
	assert_gt((fact["readers"] as Array).size(), 0)
	assert_eq(str(fact["source"]), "world.is_alive")
	assert_false(diagnostics.format().contains("W_FACT_NEVER_SET"))
	assert_false(diagnostics.format().contains("W_FACT_UNUSED"))


func test_set_without_a_read_is_never_read_and_deed_is_not_a_write() -> void:
	var diagnostics := WyrdDiagnostics.new()
	var pack := _compile(diagnostics, """
		language 1
		facts
		  player.coins : int stored
		  ferry.toll_coins : int stored
		quest gate "Gate"
		  stage arrive
		    ~ set player.coins = 1
		    ~ record deed paid(actor: player, target: ferry, place: gullhaven, tags: [toll], magnitude: 1, witnesses: auto, visibility: public, memorable: true)
		    ~ outcome route = done
		""")
	assert_true(diagnostics.format().contains("warning[W_FACT_NEVER_READ]"))
	assert_true(diagnostics.format().contains("player.coins"))
	assert_true(diagnostics.format().contains("warning[W_FACT_UNUSED]"))
	assert_true(diagnostics.format().contains("ferry.toll_coins"))
	var coins: Dictionary = _fact(pack, "player.coins")
	assert_eq((coins["writers"] as Array).size(), 1)
	assert_eq((coins["readers"] as Array).size(), 0)


func _compile(diagnostics: WyrdDiagnostics, body: String) -> WyrdLinkedPack:
	var path := "user://wyrd_xref_%d.wyrd" % Time.get_ticks_usec()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(_text(body))
	file.close()
	return WyrdPack.compile(PackedStringArray([path]), "xref", 1, null, diagnostics, path, true)


func _fact(pack: WyrdLinkedPack, key: String) -> Dictionary:
	for fact in pack.xref.facts:
		if str(fact["key"]) == key:
			return fact
	return {}


func _text(body: String) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for line in body.strip_edges().split("\n"):
		if line.begins_with("\t\t"):
			lines.append(line.substr(2))
		elif line.begins_with("\t"):
			lines.append(line.substr(1))
		else:
			lines.append(line)
	return "\n".join(lines) + "\n"
