class_name WyrdApiGolden
extends RefCounted

## Golden snapshot of the stable API surface.
##
## CI compares [code]tests/golden/api/expected/stable_api.json[/code].
## [code]tools/update_goldens.sh[/code] is the only writer.

const EXPECTED_PATH := "res://tests/golden/api/expected/stable_api.json"
const _FACADE_PATH := "res://addons/wyrd/runtime/wyrd.gd"
const _LANGUAGE_SOURCE := "language 1\n"

## Scripts the snapshot covers. Member rows are the facade's typed declarations,
## read off [code]wyrd.gd[/code]. [code]trace[/code], [code]debug[/code], and
## [code]coverage[/code] stay out: those surfaces stay experimental after 1.0.
const STABLE_CLASSES := [
	{"name": "Wyrd", "path": _FACADE_PATH},
	{"name": "WyrdFactStore", "path": "res://addons/wyrd/runtime/facts/wyrd_fact_store.gd"},
	{"name": "WyrdEvents", "path": "res://addons/wyrd/runtime/wyrd_events.gd"},
	{"name": "WyrdDeedLog", "path": "res://addons/wyrd/runtime/deeds/wyrd_deed_log.gd"},
	{"name": "WyrdSocial", "path": "res://addons/wyrd/runtime/social/wyrd_social.gd"},
	{"name": "WyrdRumor", "path": "res://addons/wyrd/runtime/rumor/wyrd_rumor.gd"},
	{"name": "WyrdPublish", "path": "res://addons/wyrd/runtime/publish/wyrd_publish.gd"},
	{"name": "WyrdRoles", "path": "res://addons/wyrd/runtime/roles/wyrd_roles.gd"},
	{"name": "WyrdTopics", "path": "res://addons/wyrd/runtime/topics/wyrd_topics.gd"},
	{"name": "WyrdDocuments", "path": "res://addons/wyrd/runtime/documents/wyrd_documents.gd"},
	{"name": "WyrdQuestRunner", "path": "res://addons/wyrd/runtime/quests/wyrd_quest_runner.gd"},
	{"name": "WyrdSceneRunner", "path": "res://addons/wyrd/runtime/scenes/wyrd_scene_runner.gd"},
	{"name": "WyrdStoryletDeck", "path": "res://addons/wyrd/runtime/storylets/wyrd_storylet_deck.gd"},
	{"name": "WyrdSequences", "path": "res://addons/wyrd/runtime/quests/wyrd_sequences.gd"},
	{"name": "WyrdDirector", "path": "res://addons/wyrd/runtime/storylets/wyrd_director.gd"},
	{"name": "WyrdGenerator", "path": "res://addons/wyrd/runtime/generator/wyrd_generator.gd"},
	{"name": "WyrdAI", "path": "res://addons/wyrd/runtime/ai/wyrd_ai.gd"},
	{"name": "WyrdWorldAdapter", "path": "res://addons/wyrd/runtime/adapters/wyrd_world_adapter.gd"},
	{"name": "WyrdInventoryAdapter", "path": "res://addons/wyrd/runtime/adapters/wyrd_inventory_adapter.gd"},
	{"name": "WyrdSpatialAdapter", "path": "res://addons/wyrd/runtime/adapters/wyrd_spatial_adapter.gd"},
	{"name": "WyrdTimeAdapter", "path": "res://addons/wyrd/runtime/adapters/wyrd_time_adapter.gd"},
	{"name": "WyrdActionAdapter", "path": "res://addons/wyrd/runtime/adapters/wyrd_action_adapter.gd"},
	{"name": "WyrdElectionAdapter", "path": "res://addons/wyrd/runtime/adapters/wyrd_election_adapter.gd"},
	{"name": "WyrdAIProvider", "path": "res://addons/wyrd/runtime/adapters/wyrd_ai_provider.gd"},
	{"name": "WyrdSkillAdapter", "path": "res://addons/wyrd/runtime/adapters/wyrd_skill_adapter.gd"},
	{"name": "WyrdConfig", "path": "res://addons/wyrd/runtime/wyrd_config.gd"},
	{"name": "WyrdLoadReport", "path": "res://addons/wyrd/runtime/wyrd_load_report.gd"},
	{"name": "WyrdLineView", "path": "res://addons/wyrd/runtime/scenes/wyrd_line_view.gd"},
	{"name": "WyrdContentManifest", "path": "res://addons/wyrd/compiler/wyrd_content_manifest.gd"},
	{"name": "WyrdCommand", "path": "res://addons/wyrd/runtime/adapters/wyrd_command.gd"},
	{"name": "WyrdCommandResult", "path": "res://addons/wyrd/runtime/adapters/wyrd_command_result.gd"},
	{"name": "WyrdCommandSchema", "path": "res://addons/wyrd/runtime/adapters/wyrd_command_schema.gd"},
	{"name": "WyrdEntityFilter", "path": "res://addons/wyrd/runtime/adapters/wyrd_entity_filter.gd"},
	{"name": "WyrdSkillCheck", "path": "res://addons/wyrd/runtime/adapters/wyrd_skill_check.gd"},
]

