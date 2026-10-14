class_name WyrdGolden
extends RefCounted

## Deterministic JSON dump of a token stream, block tree, and diagnostics.
##
## @experimental
## Object keys are sorted. [code]tools/update_goldens.sh[/code] writes the snapshots.
## CI compares them and does not regenerate them.

const CASES_DIR := "res://tests/golden/cases"
const EXPECTED_DIR := "res://tests/golden/expected"


static func compile(source: WyrdSource) -> Dictionary:
	var diagnostics := WyrdDiagnostics.new()
	var tokens := WyrdLexer.new().tokenize(source, diagnostics)
	var tree := WyrdParser.new().parse_tokens(source, tokens, diagnostics)
	return {
		"diagnostics": _diagnostics(diagnostics),
		"tokens": _tokens(tokens),
		"tree": _node(tree),
	}


static func to_json(data: Dictionary) -> String:
	return _encode(data, 0) + "\n"


static func write_expected() -> int:
	DirAccess.make_dir_recursive_absolute(EXPECTED_DIR)
	var names := case_names()
	for file_name in names:
		var base := file_name.trim_suffix(".wyrd")
		var source := WyrdSource.load_file("%s/%s" % [CASES_DIR, file_name])
		var body := to_json(compile(source))
		var out := FileAccess.open("%s/%s.json" % [EXPECTED_DIR, base], FileAccess.WRITE)
		out.store_string(body)
	return names.size()


static func case_names() -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	var dir := DirAccess.open(CASES_DIR)
	if dir == null:
		return names
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".wyrd"):
			names.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	names.sort()
	return names


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


static func _tokens(tokens: Array[WyrdToken]) -> Array:
	var rows: Array = []
	for token in tokens:
		rows.append({
			"col": token.col,
			"kind": String(token.kind),
			"line": token.line,
			"text": token.text,
		})
	return rows


static func _node(node: WyrdNode) -> Dictionary:
	var head: Array = []
	for token in node.head:
		head.append({
			"col": token.col,
			"kind": String(token.kind),
			"line": token.line,
			"text": token.text,
		})
	var children: Array = []
	for child in node.children:
		children.append(_node(child))
	var data := {
		"children": children,
		"end_col": node.end_col,
		"end_line": node.end_line,
		"head": head,
		"keyword": node.keyword,
		"kind": String(node.kind),
		"line_tag": node.line_tag,
		"start_col": node.start_col,
		"start_line": node.start_line,
		"title": node.title,
	}
	if node.kind == &"facts":
		data["entries"] = _entries(node.entries)
	return data


static func _entries(entries: Array[WyrdFact]) -> Array:
	var rows: Array = []
	for fact in entries:
		var segments: Array = []
		for segment in fact.segments:
			segments.append(segment)
		rows.append({
			"col": fact.col,
			"doc": fact.doc,
			"invalidate": String(fact.invalidate),
			"invalidate_arg": fact.invalidate_arg,
			"key": fact.key,
			"line": fact.line,
			"origin": String(fact.origin),
			"pattern": fact.is_pattern(),
			"resolver": fact.resolver,
			"segments": segments,
			"type": String(fact.type_name),
		})
	return rows


static func _encode(value: Variant, indent: int) -> String:
	if value == null:
		return "null"
	if value is bool:
		return "true" if value else "false"
	if value is int:
		return str(value)
	if value is float:
		return str(value)
	if value is String:
		return _string(value)
	if value is Array:
		return _array(value, indent)
	if value is Dictionary:
		return _dict(value, indent)
	return _string(str(value))


static func _dict(dict: Dictionary, indent: int) -> String:
	var keys: PackedStringArray = PackedStringArray()
	for key in dict.keys():
		keys.append(str(key))
	keys.sort()
	if keys.is_empty():
		return "{}"
	var pad := "  ".repeat(indent + 1)
	var lines: PackedStringArray = PackedStringArray()
	for i in keys.size():
		var key := keys[i]
		var line := "%s%s: %s" % [pad, _string(key), _encode(dict[key], indent + 1)]
		if i < keys.size() - 1:
			line += ","
		lines.append(line)
	return "{\n" + "\n".join(lines) + "\n" + "  ".repeat(indent) + "}"


static func _array(items: Array, indent: int) -> String:
	if items.is_empty():
		return "[]"
	var pad := "  ".repeat(indent + 1)
	var lines: PackedStringArray = PackedStringArray()
	for i in items.size():
		var line := "%s%s" % [pad, _encode(items[i], indent + 1)]
		if i < items.size() - 1:
			line += ","
		lines.append(line)
	return "[\n" + "\n".join(lines) + "\n" + "  ".repeat(indent) + "]"


static func _string(value: String) -> String:
	var out := "\""
	for i in value.length():
		var ch := value[i]
		var code := value.unicode_at(i)
		if ch == "\\":
			out += "\\\\"
		elif ch == "\"":
			out += "\\\""
		elif ch == "\n":
			out += "\\n"
		elif ch == "\r":
			out += "\\r"
		elif ch == "\t":
			out += "\\t"
		elif code < 32:
			out += "\\u%04x" % code
		else:
			out += ch
	return out + "\""
