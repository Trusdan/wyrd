extends GutTest


func test_design_storylets_score_and_export() -> void:
	var compiled := _compile(_TRIO)
	var diagnostics: WyrdDiagnostics = compiled["diagnostics"]
	assert_false(diagnostics.has_errors(), diagnostics.format())
	var pack: WyrdLinkedPack = compiled["pack"]
	var generic := _find(pack, "harbor_gossip.generic")
	assert_eq(generic.specificity, 0)
	assert_true(generic.generic)
	assert_eq(generic.priority, 0)
	assert_eq(generic.weight, 1)
	assert_eq(generic.cooldown_minutes, 0)
	assert_eq(String(generic.body_kind), "line")
	assert_eq(generic.scope_text(), "topic rumor.ferry_toll")
	assert_eq(generic.speaker, "any")
	assert_eq(generic.lines.size(), 1)
	assert_eq(generic.lines[0].line_id, "sg01")
	var tavern := _find(pack, "harbor_gossip.tavern")
	assert_eq(tavern.specificity, 2)
	assert_false(tavern.generic)
	assert_eq(tavern.weight, 2)
	assert_eq(tavern.cooldown_minutes, 60)
	assert_eq(String(tavern.body_kind), "set")
	assert_eq(tavern.lines.size(), 2)
	var bark := _find(pack, "dock_bark_lantern")
	assert_eq(bark.specificity, 1)
	assert_false(bark.generic)
	assert_eq(bark.cooldown_minutes, 30)
	assert_eq(bark.speaker, "ferry")
	assert_true(diagnostics.format().contains("storylet \"harbor_gossip.generic\" specificity 0 priority 0 generic=true"))
	assert_true(diagnostics.format().contains("storylet \"harbor_gossip.tavern\" specificity 2 priority 0 generic=false"))
	assert_true(diagnostics.format().contains("storylet \"dock_bark_lantern\" specificity 1 priority 0 generic=false"))
	var data := WyrdExport.to_data(pack)
	assert_true(data.has("storylets"))
	var rows: Array = data["storylets"]
	assert_eq(rows.size(), 3)
	assert_eq(str(rows[0]["id"]), "dock_bark_lantern")
	assert_eq(int(rows[1]["specificity"]), 0)
	assert_eq(str(rows[1]["id"]), "harbor_gossip.generic")


func test_named_argument_calls_score_as_one_clause() -> void:
	var compiled := _compile(_TRIO + """
storylet harbor.named
  scope: topic rumor.ferry_toll
  speaker: any
  when: knows(player, harbor.toll_fate) and nearby(player, 4m, tag: lantern) > 0
  priority: 4
  - The ropes. #line:named1
storylet harbor.nearby
  scope: bark
  speaker: ferry
  when: nearby(player, 4m, tag: lantern) > 0
  - Mind the flame. #line:named2
storylet harbor.negated
  scope: bark
  speaker: ferry
  when: not knows(player, harbor.toll_fate)
  - Nobody asked. #line:named3
storylet harbor.either
  scope: bark
  speaker: ferry
  when: (knows(player, harbor.toll_fate) and world.season == autumn) or nearby(player, 4m, tag: lantern) > 0
  - One or the other. #line:named4
storylet harbor.plain
  scope: bark
  speaker: any
  when: true
  priority: -1
  weight: 0
  - A plain line. #line:named5
storylet harbor.chance
  scope: bark
  speaker: any
  when: chance(0.25)
  - Maybe. #line:named6
storylet harbor.beat
  scope: beat ferry_toll.offer
  speaker: tavern
  cooldown: 6h
  - The beat. #line:named7
""")
	var diagnostics: WyrdDiagnostics = compiled["diagnostics"]
	assert_false(diagnostics.has_errors(), diagnostics.format())
	var pack: WyrdLinkedPack = compiled["pack"]
	assert_eq(_find(pack, "harbor.named").specificity, 2)
	assert_eq(_find(pack, "harbor.named").priority, 4)
	assert_false(_find(pack, "harbor.named").generic)
	assert_eq(_find(pack, "harbor.nearby").specificity, 1)
	assert_eq(_find(pack, "harbor.negated").specificity, 1)
	assert_eq(_find(pack, "harbor.either").specificity, 1)
	var plain := _find(pack, "harbor.plain")
	assert_eq(plain.specificity, 1)
	assert_false(plain.generic)
	assert_eq(plain.priority, -1)
	assert_eq(plain.weight, 0)
	assert_eq(_find(pack, "harbor.chance").specificity, 1)
	var beat := _find(pack, "harbor.beat")
	assert_eq(beat.scope_text(), "beat ferry_toll.offer")
	assert_eq(beat.cooldown_minutes, 6 * 60)
	assert_true(beat.generic)
	assert_eq(beat.condition, null)
	var runtime := _runtime_from(compiled)
	assert_eq(runtime.condition_count(), 0)


