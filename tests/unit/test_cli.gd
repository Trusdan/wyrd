extends GutTest


func test_render_prints_version_and_unimplemented_commands() -> void:
	var text := WyrdCli.render()
	assert_true(text.begins_with("wyrd 0.0.1\n"))
	assert_eq(text, WyrdCli.version_line() + "\n" + "\n".join(WyrdCli.command_lines()) + "\n")
	for command in WyrdCli.COMMANDS:
		assert_true(text.contains("%s: not implemented" % command))
	assert_eq(WyrdCli.COMMANDS.size(), 4)
