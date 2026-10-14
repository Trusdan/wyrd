class_name WyrdTagLines
extends RefCounted

## Writes missing [code]#line:[/code] ids. The only command that edits source.
##
## @experimental
## Ids are lowercase hex from [WyrdHash] and [WyrdRng], four characters, longer
## on a pack collision. An existing id is never changed. Every other byte stays,
## including indent, comments, and CRLF. A second run changes nothing.

const _SKIP := {
	"*": true,
	"-": true,
	"->": true,
	"facts": true,
	"journal": true,
	"language": true,
	"on_abort": true,
	"on_empty": true,
	"outcome": true,
	"quest": true,
	"redirect": true,
	"requires": true,
	"scene": true,
	"slot": true,
	"stage": true,
	"start": true,
	"variant": true,
	"waits_until": true,
	"when": true,
	"~": true,
}


static func tag_files(files: PackedStringArray, pack_id: String, dry_run: bool) -> Dictionary:
	var taken := {}
	var notes: PackedStringArray = PackedStringArray()
	var parsed: Array = []
	for path in files:
		var raw := _read(path)
		if raw.is_empty() and not FileAccess.file_exists(path):
			return {"exit_code": 1, "notes": notes, "output": "wyrd: could not read %s\n" % path}
		var source := WyrdSource.new(path, raw)
		var tree := WyrdParser.new().parse(source, WyrdDiagnostics.new())
		_gather_tags(tree, taken)
		parsed.append({"path": path, "raw": raw, "tree": tree})
	var changed := 0
	for row in parsed:
		var sites := _sites(row["tree"])
		var edits: Array = []
		for ordinal in sites.size():
			var site: Dictionary = sites[ordinal]
			if not str(site["tag"]).is_empty():
				continue
			var id := make_id(pack_id, str(row["path"]), str(site["owner"]), ordinal, taken)
			taken[id] = true
			edits.append({"id": id, "line": int(site["line"])})
			notes.append("%s:%d: + #line:%s" % [str(row["path"]), int(site["line"]), id])
		if edits.is_empty():
			continue
		var next := _apply(str(row["raw"]), edits)
		changed += 1
		if not dry_run:
			_write(str(row["path"]), next)
	var output := ""
	if not notes.is_empty():
		output = "\n".join(notes) + "\n"
	return {"changed": changed, "exit_code": 0, "notes": notes, "output": output}


static func tag_text(text: String, path: String, pack_id: String, taken: Dictionary) -> Dictionary:
	var source := WyrdSource.new(path, text)
	var tree := WyrdParser.new().parse(source, WyrdDiagnostics.new())
	_gather_tags(tree, taken)
	var sites := _sites(tree)
	var edits: Array = []
	var notes: PackedStringArray = PackedStringArray()
	for ordinal in sites.size():
		var site: Dictionary = sites[ordinal]
		if not str(site["tag"]).is_empty():
			continue
		var id := make_id(pack_id, path, str(site["owner"]), ordinal, taken)
		taken[id] = true
		edits.append({"id": id, "line": int(site["line"])})
		notes.append("%s:%d: + #line:%s" % [path, int(site["line"]), id])
	return {"notes": notes, "text": _apply(text, edits)}


static func make_id(pack_id: String, path: String, owner: String, ordinal: int, taken: Dictionary) -> String:
	var seed := WyrdHash.of_string_name(StringName("%s\n%s\n%s\n%d" % [pack_id, path, owner, ordinal]))
	var rng := WyrdRng.new(seed)
	var roll := rng.randi()
	var width := 4
	for _guard in 32:
		var body := _hex(roll, width)
		if not taken.has(body):
			return body
		width += 1
		if width > 8:
			roll = rng.randi()
			width = 4
	return _hex(rng.randi(), 8)


static func _sites(tree: WyrdNode) -> Array:
	var sites: Array = []
	_walk(tree, "", "", sites)
	return sites


static func _walk(node: WyrdNode, kind: String, owner: String, sites: Array) -> void:
	var next_kind := kind
	var next_owner := owner
	if node.keyword == "quest":
		next_kind = "quest"
		next_owner = _dotted(node)
	elif node.keyword == "scene":
		next_kind = "scene"
		next_owner = _dotted(node)
	elif _is_site(node, kind):
		sites.append({"line": node.start_line, "owner": owner, "tag": node.line_tag})
	for child in node.children:
		_walk(child, next_kind, next_owner, sites)


static func _is_site(node: WyrdNode, kind: String) -> bool:
	if kind == "quest" and node.keyword == "journal":
		return true
	if kind != "scene":
		return false
	if node.keyword == "when":
		return true
	if node.keyword == "*":
		for token in node.head:
			if token.kind == &"lbracket":
				return true
		return false
	if _SKIP.has(node.keyword):
		return false
	for token in node.head:
		if token.kind == &"colon":
			return true
	return false


static func _dotted(node: WyrdNode) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var pending := false
	for token in node.head:
		if token.kind == &"ident":
			parts.append(token.text)
			pending = false
			continue
		if token.kind == &"dot":
			pending = true
			continue
		break
	if pending:
		return ""
	return ".".join(parts)


static func _gather_tags(node: WyrdNode, taken: Dictionary) -> void:
	if not node.line_tag.is_empty():
		taken[node.line_tag] = true
	for child in node.children:
		_gather_tags(child, taken)


static func _apply(text: String, edits: Array) -> String:
	if edits.is_empty():
		return text
	var ends := text.ends_with("\n")
	var lines := text.split("\n")
	if ends and not lines.is_empty():
		lines.remove_at(lines.size() - 1)
	for edit in edits:
		var index := int(edit["line"]) - 1
		if index < 0 or index >= lines.size():
			continue
		lines[index] = _insert(str(lines[index]), str(edit["id"]))
	var rebuilt := "\n".join(lines)
	if ends:
		rebuilt += "\n"
	return rebuilt


static func _insert(line: String, id: String) -> String:
	var cr := ""
	var body := line
	if body.ends_with("\r"):
		cr = "\r"
		body = body.substr(0, body.length() - 1)
	var at := _comment_at(body)
	if at < 0:
		at = body.length()
	else:
		while at > 0 and (body[at - 1] == " " or body[at - 1] == "\t"):
			at -= 1
	return body.substr(0, at) + " #line:" + id + body.substr(at) + cr


static func _comment_at(body: String) -> int:
	var quote := false
	var i := 0
	while i < body.length():
		var ch := body[i]
		if ch == "\"":
			quote = not quote
			if quote and i > 0 and body[i - 1] == "\\":
				quote = true
		elif not quote and ch == "/" and i + 1 < body.length() and body[i + 1] == "/":
			return i
		i += 1
	return -1


static func _hex(value: int, width: int) -> String:
	var digits := "0123456789abcdef"
	var out := ""
	var bits := value
	for _i in width:
		out = digits[bits & 0xF] + out
		bits >>= 4
	return out


static func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var bytes := file.get_buffer(file.get_length())
	return bytes.get_string_from_utf8()


static func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_buffer(text.to_utf8_buffer())