func test_storylet_syntax_errors() -> void:
	assert_true(_text(_compile("""
language 1
facts
  harbor.toll_fate : symbol stored
storylet harbor.rumor
  scope: topic rumor.ferry_toll
  speaker: any
  - The ferry. 
""")).contains("error[E_LINE_ID_MISSING]"))
	assert_true(_text(_compile("""
language 1
storylet harbor.rumor
  scope: topic rumor.ferry_toll
  speaker: any
  - One line. #line:one
  - Two lines. #line:two
""")).contains("error[E_STORYLET_SYNTAX]"))
	assert_true(_text(_compile("""
language 1
storylet harbor.rumor
  scope: bark
  speaker: ferry
  weight: -1
  - No. #line:neg
""")).contains("weight cannot be negative"))
	assert_true(_text(_compile("""
language 1
storylet harbor.rumor
  scope: bark
  speaker: ferry
  cooldown: 30
  - No. #line:bare
""")).contains("cooldown needs a duration"))
	assert_true(_text(_compile("""
language 1
storylet harbor.rumor
  scope: bark
  speaker: ferry
  cooldown: -5m
  - No. #line:cold
""")).contains("cooldown cannot be negative"))
	assert_true(_text(_compile("""
language 1
storylet harbor.rumor
  scope: beat ferry_toll
  speaker: ferry
  - No. #line:beat
""")).contains("beat scope needs"))
	assert_true(_text(_compile("""
language 1
storylet harbor.one
  scope: bark
  speaker: any
  - First. #line:a
storylet harbor.one
  scope: bark
  speaker: any
  - Second. #line:b
""")).contains("error[E_STORYLET_DUPLICATE]"))
	assert_true(_text(_compile("""
language 1
storylet harbor.room
  scope: bark
  speaker: tavern
  -> scene toll.offer_room
""")).contains("error[E_SCENE_UNKNOWN]"))
	assert_true(_text(_compile("""
language 1
storylet harbor.pour
  scope: event bucket_poured
  speaker: ferry
  - The bucket. #line:pour1
""")).contains("error[E_EVENT_UNKNOWN]"))


func test_scene_body_and_known_event() -> void:
	var compiled := _compile("""
language 1
events
  bucket_poured()
scene toll.offer_room
  narrator: The room. #line:room1
  -> end
storylet harbor.room
  scope: bark
  speaker: tavern
  -> scene toll.offer_room
storylet harbor.pour
  scope: event bucket_poured
  speaker: ferry
  cooldown: 14d
  - The bucket. #line:pour1
""")
	var diagnostics: WyrdDiagnostics = compiled["diagnostics"]
	assert_false(diagnostics.has_errors(), diagnostics.format())
	var pack: WyrdLinkedPack = compiled["pack"]
	var room := _find(pack, "harbor.room")
	assert_eq(String(room.body_kind), "scene")
	assert_eq(room.scene_id, "toll.offer_room")
	assert_eq(_find(pack, "harbor.pour").cooldown_minutes, 14 * 1440)
	assert_eq(_find(pack, "harbor.pour").scope_text(), "event bucket_poured")


