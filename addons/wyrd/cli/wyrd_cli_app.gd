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
## [code]why-not[/code] explains one storylet for a scope and speaker.
## [code]voice-check[/code] reports variable text per speaker.
## [code]script-export[/code] writes one speaker's lines for a recording pass.
## [code]unvoiced-report[/code] lists line ids with no audio for each locale.
## [code]test[/code] stays unimplemented until the runtime can run a scene.
## Engine unit tests stay on GUT.

const COMMANDS: PackedStringArray = ["check", "test", "tag-lines", "export-json", "facts", "roles", "why-not", "voice-check", "script-export", "unvoiced-report"]


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
		"why-not: explain one storylet for a scope and speaker",
		"voice-check: report variable text per speaker",
		"script-export: write one speaker's lines for a recording pass",
		"unvoiced-report: list line ids with no audio for each locale",
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
	if command == "why-not":
		return _why_not(args)
	if command == "voice-check":
		return _voice_check(args)
	if command == "script-export":
		return _script_export(args)
	if command == "unvoiced-report":
		return _unvoiced_report(args)
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


static func _why_not(args: PackedStringArray) -> Dictionary:
	var parsed := _options(args)
	if not str(parsed["error"]).is_empty():
		return {"exit_code": 1, "output": str(parsed["error"])}
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
	var storylet_id := str(parsed["storylet"])
	var scope := str(parsed["scope"])
	var scope_id := str(parsed["scope_id"])
	var speaker := str(parsed["speaker"])
	var found: Variant = runtime.content().storylets.get(storylet_id, null)
	if found is WyrdStoryletDef:
		var story: WyrdStoryletDef = found
		if not bool(parsed["scope_set"]):
			scope = String(story.scope_kind)
		if not bool(parsed["scope_id_set"]) and scope != "bark":
			scope_id = story.scope_id
		if not bool(parsed["speaker_set"]):
			speaker = story.speaker
	var row := runtime.director.why_not(storylet_id, scope, scope_id, speaker)
	if str(row.get("reason", "")) == "missing":
		return {"exit_code": 1, "output": "wyrd: unknown storylet \"%s\"\n" % storylet_id}
	return {"exit_code": 0, "output": WyrdDirector.format_why_not(row) + "\n"}


static func _voice_check(args: PackedStringArray) -> Dictionary:
	var parsed := _options(args)
	if not str(parsed["error"]).is_empty():
		return {"exit_code": 1, "output": str(parsed["error"])}
	var loaded := _load(parsed)
	if int(loaded["exit_code"]) != 0:
		return loaded
	var diagnostics: WyrdDiagnostics = loaded["diagnostics"]
	if diagnostics.has_errors():
		return {"exit_code": 1, "output": diagnostics.format()}
	var rows := _voice_rows(loaded["pack"])
	var groups := {}
	for row in rows:
		var speaker := str(row["speaker"])
		if not groups.has(speaker):
			groups[speaker] = {"details": [], "lines": 0, "variable": 0, "voiced": 0}
		var group: Dictionary = groups[speaker]
		group["lines"] = int(group["lines"]) + 1
		if bool(row["voiced"]):
			group["voiced"] = int(group["voiced"]) + 1
		if bool(row["variable"]):
			group["variable"] = int(group["variable"]) + 1
			(group["details"] as Array).append(row)
	var names: Array = groups.keys()
	names.sort()
	var lines := PackedStringArray()
	var any_variable := false
	for name in names:
		var group: Dictionary = groups[name]
		lines.append("speaker=%s lines=%d voiced=%d variable=%d" % [name, int(group["lines"]), int(group["voiced"]), int(group["variable"])])
		var details: Array = group["details"]
		details.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
		for detail in details:
			any_variable = true
			lines.append("  %s %s" % [str(detail["id"]), str(detail["context"])])
	var output := ""
	if not lines.is_empty():
		output = "\n".join(lines) + "\n"
	return {"exit_code": 1 if any_variable else 0, "output": output}