## Facade properties whose scripts are in [constant STABLE_CLASSES].
const FACADE_MEMBERS: PackedStringArray = [
	"facts",
	"events",
	"deeds",
	"social",
	"rumors",
	"publish",
	"roles",
	"topics",
	"documents",
	"quests",
	"dialogue",
	"storylets",
	"sequences",
	"director",
	"generator",
	"ai",
]


static func build() -> Dictionary:
	var covered := {}
	var classes := {}
	for row in STABLE_CLASSES:
		var reported := str(row["name"])
		var path := str(row["path"])
		covered[reported] = true
		var script := load(path) as Script
		var entry := reflect_script(script)
		var flags := member_flags(path)
		entry["experimental"] = bool(flags["class"])
		_apply_member_flags(entry, flags)
		entry["path"] = path
		classes[reported] = entry
	var known := _known_classes()
	var found := {}
	for reported in classes.keys():
		var entry: Dictionary = classes[reported]
		for method in entry["methods"]:
			_collect_signature(found, covered, known, method, true)
		for sig in entry["signals"]:
			_collect_signature(found, covered, known, sig, false)
		for prop in entry["properties"]:
			_collect_named(found, covered, known, str(prop.get("class", "")))
	var unlisted: Array = found.keys()
	unlisted.sort()
	return {
		"classes": classes,
		"language": _language_version(),
		"save_schema": _save_schema(),
		"unlisted_types": unlisted,
	}


static func reflect_script(script: Script) -> Dictionary:
	if script == null:
		return {"methods": [], "properties": [], "signals": []}
	return {
		"methods": _methods(script),
		"properties": _properties(script),
		"signals": _signals(script),
	}


static func write_expected() -> int:
	DirAccess.make_dir_recursive_absolute(EXPECTED_PATH.get_base_dir())
	var out := FileAccess.open(EXPECTED_PATH, FileAccess.WRITE)
	if out == null:
		push_error("WyrdApiGolden: could not write %s" % EXPECTED_PATH)
		return 0
	out.store_string(to_json(build()))
	return 1


static func to_json(data: Dictionary) -> String:
	return JSON.stringify(data, "\t", true) + "\n"


## Differences between two snapshots, or two [method reflect_script] results.
## Each line reads [code]left -> right[/code]. Empty when the two sides match.
static func compare(left: Dictionary, right: Dictionary) -> PackedStringArray:
	var diffs := PackedStringArray()
	if left.has("classes") or right.has("classes") or left.has("language") or right.has("language"):
		_compare_snapshot(left, right, diffs)
	else:
		_compare_class("", left, right, diffs)
	diffs.sort()
	return diffs


