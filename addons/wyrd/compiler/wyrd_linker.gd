class_name WyrdLinker
extends RefCounted

## Links one pack: symbols, line ids, commands, and the fact cross-reference.
##
## @experimental
## Files are already sorted. Diagnostics are added to the shared collector;
## [WyrdPack] sorts them. Topics are collected and are not errors.

var _pack_id: String = ""
var _commands: WyrdCommandSchema
var _note_path: String = ""
var _diagnostics: WyrdDiagnostics
var _scenes: Dictionary = {}
var _skip_commands_note: bool = false


func link(
	units: Array,
	schema: WyrdFactSchema,
	pack_id: String,
	language_version: int,
	commands: WyrdCommandSchema,
	note_path: String,
	skip_commands_note: bool,
	diagnostics: WyrdDiagnostics
) -> WyrdLinkedPack:
	_pack_id = pack_id
	_commands = commands
	_note_path = note_path
	_skip_commands_note = skip_commands_note
	_diagnostics = diagnostics
	_scenes = {}
	var pack := WyrdLinkedPack.new()
	pack.pack_id = pack_id
	pack.language_version = language_version
	pack.schema = schema
	pack.units = units
	_index_symbols(units)
	_lines(units)
	_host_steps(units)
	_quests(units, pack)
	_scenes_of(units)
	_commands_of(units)
	pack.xref = WyrdFactXref.new()
	return pack


func finish_xref(pack: WyrdLinkedPack, fact_paths: Dictionary) -> void:
	if pack.xref == null:
		pack.xref = WyrdFactXref.new()
	pack.xref.build(pack.schema, pack.units, fact_paths, _diagnostics)


func _index_symbols(units: Array) -> void:
	var quests := {}
	for unit in units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		for quest in file.quests:
			_claim(quests, quest.id, path, quest.line, quest.col, WyrdDiagnostic.E_QUEST_DUPLICATE, "quest")
		for scene in file.scenes:
			if scene.id.is_empty():
				continue
			if _scenes.has(scene.id):
				var prior: Dictionary = _scenes[scene.id]
				_diagnostics.add(
					WyrdDiagnostic.E_SCENE_DUPLICATE,
					"duplicate scene \"%s\" also declared in %s:%d:%d" % [scene.id, str(prior["path"]), int(prior["line"]), int(prior["col"])],
					path,
					scene.line,
					scene.col
				)
				continue
			_scenes[scene.id] = {"col": scene.col, "line": scene.line, "path": path, "scene": scene}


func _claim(table: Dictionary, id: String, path: String, line: int, col: int, code: StringName, noun: String) -> void:
	if id.is_empty():
		return
	if table.has(id):
		var prior: Dictionary = table[id]
		_diagnostics.add(
			code,
			"duplicate %s \"%s\" also declared in %s:%d:%d" % [noun, id, str(prior["path"]), int(prior["line"]), int(prior["col"])],
			path,
			line,
			col
		)
		return
	table[id] = {"col": col, "line": line, "path": path}


func _lines(units: Array) -> void:
	var seen := {}
	for unit in units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		for quest in file.quests:
			for stage in quest.stages:
				_line_stage(stage, path, seen)
		for scene in file.scenes:
			for item in scene.items:
				if item.line_def != null:
					_take_line(seen, item.line_def.line_id, path, item.line_def.line, item.line_def.col)
				if item.choice != null:
					_take_line(seen, item.choice.line_id, path, item.choice.line, item.choice.col)


func _line_stage(stage: WyrdStageDef, path: String, seen: Dictionary) -> void:
	for journal in stage.journals:
		_take_line(seen, journal.line_id, path, journal.line, journal.col)
	for variant in stage.variants:
		if variant.body != null:
			_line_stage(variant.body, path, seen)


func _take_line(seen: Dictionary, id: String, path: String, line: int, col: int) -> void:
	if id.is_empty():
		return
	if not seen.has(id):
		seen[id] = {"col": col, "line": line, "path": path}
		return
	var prior: Dictionary = seen[id]
	if str(prior["path"]) == path:
		return
	_diagnostics.add(
		WyrdDiagnostic.E_LINE_ID_DUPLICATE,
		"duplicate #line: id \"%s\" in %s:%d:%d and %s:%d:%d" % [id, str(prior["path"]), int(prior["line"]), int(prior["col"]), path, line, col],
		path,
		line,
		col
	)


