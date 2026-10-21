extends GutTest


func test_from_pack_fills_templates_and_create_instance() -> void:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var manifest := load("res://tests/support/m9_templates.wyrdmanifest.tres") as WyrdContentManifest
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	var content := runtime.content()
	assert_true(content.templates.has("errand"))
	assert_true(content.templates["errand"] is WyrdTemplateDef)
	assert_false(content.quests.has("errand"))
	runtime.start_new_game(4)
	assert_eq(runtime.quests.status("errand"), &"")
	assert_eq(runtime.quests.create_instance("errand"), "errand#1")
	assert_eq(runtime.quests.status("errand#1"), &"active")


func test_assumes_rewrites_a_slot_and_a_wait_does_not() -> void:
	var file := _file("""
		language 1
		template ferry.errand "Errand"
		  slot giver = dock_keeper mode: live
		  assumes: alive(giver)
		  stage ask
		    waits_until alive(giver)
		    journal: Hi. #line:aa01
	""")
	assert_eq(file.templates.size(), 1)
	var template := file.templates[0]
	var assumes := _const_text(template.assumes)
	assert_true(assumes.contains("holder"), assumes)
	assert_true(assumes.contains("giver"), assumes)
	assert_eq(PackedStringArray(template.assumption_texts), PackedStringArray(["alive(giver)"]))
	var wait := _const_text(template.stages[0].waits_until)
	assert_false(wait.contains("holder"), wait)
	assert_true(wait.contains("giver"), wait)


func test_defs_pot_tag_lines_and_export() -> void:
	var path := "user://wyrd_m9_template_tool.wyrd"
	var raw := "language 1\ntemplate ferry.errand \"Errand\"\n  stage ask\n    journal: Ask the giver. #line:ask1\n"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(raw)
	file.close()
	var diagnostics := WyrdDiagnostics.new()
	var pack := WyrdPack.compile(PackedStringArray([path]), "harbor", 1, null, diagnostics, path, true)
	assert_false(diagnostics.has_errors(), diagnostics.format())
	var defs := WyrdDefsWriter.render(pack)
	assert_true(defs.contains("ferry.errand\t"), defs)
	assert_true(defs.contains("\tp\n"), defs)
	assert_true(defs.contains("ferry.errand.ask\t"), defs)
	var saw_text := false
	for row in WyrdPotExtractor.rows(pack):
		if str(row["msgid"]) == "Ask the giver.":
			saw_text = true
	assert_true(saw_text)
	var tagged: Dictionary = WyrdTagLines.tag_text("language 1\ntemplate ferry.errand \"Errand\"\n  stage ask\n    journal: Ask the giver.\n", "res://errand.wyrd", "harbor", {})
	assert_true(str(tagged["text"]).contains("#line:"), str(tagged["text"]))
	var exported: Dictionary = WyrdExport.to_data(pack)
	assert_true(exported.has("templates"))
	assert_eq(str((exported["templates"][0] as Dictionary)["id"]), "ferry.errand")
	var voice: Array = WyrdCli._voice_rows(pack)
	assert_eq(voice.size(), 1)
	assert_eq(str((voice[0] as Dictionary)["id"]), "ask1")
	assert_eq(str((voice[0] as Dictionary)["context"]), "journal:ferry.errand")
	var clean := WyrdPack.compile(PackedStringArray([_facts_only()]), "harbor", 1, null, WyrdDiagnostics.new(), path, true)
	assert_false(WyrdExport.to_data(clean).has("templates"))


func _file(body: String) -> WyrdFileDef:
	var lines := PackedStringArray()
	for line in body.strip_edges().split("\n"):
		if line.begins_with("\t\t"):
			lines.append(line.substr(2))
		else:
			lines.append(line)
	var source := WyrdSource.new("res://template.wyrd", "\n".join(lines) + "\n")
	var diagnostics := WyrdDiagnostics.new()
	var tree := WyrdParser.new().parse(source, diagnostics)
	var file := WyrdStatements.new().compile(source, tree, diagnostics)
	assert_false(diagnostics.has_errors(), diagnostics.format())
	return file


func _const_text(cond: WyrdCompiledCondition) -> String:
	if cond == null:
		return ""
	var parts := PackedStringArray()
	for item in cond.consts:
		parts.append(str(item))
	return " ".join(parts)


func _facts_only() -> String:
	var path := "user://wyrd_m9_template_clean.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("language 1\nfacts\n  player.coins : int stored\n")
	file.close()
	return path