static func _compare_snapshot(left: Dictionary, right: Dictionary, diffs: PackedStringArray) -> void:
	_compare_scalar(diffs, "language", left.get("language", null), right.get("language", null))
	_compare_scalar(diffs, "save_schema", left.get("save_schema", null), right.get("save_schema", null))
	var left_types: Array = left.get("unlisted_types", [])
	var right_types: Array = right.get("unlisted_types", [])
	if _join(left_types) != _join(right_types):
		diffs.append("unlisted_types: %s -> %s" % [_join(left_types), _join(right_types)])
	var left_classes: Dictionary = left.get("classes", {})
	var right_classes: Dictionary = right.get("classes", {})
	var names := {}
	for key in left_classes.keys():
		names[str(key)] = true
	for key in right_classes.keys():
		names[str(key)] = true
	var ordered: Array = names.keys()
	ordered.sort()
	for reported in ordered:
		if not left_classes.has(reported):
			diffs.append("class %s: only on the right" % reported)
			continue
		if not right_classes.has(reported):
			diffs.append("class %s: only on the left" % reported)
			continue
		_compare_class("%s." % reported, left_classes[reported], right_classes[reported], diffs)


static func _compare_class(prefix: String, left: Dictionary, right: Dictionary, diffs: PackedStringArray) -> void:
	if left.has("experimental") or right.has("experimental"):
		_compare_scalar(diffs, "%sexperimental" % prefix, left.get("experimental", null), right.get("experimental", null))
	if left.has("path") or right.has("path"):
		_compare_scalar(diffs, "%spath" % prefix, left.get("path", ""), right.get("path", ""))
	_compare_callables(diffs, prefix, left.get("methods", []), right.get("methods", []), true)
	_compare_callables(diffs, prefix, left.get("signals", []), right.get("signals", []), false)
	_compare_properties(diffs, prefix, left.get("properties", []), right.get("properties", []))


static func _compare_callables(diffs: PackedStringArray, prefix: String, left_rows: Array, right_rows: Array, with_return: bool) -> void:
	var left := _by_name(left_rows)
	var right := _by_name(right_rows)
	var names := {}
	for key in left.keys():
		names[str(key)] = true
	for key in right.keys():
		names[str(key)] = true
	var ordered: Array = names.keys()
	ordered.sort()
	for method_name in ordered:
		var label := "%s%s" % [prefix, method_name]
		if not left.has(method_name):
			diffs.append("%s: only on the right" % label)
			continue
		if not right.has(method_name):
			diffs.append("%s: only on the left" % label)
			continue
		var left_method: Dictionary = left[method_name]
		var right_method: Dictionary = right[method_name]
		_compare_args(diffs, label, left_method, right_method, with_return)


static func _compare_args(diffs: PackedStringArray, label: String, left_method: Dictionary, right_method: Dictionary, with_return: bool) -> void:
	var left_args: Array = left_method.get("args", [])
	var right_args: Array = right_method.get("args", [])
	var count: int = maxi(left_args.size(), right_args.size())
	for index in count:
		var number := index + 1
		if index >= left_args.size():
			diffs.append("%s: argument %d only on the right (%s)" % [label, number, right_args[index].get("name", "")])
			continue
		if index >= right_args.size():
			diffs.append("%s: argument %d only on the left (%s)" % [label, number, left_args[index].get("name", "")])
			continue
		var left_arg: Dictionary = left_args[index]
		var right_arg: Dictionary = right_args[index]
		if str(left_arg.get("name", "")) != str(right_arg.get("name", "")):
			diffs.append("%s: argument %d name %s -> %s" % [label, number, left_arg.get("name", ""), right_arg.get("name", "")])
		if str(left_arg.get("type", "")) != str(right_arg.get("type", "")):
			diffs.append("%s: argument %d type %s -> %s" % [label, number, left_arg.get("type", ""), right_arg.get("type", "")])
		if str(left_arg.get("class", "")) != str(right_arg.get("class", "")):
			diffs.append("%s: argument %d class %s -> %s" % [label, number, left_arg.get("class", ""), right_arg.get("class", "")])
		if with_return:
			var left_default := _default_at(left_method, index)
			var right_default := _default_at(right_method, index)
			if left_default != right_default:
				diffs.append("%s: argument %d default %s -> %s" % [label, number, _shown_default(left_default), _shown_default(right_default)])
		if with_return:
			var left_return: Dictionary = left_method.get("return", {})
			var right_return: Dictionary = right_method.get("return", {})
			if str(left_return.get("type", "")) != str(right_return.get("type", "")):
				diffs.append("%s: return type %s -> %s" % [label, left_return.get("type", ""), right_return.get("type", "")])
			if str(left_return.get("class", "")) != str(right_return.get("class", "")):
				diffs.append("%s: return class %s -> %s" % [label, left_return.get("class", ""), right_return.get("class", "")])
		if left_method.has("experimental") or right_method.has("experimental"):
			_compare_scalar(diffs, "%s experimental" % label, left_method.get("experimental", null), right_method.get("experimental", null))


