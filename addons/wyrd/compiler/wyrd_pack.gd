class_name WyrdPack
extends RefCounted

## Compiles a pack: parse every file, merge facts, compile statements, link.
##
## @experimental
## Statement lookup uses the merged schema, so a quest can read facts declared
## in another file of the same pack. [code]wyrd_commands.json[/code] is optional.

static func compile(
	files: PackedStringArray,
	pack_id: String,
	language_version: int,
	commands: WyrdCommandSchema,
	diagnostics: WyrdDiagnostics,
	note_path: String = "",
	skip_commands_note: bool = false
) -> WyrdLinkedPack:
	var parsed: Array = []
	for path in _unique(files):
		var source := WyrdSource.load_file(path)
		if source == null:
			diagnostics.add(WyrdDiagnostic.E_HEADER_MISSING, "could not read file", path, 1, 1)
			continue
		var tree := WyrdParser.new().parse(source, diagnostics)
		var schema := tree.schema if tree.schema != null else WyrdFactSchema.new()
		parsed.append({"path": path, "schema": schema, "source": source, "tree": tree})
	var merged := WyrdFactSchema.new()
	var fact_paths := {}
	for row in parsed:
		var path := str(row["path"])
		var schema: WyrdFactSchema = row["schema"]
		for fact in schema.entries:
			var prior := merged.conflict(fact)
			if prior != null:
				var prior_path := str(fact_paths.get(prior, ""))
				if prior_path != path:
					diagnostics.add(
						WyrdDiagnostic.E_FACT_REDECLARED,
						_redeclare(prior, fact, prior_path),
						path,
						fact.line,
						fact.col
					)
				continue
			merged.entries.append(fact)
			fact_paths[fact] = path
	var units: Array = []
	for row in parsed:
		var tree: WyrdNode = row["tree"]
		var source: WyrdSource = row["source"]
		tree.schema = merged
		var file := WyrdStatements.new().compile(source, tree, diagnostics)
		units.append({
			"file": file,
			"hash": WyrdExport.hash_text(source.text),
			"path": source.path,
			"text": source.text,
		})
	var linker := WyrdLinker.new()
	var pack := linker.link(units, merged, pack_id, language_version, commands, note_path, skip_commands_note, diagnostics)
	linker.finish_xref(pack, fact_paths)
	diagnostics.sort_items()
	return pack


static func read_commands(path: String, diagnostics: WyrdDiagnostics) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"schema": null, "skip_note": false}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not (parser.data is Dictionary):
		diagnostics.add(
			WyrdDiagnostic.E_COMMANDS_FILE,
			"could not read command schemas",
			path,
			1,
			1
		)
		return {"schema": null, "skip_note": true}
	var data: Dictionary = parser.data
	var names: Variant = data.get("commands", [])
	if not (names is Array):
		diagnostics.add(WyrdDiagnostic.E_COMMANDS_FILE, "could not read command schemas", path, 1, 1)
		return {"schema": null, "skip_note": true}
	var schema := WyrdCommandSchema.new()
	for name in names:
		schema.add_command(StringName(str(name)))
	return {"schema": schema, "skip_note": true}


static func pack_id_for(path: String) -> String:
	var name := path.get_file()
	if name.ends_with(".wyrd"):
		return name.trim_suffix(".wyrd")
	return name


static func _unique(files: PackedStringArray) -> PackedStringArray:
	var copy := files.duplicate()
	copy.sort()
	var out := PackedStringArray()
	var prev := ""
	for item in copy:
		if item.is_empty() or item == prev:
			continue
		out.append(item)
		prev = item
	return out


static func _redeclare(prior: WyrdFact, fact: WyrdFact, prior_path: String) -> String:
	if prior.key == fact.key:
		return "fact \"%s\" is also declared in %s:%d:%d" % [fact.key, prior_path, prior.line, prior.col]
	return "fact \"%s\" overlaps \"%s\" declared in %s:%d:%d" % [fact.key, prior.key, prior_path, prior.line, prior.col]
