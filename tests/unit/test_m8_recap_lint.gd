extends GutTest

## Recap lint. Gullhaven names only.


func test_outcome_stage_write_without_recap_warns() -> void:
	var diagnostics := WyrdDiagnostics.new()
	var path := _compile(diagnostics, """
		language 1
		facts
		  harbor.toll_fate : symbol stored
		quest harbor_guild "The Guild"
		  stage hearing
		    ~ set harbor.toll_fate = lost_at_sea
		    ~ outcome hearing = done
		""")
	assert_false(diagnostics.has_errors(), diagnostics.format())
	assert_true(diagnostics.has_warnings())
	var warning := _warning(diagnostics)
	assert_eq(warning.message, "stored fact \"harbor.toll_fate\" is written in an outcome stage and has no recap key")
	_assert_tilde(path, warning)


func test_choice_effect_write_warns() -> void:
	var diagnostics := WyrdDiagnostics.new()
	var path := _compile(diagnostics, """
		language 1
		facts
		  harbor.room_taken : bool stored
		scene dock
		  narrator: The room is open. #line:d_room
		  * [Take the room] -> took #line:c_room
		    ~ set harbor.room_taken = true
		  - (took)
		  narrator: The room is taken. #line:d_took
		  -> end
		""")
	assert_false(diagnostics.has_errors(), diagnostics.format())
	var warning := _warning(diagnostics)
	assert_eq(warning.message, "stored fact \"harbor.room_taken\" is written by a choice and has no recap key")
	_assert_tilde(path, warning)


func test_inc_in_an_outcome_stage_warns() -> void:
	var diagnostics := WyrdDiagnostics.new()
	_compile(diagnostics, """
		language 1
		facts
		  ferry.toll_coins : int stored
		quest harbor_guild "The Guild"
		  stage hearing
		    ~ inc ferry.toll_coins by 1
		    ~ outcome hearing = done
		""")
	assert_false(diagnostics.has_errors(), diagnostics.format())
	var warning := _warning(diagnostics)
	assert_true(warning.message.contains("ferry.toll_coins"))
	assert_true(warning.message.contains("outcome stage"))


func test_recap_true_and_false_are_silent() -> void:
	for mark in ["true", "false"]:
		var diagnostics := WyrdDiagnostics.new()
		_compile(diagnostics, """
			language 1
			facts
			  harbor.toll_fate : symbol stored recap: %s
			  harbor.room_taken : bool stored recap: %s
			  player.coins : int stored recap: %s
			quest harbor_guild "The Guild"
			  stage hearing
			    ~ set harbor.toll_fate = lost_at_sea
			    ~ inc player.coins by 1
			    ~ outcome hearing = done
			scene dock
			  narrator: The room is open. #line:d_room
			  * [Take the room] -> took #line:c_room
			    ~ set harbor.room_taken = true
			  - (took)
			  narrator: The room is taken. #line:d_took
			  -> end
			""" % [mark, mark, mark])
		assert_false(diagnostics.has_errors(), diagnostics.format())
		assert_false(diagnostics.format().contains("W_RECAP_UNMARKED"), diagnostics.format())


func test_non_outcome_and_non_stored_writes_are_silent() -> void:
	var plain := WyrdDiagnostics.new()
	_compile(plain, """
		language 1
		facts
		  harbor.toll_fate : symbol stored
		quest harbor_guild "The Guild"
		  stage note
		    ~ set harbor.toll_fate = lost_at_sea
		  stage hearing
		    ~ outcome hearing = done
		""")
	assert_false(plain.has_errors(), plain.format())
	assert_false(plain.format().contains("W_RECAP_UNMARKED"), plain.format())
	var resolved := WyrdDiagnostics.new()
	_compile(resolved, """
		language 1
		facts
		  world.season : symbol source: time.season invalidate: per_query
		quest harbor_guild "The Guild"
		  stage hearing
		    ~ set world.season = storm
		    ~ outcome hearing = done
		""")
	assert_true(resolved.format().contains("error[E_WRITE_RESOLVED]"), resolved.format())
	assert_false(resolved.format().contains("W_RECAP_UNMARKED"), resolved.format())
	var pattern := WyrdDiagnostics.new()
	_compile(pattern, """
		language 1
		facts
		  npc.{id}.alive : bool stored
		quest harbor_guild "The Guild"
		  stage hearing
		    ~ set npc.dock_hand.alive = false
		    ~ outcome hearing = done
		""")
	assert_false(pattern.has_errors(), pattern.format())
	assert_false(pattern.format().contains("W_RECAP_UNMARKED"), pattern.format())
	var belief := WyrdDiagnostics.new()
	_compile(belief, """
		language 1
		facts
		  harbor.toll_fate : symbol stored
		quest harbor_guild "The Guild"
		  stage hearing
		    ~ believe line_fisher harbor.toll_fate = stolen
		    ~ outcome hearing = done
		""")
	assert_false(belief.has_errors(), belief.format())
	assert_false(belief.format().contains("W_RECAP_UNMARKED"), belief.format())
	var abort := WyrdDiagnostics.new()
	_compile(abort, """
		language 1
		facts
		  harbor.toll_fate : symbol stored
		quest harbor_guild "The Guild"
		  stage hearing
		    ~ outcome hearing = done
		scene dock
		  on_abort:
		    ~ set harbor.toll_fate = lost_at_sea
		  narrator: The dock is quiet. #line:d_abort
		  -> end
		""")
	assert_false(abort.has_errors(), abort.format())
	assert_false(abort.format().contains("W_RECAP_UNMARKED"), abort.format())


