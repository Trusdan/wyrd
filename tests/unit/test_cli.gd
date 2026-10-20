extends GutTest


func test_render_prints_version_and_command_list() -> void:
	var text := WyrdCli.render()
	assert_true(text.begins_with("wyrd 0.6.3-m8\n"))
	assert_eq(text, WyrdCli.version_line() + "\n" + "\n".join(WyrdCli.command_lines()) + "\n")
	assert_true(text.contains("check: compile and link a content pack"))
	assert_true(text.contains("test: not implemented"))
	assert_true(text.contains("tag-lines: write missing #line: ids"))
	assert_true(text.contains("export-json: write the linked pack as JSON"))
	assert_true(text.contains("pot: write a gettext POT for one pack's player text"))
	assert_true(text.contains("facts: print the fact cross-reference"))
	assert_true(text.contains("roles: print a sorted table of role holders"))
	assert_true(text.contains("why-not: explain one storylet for a scope and speaker"))
	assert_true(text.contains("voice-check: report variable text per speaker"))
	assert_true(text.contains("script-export: write one speaker's lines for a recording pass"))
	assert_true(text.contains("unvoiced-report: list line ids with no audio for each locale"))
	assert_true(text.contains("storylets: list storylets for a scope and speaker"))
	assert_true(text.contains("cooldowns: list storylet rows and speaker clocks"))
	assert_true(text.contains("choices: list fact writes by scene, choice, prefix, or time"))
	assert_true(text.contains("coverage: list storylets, variants, and lines that were never hit"))
	assert_true(text.contains("console: playtest prompt for facts, roles, time, events, and scenes"))
	assert_eq(WyrdCli.COMMANDS.size(), 16)


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


func test_check_watch_returns_a_loop_without_compiling() -> void:
	var plain: Dictionary = WyrdCli.execute(PackedStringArray([
		"check",
		"--manifest",
		"example/content/gullhaven/harbor.wyrdmanifest.tres",
	]))
	var watched: Dictionary = WyrdCli.execute(PackedStringArray([
		"check",
		"--watch",
		"--manifest",
		"example/content/gullhaven/harbor.wyrdmanifest.tres",
	]))
	assert_false(plain.has("watch"))
	assert_false(str(plain["output"]).is_empty())
	assert_eq(int(watched["exit_code"]), 0)
	assert_eq(str(watched["output"]), "")
	assert_true(watched["watch"] is WyrdCheckWatch)
	var keys: Array = plain.keys()
	keys.sort()
	assert_eq(keys, ["exit_code", "output"])


func test_check_watch_with_strict_exits_one() -> void:
	var result: Dictionary = WyrdCli.execute(PackedStringArray(["check", "--watch", "--strict"]))
	assert_eq(int(result["exit_code"]), 1)
	assert_eq(str(result["output"]), "wyrd: --watch does not take --strict\n")
	assert_false(result.has("watch"))


func test_check_watch_missing_path_exits_before_a_loop() -> void:
	var result: Dictionary = WyrdCli.execute(PackedStringArray(["check", "--watch", "res://example/missing.wyrd"]))
	assert_eq(int(result["exit_code"]), 1)
	assert_eq(str(result["output"]), "wyrd: no such file: res://example/missing.wyrd\n")
	assert_false(result.has("watch"))


func test_tag_lines_watch_is_an_unknown_option() -> void:
	var result: Dictionary = WyrdCli.execute(PackedStringArray(["tag-lines", "--watch"]))
	assert_eq(int(result["exit_code"]), 1)
	assert_eq(str(result["output"]), "wyrd: unknown option \"--watch\"\n")
	assert_false(result.has("watch"))


func test_check_invalid_file_exits_one() -> void:
	var result: Dictionary = WyrdCli.execute(PackedStringArray([
		"check",
		"res://tests/golden/cases/s5_header_missing.wyrd",
	]))
	assert_eq(int(result["exit_code"]), 1)
	assert_true(str(result["output"]).contains("error[E_HEADER_MISSING]"))


func test_pot_without_manifest_exits_one() -> void:
	var result: Dictionary = WyrdCli.execute(PackedStringArray(["pot"]))
	assert_eq(int(result["exit_code"]), 1)
	assert_eq(str(result["output"]), "wyrd: pot needs --manifest\n")


func test_pot_path_is_refused() -> void:
	var result: Dictionary = WyrdCli.execute(PackedStringArray(["pot", "example/content/gullhaven"]))
	assert_eq(int(result["exit_code"]), 1)
	assert_eq(str(result["output"]), "wyrd: pot needs --manifest\n")


func test_pot_with_errors_writes_nothing() -> void:
	var dir := "user://wyrd_pot_bad"
	DirAccess.make_dir_recursive_absolute(dir)
	var source := dir + "/broken.wyrd"
	var manifest_path := dir + "/broken.wyrdmanifest.tres"
	var out := dir + "/out.pot"
	var source_file := FileAccess.open(source, FileAccess.WRITE)
	source_file.store_string("not a header\n")
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"bad"
	manifest.language_version = 1
	manifest.files = PackedStringArray([source])
	assert_eq(ResourceSaver.save(manifest, manifest_path), OK)
	if FileAccess.file_exists(out):
		DirAccess.remove_absolute(out)
	var result: Dictionary = WyrdCli.execute(PackedStringArray([
		"pot", "--manifest", manifest_path, "--out", out,
	]))
	assert_eq(int(result["exit_code"]), 1)
	assert_true(str(result["output"]).contains("error["))
	assert_false(FileAccess.file_exists(out))


func test_pot_stdout_matches_out_file() -> void:
	var manifest := "example/content/gullhaven/harbor.wyrdmanifest.tres"
	var printed: Dictionary = WyrdCli.execute(PackedStringArray(["pot", "--manifest", manifest]))
	var out := "user://wyrd_pot_stdout.pot"
	var written: Dictionary = WyrdCli.execute(PackedStringArray([
		"pot", "--manifest", manifest, "--out", out,
	]))
	assert_eq(int(printed["exit_code"]), 0)
	assert_eq(int(written["exit_code"]), 0)
	assert_eq(str(written["output"]), "")
	assert_eq(FileAccess.get_file_as_string(out), str(printed["output"]))
