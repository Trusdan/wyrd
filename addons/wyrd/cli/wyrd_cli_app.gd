class_name WyrdCli
extends RefCounted

const _Runtime := preload("res://addons/wyrd/runtime/wyrd_runtime.gd")

## Text and exit status for the command-line entry.
##
## @experimental
## [code]check[/code] lexes, parses, compiles, and links a pack.
## [code]tag-lines[/code] writes missing line ids. [code]export-json[/code] writes
## the debug pack document. [code]facts[/code] prints the cross-reference.
## [code]roles[/code] prints a sorted table of role holders.
## [code]test[/code] stays unimplemented until the runtime can run a scene.
## Engine unit tests stay on GUT.

const COMMANDS: PackedStringArray = ["check", "test", "tag-lines", "export-json", "facts", "roles"]


static func version_line() -> String:
	return "wyrd %s" % _Runtime.read_version()


static func command_lines() -> PackedStringArray:
	return PackedStringArray([
		"check: compile and link a content pack",
		"test: not implemented",
		"tag-lines: write missing #line: ids",
		"export-json: write the linked pack as JSON",
		"facts: print the fact cross-reference",
		"roles: print a sorted table of role holders",
	])


static func render() -> String:
	var lines := PackedStringArray()
	lines.append(version_line())
	lines.append_array(command_lines())
	return "\n".join(lines) + "\n"


static func execute(args: PackedStringArray) -> Dictionary:
	if args.is_empty():
		return {"exit_code": 0, "output": render()}
	var command := args[0]
	if command == "test":
		return {"exit_code": 0, "output": "test: not implemented\n"}
	if command == "check":
		return _check(args)
	if command == "tag-lines":
		return _tag(args)
	if command == "export-json":
		return _export(args)
	if command == "facts":
		return _facts(args)
	if command == "roles":
		return _roles(args)
	return {"exit_code": 1, "output": "wyrd: unknown command \"%s\"\n" % command}


class _NoElection extends WyrdElectionAdapter:
	func start_election(_role: StringName, _departed: StringName) -> void:
		pass


class _NoHost extends RefCounted:
	func decide(_role: StringName, _departed: StringName) -> void:
		pass


static func _check(args: PackedStringArray) -> Dictionary:
	var parsed := _options(args)
	if not str(parsed["error"]).is_empty():
		return {"exit_code": 1, "output": str(parsed["error"])}
	var loaded := _load(parsed)
	if int(loaded["exit_code"]) != 0:
		return loaded
	var diagnostics: WyrdDiagnostics = loaded["diagnostics"]
	var exit_code := 0
	if diagnostics.has_errors() or (bool(parsed["strict"]) and diagnostics.has_warnings()):
		exit_code = 1
	return {"exit_code": exit_code, "output": diagnostics.format()}


static func _tag(args: PackedStringArray) -> Dictionary:
	var parsed := _options(args)
	if not str(parsed["error"]).is_empty():
		return {"exit_code": 1, "output": str(parsed["error"])}
	var files: PackedStringArray = parsed["files"]
	var pack_id := str(parsed["pack_id"])
	if files.is_empty():
		return {"exit_code": 1, "output": "wyrd: tag-lines needs one file or directory\n"}
	return WyrdTagLines.tag_files(files, pack_id, bool(parsed["dry_run"]))


static func _export(args: PackedStringArray) -> Dictionary:
	var parsed := _options(args)
	if not str(parsed["error"]).is_empty():
		return {"exit_code": 1, "output": str(parsed["error"])}
	var loaded := _load(parsed)
	if int(loaded["exit_code"]) != 0:
		return loaded
	var body := WyrdExport.to_json(WyrdExport.to_data(loaded["pack"]))
	var out := str(parsed["out"])
	if out.is_empty():
		return {"exit_code": 0, "output": body}
	var path := out if out.begins_with("res://") or out.begins_with("user://") or out.begins_with("/") else "res://" + out
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"exit_code": 1, "output": "wyrd: could not write %s\n" % out}
	file.store_string(body)
	return {"exit_code": 0, "output": ""}


