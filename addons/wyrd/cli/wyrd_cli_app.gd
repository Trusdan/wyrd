class_name WyrdCli
extends RefCounted

const _Runtime := preload("res://addons/wyrd/runtime/wyrd_runtime.gd")

## Text and exit status for the command-line entry.
##
## @experimental
## [code]check[/code] lexes, parses, and compiles statements in [code].wyrd[/code] files.
## [code]test[/code], [code]tag-lines[/code], and [code]export-json[/code] are not implemented.
## Engine unit tests stay on GUT.

const COMMANDS: PackedStringArray = ["check", "test", "tag-lines", "export-json"]


static func version_line() -> String:
	return "wyrd %s" % _Runtime.read_version()


static func command_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	for command in COMMANDS:
		if command == "check":
			lines.append("check: compile .wyrd files and print diagnostics")
		else:
			lines.append("%s: not implemented" % command)
	return lines


static func render() -> String:
	var lines := PackedStringArray()
	lines.append(version_line())
	lines.append_array(command_lines())
	return "\n".join(lines) + "\n"


static func execute(args: PackedStringArray) -> Dictionary:
	if args.is_empty():
		return {"exit_code": 0, "output": render()}
	var command := args[0]
	if command == "check":
		if args.size() != 2:
			return {"exit_code": 1, "output": "wyrd: check needs one file or directory\n"}
		return _check(args[1])
	if command == "test" or command == "tag-lines" or command == "export-json":
		return {"exit_code": 0, "output": "%s: not implemented\n" % command}
	return {"exit_code": 1, "output": "wyrd: unknown command \"%s\"\n" % command}


static func _check(argument: String) -> Dictionary:
	var path := _resolve(argument)
	var files := _collect(path)
	if files.is_empty():
		if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
			return {"exit_code": 0, "output": ""}
		return {"exit_code": 1, "output": "wyrd: no such file: %s\n" % argument}
	var diagnostics := WyrdDiagnostics.new()
	for file_path in files:
		var source := WyrdSource.load_file(file_path)
		if source == null:
			return {"exit_code": 1, "output": "wyrd: could not read %s\n" % file_path}
		var tree := WyrdParser.new().parse(source, diagnostics)
		WyrdStatements.new().compile(source, tree, diagnostics)
	var exit_code := 0
	if diagnostics.has_errors():
		exit_code = 1
	return {"exit_code": exit_code, "output": diagnostics.format()}


static func _resolve(argument: String) -> String:
	var path := argument.replace("\\", "/")
	while path.ends_with("/") and path.length() > 1:
		path = path.trim_suffix("/")
	if path.begins_with("res://") or path.begins_with("user://") or path.begins_with("/"):
		return path
	return "res://" + path.trim_prefix("./")


static func _collect(path: String) -> PackedStringArray:
	var files: PackedStringArray = PackedStringArray()
	if FileAccess.file_exists(path):
		files.append(path)
		return files
	if DirAccess.dir_exists_absolute(path):
		_walk(path, files)
		files.sort()
	return files


static func _walk(dir_path: String, files: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name != "." and file_name != "..":
			var child := dir_path.trim_suffix("/") + "/" + file_name
			if dir.current_is_dir():
				_walk(child, files)
			elif file_name.ends_with(".wyrd"):
				files.append(child)
		file_name = dir.get_next()
	dir.list_dir_end()
