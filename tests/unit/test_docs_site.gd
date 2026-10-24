extends GutTest

## The docs site pages quote real files and name real API.


const _ROOT_PAGES: PackedStringArray = [
	"res://docs/index.md",
	"res://docs/adapters.md",
	"res://docs/rationale.md",
	"res://docs/tutorial.md",
]

const _INDEX_LINKS: PackedStringArray = [
	"language.md",
	"tutorial.md",
	"api/index.md",
	"adapters.md",
	"host-checklist.md",
	"cookbook/index.md",
	"rationale.md",
	"stability.md",
	"CONTRIBUTING.md",
]

const _RECIPES: PackedStringArray = [
	"role-fallbacks.md",
	"topics.md",
	"barks.md",
	"social-and-reputation.md",
	"epilogues.md",
	"migration.md",
]


func test_pages_quote_sources_link_files_and_name_real_api() -> void:
	var api := FileAccess.get_file_as_string("res://docs/api/Wyrd.md")
	assert_false(api.is_empty(), "docs/api/Wyrd.md")
	var pages := _pages()
	assert_gt(pages.size(), _ROOT_PAGES.size(), "cookbook pages")
	for page in pages:
		_check_page(page, api)
	var index_paths := _relative_paths("res://docs/index.md")
	for required in _INDEX_LINKS:
		assert_true(index_paths.has(required), required)
	var recipe_paths := _relative_paths("res://docs/cookbook/index.md")
	for recipe in _RECIPES:
		assert_true(recipe_paths.has(recipe), recipe)


func _pages() -> PackedStringArray:
	var pages := _ROOT_PAGES.duplicate()
	var dir := DirAccess.open("res://docs/cookbook")
	assert_not_null(dir, "res://docs/cookbook")
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".md"):
			pages.append("res://docs/cookbook/%s" % entry)
		entry = dir.get_next()
	dir.list_dir_end()
	return pages


func _check_page(page: String, api: String) -> void:
	var text := FileAccess.get_file_as_string(page)
	assert_false(text.is_empty(), page)
	assert_false(text.begins_with("---"), page)
	var lines := text.split("\n")
	var in_wyrd := false
	var in_script := false
	var cited := ""
	var block := PackedStringArray()
	var script_body := ""
	for index in lines.size():
		var line: String = lines[index]
		assert_false(line.to_lower().contains("approv"), "%s: %s" % [page, line])
		assert_false(line.contains("{%"), "%s: %s" % [page, line])
		assert_ne(line.strip_edges(), "---", page)
		if line == "```wyrd":
			assert_false(in_wyrd or in_script, page)
			assert_gt(index, 0, page)
			cited = _cited_source(lines[index - 1])
			assert_false(cited.is_empty(), "%s: %s" % [page, lines[index - 1]])
			assert_true(cited.begins_with("example/") or cited.begins_with("tests/"), cited)
			assert_true(FileAccess.file_exists("res://%s" % cited), cited)
			in_wyrd = true
			block = PackedStringArray()
			continue
		if line == "```gdscript":
			assert_false(in_wyrd or in_script, page)
			in_script = true
			script_body = ""
			continue
		if line == "```" and in_wyrd:
			assert_false(block.is_empty(), page)
			var source_lines := FileAccess.get_file_as_string("res://%s" % cited).split("\n")
			assert_true(_has_run(source_lines, block), "%s quotes %s" % [page, cited])
			in_wyrd = false
			continue
		if line == "```" and in_script:
			_check_script(page, script_body, api)
			in_script = false
			continue
		if in_wyrd:
			block.append(line)
		elif in_script:
			script_body += line + "\n"
	assert_false(in_wyrd or in_script, "%s fence" % page)
	for target in _targets(text):
		var rel := _link_path(target)
		if not _is_relative(target, rel):
			continue
		var resolved := page.get_base_dir().path_join(rel).simplify_path()
		assert_true(FileAccess.file_exists(resolved), "%s -> %s" % [page, target])


func _cited_source(line: String) -> String:
	if not line.begins_with("From `") or not line.ends_with("`:"):
		return ""
	return line.trim_prefix("From `").trim_suffix("`:")


func _has_run(source: PackedStringArray, block: PackedStringArray) -> bool:
	var last := source.size() - block.size()
	for start in last + 1:
		var same := true
		for offset in block.size():
			if source[start + offset] != block[offset]:
				same = false
				break
		if same:
			return true
	return false


func _check_script(page: String, body: String, api: String) -> void:
	var types := RegEx.new()
	assert_eq(types.compile("\\bWyrd[A-Z][A-Za-z0-9_]*\\b"), OK)
	for found in types.search_all(body):
		var type_name := found.get_string(0)
		var doc := "res://docs/api/%s.md" % type_name
		assert_true(FileAccess.file_exists(doc), "%s names %s" % [page, type_name])
	var calls := RegEx.new()
	assert_eq(calls.compile("\\bWyrd\\.([A-Za-z_][A-Za-z0-9_]*)"), OK)
	for found in calls.search_all(body):
		var member := found.get_string(1)
		var needle := "### `%s`" % member
		var headed := false
		for heading in api.split("\n"):
			if heading == needle:
				headed = true
				break
		assert_true(headed, "%s names Wyrd.%s" % [page, member])


func _targets(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var link_re := RegEx.new()
	assert_eq(link_re.compile("\\[[^\\]]*\\]\\(([^)]+)\\)"), OK)
	var in_fence := false
	for line in text.split("\n"):
		if line.begins_with("```"):
			in_fence = not in_fence
			continue
		if in_fence:
			continue
		for found in link_re.search_all(line):
			out.append(found.get_string(1).strip_edges())
	return out


func _relative_paths(page: String) -> PackedStringArray:
	var out := PackedStringArray()
	for target in _targets(FileAccess.get_file_as_string(page)):
		var rel := _link_path(target)
		if _is_relative(target, rel):
			out.append(rel)
	return out


func _link_path(target: String) -> String:
	var path := target.strip_edges()
	var space := path.find(" ")
	if space >= 0:
		path = path.substr(0, space)
	if path.begins_with("<") and path.ends_with(">"):
		path = path.substr(1, path.length() - 2)
	var hash := path.find("#")
	if hash >= 0:
		path = path.substr(0, hash)
	var query := path.find("?")
	if query >= 0:
		path = path.substr(0, query)
	return path


func _is_relative(target: String, path: String) -> bool:
	var lowered := target.strip_edges().to_lower()
	if lowered.begins_with("http://") or lowered.begins_with("https://") or lowered.begins_with("mailto:"):
		return false
	if path.is_empty():
		return false
	return true