static func _script_export(args: PackedStringArray) -> Dictionary:
	var parsed := _options(args)
	if not str(parsed["error"]).is_empty():
		return {"exit_code": 1, "output": str(parsed["error"])}
	var loaded := _load(parsed)
	if int(loaded["exit_code"]) != 0:
		return loaded
	var diagnostics: WyrdDiagnostics = loaded["diagnostics"]
	if diagnostics.has_errors():
		return {"exit_code": 1, "output": diagnostics.format()}
	var speaker := str(parsed["speaker"])
	var rows := _voice_rows(loaded["pack"])
	var kept: Array = []
	for row in rows:
		if str(row["speaker"]) == speaker:
			kept.append(row)
	kept.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	var lines := PackedStringArray()
	for row in kept:
		lines.append("id=%s text=%s tags=%s scene=%s context=%s" % [str(row["id"]), str(row["text"]), str(row["tags"]), str(row["scene"]), str(row["context"])])
	var body := ""
	if not lines.is_empty():
		body = "\n".join(lines) + "\n"
	var out := str(parsed["out"])
	if out.is_empty():
		return {"exit_code": 0, "output": body}
	var path := out if out.begins_with("res://") or out.begins_with("user://") or out.begins_with("/") else "res://" + out
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"exit_code": 1, "output": "wyrd: could not write %s\n" % out}
	file.store_string(body)
	return {"exit_code": 0, "output": ""}


static func _unvoiced_report(args: PackedStringArray) -> Dictionary:
	var parsed := _options(args)
	if not str(parsed["error"]).is_empty():
		return {"exit_code": 1, "output": str(parsed["error"])}
	var loaded := _load(parsed)
	if int(loaded["exit_code"]) != 0:
		return loaded
	var diagnostics: WyrdDiagnostics = loaded["diagnostics"]
	if diagnostics.has_errors():
		return {"exit_code": 1, "output": diagnostics.format()}
	var heard := _audio_map(str(parsed["audio"]))
	if not str(heard["error"]).is_empty():
		return {"exit_code": 1, "output": str(heard["error"])}
	var audio: Dictionary = heard["map"]
	var ids := PackedStringArray()
	var seen := {}
	for row in _voice_rows(loaded["pack"]):
		var id := str(row["id"])
		if id.is_empty() or seen.has(id):
			continue
		seen[id] = true
		ids.append(id)
	ids.sort()
	var locales: PackedStringArray = parsed["locales"]
	if locales.is_empty():
		locales = PackedStringArray(["en"])
	var ordered: Array = []
	for locale in locales:
		ordered.append(locale)
	ordered.sort()
	var lines := PackedStringArray()
	for locale in ordered:
		var have: Dictionary = audio.get(String(locale), {})
		lines.append("locale=%s" % String(locale))
		for id in ids:
			if not have.has(id):
				lines.append(id)
	var output := ""
	if not lines.is_empty():
		output = "\n".join(lines) + "\n"
	return {"exit_code": 0, "output": output}


static func _audio_map(path: String) -> Dictionary:
	if path.is_empty():
		return {"error": "", "map": {}}
	var resolved := _resolve(path)
	if not FileAccess.file_exists(resolved):
		return {"error": "wyrd: no such file: %s\n" % path, "map": {}}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(resolved))
	if not (data is Dictionary):
		return {"error": "wyrd: audio file is not a JSON object\n", "map": {}}
	var mapped := {}
	for locale in (data as Dictionary).keys():
		var listed: Variant = (data as Dictionary)[locale]
		if not (listed is Array):
			return {"error": "wyrd: audio locale \"%s\" needs a list of line ids\n" % String(locale), "map": {}}
		var have := {}
		for id in listed:
			have[str(id)] = true
		mapped[String(locale)] = have
	return {"error": "", "map": mapped}


static func _voice_rows(pack: WyrdLinkedPack) -> Array:
	var rows: Array = []
	if pack == null:
		return rows
	for unit in pack.units:
		var file: WyrdFileDef = unit["file"]
		for quest in file.quests:
			for stage in quest.stages:
				_voice_stage(rows, quest.id, stage)
		for scene in file.scenes:
			for item in scene.items:
				if item.line_def != null:
					_voice_line(rows, item.line_def, item.line_def.speaker, "scene:%s" % scene.id, scene.id)
				if item.choice != null and not item.choice.line_id.is_empty():
					_voice_choice(rows, item.choice, scene.id)
		for story in file.storylets:
			for line_def in story.lines:
				var who := line_def.speaker if not line_def.speaker.is_empty() else story.speaker
				_voice_line(rows, line_def, who, "storylet:%s" % story.id, "")
	return rows


