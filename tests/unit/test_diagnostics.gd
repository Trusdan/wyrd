extends GutTest


func test_offset_maps_lines_and_columns() -> void:
	var source := WyrdSource.new("sample.wyrd", "a\ncafé\n")
	assert_eq(source.line_at(0), 1)
	assert_eq(source.column_at(0), 1)
	assert_eq(source.line_at(2), 2)
	assert_eq(source.column_at(2), 1)
	assert_eq(source.column_at(5), 4)
	assert_eq(source.line_at(source.text.length()), 3)
	assert_eq(source.column_at(source.text.length()), 1)


func test_crlf_is_one_newline() -> void:
	var source := WyrdSource.new("sample.wyrd", "language 1\r\nquest ferry \"T\"\r\n")
	assert_eq(source.line_at(11), 2)
	assert_false(source.text.contains("\r"))


func test_prose_double_brace_follows_the_escape_rules() -> void:
	# Grammar v1 §4 says {{ is a literal { and a stray } is literal, so }} is not an escape.
	# The display sentence in that section shows one closing brace; the rules yield two.
	var tokens := _tokens("language 1\nscene dock\n  clerk: The board lists the price as {{two coins}}. #line:b1\n")
	assert_eq(_text(tokens, &"prose"), "The board lists the price as {two coins}}.")
	assert_eq(_text(tokens, &"line_tag"), "b1")


func test_interpolation_is_a_raw_span() -> void:
	var tokens := _tokens("language 1\nscene dock\n  keeper: Pay {ferry.toll} now. #line:p1\n")
	assert_eq(_text(tokens, &"interp"), "ferry.toll")
	var prose: PackedStringArray = PackedStringArray()
	for token in tokens:
		if token.kind == &"prose":
			prose.append(token.text)
	assert_eq(prose, PackedStringArray(["Pay ", " now."]))


func test_header_missing_message() -> void:
	assert_eq(_format("// note only\n"), "sample.wyrd:1:1: error[E_HEADER_MISSING]: missing language header\n")


func test_header_invalid_message() -> void:
	assert_eq(_format("language 2\n"), "sample.wyrd:1:1: error[E_HEADER_INVALID]: header must be exactly \"language 1\"\n")


func test_tab_indent_message() -> void:
	assert_eq(_format("language 1\n\tfacts\n"), "sample.wyrd:2:1: error[E_TAB_INDENT]: tab indentation is not allowed\n")


func test_indent_width_message() -> void:
	assert_eq(
		_format("language 1\nfacts\n   player.coins : int stored\n"),
		"sample.wyrd:3:1: error[E_INDENT_WIDTH]: indentation must be a multiple of two spaces\n"
	)


func test_indent_jump_message() -> void:
	assert_eq(
		_format("language 1\nfacts\n    player.coins : int stored\n"),
		"sample.wyrd:3:1: error[E_INDENT_JUMP]: indentation jumped more than one level\n"
	)


func test_reserved_word_message() -> void:
	assert_eq(
		_format("language 1\nquest document \"A\"\n"),
		"sample.wyrd:2:7: error[E_RESERVED_WORD]: reserved word \"document\"\n"
	)


func test_unterminated_string_message() -> void:
	assert_eq(
		_format("language 1\nquest ferry \"Toll\n"),
		"sample.wyrd:2:13: error[E_UNTERMINATED_STRING]: unterminated string\n"
	)


func test_bad_escape_message() -> void:
	assert_eq(
		_format("language 1\nquest ferry \"\\n\"\n"),
		"sample.wyrd:2:14: error[E_BAD_ESCAPE]: unknown string escape \"\\n\"\n"
	)


func test_line_tag_position_message() -> void:
	assert_eq(
		_format("language 1\nscene dock\n  keeper: Hello #line:abc extra\n"),
		"sample.wyrd:3:17: error[E_LINE_TAG_POSITION]: line tag must be the last token on the line\n"
	)


func test_line_tag_format_message() -> void:
	assert_eq(
		_format("language 1\nscene dock\n  keeper: Hello #line:ab-c\n"),
		"sample.wyrd:3:17: error[E_LINE_TAG_FORMAT]: line tag id must match [A-Za-z0-9_]+\n"
	)


func test_unexpected_token_message() -> void:
	assert_eq(
		_format("language 1\nscene dock\n  @\n"),
		"sample.wyrd:3:3: error[E_UNEXPECTED_TOKEN]: unexpected token \"@\"\n"
	)


func test_facts_syntax_message() -> void:
	assert_eq(
		_format("language 1\nfacts\n  player.coins int stored\n"),
		"sample.wyrd:3:16: error[E_FACTS_SYNTAX]: expected \":\" after the fact key\n"
	)


func test_compiler_scripts_do_not_use_the_editor_api() -> void:
	var forbidden: PackedStringArray = PackedStringArray([
		"EditorInterface",
		"EditorPlugin",
		"EditorImportPlugin",
		"@tool",
	])
	var scripts: PackedStringArray = PackedStringArray()
	_scripts("res://addons/wyrd/compiler", scripts)
	assert_gt(scripts.size(), 0)
	for path in scripts:
		var body := FileAccess.get_file_as_string(path)
		for term in forbidden:
			assert_false(body.contains(term), "%s contains %s" % [path, term])


func _format(text: String) -> String:
	var source := WyrdSource.new("sample.wyrd", text)
	var diagnostics := WyrdDiagnostics.new()
	WyrdParser.new().parse(source, diagnostics)
	return diagnostics.format()


func _tokens(text: String) -> Array[WyrdToken]:
	return WyrdLexer.new().tokenize(WyrdSource.new("sample.wyrd", text), WyrdDiagnostics.new())


func _text(tokens: Array[WyrdToken], kind: StringName) -> String:
	for token in tokens:
		if token.kind == kind:
			return token.text
	return ""


func _scripts(dir_path: String, into: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not file_name.begins_with("."):
			var child := dir_path.trim_suffix("/") + "/" + file_name
			if dir.current_is_dir():
				_scripts(child, into)
			elif file_name.ends_with(".gd"):
				into.append(child)
		file_name = dir.get_next()
	dir.list_dir_end()
