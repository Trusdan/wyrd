extends GutTest

## Proposals match check's missing ids. Document sites stay optional.


const _ROOT := "user://tag_parity"


func after_each() -> void:
	_wipe(_ROOT)


func test_proposals_match_missing_line_ids() -> void:
	var files := _tracked_wyrd_files()
	assert_gt(files.size(), 0)
	var mismatches := PackedStringArray()
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		mismatches.append_array(_proposal_mismatch(path, text, path, "as-is"))
		var stripped := _strip_line_tags(text)
		var copy := _ROOT + "/" + path.trim_prefix("res://")
		_write(copy, stripped)
		mismatches.append_array(_proposal_mismatch(path, stripped, copy, "stripped"))
	assert_eq(mismatches, PackedStringArray(), "\n".join(mismatches))


func test_gullhaven_single_file_sites_match_the_pack() -> void:
	var spec := load("res://example/content/gullhaven/harbor.wyrdmanifest.tres") as WyrdContentManifest
	var diagnostics := WyrdDiagnostics.new()
	var parsed: Array = []
	for listed in spec.files:
		var path := str(listed)
		var source := WyrdSource.load_file(path)
		var tree := WyrdParser.new().parse(source, diagnostics)
		var schema := tree.schema if tree.schema != null else WyrdFactSchema.new()
		parsed.append({"path": path, "schema": schema, "source": source, "tree": tree})
	var merged := WyrdFactSchema.new()
	for row in parsed:
		var schema: WyrdFactSchema = row["schema"]
		for fact in schema.entries:
			if merged.conflict(fact) != null:
				continue
			merged.entries.append(fact)
	var events := WyrdPack._merge_events(parsed, diagnostics)
	var mismatches := PackedStringArray()
	for row in parsed:
		var source: WyrdSource = row["source"]
		var alone_source := WyrdSource.new(source.path, source.text)
		var alone_tree := WyrdParser.new().parse(alone_source, WyrdDiagnostics.new())
		var alone := WyrdStatements.new()
		alone.compile(alone_source, alone_tree, WyrdDiagnostics.new())
		var tree: WyrdNode = row["tree"]
		tree.schema = merged
		var packed := WyrdStatements.new()
		packed.compile(source, tree, WyrdDiagnostics.new(), events)
		var left := _required_lines(alone.line_sites)
		var right := _required_lines(packed.line_sites)
		if left != right:
			mismatches.append("%s alone=%s pack=%s" % [source.path, str(left), str(right)])
	assert_eq(mismatches, PackedStringArray(), "\n".join(mismatches))


func _proposal_mismatch(label: String, text: String, path: String, pass_name: String) -> PackedStringArray:
	var tagged: Dictionary = WyrdTagLines.tag_files(PackedStringArray([path]), "harbor", true)
	assert_eq(int(tagged["exit_code"]), 0, path)
	var proposed := {}
	var note_line := RegEx.new()
	note_line.compile(":(\\d+): \\+ #line:")
	for note in tagged["notes"]:
		var found := note_line.search(str(note))
		assert_ne(found, null, str(note))
		proposed[int(found.get_string(1))] = true
	var diagnostics := WyrdDiagnostics.new()
	WyrdPack.compile(PackedStringArray([path]), "harbor", 1, null, diagnostics)
	var missing := {}
	var other := {}
	for item in diagnostics.items:
		if item.severity != WyrdDiagnostic.SEVERITY_ERROR:
			continue
		if item.code == WyrdDiagnostic.E_LINE_ID_MISSING:
			missing[item.line] = true
		else:
			other[item.line] = true
	var documents := _document_lines(text, path)
	var wanted := PackedStringArray()
	for line in missing:
		if other.has(line):
			continue
		wanted.append(str(int(line)))
	var got := PackedStringArray()
	for line in proposed:
		if documents.has(line) or other.has(line):
			continue
		got.append(str(int(line)))
	wanted.sort()
	got.sort()
	if wanted == got:
		return PackedStringArray()
	return PackedStringArray(["%s (%s): tag-lines %s check %s" % [label, pass_name, str(got), str(wanted)]])


func _required_lines(sites: Array) -> PackedStringArray:
	var lines := PackedStringArray()
	for site in sites:
		var row: Dictionary = site
		if not bool(row["required"]):
			continue
		lines.append(str(int(row["line"])))
	lines.sort()
	return lines


func _document_lines(text: String, path: String) -> Dictionary:
	var source := WyrdSource.new(path, text)
	var tree := WyrdParser.new().parse(source, WyrdDiagnostics.new())
	var lines := {}
	_doc_walk(tree, "", lines)
	return lines


func _doc_walk(node: WyrdNode, kind: String, lines: Dictionary) -> void:
	var next := kind
	if node.keyword == "document" and not _periodic(node):
		next = "document"
		lines[node.start_line] = true
	elif kind == "document" and node.keyword == "page":
		next = "docpage"
	elif kind == "docpage":
		lines[node.start_line] = true
	for child in node.children:
		_doc_walk(child, next, lines)


func _periodic(node: WyrdNode) -> bool:
	for token in node.head:
		if token.kind != &"ident":
			continue
		if token.text == "publishes_by" or token.text == "every" or token.text == "delay":
			return true
	return false


func _strip_line_tags(text: String) -> String:
	var expression := RegEx.new()
	expression.compile("#line:[A-Za-z0-9_]+")
	return expression.sub(text, "", true)


func _tracked_wyrd_files() -> PackedStringArray:
	var files := PackedStringArray()
	_scan("res://example", files)
	_scan("res://tests", files)
	_scan("res://tools", files)
	files.sort()
	return files


func _scan(root: String, files: PackedStringArray) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not name.begins_with("."):
			var path := root.path_join(name)
			if dir.current_is_dir():
				if name != "gut":
					_scan(path, files)
			elif name.ends_with(".wyrd"):
				files.append(path)
		name = dir.get_next()
	dir.list_dir_end()


func _write(path: String, body: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, path)
	file.store_string(body)


func _wipe(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		return
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name != "." and name != "..":
			_wipe(path.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
