class_name WyrdLinkGolden
extends RefCounted

## Multi-file link goldens: sorted diagnostics plus export-json.
##
## @experimental
## Each directory under [code]tests/golden/link[/code] is one pack. A
## [code]wyrd_commands.json[/code] in that directory is the command schema.

const ROOT := "res://tests/golden/link"


static func write_expected() -> int:
	var names := case_names()
	for name in names:
		var dir := "%s/%s" % [ROOT, name]
		var body := WyrdExport.to_json(compile_dir(dir))
		var out := FileAccess.open("%s/expected.json" % dir, FileAccess.WRITE)
		out.store_string(body)
	return names.size()


static func case_names() -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	var dir := DirAccess.open(ROOT)
	if dir == null:
		return names
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if dir.current_is_dir() and not file_name.begins_with("."):
			names.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	names.sort()
	return names


static func compile_dir(dir: String) -> Dictionary:
	var files := _wyrd(dir)
	var diagnostics := WyrdDiagnostics.new()
	var commands_path := dir.trim_suffix("/") + "/wyrd_commands.json"
	var read := WyrdPack.read_commands(commands_path, diagnostics)
	var pack := WyrdPack.compile(
		files,
		dir.get_file(),
		1,
		read["schema"],
		diagnostics,
		dir,
		bool(read["skip_note"])
	)
	return {
		"diagnostics": _diagnostics(diagnostics),
		"export": WyrdExport.to_data(pack),
	}


static func _wyrd(dir: String) -> PackedStringArray:
	var files: PackedStringArray = PackedStringArray()
	var listing := DirAccess.open(dir)
	if listing == null:
		return files
	listing.list_dir_begin()
	var file_name := listing.get_next()
	while file_name != "":
		if not listing.current_is_dir() and file_name.ends_with(".wyrd"):
			files.append(dir.trim_suffix("/") + "/" + file_name)
		file_name = listing.get_next()
	listing.list_dir_end()
	files.sort()
	return files


static func _diagnostics(diagnostics: WyrdDiagnostics) -> Array:
	var rows: Array = []
	for item in diagnostics.items:
		rows.append({
			"code": String(item.code),
			"col": item.col,
			"line": item.line,
			"message": item.message,
			"path": item.path,
			"severity": String(item.severity),
		})
	return rows