static func _compare_properties(diffs: PackedStringArray, prefix: String, left_rows: Array, right_rows: Array) -> void:
	var left := _by_name(left_rows)
	var right := _by_name(right_rows)
	var names := {}
	for key in left.keys():
		names[str(key)] = true
	for key in right.keys():
		names[str(key)] = true
	var ordered: Array = names.keys()
	ordered.sort()
	for prop_name in ordered:
		var label := "%s%s" % [prefix, prop_name]
		if not left.has(prop_name):
			diffs.append("%s: only on the right" % label)
			continue
		if not right.has(prop_name):
			diffs.append("%s: only on the left" % label)
			continue
		var left_prop: Dictionary = left[prop_name]
		var right_prop: Dictionary = right[prop_name]
		if str(left_prop.get("type", "")) != str(right_prop.get("type", "")):
			diffs.append("%s: type %s -> %s" % [label, left_prop.get("type", ""), right_prop.get("type", "")])
		if str(left_prop.get("class", "")) != str(right_prop.get("class", "")):
			diffs.append("%s: class %s -> %s" % [label, left_prop.get("class", ""), right_prop.get("class", "")])
		if left_prop.has("experimental") or right_prop.has("experimental"):
			_compare_scalar(diffs, "%s experimental" % label, left_prop.get("experimental", null), right_prop.get("experimental", null))


static func _default_at(method: Dictionary, index: int) -> String:
	var args: Array = method.get("args", [])
	var defaults: Array = method.get("defaults", [])
	var first := args.size() - defaults.size()
	if index < first or index >= args.size():
		return ""
	return str(defaults[index - first])


static func _shown_default(value: String) -> String:
	if value.is_empty():
		return "(none)"
	return value


static func _compare_scalar(diffs: PackedStringArray, label: String, left: Variant, right: Variant) -> void:
	var left_text := _text(left)
	var right_text := _text(right)
	if left_text != right_text:
		diffs.append("%s: %s -> %s" % [label, left_text, right_text])


static func _text(value: Variant) -> String:
	if value == null:
		return "null"
	if typeof(value) == TYPE_BOOL:
		return "true" if value else "false"
	if typeof(value) == TYPE_FLOAT:
		var number := float(value)
		if number == floor(number) and not is_inf(number) and not is_nan(number):
			return str(int(number))
	return str(value)


static func _join(values: Array) -> String:
	var parts := PackedStringArray()
	for item in values:
		parts.append(str(item))
	return ", ".join(parts)


static func _by_name(rows: Array) -> Dictionary:
	var indexed := {}
	for row in rows:
		indexed[str(row.get("name", ""))] = row
	return indexed


static func _methods(script: Script) -> Array:
	var rows: Array = []
	var seen := {}
	for method in script.get_script_method_list():
		var name := str(method.get("name", ""))
		if name.is_empty() or name.begins_with("_") or seen.has(name):
			continue
		seen[name] = true
		var args: Array = []
		for arg in method.get("args", []):
			args.append(_arg(arg))
		var defaults: Array = []
		for item in method.get("default_args", []):
			defaults.append(var_to_str(item))
		rows.append({
			"args": args,
			"defaults": defaults,
			"name": name,
			"return": _typed(method.get("return", {})),
		})
	_sort_by_name(rows)
	return rows


