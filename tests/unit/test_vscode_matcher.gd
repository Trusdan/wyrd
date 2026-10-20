extends GutTest


func test_wyrd_matcher_indexes_and_file_location() -> void:
	var matcher := _matcher()
	var pattern: Dictionary = matcher["pattern"]
	assert_eq(int(pattern["file"]), 1)
	assert_eq(int(pattern["line"]), 2)
	assert_eq(int(pattern["column"]), 3)
	assert_eq(int(pattern["severity"]), 4)
	assert_eq(int(pattern["code"]), 5)
	assert_eq(int(pattern["message"]), 6)
	var where: Array = matcher["fileLocation"]
	assert_eq(where, ["autoDetect", "${workspaceFolder}"])


func test_check_lines_match_compiled_diagnostics() -> void:
	var expression := RegEx.new()
	var pattern: Dictionary = _matcher()["pattern"]
	assert_eq(expression.compile(str(pattern["regexp"])), OK)
	var saw := {"error": false, "warning": false, "info": false}
	_expect(expression, ["check", "tests/golden/cases/s5_header_missing.wyrd"], _compile_file("res://tests/golden/cases/s5_header_missing.wyrd"), saw)
	_expect(expression, ["check", "tests/golden/link/never_set"], _compile_dir("res://tests/golden/link/never_set"), saw)
	_expect(expression, ["check", "--manifest", "example/content/gullhaven/harbor.wyrdmanifest.tres"], _compile_manifest(), saw)
	assert_true(bool(saw["error"]))
	assert_true(bool(saw["warning"]))
	assert_true(bool(saw["info"]))


func test_wyrd_watch_matcher_copies_the_wyrd_pattern() -> void:
	var plain := _matcher()
	var watch := _matcher_named("wyrd-watch")
	assert_eq(watch["pattern"], plain["pattern"])
	assert_eq(str(watch["owner"]), str(plain["owner"]))
	assert_eq(str(watch["source"]), str(plain["source"]))
	assert_eq(watch["fileLocation"], plain["fileLocation"])
	var background: Dictionary = watch["background"]
	assert_eq(bool(background["activeOnStart"]), true)
	var begins := RegEx.new()
	var ends := RegEx.new()
	var diagnostic := RegEx.new()
	assert_eq(begins.compile(str(background["beginsPattern"])), OK)
	assert_eq(ends.compile(str(background["endsPattern"])), OK)
	assert_eq(diagnostic.compile(str(plain["pattern"]["regexp"])), OK)
	var lines := _sample_cycle().strip_edges().split("\n")
	assert_not_null(begins.search(lines[0]))
	assert_not_null(ends.search(lines[lines.size() - 1]))
	assert_null(diagnostic.search(lines[0]))
	assert_null(diagnostic.search(lines[lines.size() - 1]))
	for line in lines:
		if line.begins_with("wyrd: check "):
			continue
		assert_null(begins.search(line), line)
		assert_null(ends.search(line), line)
	for args in [
		["check", "tests/golden/cases/s5_header_missing.wyrd"],
		["check", "tests/golden/link/never_set"],
		["check", "--manifest", "example/content/gullhaven/harbor.wyrdmanifest.tres"],
	]:
		var result: Dictionary = WyrdCli.execute(PackedStringArray(args))
		for line in str(result["output"]).split("\n"):
			if line.is_empty():
				continue
			assert_null(begins.search(line), line)
			assert_null(ends.search(line), line)


func _sample_cycle() -> String:
	var fake := _Cycle.new()
	var watch := WyrdCheckWatch.new(
		{"manifest": "", "note_path": "res://example/content/gullhaven/facts.wyrd"},
		PackedStringArray(["check", "res://example/content/gullhaven/facts.wyrd"]),
		Callable(fake, &"read_md5"),
		Callable(fake, &"run_check")
	)
	return watch.tick(0)


func _matcher_named(name: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/vscode-wyrd/package.json"))
	var root: Dictionary = parsed
	var contributes: Dictionary = root["contributes"]
	var matchers: Array = contributes["problemMatchers"]
	for row in matchers:
		var matcher: Dictionary = row
		if str(matcher["name"]) == name:
			return matcher
	return {}


func _expect(expression: RegEx, args: Array, diagnostics: WyrdDiagnostics, saw: Dictionary) -> void:
	var result: Dictionary = WyrdCli.execute(PackedStringArray(args))
	assert_eq(str(result["output"]), diagnostics.format())
	var lines := diagnostics.format().split("\n")
	var items: Array[WyrdDiagnostic] = diagnostics.items
	var matched := 0
	for line in lines:
		if line.is_empty():
			continue
		var found := expression.search(line)
		assert_not_null(found, line)
		var file := found.get_string(1)
		assert_true(FileAccess.file_exists("res://" + file), file)
		var line_no := int(found.get_string(2))
		var column := int(found.get_string(3))
		assert_gt(line_no, 0)
		assert_gt(column, 0)
		var severity := found.get_string(4)
		assert_true(severity == "error" or severity == "warning" or severity == "info", severity)
		saw[severity] = true
		var item := items[matched]
		assert_eq(severity, String(item.severity))
		assert_eq(found.get_string(5), String(item.code))
		assert_eq(found.get_string(6), item.message)
		assert_eq(line_no, item.line)
		assert_eq(column, item.col)
		assert_eq(file, item.path.trim_prefix("res://"))
		matched += 1
	assert_eq(matched, items.size())


func _matcher() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/vscode-wyrd/package.json"))
	var root: Dictionary = parsed
	var contributes: Dictionary = root["contributes"]
	var matchers: Array = contributes["problemMatchers"]
	for row in matchers:
		var matcher: Dictionary = row
		if str(matcher["name"]) == "wyrd":
			return matcher
	return {}


func _compile_file(path: String) -> WyrdDiagnostics:
	var diagnostics := WyrdDiagnostics.new()
	WyrdPack.compile(PackedStringArray([path]), WyrdPack.pack_id_for(path), 1, null, diagnostics, path, false)
	return diagnostics


func _compile_dir(path: String) -> WyrdDiagnostics:
	var files := PackedStringArray()
	_wyrd_files(path, files)
	files.sort()
	var diagnostics := WyrdDiagnostics.new()
	WyrdPack.compile(files, WyrdPack.pack_id_for(path), 1, null, diagnostics, path, false)
	return diagnostics


func _compile_manifest() -> WyrdDiagnostics:
	var path := "res://example/content/gullhaven/harbor.wyrdmanifest.tres"
	var spec := load(path) as WyrdContentManifest
	var diagnostics := WyrdDiagnostics.new()
	var read := WyrdPack.read_commands(path.get_base_dir() + "/wyrd_commands.json", diagnostics)
	WyrdPack.compile(spec.files, String(spec.pack_id), spec.language_version, read["schema"], diagnostics, path, bool(read["skip_note"]))
	return diagnostics


func _wyrd_files(dir_path: String, into: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not file_name.begins_with("."):
			var child := dir_path.trim_suffix("/") + "/" + file_name
			if dir.current_is_dir():
				_wyrd_files(child, into)
			elif file_name.ends_with(".wyrd"):
				into.append(child)
		file_name = dir.get_next()
	dir.list_dir_end()


class _Cycle extends RefCounted:
	func read_md5(_path: String) -> String:
		return "a"

	func run_check(_args: PackedStringArray) -> Dictionary:
		return {
			"exit_code": 1,
			"output": "res://a.wyrd:1:1: error[E_HEADER_MISSING]: missing language header\n",
			"errors": 1,
			"warnings": 0,
		}
