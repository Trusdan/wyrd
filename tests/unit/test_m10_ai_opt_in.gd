extends GutTest

## Compiler opt-in for AI flavor. Nothing here reads the flag at runtime.


func test_ai_line_messages() -> void:
	var voiced := _codes(_statements("res://tests/golden/statements/m10_ai_line_voiced.wyrd"), WyrdDiagnostic.E_AI_LINE)
	assert_eq(voiced, ["a voiced line cannot opt in to AI", "a voiced line cannot opt in to AI"])
	var secrecy := _codes(_statements("res://tests/golden/statements/m10_ai_line_secrecy.wyrd"), WyrdDiagnostic.E_AI_LINE)
	assert_eq(secrecy, [
		"a line in a secrecy tier cannot opt in to AI",
		"a line in a secrecy tier cannot opt in to AI",
		"a line in a secrecy tier cannot opt in to AI",
	])
	var interp := _codes(_statements("res://tests/golden/statements/m10_ai_line_interp.wyrd"), WyrdDiagnostic.E_AI_LINE)
	assert_eq(interp, [
		"an interpolating line cannot opt in to AI",
		"an interpolating line cannot opt in to AI",
		"an interpolating line cannot opt in to AI",
	])
	var where := _codes(_statements("res://tests/golden/statements/m10_ai_line_where.wyrd"), WyrdDiagnostic.E_AI_LINE)
	assert_eq(where.size(), 5)
	for message in where:
		assert_eq(message, "only spoken and storylet lines can opt in to AI")


func test_one_ai_line_diagnostic_per_reason() -> void:
	var compiled := _pack("""
		language 1
		facts
		  player.coins : int stored
		scene toll.gate
		  narrator: You have {player.coins} coins. #tag:ai #tag:voiced #secrecy:open #line:all
		storylet harbor.both
		  scope: bark
		  speaker: any
		  secrecy: open
		  - The harbor is quiet. #tag:ai #secrecy:hushed #line:both
	""")
	var messages := _codes(compiled["diagnostics"], WyrdDiagnostic.E_AI_LINE)
	assert_eq(messages, [
		"a voiced line cannot opt in to AI",
		"a line in a secrecy tier cannot opt in to AI",
		"an interpolating line cannot opt in to AI",
		"a line in a secrecy tier cannot opt in to AI",
	])


func test_is_ai_and_context_order() -> void:
	var compiled := _pack(_clean_body())
	var diagnostics: WyrdDiagnostics = compiled["diagnostics"]
	assert_false(diagnostics.has_errors(), diagnostics.format())
	assert_false(diagnostics.has_warnings(), diagnostics.format())
	var pack: WyrdLinkedPack = compiled["pack"]
	var gate := _scene(pack, "toll.gate")
	assert_eq(_packed(gate.ai_context), ["world.season", "player.coins"])
	assert_false(gate.reads.has(StringName("world.season")))
	var spoken := _scene_line(gate, "gate")
	assert_true(spoken.is_ai())
	assert_eq(_packed(spoken.tags), ["ai"])
	var keeper := _scene_line(gate, "keeper")
	assert_eq(keeper.speaker, "ai_keeper")
	assert_false(keeper.is_ai())
	var news := _story(pack, "harbor.news")
	assert_eq(_packed(news.ai_context), ["player.coins", "world.season"])
	assert_true(news.lines[0].is_ai())
	var rumors := _story(pack, "harbor.rumors")
	assert_true(rumors.ai_context.is_empty())
	assert_false(rumors.lines[0].is_ai())
	assert_true(rumors.lines[1].is_ai())
	var quiet := _story(pack, "harbor.quiet")
	assert_eq(_packed(quiet.ai_context), ["player.coins"])
	assert_eq(quiet.reads.size(), 0)
	assert_false(quiet.lines[0].is_ai())
	var escaped := _scene_line(_scene(_pack_file("res://tests/golden/statements/m10_ai_line_interp.wyrd"), "toll.gate"), "esc")
	assert_true(escaped.is_ai())
	assert_eq(_codes(_statements("res://tests/golden/statements/m10_ai_line_interp.wyrd"), WyrdDiagnostic.E_AI_LINE).size(), 3)