static func _facts(args: PackedStringArray) -> Dictionary:
	var parsed := _options(args)
	if not str(parsed["error"]).is_empty():
		return {"exit_code": 1, "output": str(parsed["error"])}
	var loaded := _load(parsed)
	if int(loaded["exit_code"]) != 0:
		return loaded
	var pack: WyrdLinkedPack = loaded["pack"]
	var diagnostics: WyrdDiagnostics = loaded["diagnostics"]
	if bool(parsed["as_json"]):
		return {"exit_code": 1 if diagnostics.has_errors() else 0, "output": WyrdExport.xref_json(pack)}
	var table := ""
	if pack.xref != null:
		table = pack.xref.render_table()
	var lines: PackedStringArray = PackedStringArray()
	if not table.is_empty():
		lines.append(table)
	var formatted := diagnostics.format()
	if not formatted.is_empty():
		if not lines.is_empty():
			lines.append("")
		lines.append(formatted.trim_suffix("\n"))
	var output := ""
	if not lines.is_empty():
		output = "\n".join(lines) + "\n"
	return {"exit_code": 1 if diagnostics.has_errors() else 0, "output": output}


static func _roles(args: PackedStringArray) -> Dictionary:
	var parsed := _options(args)
	if not str(parsed["error"]).is_empty():
		return {"exit_code": 1, "output": str(parsed["error"])}
	var loaded := _load(parsed)
	if int(loaded["exit_code"]) != 0:
		return loaded
	var diagnostics: WyrdDiagnostics = loaded["diagnostics"]
	if diagnostics.has_errors():
		return {"exit_code": 1, "output": diagnostics.format()}
	var runtime: WyrdRuntime = _Runtime.new()
	runtime.roles.set_host_decides(Callable(_NoHost.new(), &"decide"))
	runtime.register_adapter(WyrdElectionAdapter, _NoElection.new())
	var report := runtime.load_content(_manifest(parsed))
	if not report.ok:
		return {"exit_code": 1, "output": report.diagnostics.format()}
	runtime.start_new_game(1)
	var save_path := str(parsed["save"])
	if not save_path.is_empty():
		var resolved := _resolve(save_path)
		if not FileAccess.file_exists(resolved):
			return {"exit_code": 1, "output": "wyrd: no such file: %s\n" % save_path}
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(resolved))
		if not (data is Dictionary):
			return {"exit_code": 1, "output": "wyrd: save is not a JSON object\n"}
		var loaded_save := runtime.load_state(data)
		if not loaded_save.ok:
			return {"exit_code": 1, "output": loaded_save.diagnostics.format()}
	var table := runtime.roles.render_table(str(parsed["prefix"]))
	var lines := PackedStringArray()
	if not table.is_empty():
		lines.append(table.trim_suffix("\n"))
	var formatted := diagnostics.format()
	if not formatted.is_empty():
		if not lines.is_empty():
			lines.append("")
		lines.append(formatted.trim_suffix("\n"))
	var output := ""
	if not lines.is_empty():
		output = "\n".join(lines) + "\n"
	return {"exit_code": 0, "output": output}


static func _manifest(parsed: Dictionary) -> WyrdContentManifest:
	var path := str(parsed["manifest"])
	if not path.is_empty():
		return load(path) as WyrdContentManifest
	var created := WyrdContentManifest.new()
	created.pack_id = StringName(str(parsed["pack_id"]))
	created.language_version = int(parsed["language_version"])
	created.files = parsed["files"]
	return created


