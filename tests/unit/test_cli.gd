extends GutTest


func test_render_prints_version_and_command_list() -> void:
	var text := WyrdCli.render()
	assert_true(text.begins_with("wyrd 0.3.0-m5\n"))
	assert_eq(text, WyrdCli.version_line() + "\n" + "\n".join(WyrdCli.command_lines()) + "\n")
	assert_true(text.contains("check: compile and link a content pack"))
	assert_true(text.contains("test: not implemented"))
	assert_true(text.contains("tag-lines: write missing #line: ids"))
	assert_true(text.contains("export-json: write the linked pack as JSON"))
	assert_true(text.contains("facts: print the fact cross-reference"))
	assert_true(text.contains("roles: print a sorted table of role holders"))
	assert_true(text.contains("why-not: explain one storylet for a scope and speaker"))
	assert_eq(WyrdCli.COMMANDS.size(), 7)


func test_execute_without_args_matches_render() -> void:
	var result: Dictionary = WyrdCli.execute(PackedStringArray())
	assert_eq(int(result["exit_code"]), 0)
	assert_eq(str(result["output"]), WyrdCli.render())


func test_unimplemented_commands_exit_zero() -> void:
	var result: Dictionary = WyrdCli.execute(PackedStringArray(["test"]))
	assert_eq(int(result["exit_code"]), 0)
	assert_eq(str(result["output"]), "test: not implemented\n")


func test_unknown_command_exits_one() -> void:
	var result: Dictionary = WyrdCli.execute(PackedStringArray(["link"]))
	assert_eq(int(result["exit_code"]), 1)
	assert_eq(str(result["output"]), "wyrd: unknown command \"link\"\n")


func test_check_without_a_path_exits_one() -> void:
	var result: Dictionary = WyrdCli.execute(PackedStringArray(["check"]))
	assert_eq(int(result["exit_code"]), 1)
	assert_true(str(result["output"]).begins_with("wyrd: check needs one file or directory"))


func test_check_missing_path_exits_one() -> void:
	var result: Dictionary = WyrdCli.execute(PackedStringArray(["check", "res://example/missing.wyrd"]))
	assert_eq(int(result["exit_code"]), 1)
	assert_eq(str(result["output"]), "wyrd: no such file: res://example/missing.wyrd\n")


func test_check_example_content_exits_zero() -> void:
	var result: Dictionary = WyrdCli.execute(PackedStringArray(["check", "example/content"]))
	assert_eq(int(result["exit_code"]), 0, str(result["output"]))


func test_check_gullhaven_manifest_is_clean() -> void:
	var result: Dictionary = WyrdCli.execute(PackedStringArray([
		"check",
		"--manifest",
		"example/content/gullhaven/harbor.wyrdmanifest.tres",
	]))
	assert_eq(int(result["exit_code"]), 0, str(result["output"]))
	var output := str(result["output"])
	assert_true(output.contains("warning[W_CLAIM]"), output)
	assert_true(output.contains("info[I_STORYLET_SCORE]"), output)
	assert_false(output.contains("error["), output)
	for line in output.split("\n"):
		if line.is_empty():
			continue
		var claim := line.contains("warning[W_CLAIM]")
		var score := line.contains("info[I_STORYLET_SCORE]")
		assert_true(claim or score, line)


func test_check_invalid_file_exits_one() -> void:
	var result: Dictionary = WyrdCli.execute(PackedStringArray([
		"check",
		"res://tests/golden/cases/s5_header_missing.wyrd",
	]))
	assert_eq(int(result["exit_code"]), 1)
	assert_true(str(result["output"]).contains("error[E_HEADER_MISSING]"))