func test_ai_context_syntax_messages() -> void:
	var diagnostics := _statements("res://tests/golden/statements/m10_ai_context_syntax.wyrd")
	assert_eq(_count(diagnostics, WyrdDiagnostic.E_STORYLET_SYNTAX, "ai_context needs [<fact keys>]"), 3)
	assert_eq(_count(diagnostics, WyrdDiagnostic.E_STORYLET_SYNTAX, "ai_context needs at least one fact key"), 1)
	assert_eq(_count(diagnostics, WyrdDiagnostic.E_STORYLET_SYNTAX, "duplicate ai_context key \"player.coins\""), 1)
	assert_eq(_count(diagnostics, WyrdDiagnostic.E_STORYLET_SYNTAX, "ai_context keys are concrete fact keys"), 1)
	assert_eq(_count(diagnostics, WyrdDiagnostic.E_STORYLET_SYNTAX, "duplicate storylet field \"ai_context\""), 1)
	assert_eq(_count(diagnostics, WyrdDiagnostic.E_STORYLET_SYNTAX, "a line tag is not allowed on ai_context"), 1)
	assert_eq(_count(diagnostics, WyrdDiagnostic.E_STORYLET_SYNTAX, "a storylet field cannot contain a block"), 1)
	assert_eq(_count(diagnostics, WyrdDiagnostic.E_STMT_UNKNOWN, "ai_context needs [<fact keys>]"), 2)
	assert_eq(_count(diagnostics, WyrdDiagnostic.E_STMT_UNKNOWN, "ai_context needs at least one fact key"), 1)
	assert_eq(_count(diagnostics, WyrdDiagnostic.E_STMT_UNKNOWN, "duplicate ai_context key \"player.coins\""), 1)
	assert_eq(_count(diagnostics, WyrdDiagnostic.E_STMT_UNKNOWN, "ai_context keys are concrete fact keys"), 1)
	assert_eq(_count(diagnostics, WyrdDiagnostic.E_STMT_UNKNOWN, "duplicate statement \"ai_context\""), 1)
	assert_eq(_count(diagnostics, WyrdDiagnostic.E_STMT_UNKNOWN, "a line tag is not allowed on ai_context"), 1)
	assert_eq(_count(diagnostics, WyrdDiagnostic.E_STMT_UNKNOWN, "ai_context cannot contain a block"), 1)


func test_unknown_and_per_query_keys() -> void:
	var unknown := _statements("res://tests/golden/statements/m10_ai_context_unknown.wyrd")
	assert_eq(_codes(unknown, WyrdDiagnostic.E_AI_CONTEXT_UNKNOWN), [
		"unknown fact \"ferry.gone\" in ai_context",
		"unknown fact \"harbor.missing\" in ai_context",
	])
	var per_query := _statements("res://tests/golden/statements/m10_ai_context_per_query.wyrd")
	var warning := "ai_context key \"world.weather\" is resolved per query; the packet reads it once when built"
	assert_eq(_codes(per_query, WyrdDiagnostic.W_AI_CONTEXT_RESOLVED_PER_QUERY), [warning, warning])
	for item in per_query.items:
		if item.code == WyrdDiagnostic.W_AI_CONTEXT_RESOLVED_PER_QUERY:
			assert_eq(item.severity, WyrdDiagnostic.SEVERITY_WARNING)
	var loose := WyrdCli.execute(PackedStringArray(["check", "res://tests/golden/statements/m10_ai_context_per_query.wyrd"]))
	assert_eq(int(loose["exit_code"]), 0, str(loose["output"]))
	assert_true(str(loose["output"]).contains(warning))
	var strict := WyrdCli.execute(PackedStringArray(["check", "--strict", "res://tests/golden/statements/m10_ai_context_per_query.wyrd"]))
	assert_eq(int(strict["exit_code"]), 1)
	assert_true(str(strict["output"]).contains("warning[W_AI_CONTEXT_RESOLVED_PER_QUERY]"))


