extends GutTest

## Compile-time was: tables. Nothing at runtime reads them.


var _case := 0


func test_chains_resolve_to_the_final_id() -> void:
	var compiled := _pack({
		"a.wyrd": """
language 1
verb settle was: pay
verb pay was: paid, tendered
""",
		"b.wyrd": """
language 1
verb paid was: coin
""",
	})
	var pack: WyrdLinkedPack = compiled["pack"]
	var verbs: Dictionary = pack.aliases["verb"]
	assert_eq(String(verbs["pay"]), "settle")
	assert_eq(String(verbs["paid"]), "settle")
	assert_eq(String(verbs["tendered"]), "settle")
	assert_eq(String(verbs["coin"]), "settle")
	assert_false(_codes(compiled["diagnostics"]).has("E_ALIAS_CYCLE"))
	assert_false(_codes(compiled["diagnostics"]).has("E_ALIAS_CONFLICT"))
	assert_false(_codes(compiled["diagnostics"]).has("E_ALIAS_DUPLICATE"))


func test_two_verb_statements_with_the_same_new_id_merge() -> void:
	var compiled := _pack({
		"a.wyrd": """
language 1
verb pay was: paid
verb pay was: tendered
""",
	})
	var pack: WyrdLinkedPack = compiled["pack"]
	var verbs: Dictionary = pack.aliases["verb"]
	assert_eq(String(verbs["paid"]), "pay")
	assert_eq(String(verbs["tendered"]), "pay")
	assert_eq(verbs.size(), 2)
	assert_false(_codes(compiled["diagnostics"]).has("E_ALIAS_DUPLICATE"))


func test_a_cycle_is_left_out_of_the_table() -> void:
	var compiled := _pack({
		"a.wyrd": """
language 1
verb pay was: paid
verb paid was: pay
verb keep was: kept
""",
	})
	var pack: WyrdLinkedPack = compiled["pack"]
	var verbs: Dictionary = pack.aliases["verb"]
	assert_eq(String(verbs["kept"]), "keep")
	assert_false(verbs.has("pay"))
	assert_false(verbs.has("paid"))
	assert_true(_codes(compiled["diagnostics"]).has("E_ALIAS_CYCLE"))


func test_the_same_old_stage_id_in_two_quests_is_fine() -> void:
	var compiled := _pack({
		"a.wyrd": """
language 1
quest ferry_toll "Ferry Toll"
  stage offer was: wait
quest dock_errand "Dock Errand"
  stage arrive was: wait
""",
	})
	var pack: WyrdLinkedPack = compiled["pack"]
	var stages: Dictionary = pack.aliases["stage"]
	var toll: Dictionary = stages["ferry_toll"]
	var errand: Dictionary = stages["dock_errand"]
	assert_eq(String(toll["wait"]), "offer")
	assert_eq(String(errand["wait"]), "arrive")
	assert_false(_codes(compiled["diagnostics"]).has("E_ALIAS_DUPLICATE"))
	assert_false(_codes(compiled["diagnostics"]).has("E_ALIAS_CONFLICT"))


func test_on_deed_and_a_document_verb_are_live() -> void:
	var deed := _pack({
		"a.wyrd": """
language 1
template ferry_job "Ferry Job"
  on_deed pay
  stage hire
verb pay was: pay
""",
	})
	assert_true(_has_message(deed["diagnostics"], "alias \"pay\" is still a live verb"))
	var issue := _pack({
		"a.wyrd": """
language 1
document tide_notice "Tide Notice" publishes_by harbor_guild every 1 day delay 1 hour
  verb pay
verb pay was: pay
""",
	})
	assert_true(_has_message(issue["diagnostics"], "alias \"pay\" is still a live verb"))


func test_hash_pack_folds_aliases_only_when_present() -> void:
	var bare := _pack({
		"a.wyrd": """
language 1
quest ferry_toll "Ferry Toll"
  stage offer
""",
	})
	var pack: WyrdLinkedPack = bare["pack"]
	assert_true(pack.aliases.is_empty())
	var manual := _unit_hash(pack)
	assert_eq(WyrdContent.hash_pack(pack), manual)
	var left := _pack({
		"a.wyrd": """
language 1
verb settle was: pay
verb pay was: paid
""",
		"b.wyrd": """
language 1
verb paid was: tendered
""",
	})
	var right := _pack({
		"a.wyrd": """
language 1
verb paid was: tendered
""",
		"b.wyrd": """
language 1
verb settle was: pay
verb pay was: paid
""",
	})
	var left_pack: WyrdLinkedPack = left["pack"]
	var right_pack: WyrdLinkedPack = right["pack"]
	var text := WyrdContent.alias_text(left_pack.aliases)
	assert_eq(text, WyrdContent.alias_text(right_pack.aliases))
	assert_eq(text, "verb\t\tpaid\tsettle\nverb\t\tpay\tsettle\nverb\t\ttendered\tsettle\n")
	pack.aliases = left_pack.aliases.duplicate(true)
	var folded := WyrdHash.combine(manual, WyrdHash.of_text(text))
	assert_ne(folded, manual)
	assert_eq(WyrdContent.hash_pack(pack), folded)
	pack.aliases = right_pack.aliases.duplicate(true)
	assert_eq(WyrdContent.hash_pack(pack), folded)
	var content := WyrdContent.from_pack(pack)
	assert_eq(WyrdContent.alias_text(content.aliases), text)


