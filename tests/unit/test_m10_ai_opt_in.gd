extends GutTest


func test_ai_line_messages_and_codes() -> void:
	var voiced := _text(_pack("res://tests/golden/cases/m10_ai_line_voiced.wyrd"))
	assert_eq(voiced.count("error[E_AI_LINE]: a voiced line cannot opt in to AI"), 2)
	var secrecy := _text(_pack("res://tests/golden/cases/m10_ai_line_secrecy.wyrd"))
	assert_eq(secrecy.count("error[E_AI_LINE]: a line in a secrecy tier cannot opt in to AI"), 2)
	var interp := _text(_pack("res://tests/golden/cases/m10_ai_line_interp.wyrd"))
	assert_eq(interp.count("error[E_AI_LINE]: an interpolating line cannot opt in to AI"), 3)
	assert_false(interp.contains("dw_plain"))
	var where := _text(_pack("res://tests/golden/cases/m10_ai_line_where.wyrd"))
	assert_eq(where.count("error[E_AI_LINE]: only spoken and storylet lines can opt in to AI"), 3)
	var unknown := _text(_pack("res://tests/golden/cases/m10_ai_context_unknown.wyrd"))
	assert_true(unknown.contains("error[E_AI_CONTEXT_UNKNOWN]: unknown fact \"harbor.missing\" in ai_context"))
	assert_true(unknown.contains("error[E_AI_CONTEXT_UNKNOWN]: unknown fact \"harbor.also\" in ai_context"))
	assert_true(unknown.contains("error[E_AI_CONTEXT_UNKNOWN]: unknown fact \"harbor.gone\" in ai_context"))
	var per_query := _text(_pack("res://tests/golden/cases/m10_ai_context_per_query.wyrd"))
	assert_eq(per_query.count("warning[W_AI_CONTEXT_RESOLVED_PER_QUERY]: ai_context key \"harbor.tide\" is resolved per query; the packet reads it once when built"), 2)
	var syntax := _text(_pack("res://tests/golden/cases/m10_ai_context_syntax.wyrd"))
	assert_true(syntax.contains("error[E_STORYLET_SYNTAX]: ai_context needs [<fact keys>]"))
	assert_true(syntax.contains("error[E_STORYLET_SYNTAX]: ai_context needs at least one fact key"))
	assert_true(syntax.contains("error[E_STORYLET_SYNTAX]: duplicate ai_context key \"harbor.tide\""))
	assert_true(syntax.contains("error[E_STORYLET_SYNTAX]: ai_context keys are concrete fact keys"))
	assert_true(syntax.contains("error[E_STORYLET_SYNTAX]: a line tag is not allowed on ai_context"))
	assert_true(syntax.contains("error[E_STORYLET_SYNTAX]: duplicate storylet field \"ai_context\""))
	assert_true(syntax.contains("error[E_STMT_UNKNOWN]: duplicate ai_context"))
	assert_true(syntax.contains("error[E_STMT_UNKNOWN]: ai_context cannot contain a block"))
	assert_true(syntax.contains("error[E_STMT_UNKNOWN]: a line tag is not allowed on ai_context"))


func test_one_diagnostic_per_reason_on_one_line() -> void:
	var text := _text(_compile("""
		language 1
		facts
		  harbor.tide : symbol stored
		scene dock.watch
		  narrator: The tide is {harbor.tide}. #tag:voiced #tag:ai #secrecy:sealed #line:all_three
	"""))
	assert_true(text.contains("error[E_AI_LINE]: a voiced line cannot opt in to AI"))
	assert_true(text.contains("error[E_AI_LINE]: a line in a secrecy tier cannot opt in to AI"))
	assert_true(text.contains("error[E_AI_LINE]: an interpolating line cannot opt in to AI"))
	assert_eq(text.count("error[E_AI_LINE]"), 3)


func test_scene_ai_context_syntax_uses_statement_errors() -> void:
	var text := _text(_compile("""
		language 1
		facts
		  harbor.tide : symbol stored
		scene dock.missing
		  ai_context [harbor.tide]
		  narrator: The tide. #line:m1
		scene dock.brackets
		  ai_context: harbor.tide
		  narrator: The tide. #line:m2
		scene dock.trail
		  ai_context: [harbor.tide] extra
		  narrator: The tide. #line:m3
		scene dock.empty
		  ai_context: []
		  narrator: The tide. #line:m4
		scene dock.dup
		  ai_context: [harbor.tide, harbor.tide]
		  narrator: The tide. #line:m5
		scene dock.pattern
		  ai_context: [npc.{id}.alive]
		  narrator: The tide. #line:m6
	"""))
	assert_eq(text.count("error[E_STMT_UNKNOWN]: ai_context needs [<fact keys>]"), 3)
	assert_true(text.contains("error[E_STMT_UNKNOWN]: ai_context needs at least one fact key"))
	assert_true(text.contains("error[E_STMT_UNKNOWN]: duplicate ai_context key \"harbor.tide\""))
	assert_true(text.contains("error[E_STMT_UNKNOWN]: ai_context keys are concrete fact keys"))
	assert_false(text.contains("E_STORYLET_SYNTAX"))


