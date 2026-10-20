extends GutTest


func test_linear_chain_is_clean() -> void:
	var diagnostics := _compile("""
		language 1
		quest ferry_toll "The Ferry Toll"
		  stage arrive
		    -> pay
		  stage pay
		    -> done
		  stage done
		""")
	assert_false(diagnostics.has_errors(), diagnostics.format())
	assert_eq(_hits(diagnostics).size(), 0, diagnostics.format())


func test_orphan_stage_warns_once() -> void:
	var diagnostics := _compile("""
		language 1
		quest ferry_toll "The Ferry Toll"
		  stage arrive
		    -> done
		  stage done
		  stage side
		""")
	assert_false(diagnostics.has_errors(), diagnostics.format())
	assert_eq(_hits(diagnostics), PackedStringArray([
		"stage \"ferry_toll.side\" is never reached from \"ferry_toll.arrive\"",
	]))


func test_handler_transition_reaches_its_target() -> void:
	var diagnostics := _compile("""
		language 1
		events
		  bell_rung()
		quest ferry_toll "The Ferry Toll"
		  stage arrive
		    on bell_rung where true:
		      -> rung
		  stage rung
		  stage side
		""")
	assert_false(diagnostics.has_errors(), diagnostics.format())
	assert_eq(_hits(diagnostics), PackedStringArray([
		"stage \"ferry_toll.side\" is never reached from \"ferry_toll.arrive\"",
	]))


func test_variant_body_reaches_its_target() -> void:
	var diagnostics := _compile("""
		language 1
		quest ferry_toll "The Ferry Toll"
		  slot keeper = dock_keeper mode: live
		  stage arrive
		    variant keeper.empty:
		      -> hidden
		  stage hidden
		  stage side
		""")
	assert_false(diagnostics.has_errors(), diagnostics.format())
	assert_eq(_hits(diagnostics), PackedStringArray([
		"stage \"ferry_toll.side\" is never reached from \"ferry_toll.arrive\"",
	]))


func test_region_first_stage_and_sibling_are_reached() -> void:
	var diagnostics := _compile("""
		language 1
		quest ferry_toll "The Ferry Toll"
		  stage arrive
		    region rope
		      stage coil
		        -> tied
		      stage tied
		    -> done
		  stage done
		""")
	assert_false(diagnostics.has_errors(), diagnostics.format())
	assert_eq(_hits(diagnostics).size(), 0, diagnostics.format())


func test_orphan_region_stage_warns_with_its_full_id() -> void:
	var diagnostics := _compile("""
		language 1
		quest ferry_toll "The Ferry Toll"
		  stage arrive
		    region rope
		      stage coil
		        -> tied
		      stage tied
		      stage lost
		    -> done
		  stage done
		""")
	assert_false(diagnostics.has_errors(), diagnostics.format())
	assert_eq(_hits(diagnostics), PackedStringArray([
		"stage \"ferry_toll.arrive.rope.lost\" is never reached from \"ferry_toll.arrive\"",
	]))


func test_advance_in_a_scene_or_storylet_reaches_its_target() -> void:
	var diagnostics := _compile("""
		language 1
		quest ferry_toll "The Ferry Toll"
		  stage arrive
		    -> done
		  stage done
		  stage sent
		  stage paid
		  stage side
		scene dock.spare
		  narrator: The dock is quiet. #line:dock_quiet
		  ~ advance ferry_toll to sent
		  -> end
		storylet harbor.errand
		  scope: bark
		  speaker: dock_clerk
		  ~ advance ferry_toll to paid
		  - The errand is waiting. #line:errand
		""")
	assert_false(diagnostics.has_errors(), diagnostics.format())
	assert_eq(_hits(diagnostics), PackedStringArray([
		"stage \"ferry_toll.side\" is never reached from \"ferry_toll.arrive\"",
	]))
	assert_true(diagnostics.format().contains("warning[W_SCENE_UNUSED]"))


func test_stage_nested_in_an_unreached_stage_is_not_reported() -> void:
	var diagnostics := _compile("""
		language 1
		quest ferry_toll "The Ferry Toll"
		  stage arrive
		    -> done
		  stage done
		  stage side
		    region rope
		      stage coil
		        -> tied
		      stage tied
		""")
	assert_false(diagnostics.has_errors(), diagnostics.format())
	assert_eq(_hits(diagnostics), PackedStringArray([
		"stage \"ferry_toll.side\" is never reached from \"ferry_toll.arrive\"",
	]))


func _compile(body: String) -> WyrdDiagnostics:
	var diagnostics := WyrdDiagnostics.new()
	var path := "user://wyrd_stage_%d.wyrd" % Time.get_ticks_usec()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(_text(body))
	file.close()
	WyrdPack.compile(PackedStringArray([path]), "gullhaven", 1, null, diagnostics, path, true)
	return diagnostics


func _hits(diagnostics: WyrdDiagnostics) -> PackedStringArray:
	var hits := PackedStringArray()
	for item in diagnostics.items:
		if item.code == WyrdDiagnostic.W_STAGE_UNREACHABLE:
			hits.append(item.message)
	return hits


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
