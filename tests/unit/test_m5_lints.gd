extends GutTest

## Learning-the-truth and leak lints. Gullhaven names only.


func test_scene_learn_warns_when_a_contradicting_belief_remains() -> void:
	var diagnostics := WyrdDiagnostics.new()
	_compile(diagnostics, """
		language 1
		facts
		  harbor.toll_fate : symbol stored
		quest gate "Gate"
		  stage arrive
		    ~ believe line_fisher harbor.toll_fate = stolen
		    ~ outcome route = done
		scene dock
		  on_abort:
		    ~ learn line_fisher harbor.toll_fate = lost_at_sea
		  narrator: On the dock. #line:d1
		  -> end
		""")
	assert_false(diagnostics.has_errors(), diagnostics.format())
	assert_true(diagnostics.format().contains("warning[W_STALE_BELIEF]"))
	assert_true(diagnostics.format().contains("line_fisher"))
	assert_true(diagnostics.format().contains("harbor.toll_fate"))


func test_matching_belief_or_an_unbelieve_does_not_warn() -> void:
	var same := WyrdDiagnostics.new()
	_compile(same, """
		language 1
		facts
		  harbor.toll_fate : symbol stored
		quest gate "Gate"
		  stage arrive
		    ~ believe line_fisher harbor.toll_fate = lost_at_sea
		    ~ outcome route = done
		scene dock
		  on_abort:
		    ~ learn line_fisher harbor.toll_fate = lost_at_sea
		  narrator: On the dock. #line:d1
		  -> end
		""")
	assert_false(same.format().contains("W_STALE_BELIEF"), same.format())
	var cleared := WyrdDiagnostics.new()
	_compile(cleared, """
		language 1
		facts
		  harbor.toll_fate : symbol stored
		quest gate "Gate"
		  stage arrive
		    ~ believe line_fisher harbor.toll_fate = stolen
		    ~ unbelieve line_fisher harbor.toll_fate
		    ~ outcome route = done
		scene dock
		  on_abort:
		    ~ learn line_fisher harbor.toll_fate = lost_at_sea
		  narrator: On the dock. #line:d1
		  -> end
		""")
	assert_false(cleared.format().contains("W_STALE_BELIEF"), cleared.format())
	var stage_only := WyrdDiagnostics.new()
	_compile(stage_only, """
		language 1
		facts
		  harbor.toll_fate : symbol stored
		quest gate "Gate"
		  stage arrive
		    ~ believe line_fisher harbor.toll_fate = stolen
		    ~ learn line_fisher harbor.toll_fate = lost_at_sea
		    ~ outcome route = done
		""")
	assert_false(stage_only.format().contains("W_STALE_BELIEF"), stage_only.format())


func test_world_gate_leaks_and_a_knows_gate_does_not() -> void:
	var leaked := WyrdDiagnostics.new()
	_compile(leaked, """
		language 1
		facts
		  harbor.toll_fate : symbol stored
		scene dock
		  when harbor.toll_fate == lost_at_sea: narrator: It was {harbor.toll_fate}. #line:d1
		  -> end
		""")
	assert_true(leaked.has_errors(), leaked.format())
	assert_true(leaked.format().contains("error[E_FACT_LEAK]"))
	assert_true(leaked.format().contains("harbor.toll_fate"))
	var knows := WyrdDiagnostics.new()
	_compile(knows, """
		language 1
		facts
		  harbor.toll_fate : symbol stored
		scene dock
		  * [Learn the toll] -> end #line:c_learn
		    ~ learn player harbor.toll_fate = lost_at_sea
		  when knows(player, harbor.toll_fate): narrator: It was {harbor.toll_fate}. #line:d1
		  -> end
		""")
	assert_false(knows.has_errors(), knows.format())
	assert_false(knows.format().contains("E_FACT_LEAK"), knows.format())
	var inside := WyrdDiagnostics.new()
	_compile(inside, """
		language 1
		facts
		  harbor.toll_fate : symbol stored
		scene dock
		  narrator: {if harbor.toll_fate == lost_at_sea}{harbor.toll_fate}{end} #line:d1
		  -> end
		""")
	assert_true(inside.format().contains("error[E_FACT_LEAK]"), inside.format())


func test_belief_and_held_text_is_a_claim() -> void:
	var claim := WyrdDiagnostics.new()
	_compile(claim, """
		language 1
		facts
		  harbor.toll_fate : symbol stored
		scene dock
		  narrator: Heard {belief(line_fisher, harbor.toll_fate)}. #line:d1
		  narrator: The council holds {held(harbor_council, harbor.toll_fate)}. #line:d2
		  when harbor.toll_fate == lost_at_sea: narrator: They say {belief(dock_apprentice, harbor.toll_fate)}. #line:d3
		  -> end
		""")
	assert_false(claim.has_errors(), claim.format())
	assert_true(claim.format().contains("warning[W_CLAIM]"))
	assert_false(claim.format().contains("W_INTERP_UNSET"), claim.format())
	assert_false(claim.format().contains("E_FACT_LEAK"), claim.format())
	var count := 0
	for line in claim.format().split("\n"):
		if line.contains("warning[W_CLAIM]"):
			count += 1
	assert_eq(count, 3)


func _compile(diagnostics: WyrdDiagnostics, body: String) -> WyrdLinkedPack:
	var path := "user://wyrd_m5_lints_%d.wyrd" % Time.get_ticks_usec()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(_text(body))
	file.close()
	return WyrdPack.compile(PackedStringArray([path]), "harbor", 1, null, diagnostics, path, true)


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
