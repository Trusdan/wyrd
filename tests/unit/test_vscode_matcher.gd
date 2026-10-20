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
