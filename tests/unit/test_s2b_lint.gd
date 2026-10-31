extends GutTest


func test_empty_slot_without_coverage_warns() -> void:
	var diagnostics := WyrdDiagnostics.new()
	var path := "user://wyrd_s2b_empty.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("""
language 1
quest gate "Gate"
  slot keeper = dock_keeper mode: live
  slot clerk = dock_clerk mode: live
  slot spare = dock_spare mode: live
  stage arrive
    scene room with clerk
    variant keeper.empty:
      -> done
    -> done
  stage side
    scene room with spare
  stage done
scene room
  narrator: Room. #line:room
  -> end
""")
	file.close()
	WyrdPack.compile(PackedStringArray([path]), "sample", 1, null, diagnostics, path, true)
	assert_false(diagnostics.has_errors(), diagnostics.format())
	var hits: PackedStringArray = PackedStringArray()
	for item in diagnostics.items:
		if item.code == WyrdDiagnostic.W_EMPTY_UNCOVERED:
			hits.append(item.message)
	assert_eq(hits.size(), 1)
	assert_true(hits[0].contains("clerk"))
	assert_false(hits[0].contains("keeper"))


func test_holder_and_filled_references_warn_until_on_empty() -> void:
	var body := """
language 1
quest gate "Gate"
  slot journalled = dock_keeper mode: live
  slot waited = dock_clerk mode: live
  slot spare = dock_spare mode: live
  stage arrive
    journal: {holder(journalled).name} waits. #line:j_hold
    waits_until filled(waited)
"""
	var bare := _compile_body(body)
	assert_false(bare.has_errors(), bare.format())
	var hits := _empty_messages(bare)
	assert_eq(hits.size(), 2, "\n".join(hits))
	var text := "\n".join(hits)
	assert_true(text.contains("slot \"journalled\""), text)
	assert_true(text.contains("slot \"waited\""), text)
	assert_false(text.contains("slot \"spare\""), text)
	var covered := _compile_body(body.replace("quest gate \"Gate\"", "quest gate \"Gate\"\n  on_empty: wait"))
	assert_false(covered.has_errors(), covered.format())
	assert_eq(_empty_messages(covered).size(), 0, covered.format())


func test_on_empty_covers_every_slot() -> void:
	var result := WyrdCli.execute(PackedStringArray(["check", "res://tests/golden/link/empty_uncovered"]))
	assert_eq(int(result["exit_code"]), 0, str(result["output"]))
	var output := str(result["output"])
	assert_eq(output.count("W_EMPTY_UNCOVERED"), 1)
	assert_true(output.contains("scribe"))
	assert_false(output.contains("\"keeper\""))
	assert_false(output.contains("slot \"clerk\""))


func _compile_body(body: String) -> WyrdDiagnostics:
	var diagnostics := WyrdDiagnostics.new()
	var path := "user://wyrd_s2b_empty_%d.wyrd" % body.hash()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(body)
	file.close()
	WyrdPack.compile(PackedStringArray([path]), "sample", 1, null, diagnostics, path, true)
	return diagnostics


func _empty_messages(diagnostics: WyrdDiagnostics) -> PackedStringArray:
	var hits := PackedStringArray()
	for item in diagnostics.items:
		if item.code == WyrdDiagnostic.W_EMPTY_UNCOVERED:
			hits.append(item.message)
	return hits
