extends GutTest

const _PATTERN := "-?\\d+(?:\\.\\d+)?|[A-Za-z_][A-Za-z0-9_]*(?:\\.[A-Za-z_][A-Za-z0-9_]*)*"


func test_word_pattern_compiles_and_covers_tag_names() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/vscode-wyrd/language-configuration.json"))
	var root: Dictionary = parsed
	var pattern := str(root["wordPattern"])
	assert_eq(pattern, _PATTERN)
	var expression := RegEx.new()
	assert_eq(expression.compile(pattern), OK)
	assert_eq(expression.search("bell.").get_string(), "bell")
	assert_eq(expression.search("{player.name}").get_string(), "player.name")
	assert_eq(expression.search("ferry_toll.pay_toll").get_string(), "ferry_toll.pay_toll")
	assert_eq(expression.search("harbor.rope_done").get_string(), "harbor.rope_done")
	var plain: PackedStringArray = PackedStringArray()
	var patterns: PackedStringArray = PackedStringArray()
	var lines := FileAccess.get_file_as_string("res://tests/golden/defs/gullhaven.tags").split("\n")
	for line in lines:
		if line.is_empty() or line.begins_with("!"):
			continue
		var name := line.split("\t", false)[0]
		if name.contains("{"):
			patterns.append(name)
			continue
		plain.append(name)
		var found := expression.search(name)
		assert_ne(found, null, name)
		assert_eq(found.get_start(), 0, name)
		assert_eq(found.get_string(), name, name)
	assert_gt(plain.size(), 0)
	assert_true(patterns.has("npc.{id}.alive"))
	for name in patterns:
		assert_true(name.contains("{"), name)
		assert_false(name.contains(" "), name)
