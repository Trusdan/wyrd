extends GutTest


func test_grammar_keyword_groups_match_wyrd_keywords() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/vscode-wyrd/syntaxes/wyrd.tmLanguage.json"))
	var grammar: Dictionary = parsed
	var repository: Dictionary = grammar["repository"]
	var expression := RegEx.new()
	assert_eq(expression.compile("\\(\\?:([^)]+)\\)"), OK)
	var groups: Dictionary = WyrdKeywords.groups()
	var scopes: Dictionary = WyrdKeywords.scopes()
	for name in groups:
		var rule: Dictionary = repository[name]
		assert_eq(str(rule["name"]), str(scopes[name]))
		var found := expression.search(str(rule["match"]))
		assert_not_null(found, name)
		var words := found.get_string(1).split("|")
		var expected: PackedStringArray = groups[name]
		assert_eq(words.size(), expected.size(), name)
		for index in expected.size():
			assert_eq(str(words[index]), expected[index], name)


func test_every_keyword_is_a_quoted_literal_in_the_compiler() -> void:
	var bodies := ""
	var scripts: PackedStringArray = PackedStringArray()
	_scripts("res://addons/wyrd/compiler", scripts)
	for path in scripts:
		if path.ends_with("wyrd_keywords.gd"):
			continue
		bodies += FileAccess.get_file_as_string(path)
	var groups: Dictionary = WyrdKeywords.groups()
	for name in groups:
		var words: PackedStringArray = groups[name]
		for word in words:
			assert_true(bodies.contains("\"%s\"" % word), word)


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
