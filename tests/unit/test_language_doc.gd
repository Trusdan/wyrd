extends GutTest

## docs/language.md names every keyword and built-in, and the old files point at it.


const _POINTERS: PackedStringArray = [
	"res://docs/grammar-v1.md",
	"res://docs/statements-draft.md",
	"res://docs/conditions-draft.md",
	"res://docs/events-draft.md",
]


func test_language_reference_covers_keywords_builtins_and_pointers() -> void:
	var text := FileAccess.get_file_as_string("res://docs/language.md")
	assert_false(text.is_empty())
	var headings: PackedStringArray = PackedStringArray()
	for line in text.split("\n"):
		if line.begins_with("#"):
			headings.append(line)
		assert_false(line.to_lower().contains("approv"), line)
	var groups: Dictionary = WyrdKeywords.groups()
	for group in groups.keys():
		for word in groups[group]:
			var needle := "`%s`" % String(word)
			var found := false
			for heading in headings:
				if heading.contains(needle):
					found = true
					break
			assert_true(found, "%s %s" % [String(group), String(word)])
	for spec in WyrdSignatures._BUILTINS:
		var name := String(spec).get_slice("(", 0)
		assert_true(text.contains("`%s(" % name), name)
	assert_true(text.contains("E_KNOWN_REMOVED"))
	assert_true(text.contains("show_disabled_when"))
	for path in _POINTERS:
		var body := FileAccess.get_file_as_string(path)
		var kept: PackedStringArray = PackedStringArray()
		for line in body.split("\n"):
			if not line.is_empty():
				kept.append(line)
		assert_eq(kept.size(), 1, path)
		assert_true(kept[0].contains("language.md"), path)
