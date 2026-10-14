class_name WyrdConditionGolden
extends RefCounted

## JSON dump of condition directives and prose interpolation in a `.wyrd` file.
##
## @experimental
## Directives live in comments: `@context`, `@day`, `@when`, and `@value`.
## They are not grammar. Block goldens stay in `tests/golden/cases`.

const CASES_DIR := "res://tests/golden/conditions"
const EXPECTED_DIR := "res://tests/golden/conditions/expected"


static func compile(source: WyrdSource) -> Dictionary:
	var file_diag := WyrdDiagnostics.new()
	var tokens := WyrdLexer.new().tokenize(source, file_diag)
	var tree := WyrdParser.new().parse_tokens(source, tokens, file_diag)
	var schema := tree.schema if tree.schema != null else WyrdFactSchema.new()
	var lines := source.text.split("\n")
	var context := WyrdCondition.CONTEXT_STORYLET
	var day := WyrdCondition.MINUTES_PER_DAY
	var contexts: Array[StringName] = []
	var days: Array[int] = []
	contexts.resize(lines.size())
	days.resize(lines.size())
	var conditions: Array = []
	for i in lines.size():
		var directive := _directive(lines[i])
		if directive["kind"] == "context":
			context = StringName(directive["text"])
		elif directive["kind"] == "day":
			day = int(directive["text"])
		contexts[i] = context
		days[i] = day
		if directive["kind"] != "when" and directive["kind"] != "value":
			continue
		var diag := WyrdDiagnostics.new()
		var compiler := WyrdCondition.new()
		var compiled := compiler.compile(
			directive["text"],
			schema,
			diag,
			source.path,
			i + 1,
			int(directive["col"]),
			context,
			day,
			null,
			directive["kind"] == "when"
		)
		compiler.ast.payload = compiled
		conditions.append({
			"ast": compiler.ast.to_data(),
			"diagnostics": _diagnostics(diag),
			"expr": directive["text"],
			"kind": directive["kind"],
			"line": i + 1,
		})
	var interps: Array = []
	var seen: Dictionary = {}
	for token in tokens:
		if token.kind != &"interp" or seen.has(token.line):
			continue
		seen[token.line] = true
		var line_tokens: Array[WyrdToken] = []
		for item in tokens:
			if item.line == token.line and item.kind != &"eof":
				line_tokens.append(item)
		var index := token.line - 1
		var diag := WyrdDiagnostics.new()
		var root := WyrdInterp.new().compile_line(
			line_tokens,
			schema,
			diag,
			source.path,
			contexts[index] if index < contexts.size() else WyrdCondition.CONTEXT_STORYLET,
			days[index] if index < days.size() else WyrdCondition.MINUTES_PER_DAY
		)
		interps.append({
			"ast": root.to_data(),
			"diagnostics": _diagnostics(diag),
			"line": token.line,
		})
	return {
		"conditions": conditions,
		"diagnostics": _diagnostics(file_diag),
		"interps": interps,
	}


static func write_expected() -> int:
	DirAccess.make_dir_recursive_absolute(EXPECTED_DIR)
	var names := case_names()
	for file_name in names:
		var base := file_name.trim_suffix(".wyrd")
		var source := WyrdSource.load_file("%s/%s" % [CASES_DIR, file_name])
		var body := WyrdGolden.to_json(compile(source))
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


static func _directive(line: String) -> Dictionary:
	var trimmed := line.strip_edges()
	if not trimmed.begins_with("//"):
		return {"kind": ""}
	var body := trimmed.substr(2).strip_edges()
	var names: PackedStringArray = PackedStringArray(["context", "day", "when", "value"])
	for name in names:
		var tag := "@" + name
		if body != tag and not body.begins_with(tag + " ") and not body.begins_with(tag + "\t"):
			continue
		var at := line.find(tag)
		var rest := line.substr(at + tag.length())
		var skip := 0
		while skip < rest.length() and (rest[skip] == " " or rest[skip] == "\t"):
			skip += 1
		return {"col": at + tag.length() + skip + 1, "kind": name, "text": rest.substr(skip).strip_edges()}
	return {"kind": ""}


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