func test_cross_file_fact_resolves_at_statement_time() -> void:
	var facts := _write("user://wyrd_m10_facts.wyrd", """
		language 1
		facts
		  harbor.ledger : int stored
	""")
	var body := _write("user://wyrd_m10_body.wyrd", """
		language 1
		scene toll.gate
		  ai_context: [harbor.ledger]
		  narrator: The gate is shut. #line:gate
		storylet harbor.quiet
		  scope: bark
		  speaker: any
		  ai_context: [harbor.ledger]
		  - The harbor is quiet. #line:quiet
	""")
	var diagnostics := WyrdDiagnostics.new()
	var pack := WyrdPack.compile(PackedStringArray([facts, body]), "harbor", 1, null, diagnostics, "", true)
	assert_false(diagnostics.format().contains("E_AI_CONTEXT_UNKNOWN"), diagnostics.format())
	var gate := _scene(pack, "toll.gate")
	assert_eq(_packed(gate.ai_context), ["harbor.ledger"])
	assert_eq(gate.reads.size(), 0)
	var quiet := _story(pack, "harbor.quiet")
	assert_eq(_packed(quiet.ai_context), ["harbor.ledger"])
	assert_eq(quiet.reads.size(), 0)
	var readers: Array = []
	for fact in pack.xref.to_data()["facts"]:
		if str(fact["key"]) == "harbor.ledger":
			readers = fact["readers"]
	assert_eq(readers.size(), 0)
	var xref := WyrdExport.xref_json(pack)
	assert_false(xref.contains("\"kind\": \"scene\""))
	assert_false(xref.contains("\"kind\": \"storylet\""))


func test_export_json_carries_tags_and_context() -> void:
	var compiled := _pack(_clean_body())
	var data: Dictionary = WyrdExport.to_data(compiled["pack"])
	var lines: Array = data["lines"]
	var tagged := 0
	for row in lines:
		var tags: Array = row["tags"]
		if tags.has("ai"):
			tagged += 1
			assert_false(row.has("ai"))
	assert_eq(tagged, 3)
	var scenes: Array = data["scenes"]
	assert_eq(scenes.size(), 1)
	assert_eq(scenes[0]["ai_context"], ["world.season", "player.coins"])
	var by_id := {}
	for row in data["storylets"]:
		by_id[str(row["id"])] = row
	assert_eq(by_id["harbor.news"]["ai_context"], ["player.coins", "world.season"])
	assert_eq(by_id["harbor.quiet"]["ai_context"], ["player.coins"])
	assert_false((by_id["harbor.rumors"] as Dictionary).has("ai_context"))


func test_export_without_opt_in_matches_the_link_golden() -> void:
	var actual := WyrdGolden.to_json(WyrdLinkGolden.compile_dir("res://tests/golden/link/clean"))
	var expected := FileAccess.get_file_as_string("res://tests/golden/link/clean/expected.json")
	assert_eq(actual, expected)


func _statements(path: String) -> WyrdDiagnostics:
	var source := WyrdSource.load_file(path)
	var diagnostics := WyrdDiagnostics.new()
	var tree := WyrdParser.new().parse(source, diagnostics)
	WyrdStatements.new().compile(source, tree, diagnostics)
	return diagnostics


func _pack(body: String) -> Dictionary:
	var path := _write("user://wyrd_m10_%d.wyrd" % body.hash(), body)
	return {"diagnostics": _file_diagnostics(path), "pack": _file_pack(path)}


func _pack_file(path: String) -> WyrdLinkedPack:
	return _file_pack(path)


func _file_pack(path: String) -> WyrdLinkedPack:
	var diagnostics := WyrdDiagnostics.new()
	return WyrdPack.compile(PackedStringArray([path]), "harbor", 1, null, diagnostics, "", true)


func _file_diagnostics(path: String) -> WyrdDiagnostics:
	var diagnostics := WyrdDiagnostics.new()
	WyrdPack.compile(PackedStringArray([path]), "harbor", 1, null, diagnostics, "", true)
	return diagnostics


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


func _clean_body() -> String:
	return FileAccess.get_file_as_string("res://tests/golden/statements/m10_ai_opt_in_clean.wyrd")


func _codes(diagnostics: WyrdDiagnostics, code: StringName) -> Array:
	var messages: Array = []
	for item in diagnostics.items:
		if item.code == code:
			messages.append(item.message)
	return messages


func _count(diagnostics: WyrdDiagnostics, code: StringName, message: String) -> int:
	var found := 0
	for item in diagnostics.items:
		if item.code == code and item.message == message:
			found += 1
	return found


func _packed(values: PackedStringArray) -> Array:
	var rows: Array = []
	for value in values:
		rows.append(value)
	return rows


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


func _scene_line(scene: WyrdSceneDef, id: String) -> WyrdLineDef:
	for item in scene.items:
		if item.line_def != null and item.line_def.line_id == id:
			return item.line_def
	return null