static func _load(parsed: Dictionary) -> Dictionary:
	var files: PackedStringArray = parsed["files"]
	if files.is_empty():
		return {"exit_code": 1, "output": "wyrd: %s needs one file or directory\n" % str(parsed["command"])}
	var diagnostics := WyrdDiagnostics.new()
	var commands: WyrdCommandSchema = null
	var skip_commands_note := false
	var commands_path := str(parsed["commands_path"])
	if not commands_path.is_empty():
		var read := WyrdPack.read_commands(commands_path, diagnostics)
		commands = read["schema"]
		skip_commands_note = bool(read["skip_note"])
	var pack: WyrdLinkedPack = WyrdPack.compile(
		files,
		str(parsed["pack_id"]),
		int(parsed["language_version"]),
		commands,
		diagnostics,
		str(parsed["note_path"]),
		skip_commands_note
	)
	return {"diagnostics": diagnostics, "exit_code": 0, "output": "", "pack": pack}


static func _options(args: PackedStringArray) -> Dictionary:
	var command := args[0]
	var strict := false
	var dry_run := false
	var as_json := false
	var manifest := ""
	var out := ""
	var prefix := ""
	var save_path := ""
	var positionals: PackedStringArray = PackedStringArray()
	var i := 1
	while i < args.size():
		var arg := args[i]
		if arg == "--strict":
			strict = true
		elif arg == "--dry-run":
			dry_run = true
		elif arg == "--json":
			as_json = true
		elif arg == "--manifest":
			i += 1
			if i >= args.size():
				return _fail("wyrd: --manifest needs a path\n")
			manifest = args[i]
		elif arg == "-o":
			i += 1
			if i >= args.size():
				return _fail("wyrd: -o needs a path\n")
			out = args[i]
		elif arg == "--prefix":
			i += 1
			if i >= args.size():
				return _fail("wyrd: --prefix needs text\n")
			prefix = args[i]
		elif arg == "--save":
			i += 1
			if i >= args.size():
				return _fail("wyrd: --save needs a path\n")
			save_path = args[i]
		elif arg.begins_with("-"):
			return _fail("wyrd: unknown option \"%s\"\n" % arg)
		else:
			positionals.append(arg)
		i += 1
	if not manifest.is_empty() and not positionals.is_empty():
		return _fail("wyrd: pass a path or --manifest\n")
	if manifest.is_empty() and positionals.size() != 1:
		return _fail("wyrd: %s needs one file or directory\n" % command)
	var files := PackedStringArray()
	var pack_id := ""
	var language_version := 1
	var note_path := ""
	var commands_path := ""
	var manifest_path := ""
	if not manifest.is_empty():
		manifest_path = _resolve(manifest)
		if not FileAccess.file_exists(manifest_path):
			return _fail("wyrd: no such file: %s\n" % manifest)
		var resource := ResourceLoader.load(manifest_path)
		if not (resource is WyrdContentManifest):
			return _fail("wyrd: not a content manifest: %s\n" % manifest)
		var spec := resource as WyrdContentManifest
		pack_id = String(spec.pack_id)
		language_version = spec.language_version
		for listed in spec.files:
			files.append(_resolve(listed))
		commands_path = manifest_path.get_base_dir() + "/wyrd_commands.json"
		note_path = manifest_path
	else:
		var path := _resolve(positionals[0])
		if not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path):
			return _fail("wyrd: no such file: %s\n" % positionals[0])
		files = _collect(path)
		pack_id = WyrdPack.pack_id_for(path)
		note_path = path
	return {
		"as_json": as_json,
		"command": command,
		"commands_path": commands_path,
		"dry_run": dry_run,
		"error": "",
		"files": files,
		"language_version": language_version,
		"manifest": manifest_path if not manifest.is_empty() else "",
		"note_path": note_path,
		"out": out,
		"pack_id": pack_id,
		"prefix": prefix,
		"save": save_path,
		"strict": strict,
	}


static func _fail(message: String) -> Dictionary:
	return {
		"as_json": false,
		"command": "",
		"commands_path": "",
		"dry_run": false,
		"error": message,
		"files": PackedStringArray(),
		"language_version": 1,
		"manifest": "",
		"note_path": "",
		"out": "",
		"pack_id": "",
		"prefix": "",
		"save": "",
		"strict": false,
	}


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