func test_duplicate_storylet_and_line_across_files() -> void:
	var first := _write("user://wyrd_m6_storylet_a.wyrd", """
language 1
storylet harbor.rumor
  scope: bark
  speaker: any
  - Shared. #line:sg01
""")
	var second := _write("user://wyrd_m6_storylet_b.wyrd", """
language 1
storylet harbor.rumor
  scope: bark
  speaker: ferry
  - Again. #line:sg01
""")
	var diagnostics := WyrdDiagnostics.new()
	WyrdPack.compile(PackedStringArray([first, second]), "harbor", 1, null, diagnostics, first, true)
	var text := diagnostics.format()
	assert_true(text.contains("error[E_STORYLET_DUPLICATE]"), text)
	assert_true(text.contains("error[E_LINE_ID_DUPLICATE]"), text)


func test_tag_lines_tags_storylet_prose() -> void:
	var taken := {}
	var result: Dictionary = WyrdTagLines.tag_text("""
language 1
storylet harbor.rumor
  scope: bark
  speaker: any
  - They say the ferry is dear.
""", "res://harbor_storylets.wyrd", "harbor", taken)
	var text := str(result["text"])
	assert_true(text.contains("#line:"), text)
	assert_eq(PackedStringArray(result["notes"]).size(), 1)


func test_export_omits_storylets_when_the_pack_has_none() -> void:
	var compiled := _compile("""
language 1
facts
  harbor.bell_count : int stored
""")
	var data := WyrdExport.to_data(compiled["pack"])
	assert_false(data.has("storylets"))


func test_line_set_draw_is_seeded_and_does_not_repeat() -> void:
	var left := _boot(_SET)
	var right := _boot(_SET)
	var first := _cycle(left)
	var second := _cycle(right)
	assert_eq(first, second)
	assert_eq(first.size(), 3)
	var seen := {}
	for line_id in first:
		assert_false(seen.has(line_id), line_id)
		seen[line_id] = true
	var again := str(left.storylets.draw("harbor.rumor")["line_id"])
	assert_eq(int(left.storylets.draw("harbor.rumor")["cycle"]), 1)
	assert_true(seen.has(again))
	assert_eq(str(right.storylets.draw("harbor.rumor")["line_id"]), again)
	assert_eq(left.condition_count(), 0)


func test_single_line_and_scene_write_no_save_row() -> void:
	var runtime := _boot(_LINE)
	var drawn := runtime.storylets.draw("harbor_gossip.generic")
	assert_eq(str(drawn["line_id"]), "sg01")
	assert_eq(str(drawn["body"]), "line")
	runtime.storylets.draw("harbor_gossip.generic")
	var scene := runtime.storylets.draw("harbor.room")
	assert_eq(str(scene["scene"]), "toll.offer_room")
	assert_eq(str(scene["line_id"]), "")
	var saved := runtime.save_state()
	assert_eq(int(saved["schema_version"]), 2)
	assert_false(saved.has("storylets"))
	runtime.storylets.draw("missing.rumor")
	assert_push_error("unknown storylet")


func test_line_set_save_load_and_json_round_trip() -> void:
	var runtime := _boot(_SET)
	var first := runtime.storylets.draw("harbor.rumor")
	var saved := runtime.save_state()
	assert_true(saved.has("storylets"))
	assert_eq(int(saved["schema_version"]), 2)
	var row: Dictionary = saved["storylets"]["harbor.rumor"]
	assert_eq(int(row["cursor"]), 1)
	assert_eq(int(row["cycle"]), 0)
	var parsed: Variant = JSON.parse_string(JSON.stringify(saved))
	assert_true(parsed is Dictionary)
	var loaded := _boot(_SET)
	var report := loaded.load_state(parsed)
	assert_true(report.ok, report.diagnostics.format())
	var from_json := loaded.storylets.draw("harbor.rumor")
	var continued := runtime.storylets.draw("harbor.rumor")
	assert_eq(str(from_json["line_id"]), str(continued["line_id"]))
	assert_ne(str(first["line_id"]), str(continued["line_id"]))
	var direct := _boot(_SET)
	assert_true(direct.load_state(saved).ok)
	assert_eq(str(direct.storylets.draw("harbor.rumor")["line_id"]), str(from_json["line_id"]))


func test_new_game_and_a_save_without_the_key_clear_draws() -> void:
	var runtime := _boot(_SET)
	runtime.storylets.draw("harbor.rumor")
	assert_true(runtime.save_state().has("storylets"))
	runtime.start_new_game(5)
	assert_false(runtime.save_state().has("storylets"))
	runtime.storylets.draw("harbor.rumor")
	var fresh := _boot(_SET)
	assert_true(runtime.load_state(fresh.save_state()).ok)
	assert_false(runtime.save_state().has("storylets"))