static func _voice_stage(rows: Array, quest_id: String, stage: WyrdStageDef) -> void:
	if stage == null:
		return
	for journal in stage.journals:
		_voice_line(rows, journal, journal.speaker, "journal:%s" % quest_id, "")
	for entry in stage.variants:
		var variant := entry as WyrdVariantDef
		if variant != null and variant.body != null:
			_voice_stage(rows, quest_id, variant.body)
	for item in stage.regions:
		var region := item as WyrdRegionDef
		if region == null:
			continue
		for child in region.stages:
			_voice_stage(rows, quest_id, child)


static func _voice_line(rows: Array, line: WyrdLineDef, speaker: String, context: String, scene_id: String) -> void:
	if line == null or line.line_id.is_empty():
		return
	rows.append(_voice_row(line.line_id, speaker, context, scene_id, line.tags, line.prose))
	for item in line.variants:
		var variant := item as WyrdLineDef
		if variant == null:
			continue
		var variant_context := "variant:%s %s" % [variant.holder, context]
		_voice_line(rows, variant, speaker, variant_context, scene_id)


static func _voice_choice(rows: Array, choice: WyrdChoiceDef, scene_id: String) -> void:
	rows.append(_voice_row(choice.line_id, "", "choice:%s" % scene_id, scene_id, choice.tags, choice.label))


static func _voice_row(
	line_id: String,
	speaker: String,
	context: String,
	scene_id: String,
	tags: PackedStringArray,
	prose: WyrdExprNode
) -> Dictionary:
	var names := PackedStringArray()
	for tag in tags:
		names.append(tag)
	names.sort()
	return {
		"context": context,
		"id": line_id,
		"scene": scene_id,
		"speaker": speaker if not speaker.is_empty() else "-",
		"tags": ",".join(names),
		"text": WyrdLineDef.source_of(prose),
		"variable": WyrdLineDef.has_variable_text(prose),
		"voiced": tags.has("voiced"),
	}


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
	var scope := ""
	var scope_id := ""
	var speaker := ""
	var scope_set := false
	var scope_id_set := false
	var speaker_set := false
	var audio := ""
	var locales := PackedStringArray()
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
		elif command == "why-not" and arg == "--scope":
			i += 1
			if i >= args.size():
				return _fail("wyrd: --scope needs a kind\n")
			scope = args[i]
			scope_set = true
		elif command == "why-not" and arg == "--scope-id":
			i += 1
			if i >= args.size():
				return _fail("wyrd: --scope-id needs an id\n")
			scope_id = args[i]
			scope_id_set = true
		elif (command == "why-not" or command == "script-export") and arg == "--speaker":
			i += 1
			if i >= args.size():
				return _fail("wyrd: --speaker needs an id\n")
			speaker = args[i]
			speaker_set = true
		elif command == "unvoiced-report" and arg == "--locale":
			i += 1
			if i >= args.size():
				return _fail("wyrd: --locale needs a locale\n")
			locales.append(args[i])
		elif command == "unvoiced-report" and arg == "--audio":
			i += 1
			if i >= args.size():
				return _fail("wyrd: --audio needs a path\n")
			audio = args[i]
		elif arg.begins_with("-"):
			return _fail("wyrd: unknown option \"%s\"\n" % arg)
		else:
			positionals.append(arg)
		i += 1
	if command == "script-export" and not speaker_set:
		return _fail("wyrd: script-export needs --speaker\n")
	if command == "why-not":
		if manifest.is_empty():
			return _fail("wyrd: why-not needs --manifest\n")
		if positionals.size() != 1:
			return _fail("wyrd: why-not needs one storylet id\n")
	else:
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
		"audio": audio,
		"command": command,
		"commands_path": commands_path,
		"dry_run": dry_run,
		"error": "",
		"files": files,
		"language_version": language_version,
		"locales": locales,
		"manifest": manifest_path if not manifest.is_empty() else "",
		"note_path": note_path,
		"out": out,
		"pack_id": pack_id,
		"prefix": prefix,
		"save": save_path,
		"scope": scope,
		"scope_id": scope_id,
		"scope_id_set": scope_id_set,
		"scope_set": scope_set,
		"speaker": speaker,
		"speaker_set": speaker_set,
		"storylet": positionals[0] if command == "why-not" and positionals.size() == 1 else "",
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