func test_document_and_header_cannot_opt_in() -> void:
	var text := _text(_compile("""
		language 1
		document dock_log "The Dock Log" #tag:ai #line:log_title
		  text: live
		  page
		    The tide is written here. #tag:ai #line:log_page
	"""))
	assert_eq(text.count("error[E_AI_LINE]: only spoken and storylet lines can opt in to AI"), 2)


func test_is_ai_and_context_keep_source_order() -> void:
	var compiled := _pack("res://tests/golden/cases/m10_ai_opt_in_clean.wyrd")
	var diagnostics: WyrdDiagnostics = compiled["diagnostics"]
	assert_false(diagnostics.has_errors(), diagnostics.format())
	assert_false(diagnostics.has_warnings(), diagnostics.format())
	var pack: WyrdLinkedPack = compiled["pack"]
	var scene := _scene(pack, "dock.watch")
	assert_eq(scene.ai_context, PackedStringArray(["harbor.tide", "harbor.fog"]))
	var spoken := scene.items[0].line_def as WyrdLineDef
	assert_true(spoken.is_ai())
	assert_eq(spoken.kind, &"spoken")
	var line_story := _story(pack, "dock_watch.line")
	assert_eq(line_story.ai_context, PackedStringArray(["harbor.fog", "harbor.tide"]))
	assert_true(line_story.lines[0].is_ai())
	assert_eq(line_story.lines[0].kind, &"storylet")
	var set_story := _story(pack, "dock_watch.set")
	assert_true(set_story.ai_context.is_empty())
	assert_true(set_story.lines[0].is_ai())
	assert_false(set_story.lines[1].is_ai())
	var plain := _line(_pack("res://tests/golden/cases/m10_ai_line_interp.wyrd")["pack"], "dw_plain")
	assert_true(plain.is_ai())
	assert_false(WyrdLineDef.has_spans(plain.prose))


func test_when_line_can_opt_in_and_ai_keeper_stays_a_speaker() -> void:
	var compiled := _compile("""
		language 1
		facts
		  harbor.tide : symbol stored
		scene dock.watch
		  when harbor.tide == high: narrator: The tide is high. #tag:ai #line:when_ok
		  ai_keeper: The lamp stays lit. #line:keep
		  -> end
	""")
	var diagnostics: WyrdDiagnostics = compiled["diagnostics"]
	assert_false(diagnostics.format().contains("E_AI_LINE"), diagnostics.format())
	assert_false(diagnostics.format().contains("E_SPEAKER_SHAPE"), diagnostics.format())
	var scene := _scene(compiled["pack"], "dock.watch")
	assert_eq(scene.items[0].line_def.speaker, "narrator")
	assert_true(scene.items[0].line_def.is_ai())
	assert_eq(scene.items[0].line_def.kind, &"spoken")
	assert_eq(scene.items[1].line_def.speaker, "ai_keeper")
	assert_false(scene.items[1].line_def.is_ai())


func test_export_json_carries_tags_and_ai_context() -> void:
	var compiled := _pack("res://tests/golden/cases/m10_ai_opt_in_clean.wyrd")
	var data := WyrdExport.to_data(compiled["pack"])
	var story := _row(data["storylets"], "dock_watch.line")
	assert_eq(story["ai_context"], ["harbor.fog", "harbor.tide"])
	var other := _row(data["storylets"], "dock_watch.set")
	assert_false(other.has("ai_context"))
	var scene := _row(data["scenes"], "dock.watch")
	assert_eq(scene["ai_context"], ["harbor.tide", "harbor.fog"])
	var tagged := _line_row(data["lines"], "harbor/dw_tide")
	assert_eq(tagged["tags"], ["ai"])
	var quiet := _line_row(data["lines"], "harbor/dw_lamp")
	assert_eq(quiet["tags"], [])
	var body := WyrdExport.to_json(data)
	assert_true(body.contains("\"ai_context\""))
	assert_true(body.contains("\"ai\""))


func test_export_without_opt_in_matches_the_existing_expected_file() -> void:
	var actual := WyrdGolden.to_json(WyrdLinkGolden.compile_dir("res://tests/golden/link/clean"))
	var expected := FileAccess.get_file_as_string("res://tests/golden/link/clean/expected.json")
	assert_eq(actual, expected)


