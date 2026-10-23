extends GutTest

## on_missing_stage: on a quest and a template.


func test_a_quest_and_a_template_compile() -> void:
	var compiled := _compile("""
language 1

quest ferry_toll "Ferry Toll"
  on_missing_stage: depart
  stage arrive
    waits_until false
  stage depart
    waits_until false

template ferry_job "Ferry Job"
  on_missing_stage: sign
  stage wait
    waits_until false
  stage sign
    waits_until false
""")
	assert_eq(_error_codes(compiled["diagnostics"]), [])
	var unit: WyrdFileDef = compiled["unit"]
	assert_eq(unit.quests[0].on_missing_stage, "depart")
	assert_eq(unit.templates[0].on_missing_stage, "sign")


func test_an_unknown_region_or_old_target_is_one_error_at_the_field() -> void:
	_assert_target("""
language 1

quest ferry_toll "Ferry Toll"
  on_missing_stage: missing
  stage arrive
    waits_until false
""", "missing", 5)
	_assert_target("""
language 1

quest lantern_watch "Lantern Watch"
  on_missing_stage: trim
  stage watch
    region wick
      stage trim
        waits_until false
""", "trim", 5)
	_assert_target("""
language 1

quest ferry_toll "Ferry Toll"
  on_missing_stage: offer
  stage depart was: offer
    waits_until false
""", "offer", 5)


func test_a_duplicate_field_is_reported() -> void:
	var compiled := _compile("""
language 1

quest ferry_toll "Ferry Toll"
  on_missing_stage: arrive
  on_missing_stage: arrive
  stage arrive
    waits_until false
""")
	var errors := _errors(compiled["diagnostics"])
	assert_eq(errors.size(), 1)
	var item: WyrdDiagnostic = errors[0]
	assert_eq(String(item.code), "E_STMT_UNKNOWN")
	assert_eq(item.message, "duplicate statement \"on_missing_stage\"")
	assert_eq(item.line, 6)
	assert_eq(item.col, 3)


func test_the_export_holds_the_key_only_when_set() -> void:
	var with_field := _pack("""
language 1

quest ferry_toll "Ferry Toll"
  on_missing_stage: depart
  stage arrive
    waits_until false
  stage depart
    waits_until false

template ferry_job "Ferry Job"
  on_missing_stage: sign
  stage sign
    waits_until false
""")
	assert_eq(_error_codes(with_field["diagnostics"]), [])
	var data: Dictionary = WyrdExport.to_data(with_field["pack"])
	var quest := _by_id(data["quests"], "ferry_toll")
	var template := _by_id(data["templates"], "ferry_job")
	assert_eq(String(quest["on_missing_stage"]), "depart")
	assert_eq(String(template["on_missing_stage"]), "sign")
	var plain := _pack("""
language 1

quest ferry_toll "Ferry Toll"
  stage arrive
    waits_until false

template ferry_job "Ferry Job"
  stage sign
    waits_until false
""")
	assert_eq(_error_codes(plain["diagnostics"]), [])
	var bare: Dictionary = WyrdExport.to_data(plain["pack"])
	assert_false(_by_id(bare["quests"], "ferry_toll").has("on_missing_stage"))
	assert_false(_by_id(bare["templates"], "ferry_job").has("on_missing_stage"))


func _assert_target(text: String, stage_id: String, line: int) -> void:
	var compiled := _compile(text)
	var errors := _errors(compiled["diagnostics"])
	assert_eq(errors.size(), 1, text)
	var item: WyrdDiagnostic = errors[0]
	assert_eq(String(item.code), "E_MISSING_STAGE_TARGET")
	assert_eq(item.message, "on_missing_stage stage \"%s\" is unknown" % stage_id)
	assert_eq(item.line, line)
	assert_eq(item.col, 3)


func _compile(text: String) -> Dictionary:
	var source := WyrdSource.new("sample.wyrd", text)
	var diagnostics := WyrdDiagnostics.new()
	var tree := WyrdParser.new().parse(source, diagnostics)
	var unit := WyrdStatements.new().compile(source, tree, diagnostics)
	return {"diagnostics": diagnostics, "unit": unit}


func _pack(text: String) -> Dictionary:
	var root := "user://on_missing_stage"
	DirAccess.make_dir_recursive_absolute(root)
	var path := "%s/%d.wyrd" % [root, text.hash()]
	var handle := FileAccess.open(path, FileAccess.WRITE)
	handle.store_string(text)
	handle.close()
	var diagnostics := WyrdDiagnostics.new()
	var pack := WyrdPack.compile(PackedStringArray([path]), "gullhaven", 1, null, diagnostics)
	return {"diagnostics": diagnostics, "pack": pack}


func _errors(diagnostics: WyrdDiagnostics) -> Array:
	var items: Array = []
	for item in diagnostics.items:
		if item.severity == WyrdDiagnostic.SEVERITY_ERROR:
			items.append(item)
	return items


func _error_codes(diagnostics: WyrdDiagnostics) -> Array:
	var codes: Array = []
	for item in _errors(diagnostics):
		codes.append(String(item.code))
	return codes


func _by_id(rows: Array, id: String) -> Dictionary:
	for item in rows:
		var row: Dictionary = item
		if String(row["id"]) == id:
			return row
	return {}