func test_variant_outcome_stays_on_that_body() -> void:
	var parent := WyrdDiagnostics.new()
	_compile(parent, """
		language 1
		facts
		  harbor.toll_fate : symbol stored
		quest harbor_guild "The Guild"
		  slot ferry = ferry_master mode: live
		  stage arrive
		    ~ outcome hearing = done
		    variant ferry.empty:
		      ~ set harbor.toll_fate = lost_at_sea
		""")
	assert_false(parent.format().contains("W_RECAP_UNMARKED"), parent.format())
	var body := WyrdDiagnostics.new()
	var path := _compile(body, """
		language 1
		facts
		  harbor.toll_fate : symbol stored
		quest harbor_guild "The Guild"
		  slot ferry = ferry_master mode: live
		  stage arrive
		    variant ferry.empty:
		      ~ set harbor.toll_fate = lost_at_sea
		      ~ outcome hearing = done
		""")
	assert_false(body.has_errors(), body.format())
	var warning := _warning(body)
	assert_true(warning.message.contains("harbor.toll_fate"))
	_assert_tilde(path, warning)


func test_handler_write_warns_when_the_stage_sets_an_outcome() -> void:
	var diagnostics := WyrdDiagnostics.new()
	var path := _compile(diagnostics, """
		language 1
		events
		  season_changed()
		facts
		  harbor.toll_fate : symbol stored
		quest harbor_guild "The Guild"
		  stage hearing
		    on season_changed where true:
		      ~ set harbor.toll_fate = lost_at_sea
		    ~ outcome hearing = done
		""")
	assert_false(diagnostics.has_errors(), diagnostics.format())
	var warning := _warning(diagnostics)
	assert_true(warning.message.contains("outcome stage"))
	_assert_tilde(path, warning)


func test_check_prints_the_warning_and_strict_fails() -> void:
	var path := "user://wyrd_m8_recap_cli_%d.wyrd" % Time.get_ticks_usec()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(_text("""
		language 1
		facts
		  harbor.toll_fate : symbol stored
		quest harbor_guild "The Guild"
		  stage hearing
		    ~ set harbor.toll_fate = lost_at_sea
		    ~ outcome hearing = done
		"""))
	file.close()
	var loose: Dictionary = WyrdCli.execute(PackedStringArray(["check", path]))
	assert_eq(int(loose["exit_code"]), 0, str(loose["output"]))
	assert_true(str(loose["output"]).contains("warning[W_RECAP_UNMARKED]"))
	assert_false(str(loose["output"]).contains("error["), str(loose["output"]))
	var strict: Dictionary = WyrdCli.execute(PackedStringArray(["check", "--strict", path]))
	assert_eq(int(strict["exit_code"]), 1)
	assert_true(str(strict["output"]).contains("warning[W_RECAP_UNMARKED]"))


func _warning(diagnostics: WyrdDiagnostics) -> WyrdDiagnostic:
	for item in diagnostics.items:
		if item.code == WyrdDiagnostic.W_RECAP_UNMARKED:
			return item
	fail_test("missing W_RECAP_UNMARKED\n%s" % diagnostics.format())
	return null


func _assert_tilde(path: String, warning: WyrdDiagnostic) -> void:
	var source := FileAccess.get_file_as_string(path)
	var lines := source.split("\n")
	assert_gt(warning.line, 0)
	assert_lte(warning.line, lines.size())
	var text := lines[warning.line - 1]
	assert_true(text.contains("harbor."), text)
	assert_eq(text.substr(warning.col - 1, 1), "~")
	assert_true(warning.format_line().contains("warning[W_RECAP_UNMARKED]"))


func _compile(diagnostics: WyrdDiagnostics, body: String) -> String:
	var path := "user://wyrd_m8_recap_%d.wyrd" % Time.get_ticks_usec()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(_text(body))
	file.close()
	WyrdPack.compile(PackedStringArray([path]), "harbor", 1, null, diagnostics, path, true)
	return path


func _text(body: String) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for line in body.strip_edges().split("\n"):
		var rest := line
		while rest.begins_with("\t"):
			rest = rest.substr(1)
		lines.append(rest)
	return "\n".join(lines) + "\n"
