extends GutTest


func test_stored_fact_lints_and_resolved_fact_is_not_never_set() -> void:
	var diagnostics := WyrdDiagnostics.new()
	var pack := _compile(diagnostics, """
		language 1
		events
		  season_changed()
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


func test_storylet_and_scene_line_writes_count_and_a_read_only_fact_is_never_set() -> void:
	var diagnostics := WyrdDiagnostics.new()
	var pack := _compile(diagnostics, """
		language 1
		facts
		  player.coins : int stored
		  ferry.toll_coins : int stored
		  harbor.tide : int stored
		scene dock.talk
		  ~ set player.coins = 1
		  when player.coins >= 1: narrator: The board shows the toll. #line:board
		  -> end
		storylet harbor.toll
		  scope: topic harbor_toll
		  speaker: any
		  when: ferry.toll_coins >= 0 and harbor.tide >= 0
		  ~ set ferry.toll_coins = 1
		  - The toll is posted. #line:toll_line
		""")
	assert_false(diagnostics.has_errors(), diagnostics.format())
	assert_true(diagnostics.format().contains("stored fact \"harbor.tide\" is read but never set"))
	assert_false(diagnostics.format().contains("stored fact \"player.coins\" is read but never set"))
	assert_false(diagnostics.format().contains("stored fact \"ferry.toll_coins\" is read but never set"))
	var coins: Dictionary = _fact(pack, "player.coins")
	var coin_writers: Array = coins["writers"]
	assert_eq(coin_writers.size(), 1)
	assert_eq(str(coin_writers[0]["kind"]), "effect")
	assert_eq(str(coin_writers[0]["id"]), "dock.talk")
	var toll: Dictionary = _fact(pack, "ferry.toll_coins")
	var toll_writers: Array = toll["writers"]
	assert_eq(toll_writers.size(), 1)
	assert_eq(str(toll_writers[0]["kind"]), "effect")
	assert_eq(str(toll_writers[0]["id"]), "harbor.toll")
	var tide: Dictionary = _fact(pack, "harbor.tide")
	assert_eq((tide["writers"] as Array).size(), 0)


func test_interpolation_before_a_write_warns() -> void:
	var early := WyrdDiagnostics.new()
	_compile(early, """
		language 1
		facts
		  ferry.toll_coins : int stored
		quest gate "Gate"
		  stage arrive
		    journal: Wants {ferry.toll_coins}. #line:j1
		    ~ inc ferry.toll_coins by 2
		    ~ outcome route = done
		scene dock
		  narrator: Toll {ferry.toll_coins}. #line:d1
		  -> end
		""")
	assert_true(early.format().contains("warning[W_INTERP_UNSET]"))
	assert_true(early.format().contains("ferry.toll_coins"))
	var late := WyrdDiagnostics.new()
	_compile(late, """
		language 1
		facts
		  ferry.toll_coins : int stored
		quest gate "Gate"
		  stage arrive
		    ~ inc ferry.toll_coins by 2
		    journal: Wants {ferry.toll_coins}. #line:j1
		    ~ outcome route = done
		""")
	assert_false(late.format().contains("W_INTERP_UNSET"))


func test_holder_interpolation_warns_when_the_slot_can_be_empty() -> void:
	var open_slot := WyrdDiagnostics.new()
	_compile(open_slot, """
		language 1
		quest gate "Gate"
		  slot ferry = ferry_master mode: live
		  on_empty: wait
		  stage arrive
		    scene dock with ferry
		    ~ outcome route = done
		scene dock
		  lookout: {holder(ferry).name} is here. #line:d1
		  -> end
		""")
	assert_true(open_slot.format().contains("warning[W_HOLDER_UNGUARDED]"))
	assert_true(open_slot.format().contains("holder(\"ferry\")"))
	var alive_fact := WyrdDiagnostics.new()
	_compile(alive_fact, """
		language 1
		facts
		  npc.{id}.alive : bool source: world.is_alive
		quest gate "Gate"
		  slot ferry = ferry_master mode: live
		  on_empty: wait
		  stage arrive
		    scene dock with ferry
		    ~ outcome route = done
		scene dock
		  when npc.ferry_master.alive: lookout: {holder(ferry).name} is here. #line:d1
		  -> end
		""")
	assert_true(alive_fact.format().contains("warning[W_HOLDER_UNGUARDED]"))
	var either := WyrdDiagnostics.new()
	_compile(either, """
		language 1
		facts
		  player.coins : int stored
		quest gate "Gate"
		  slot ferry = ferry_master mode: live
		  on_empty: wait
		  stage arrive
		    ~ set player.coins = 2
		    scene dock with ferry
		    ~ outcome route = done
		scene dock
		  when filled(ferry) or player.coins > 0: lookout: {holder(ferry).name} is here. #line:d1
		  -> end
		""")
	assert_true(either.format().contains("warning[W_HOLDER_UNGUARDED]"))
	var guarded := WyrdDiagnostics.new()
	_compile(guarded, """
		language 1
		facts
		  player.coins : int stored
		quest gate "Gate"
		  slot ferry = ferry_master mode: live
		  on_empty: wait
		  stage arrive
		    ~ set player.coins = 2
		    scene dock with ferry
		    ~ outcome route = done
		scene dock
		  when filled(ferry) and player.coins >= 2: lookout: {holder(ferry).name} is here. #line:d1
		  when not filled(ferry): lookout: The dock is empty. #line:d2
		  -> end
		""")
	assert_false(guarded.format().contains("W_HOLDER_UNGUARDED"), guarded.format())
	var replaced := WyrdDiagnostics.new()
	_compile(replaced, """
		language 1
		quest gate "Gate"
		  slot ferry = ferry_master mode: live
		  stage arrive
		    journal: {holder(ferry).name} is at the dock. #line:j1
		    variant ferry.empty:
		      journal: The dock is empty. #line:j_empty
		    ~ outcome route = done
		""")
	assert_false(replaced.format().contains("W_HOLDER_UNGUARDED"), replaced.format())
	var inside := WyrdDiagnostics.new()
	_compile(inside, """
		language 1
		quest gate "Gate"
		  slot ferry = ferry_master mode: live
		  stage arrive
		    ~ outcome route = done
		    variant ferry.empty:
		      journal: {holder(ferry).name} is gone. #line:j_empty
		""")
	assert_true(inside.format().contains("warning[W_HOLDER_UNGUARDED]"))


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