static func _signals(script: Script) -> Array:
	var rows: Array = []
	var seen := {}
	for sig in script.get_script_signal_list():
		var name := str(sig.get("name", ""))
		if name.is_empty() or name.begins_with("_") or seen.has(name):
			continue
		seen[name] = true
		var args: Array = []
		for arg in sig.get("args", []):
			args.append(_arg(arg))
		rows.append({"args": args, "name": name})
	_sort_by_name(rows)
	return rows


static func _properties(script: Script) -> Array:
	var rows: Array = []
	var seen := {}
	for prop in script.get_script_property_list():
		var usage := int(prop.get("usage", 0))
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var name := str(prop.get("name", ""))
		if name.is_empty() or name.begins_with("_") or seen.has(name):
			continue
		seen[name] = true
		rows.append({
			"class": _info_class(prop),
			"name": name,
			"type": _info_type(prop),
		})
	_sort_by_name(rows)
	return rows


static func _arg(info: Dictionary) -> Dictionary:
	return {
		"class": _info_class(info),
		"name": str(info.get("name", "")),
		"type": _info_type(info),
	}


static func _typed(info: Dictionary) -> Dictionary:
	return {
		"class": _info_class(info),
		"type": _info_type(info),
	}


## [code]type_string(TYPE_NIL)[/code] is [code]Nil[/code] for both [code]void[/code]
## and [code]Variant[/code]. The engine marks [code]Variant[/code] with
## [constant PROPERTY_USAGE_NIL_IS_VARIANT], so the snapshot stores that as [code]Variant[/code].
static func _info_type(info: Dictionary) -> String:
	var usage := int(info.get("usage", 0))
	if usage & PROPERTY_USAGE_NIL_IS_VARIANT:
		return "Variant"
	return type_string(int(info.get("type", TYPE_NIL)))


## Typed arrays leave [code]class_name[/code] empty and put the element type in
## [code]hint_string[/code] ([constant PROPERTY_HINT_ARRAY_TYPE]). The snapshot
## copies that element name into [code]class[/code] so the element type is pinned.
static func _info_class(info: Dictionary) -> String:
	var named := str(info.get("class_name", ""))
	if not named.is_empty():
		return named
	if int(info.get("hint", 0)) == PROPERTY_HINT_ARRAY_TYPE:
		return str(info.get("hint_string", ""))
	return ""


static func _known_classes() -> Dictionary:
	var names := {}
	for row in ProjectSettings.get_global_class_list():
		names[str(row.get("class", ""))] = true
	return names


static func _collect_signature(found: Dictionary, covered: Dictionary, known: Dictionary, row: Dictionary, with_return: bool) -> void:
	for arg in row.get("args", []):
		_collect_named(found, covered, known, str(arg.get("class", "")))
	if with_return:
		var returned: Dictionary = row.get("return", {})
		_collect_named(found, covered, known, str(returned.get("class", "")))


## Engine classes and project [code]class_name[/code] scripts count. Built-in
## types and enums (for example [code]WyrdCommandResult.Status[/code]) do not.
static func _collect_named(found: Dictionary, covered: Dictionary, known: Dictionary, reported: String) -> void:
	if reported.is_empty() or covered.has(reported):
		return
	if not known.has(reported) and not ClassDB.class_exists(reported):
		return
	found[reported] = true


static func _sort_by_name(rows: Array) -> void:
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", "")) < str(b.get("name", ""))
	)


static func _apply_member_flags(entry: Dictionary, flags: Dictionary) -> void:
	var methods: Dictionary = flags["methods"]
	var signals: Dictionary = flags["signals"]
	var properties: Dictionary = flags["properties"]
	for row in entry["methods"]:
		row["experimental"] = bool(methods.get(str(row.get("name", "")), false))
	for row in entry["signals"]:
		row["experimental"] = bool(signals.get(str(row.get("name", "")), false))
	for row in entry["properties"]:
		row["experimental"] = bool(properties.get(str(row.get("name", "")), false))