func _quests(units: Array, pack: WyrdLinkedPack) -> void:
	for unit in units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		for quest in file.quests:
			var stages := {}
			for stage in quest.stages:
				if not stage.id.is_empty():
					stages[stage.id] = true
			for pack_ref in quest.requires:
				var id := pack_ref.substr(5) if pack_ref.begins_with("pack.") else pack_ref
				if id == _pack_id:
					continue
				_diagnostics.add(
					WyrdDiagnostic.W_PACK_UNKNOWN,
					"pack \"%s\" is not loaded; the quest stays unavailable until it is" % id,
					path,
					quest.requires_line,
					quest.requires_col,
					WyrdDiagnostic.SEVERITY_WARNING
				)
			for stage in quest.stages:
				_quest_stage(quest, stage, stages, path, pack)
			_warn_empty(quest, path)


func _warn_empty(quest: WyrdQuestDef, path: String) -> void:
	if not quest.on_empty.is_empty():
		return
	var covered := {}
	for stage in quest.stages:
		_mark_empty(stage, covered)
	for slot in quest.slots:
		if slot.name.is_empty() or covered.has(slot.name):
			continue
		_diagnostics.add(
			WyrdDiagnostic.W_EMPTY_UNCOVERED,
			"slot \"%s\" can become empty and has no empty variant or on_empty" % slot.name,
			path,
			slot.line,
			slot.col,
			WyrdDiagnostic.SEVERITY_WARNING
		)


func _mark_empty(stage: WyrdStageDef, covered: Dictionary) -> void:
	for item in stage.variants:
		var variant := item as WyrdVariantDef
		if variant == null:
			continue
		if variant.state == &"empty":
			covered[variant.slot] = true
		if variant.body != null:
			_mark_empty(variant.body, covered)


func _quest_stage(quest: WyrdQuestDef, stage: WyrdStageDef, stages: Dictionary, path: String, pack: WyrdLinkedPack) -> void:
	for ref in stage.scenes:
		var scene_id := str(ref["id"])
		if not _scenes.has(scene_id):
			_diagnostics.add(
				WyrdDiagnostic.E_SCENE_UNKNOWN,
				"unknown scene \"%s\"" % scene_id,
				path,
				int(ref["line"]),
				int(ref["col"])
			)
		elif _scenes[scene_id] is Dictionary:
			_bind(quest, ref, path)
	for effect in stage.effects:
		_topic(effect, pack)
		if effect.kind == &"do" and not effect.on_fail.is_empty() and not stages.has(effect.on_fail):
			_diagnostics.add(
				WyrdDiagnostic.E_STAGE_UNKNOWN,
				"unknown stage \"%s\"" % effect.on_fail,
				path,
				effect.line,
				effect.col
			)
	for variant in stage.variants:
		if variant.body != null:
			_quest_stage(quest, variant.body, stages, path, pack)


func _bind(quest: WyrdQuestDef, ref: Dictionary, path: String) -> void:
	var scene_id := str(ref["id"])
	var located: Dictionary = _scenes[scene_id]
	var scene: WyrdSceneDef = located["scene"]
	var slot_names := {}
	for slot in quest.slots:
		slot_names[slot.name] = true
	var passed := {}
	for entry in ref["with"]:
		var name := str(entry["name"])
		passed[name] = true
		if not _uses(scene, name):
			_diagnostics.add(
				WyrdDiagnostic.W_SLOT_UNUSED,
				"slot \"%s\" is not used in scene \"%s\"" % [name, scene_id],
				path,
				int(entry["line"]),
				int(entry["col"]),
				WyrdDiagnostic.SEVERITY_WARNING
			)
	for speaker in _speakers(scene):
		var name := str(speaker["name"])
		if slot_names.has(name) and not passed.has(name):
			_diagnostics.add(
				WyrdDiagnostic.E_SPEAKER_UNBOUND,
				"slot speaker \"%s\" is not passed to scene \"%s\"" % [name, scene_id],
				str(located["path"]),
				int(speaker["line"]),
				int(speaker["col"])
			)


