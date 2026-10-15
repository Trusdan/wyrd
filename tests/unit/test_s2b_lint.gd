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


func test_on_empty_covers_every_slot() -> void:
	var result := WyrdCli.execute(PackedStringArray(["check", "res://tests/golden/link/empty_uncovered"]))
	assert_eq(int(result["exit_code"]), 0, str(result["output"]))
	var output := str(result["output"])
	assert_eq(output.count("W_EMPTY_UNCOVERED"), 1)
	assert_true(output.contains("scribe"))
	assert_false(output.contains("\"keeper\""))
	assert_false(output.contains("slot \"clerk\""))
