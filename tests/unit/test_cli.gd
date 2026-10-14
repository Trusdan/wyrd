extends GutTest


func test_render_prints_version_and_command_list() -> void:
	var text := WyrdCli.render()
	assert_true(text.begins_with("wyrd 0.0.1\n"))
	assert_eq(text, WyrdCli.version_line() + "\n" + "\n".join(WyrdCli.command_lines()) + "\n")
	assert_true(text.contains("check: parse .wyrd files and print diagnostics"))
	assert_true(text.contains("test: not implemented"))
	assert_true(text.contains("tag-lines: not implemented"))
	assert_true(text.contains("export-json: not implemented"))
	assert_eq(WyrdCli.COMMANDS.size(), 4)


func test_execute_without_args_matches_render() -> void:
	var result: Dictionary = WyrdCli.execute(PackedStringArray())
	assert_eq(int(result["exit_code"]), 0)
	assert_eq(str(result["output"]), WyrdCli.render())


func test_unimplemented_commands_exit_zero() -> void:
	for command in ["test", "tag-lines", "export-json"]:
		var result: Dictionary = WyrdCli.execute(PackedStringArray([command]))
		assert_eq(int(result["exit_code"]), 0, command)
		assert_eq(str(result["output"]), "%s: not implemented\n" % command)


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
	assert_eq(str(result["output"]), "")


func test_check_invalid_file_exits_one() -> void:
	var result: Dictionary = WyrdCli.execute(PackedStringArray([
		"check",
		"res://tests/golden/cases/s5_header_missing.wyrd",
	]))
	assert_eq(int(result["exit_code"]), 1)
	assert_true(str(result["output"]).contains("error[E_HEADER_MISSING]"))