func _scenes_of(units: Array) -> void:
	var run: Dictionary = {}
	for unit in units:
		var file: WyrdFileDef = unit["file"]
		for quest in file.quests:
			for stage in quest.stages:
				_mark_runs(stage, run)
	for unit in units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		for scene in file.scenes:
			if scene.id.is_empty() or run.has(scene.id):
				continue
			_diagnostics.add(
				WyrdDiagnostic.W_SCENE_UNUSED,
				"scene \"%s\" is not run by a quest" % scene.id,
				path,
				scene.line,
				scene.col,
				WyrdDiagnostic.SEVERITY_WARNING
			)
			for item in scene.items:
				if item.divert_kind == &"scene" and not item.target.is_empty() and not _scenes.has(item.target):
					_diagnostics.add(
						WyrdDiagnostic.E_SCENE_UNKNOWN,
						"unknown scene \"%s\"" % item.target,
						path,
						item.line,
						item.col
					)
		for scene in file.scenes:
			if scene.id.is_empty() or not run.has(scene.id):
				continue
			for item in scene.items:
				if item.divert_kind != &"scene" or item.target.is_empty():
					continue
				if not _scenes.has(item.target):
					_diagnostics.add(
						WyrdDiagnostic.E_SCENE_UNKNOWN,
						"unknown scene \"%s\"" % item.target,
						path,
						item.line,
						item.col
					)


func _mark_runs(stage: WyrdStageDef, run: Dictionary) -> void:
	for ref in stage.scenes:
		var scene_id := str(ref["id"])
		if _scenes.has(scene_id):
			run[scene_id] = true
	for variant in stage.variants:
		if variant.body != null:
			_mark_runs(variant.body, run)


func _commands_of(units: Array) -> void:
	var saw := false
	for unit in units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		for quest in file.quests:
			for stage in quest.stages:
				if _command_stage(stage, path):
					saw = true
		for scene in file.scenes:
			for effect in scene.on_abort:
				if _command(effect, path):
					saw = true
			for item in scene.items:
				if item.choice == null:
					continue
				for effect in item.choice.effects:
					if _command(effect, path):
						saw = true
	if saw and _commands == null and not _skip_commands_note:
		var path := _note_path
		if path.is_empty() and not units.is_empty():
			path = str(units[0]["path"])
		_diagnostics.add(
			WyrdDiagnostic.I_COMMANDS_SKIPPED,
			"command schemas skipped; no wyrd_commands.json beside the manifest",
			path,
			1,
			1,
			WyrdDiagnostic.SEVERITY_INFO
		)


func _command_stage(stage: WyrdStageDef, path: String) -> bool:
	var saw := false
	for effect in stage.effects:
		if _command(effect, path):
			saw = true
	for variant in stage.variants:
		if variant.body != null and _command_stage(variant.body, path):
			saw = true
	return saw


func _command(effect: WyrdEffectDef, path: String) -> bool:
	if effect.kind != &"do":
		return false
	if _commands != null and not _commands.has_command(StringName(effect.command)):
		_diagnostics.add(
			WyrdDiagnostic.E_COMMAND_UNKNOWN,
			"unknown command \"%s\"" % effect.command,
			path,
			effect.line,
			effect.col
		)
	return true


func _topic(effect: WyrdEffectDef, pack: WyrdLinkedPack) -> void:
	if effect.kind != &"unlock_topic" or effect.topic.is_empty():
		return
	if not pack.topics.has(effect.topic):
		pack.topics.append(effect.topic)


func _speakers(scene: WyrdSceneDef) -> Array:
	var rows: Array = []
	for item in scene.items:
		if item.line_def == null:
			continue
		var name := item.line_def.speaker
		if name.is_empty() or name == "narrator" or name.contains("."):
			continue
		rows.append({"col": item.line_def.col, "line": item.line_def.line, "name": name})
	return rows


func _uses(scene: WyrdSceneDef, slot_name: String) -> bool:
	for item in scene.items:
		if item.line_def != null and item.line_def.speaker == slot_name:
			return true
	return false


func _host_steps(units: Array) -> void:
	for unit in units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		for quest in file.quests:
			for stage in quest.stages:
				_host_stage(stage, path)


func _host_stage(stage: WyrdStageDef, path: String) -> void:
	if stage == null:
		return
	for host in stage.hosts:
		var seen := {}
		var fields: PackedStringArray = host.get("fields", PackedStringArray())
		for field in fields:
			if seen.has(field):
				_diagnostics.add(
					WyrdDiagnostic.E_STMT_UNKNOWN,
					"duplicate await_host field \"%s\"" % field,
					path,
					int(host.get("line", 1)),
					int(host.get("col", 1))
				)
			seen[field] = true
		if String(host.get("screen", "")).is_empty():
			_diagnostics.add(
				WyrdDiagnostic.E_STMT_UNKNOWN,
				"await_host needs a screen id",
				path,
				int(host.get("line", 1)),
				int(host.get("col", 1))
			)
	for entry in stage.variants:
		var variant := entry as WyrdVariantDef
		if variant != null and variant.body != null:
			_host_stage(variant.body, path)