func test_import_drops_missing_line_ids_and_appends_new_ones() -> void:
	var runtime := _boot(_SET)
	runtime.storylets.import_state({
		"harbor.rumor": {"cycle": 1.0, "cursor": 1.0, "order": ["a", "gone", "b"]},
		"missing.rumor": {"cycle": 0, "cursor": 0, "order": ["a"]},
	})
	var kept := runtime.storylets.draw("harbor.rumor")
	var appended := runtime.storylets.draw("harbor.rumor")
	assert_eq(str(kept["line_id"]), "b")
	assert_eq(str(appended["line_id"]), "c")
	assert_eq(int(kept["cycle"]), 1)
	assert_eq(int(appended["cycle"]), 1)
	var saved: Dictionary = runtime.save_state()["storylets"]
	assert_false(saved.has("missing.rumor"))


func _cycle(runtime: WyrdRuntime) -> PackedStringArray:
	var ids := PackedStringArray()
	for _i in 3:
		var drawn := runtime.storylets.draw("harbor.rumor")
		assert_eq(int(drawn["cycle"]), 0)
		ids.append(str(drawn["line_id"]))
	return ids


func _boot(body: String) -> WyrdRuntime:
	return _runtime_from(_compile(body))


func _runtime_from(compiled: Dictionary) -> WyrdRuntime:
	var diagnostics: WyrdDiagnostics = compiled["diagnostics"]
	assert_false(diagnostics.has_errors(), diagnostics.format())
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([str(compiled["path"])])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(5)
	return runtime


func _compile(body: String) -> Dictionary:
	var path := _write("user://wyrd_m6_storylet_%d.wyrd" % body.hash(), body)
	var diagnostics := WyrdDiagnostics.new()
	var pack := WyrdPack.compile(PackedStringArray([path]), "harbor", 1, null, diagnostics, path, true)
	return {"diagnostics": diagnostics, "pack": pack, "path": path}


func _write(path: String, body: String) -> String:
	var lines := PackedStringArray()
	for line in body.strip_edges().split("\n"):
		if line.begins_with("\t\t"):
			lines.append(line.substr(2))
		else:
			lines.append(line)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	file.close()
	return path


func _text(compiled: Dictionary) -> String:
	var diagnostics: WyrdDiagnostics = compiled["diagnostics"]
	return diagnostics.format()


func _find(pack: WyrdLinkedPack, id: String) -> WyrdStoryletDef:
	for unit in pack.units:
		var file: WyrdFileDef = unit["file"]
		for story in file.storylets:
			if story.id == id:
				return story
	return null


const _TRIO := """
language 1
facts
  harbor.toll_fate : symbol stored
  world.season : symbol stored
storylet harbor_gossip.generic
  scope: topic rumor.ferry_toll
  speaker: any
  - They say the ferry's dear since the storm. #line:sg01
storylet harbor_gossip.tavern
  scope: topic rumor.ferry_toll
  speaker: tavern
  when: knows(player, harbor.toll_fate) and world.season == autumn
  weight: 2
  cooldown: 60m
  lines:
    - The toll money never reached the council, if you ask me. #line:sg02
    - Lost at sea, they say. Lost in someone's pocket. #line:sg03
storylet dock_bark_lantern
  scope: bark
  speaker: ferry
  when: nearby(player, 4m, tag: lantern) > 0
  cooldown: 30m
  - Mind that flame near the ropes. #line:sg04
"""


const _SET := """
language 1
storylet harbor.rumor
  scope: topic rumor.ferry_toll
  speaker: any
  lines:
    - One. #line:a
    - Two. #line:b
    - Three. #line:c
"""


const _LINE := """
language 1
scene toll.offer_room
  narrator: The room. #line:room1
  -> end
storylet harbor_gossip.generic
  scope: topic rumor.ferry_toll
  speaker: any
  - They say the ferry's dear since the storm. #line:sg01
storylet harbor.room
  scope: bark
  speaker: tavern
  -> scene toll.offer_room
"""
