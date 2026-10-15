class_name WyrdRoleGolden
extends RefCounted

## JSON dump of compiled role blocks.
##
## @experimental
## Eligibility keeps reads, specificity, and [code]uses_chance[/code].
## Opcode listings stay in the condition goldens.

const CASES_DIR := "res://tests/golden/roles"
const EXPECTED_DIR := "res://tests/golden/roles/expected"


static func compile(source: WyrdSource) -> Dictionary:
	var diagnostics := WyrdDiagnostics.new()
	var tree := WyrdParser.new().parse(source, diagnostics)
	var file := WyrdStatements.new().compile(source, tree, diagnostics)
	var roles: Array = []
	for role in file.roles:
		roles.append(_role(role))
	return {"diagnostics": _diagnostics(diagnostics), "roles": roles}


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


static func _role(role: WyrdRoleDef) -> Dictionary:
	var kinds: Array = []
	for kind in role.kinds:
		kinds.append(String(kind))
	return {
		"default_holder": role.default_holder,
		"eligibility": _cond(role.eligibility),
		"eligibility_text": role.eligibility_text,
		"id": role.id,
		"kinds": kinds,
		"reads": _reads(role.reads),
		"scope": role.scope,
		"scope_id": role.scope_id,
		"span": role.span_data(),
		"strategy": role.strategy,
		"succession": role.succession_text,
		"succession_arg": role.succession_arg,
		"vacancy": role.vacancy,
		"visibility": role.visibility,
	}


static func _cond(cond: Variant) -> Variant:
	if cond == null or not (cond is WyrdCompiledCondition):
		return null
	var compiled := cond as WyrdCompiledCondition
	return {
		"reads": _reads(compiled.reads),
		"source_span": compiled.source_span.duplicate(),
		"specificity": compiled.specificity,
		"uses_chance": compiled.uses_chance,
	}


static func _reads(reads: Array) -> Array:
	var rows: Array = []
	for item in reads:
		rows.append(String(item))
	return rows


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