## Class flag from a [code]## @experimental[/code] line that is not a member doc.
## Each method, signal, and property flag comes from that member's own doc block.
static func member_flags(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var lines := text.split("\n")
	var methods := {}
	var signals := {}
	var properties := {}
	var member_lines := {}
	for index in lines.size():
		var parsed := _declaration(lines[index])
		if parsed.is_empty():
			continue
		var doc_start := _doc_start(lines, index)
		var experimental := false
		if doc_start >= 0:
			for doc_index in range(doc_start, index):
				member_lines[doc_index] = true
				if _experimental_line(lines[doc_index]):
					experimental = true
		var member_name := str(parsed["name"])
		if member_name.is_empty() or member_name.begins_with("_"):
			continue
		var kind := str(parsed["kind"])
		if kind == "method":
			methods[member_name] = experimental
		elif kind == "signal":
			signals[member_name] = experimental
		else:
			properties[member_name] = experimental
	var class_experimental := false
	for index in lines.size():
		if member_lines.has(index):
			continue
		if _experimental_line(lines[index]):
			class_experimental = true
			break
	return {
		"class": class_experimental,
		"methods": methods,
		"properties": properties,
		"signals": signals,
	}


static func _declaration(line: String) -> Dictionary:
	var kind := ""
	var rest := ""
	if line.begins_with("signal "):
		kind = "signal"
		rest = line.substr(7)
	elif line.begins_with("static func "):
		kind = "method"
		rest = line.substr(12)
	elif line.begins_with("func "):
		kind = "method"
		rest = line.substr(5)
	elif line.begins_with("var "):
		kind = "property"
		rest = line.substr(4)
	else:
		return {}
	var member_name := ""
	for index in rest.length():
		var ch := rest.substr(index, 1)
		if ch == "(" or ch == ":" or ch == " " or ch == "=" or ch == "\t":
			break
		member_name += ch
	return {"kind": kind, "name": member_name}


static func _doc_start(lines: PackedStringArray, decl: int) -> int:
	if decl <= 0:
		return -1
	var cursor := decl - 1
	if lines[cursor].strip_edges().is_empty() or not lines[cursor].lstrip(" \t").begins_with("##"):
		return -1
	while cursor > 0 and lines[cursor - 1].lstrip(" \t").begins_with("##"):
		cursor -= 1
	return cursor


static func _experimental_line(line: String) -> bool:
	var stripped := line.strip_edges()
	return stripped == "## @experimental" or stripped.begins_with("## @experimental:")


## Compiles the one-line source [code]language 1[/code] and reads the version
## the linker stores. The parser checks the header and does not keep a field
## for it, so the integer is the header token that parse accepted.
static func _language_version() -> int:
	var source := WyrdSource.new("res://tests/golden/api/language.wyrd", _LANGUAGE_SOURCE)
	var diagnostics := WyrdDiagnostics.new()
	var tree := WyrdParser.new().parse(source, diagnostics)
	for item in diagnostics.items:
		if item.code == WyrdDiagnostic.E_HEADER_INVALID or item.code == WyrdDiagnostic.E_HEADER_MISSING:
			return -1
	var version := -1
	for token in WyrdLexer.new().tokenize(source, WyrdDiagnostics.new()):
		if token.kind == &"int":
			version = int(token.text)
			break
	if version < 0:
		return -1
	var file := WyrdStatements.new().compile(source, tree, diagnostics)
	var schema: WyrdFactSchema = tree.schema if tree.schema != null else WyrdFactSchema.new()
	var pack := WyrdLinker.new().link(
		[{"file": file, "hash": 0, "path": source.path, "text": source.text}],
		schema,
		"api",
		version,
		null,
		"",
		true,
		diagnostics
	)
	return int(pack.language_version)


static func _save_schema() -> int:
	var facade: Node = load(_FACADE_PATH).new()
	var data: Dictionary = facade.save_state()
	var schema := int(data.get("schema_version", -1))
	facade.free()
	return schema