func test_ai_context_keys_are_not_reads() -> void:
	var compiled := _compile("""
		language 1
		facts
		  harbor.packet : symbol stored
		  harbor.tide : symbol stored
		scene dock.watch
		  ai_context: [harbor.packet]
		  narrator: The tide is high. #line:r1
		storylet dock_watch.line
		  scope: bark
		  speaker: any
		  when: harbor.tide == high
		  ai_context: [harbor.packet, harbor.tide]
		  ~ set harbor.tide = high
		  - The fog sits on the water. #line:r2
	""")
	var diagnostics: WyrdDiagnostics = compiled["diagnostics"]
	assert_false(diagnostics.has_errors(), diagnostics.format())
	var pack: WyrdLinkedPack = compiled["pack"]
	var scene := _scene(pack, "dock.watch")
	var story := _story(pack, "dock_watch.line")
	assert_false(scene.reads.has(StringName("harbor.packet")))
	assert_false(story.reads.has(StringName("harbor.packet")))
	assert_true(story.reads.has(StringName("harbor.tide")))
	var xref: Variant = JSON.parse_string(WyrdExport.xref_json(pack))
	var packet_readers: Array = []
	for fact in xref["facts"]:
		if str(fact["key"]) == "harbor.packet":
			packet_readers = fact["readers"]
	assert_eq(packet_readers, [])


func test_cross_file_facts_resolve_at_statement_time() -> void:
	var facts_path := _write("user://wyrd_m10_facts.wyrd", """
		language 1
		facts
		  harbor.tide : symbol stored
	""")
	var body_path := _write("user://wyrd_m10_body.wyrd", """
		language 1
		storylet dock_watch.line
		  scope: bark
		  speaker: any
		  ai_context: [harbor.tide, harbor.missing]
		  - The tide turns. #line:x1
	""")
	var diagnostics := WyrdDiagnostics.new()
	var pack := WyrdPack.compile(
		PackedStringArray([facts_path, body_path]),
		"harbor",
		1,
		null,
		diagnostics,
		body_path,
		true
	)
	var text := diagnostics.format()
	assert_false(text.contains("unknown fact \"harbor.tide\" in ai_context"), text)
	assert_true(text.contains("error[E_AI_CONTEXT_UNKNOWN]: unknown fact \"harbor.missing\" in ai_context"))
	assert_eq(_story(pack, "dock_watch.line").ai_context, PackedStringArray(["harbor.tide", "harbor.missing"]))


func test_check_strict_fails_on_the_per_query_warning() -> void:
	var plain := WyrdCli.execute(PackedStringArray(["check", "res://tests/golden/cases/m10_ai_context_per_query.wyrd"]))
	assert_eq(int(plain["exit_code"]), 0, str(plain["output"]))
	var strict := WyrdCli.execute(PackedStringArray(["check", "--strict", "res://tests/golden/cases/m10_ai_context_per_query.wyrd"]))
	assert_eq(int(strict["exit_code"]), 1)
	assert_true(str(strict["output"]).contains("warning[W_AI_CONTEXT_RESOLVED_PER_QUERY]"))
	var clean := WyrdCli.execute(PackedStringArray(["check", "res://tests/golden/cases/m10_ai_opt_in_clean.wyrd"]))
	assert_eq(int(clean["exit_code"]), 0, str(clean["output"]))
	assert_false(str(clean["output"]).contains("error["))
	assert_false(str(clean["output"]).contains("warning["))


func _pack(path: String) -> Dictionary:
	var diagnostics := WyrdDiagnostics.new()
	var pack := WyrdPack.compile(PackedStringArray([path]), "harbor", 1, null, diagnostics, path, true)
	return {"diagnostics": diagnostics, "pack": pack}


func _compile(body: String) -> Dictionary:
	var path := _write("user://wyrd_m10_%d.wyrd" % body.hash(), body)
	return _pack(path)


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
	return (compiled["diagnostics"] as WyrdDiagnostics).format()


func _scene(pack: WyrdLinkedPack, id: String) -> WyrdSceneDef:
	for unit in pack.units:
		var file: WyrdFileDef = unit["file"]
		for scene in file.scenes:
			if scene.id == id:
				return scene
	return null


func _story(pack: WyrdLinkedPack, id: String) -> WyrdStoryletDef:
	for unit in pack.units:
		var file: WyrdFileDef = unit["file"]
		for story in file.storylets:
			if story.id == id:
				return story
	return null


func _line(pack: WyrdLinkedPack, id: String) -> WyrdLineDef:
	for unit in pack.units:
		var file: WyrdFileDef = unit["file"]
		for scene in file.scenes:
			for item in scene.items:
				if item.line_def != null and item.line_def.line_id == id:
					return item.line_def
	return null


func _row(rows: Array, id: String) -> Dictionary:
	for row in rows:
		if str(row["id"]) == id:
			return row
	return {}


func _line_row(rows: Array, id: String) -> Dictionary:
	for row in rows:
		if str(row["id"]) == id:
			return row
	return {}