func test_export_omits_an_empty_alias_table() -> void:
	var bare := _pack({
		"a.wyrd": """
language 1
quest ferry_toll "Ferry Toll"
  stage offer
""",
	})
	var empty: Dictionary = WyrdExport.to_data(bare["pack"])
	assert_false(empty.has("aliases"))
	assert_eq(WyrdExport.to_json(empty).find("\"aliases\""), -1)
	var compiled := _pack({
		"a.wyrd": """
language 1
role ferry_master was: boatman
""",
	})
	var data: Dictionary = WyrdExport.to_data(compiled["pack"])
	assert_true(data.has("aliases"))
	var roles: Dictionary = (data["aliases"] as Dictionary)["role"]
	assert_eq(String(roles["boatman"]), "ferry_master")


func test_was_headers_are_not_speaker_lines() -> void:
	var source := WyrdSource.new("sample.wyrd", """
language 1
quest ferry_toll "Ferry Toll"
  stage hire was: hire_old
role ferry_master was: boatman
document harbor_gazette "Harbor Gazette" was: gazette
  text: live
  page
    The tide is in.
verb pay was: paid
""")
	var diagnostics := WyrdDiagnostics.new()
	var tokens := WyrdLexer.new().tokenize(source, diagnostics)
	var was_count := 0
	for token in tokens:
		if token.text == "was":
			assert_eq(token.kind, &"ident", "was: on a header stays a code token")
			was_count += 1
	assert_eq(was_count, 4)
	var tree := WyrdParser.new().parse_tokens(source, tokens, diagnostics)
	var file := WyrdStatements.new().compile(source, tree, diagnostics)
	assert_eq(file.quests[0].stages[0].was_ids[0], "hire_old")
	assert_eq(file.roles[0].was_ids[0], "boatman")
	assert_eq(file.documents[0].was_ids[0], "gazette")
	assert_eq(String(file.verb_aliases[0]["id"]), "pay")


func test_a_fact_named_was_is_still_legal() -> void:
	var file := _statements("""
language 1
facts
  was : int stored
""")
	assert_eq(file.codes, [])


func test_malformed_was_uses_the_kind_syntax_code() -> void:
	var stage := _statements("""
language 1
quest ferry_toll "Ferry Toll"
  stage hire was
  stage cross was:
  stage offer was: old,
""")
	assert_eq(stage.codes, ["E_STMT_UNKNOWN", "E_STMT_UNKNOWN", "E_STMT_UNKNOWN"])
	for message in stage.messages:
		assert_eq(message, "was: needs an old id")
	var role := _statements("""
language 1
role ferry_master was
""")
	assert_eq(role.codes, ["E_ROLE_SYNTAX"])
	assert_eq(role.messages[0], "was: needs an old id")
	var document := _statements("""
language 1
document harbor_gazette "Harbor Gazette" was:
""")
	assert_eq(document.codes, ["E_DOCUMENT_SYNTAX"])
	assert_eq(document.messages[0], "was: needs an old id")


func test_a_region_stage_refuses_was() -> void:
	var file := _statements("""
language 1
quest ferry_toll "Ferry Toll"
  stage offer
    region dock
      stage hire was: hire_old
""")
	assert_eq(file.codes, ["E_STMT_UNKNOWN"])
	assert_eq(file.messages[0], "was: is only allowed on a top-level stage")


func test_a_bare_verb_needs_was() -> void:
	var file := _statements("""
language 1
verb pay
verb
verb pay "Toll" was: paid
""")
	assert_eq(file.codes[0], "E_STMT_UNKNOWN")
	assert_eq(file.messages[0], "verb needs <new> was: <old>")
	assert_eq(file.messages[1], "verb needs <new> was: <old>")
	assert_eq(file.messages[2], "verb has no title")


func _pack(files: Dictionary) -> Dictionary:
	_case += 1
	var root := "user://alias_tables/%d" % _case
	DirAccess.make_dir_recursive_absolute(root)
	var paths := PackedStringArray()
	for name in files.keys():
		var path := "%s/%s" % [root, String(name)]
		var handle := FileAccess.open(path, FileAccess.WRITE)
		handle.store_string(String(files[name]))
		handle.close()
		paths.append(path)
	var diagnostics := WyrdDiagnostics.new()
	var pack := WyrdPack.compile(paths, "gullhaven", 1, null, diagnostics)
	return {"diagnostics": diagnostics, "pack": pack}


func _statements(text: String) -> Dictionary:
	var source := WyrdSource.new("sample.wyrd", text)
	var diagnostics := WyrdDiagnostics.new()
	var tree := WyrdParser.new().parse(source, diagnostics)
	var unit := WyrdStatements.new().compile(source, tree, diagnostics)
	return {"codes": _codes(diagnostics), "messages": _messages(diagnostics), "unit": unit}


func _codes(diagnostics: WyrdDiagnostics) -> Array:
	var codes: Array = []
	for item in diagnostics.items:
		codes.append(String(item.code))
	return codes


func _messages(diagnostics: WyrdDiagnostics) -> Array:
	var messages: Array = []
	for item in diagnostics.items:
		messages.append(item.message)
	return messages


func _has_message(diagnostics: WyrdDiagnostics, message: String) -> bool:
	return _messages(diagnostics).has(message)


func _unit_hash(pack: WyrdLinkedPack) -> int:
	var mixed := WyrdHash.of_string_name(StringName(pack.pack_id))
	var rows: Array = []
	for unit in pack.units:
		rows.append({"hash": str(unit["hash"]), "path": str(unit["path"])})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["path"]) < String(b["path"])
	)
	for row in rows:
		mixed = WyrdHash.combine(mixed, WyrdContent._hex_to_int(String(row["hash"])))
	return mixed
