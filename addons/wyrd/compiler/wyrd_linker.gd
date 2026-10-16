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
	_warn_holder_gaps(units)
	pack.xref = WyrdFactXref.new()
	return pack


func finish_xref(pack: WyrdLinkedPack, fact_paths: Dictionary) -> void:
	if pack.xref == null:
		pack.xref = WyrdFactXref.new()
	var declared: Dictionary = {}
	if pack.events != null:
		declared = pack.events
	pack.xref.build(pack.schema, pack.units, fact_paths, _diagnostics, declared)


func _index_symbols(units: Array) -> void:
	var quests := {}
	var roles := {}
	var storylets := {}
	for unit in units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		for quest in file.quests:
			_claim(quests, quest.id, path, quest.line, quest.col, WyrdDiagnostic.E_QUEST_DUPLICATE, "quest")
		for role in file.roles:
			_claim(roles, role.id, path, role.line, role.col, WyrdDiagnostic.E_ROLE_DUPLICATE, "role")
		for storylet in file.storylets:
			_claim(storylets, storylet.id, path, storylet.line, storylet.col, WyrdDiagnostic.E_STORYLET_DUPLICATE, "storylet")
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
		for storylet in file.storylets:
			for line_def in storylet.lines:
				_take_line(seen, line_def.line_id, path, line_def.line, line_def.col)


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
			_warn_routes(quest, path)


func _warn_empty(quest: WyrdQuestDef, path: String) -> void:
	var reachable := _reachable(quest)
	var used := {}
	var empty_covered := {}
	var gone_covered := {}
	for stage in reachable:
		_mark_coverage(stage, used, empty_covered, gone_covered)
	if quest.on_empty.is_empty():
		for slot in quest.slots:
			if slot.name.is_empty() or not used.has(slot.name) or empty_covered.has(slot.name):
				continue
			_diagnostics.add(
				WyrdDiagnostic.W_EMPTY_UNCOVERED,
				"slot \"%s\" can become empty and has no empty variant or on_empty" % slot.name,
				path,
				slot.line,
				slot.col,
				WyrdDiagnostic.SEVERITY_WARNING
			)
	for slot in quest.slots:
		if slot.mode != &"locked_at" or slot.name.is_empty() or gone_covered.has(slot.name):
			continue
		_diagnostics.add(
			WyrdDiagnostic.W_LOCKED_GONE_UNCOVERED,
			"locked_at slot \"%s\" has no locked_gone variant" % slot.name,
			path,
			slot.line,
			slot.col,
			WyrdDiagnostic.SEVERITY_WARNING
		)


func _warn_routes(quest: WyrdQuestDef, path: String) -> void:
	var branches := {}
	for stage in _reachable(quest):
		_mark_routes(stage, branches)
	var names: Array = branches.keys()
	names.sort()
	for branch in names:
		var row: Dictionary = branches[branch]
		if int(row["closed"]) == 0 or int(row["other"]) > 0:
			continue
		_diagnostics.add(
			WyrdDiagnostic.W_ROUTE_CLOSED,
			"every route of branch \"%s\" closes" % String(branch),
			path,
			int(row["line"]),
			int(row["col"]),
			WyrdDiagnostic.SEVERITY_WARNING
		)


func _reachable(quest: WyrdQuestDef) -> Array:
	var found: Array = []
	if quest.stages.is_empty():
		return found
	var by_id := {}
	for stage in quest.stages:
		if not stage.id.is_empty():
			by_id[stage.id] = stage
	var seen := {}
	var queue: Array = [quest.stages[0]]
	while not queue.is_empty():
		var stage: WyrdStageDef = queue.pop_front()
		if stage == null:
			continue
		var token := stage.id if not stage.id.is_empty() else str(stage.get_instance_id())
		if seen.has(token):
			continue
		seen[token] = true
		if not stage.id.is_empty():
			found.append(stage)
		_enqueue_targets(stage, by_id, queue)
	return found


func _enqueue_targets(stage: WyrdStageDef, by_id: Dictionary, queue: Array) -> void:
	if stage == null:
		return
	for row in stage.transitions:
		var target := str(row.get("target", ""))
		if by_id.has(target):
			queue.append(by_id[target])
	for item in stage.variants:
		var variant := item as WyrdVariantDef
		if variant != null and variant.body != null:
			_enqueue_targets(variant.body, by_id, queue)


func _mark_coverage(stage: WyrdStageDef, used: Dictionary, empty_covered: Dictionary, gone_covered: Dictionary) -> void:
	if stage == null:
		return
	for ref in stage.scenes:
		for entry in ref.get("with", []):
			var name := str(entry.get("name", ""))
			if not name.is_empty():
				used[name] = true
	for item in stage.variants:
		var variant := item as WyrdVariantDef
		if variant == null:
			continue
		if not variant.slot.is_empty():
			used[variant.slot] = true
		# contested falls back to the empty variant, so it does not cover empty.
		if variant.state == &"empty":
			empty_covered[variant.slot] = true
		elif variant.state == &"locked_gone":
			gone_covered[variant.slot] = true
		if variant.body != null:
			_mark_coverage(variant.body, used, empty_covered, gone_covered)


func _mark_routes(stage: WyrdStageDef, branches: Dictionary) -> void:
	if stage == null:
		return
	for effect in stage.effects:
		if effect.kind != &"outcome" or effect.branch.is_empty():
			continue
		if not branches.has(effect.branch):
			branches[effect.branch] = {"closed": 0, "col": effect.col, "line": effect.line, "other": 0}
		var row: Dictionary = branches[effect.branch]
		if effect.outcome == "route_closed":
			row["closed"] = int(row["closed"]) + 1
		else:
			row["other"] = int(row["other"]) + 1
		branches[effect.branch] = row
	for item in stage.variants:
		var variant := item as WyrdVariantDef
		if variant != null and variant.body != null:
			_mark_routes(variant.body, branches)


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
		for storylet in file.storylets:
			if storylet.body_kind != &"scene" or storylet.scene_id.is_empty():
				continue
			if _scenes.has(storylet.scene_id):
				continue
			_diagnostics.add(
				WyrdDiagnostic.E_SCENE_UNKNOWN,
				"unknown scene \"%s\"" % storylet.scene_id,
				path,
				storylet.line,
				storylet.col
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


func _warn_holder_gaps(units: Array) -> void:
	# holder(slot) in prose is safe when the line's when requires filled(slot),
	# or when an empty variant replaces the branch that contains the prose.
	var sites: Dictionary = {}
	for unit in units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		for quest in file.quests:
			var slots := _slot_set(quest)
			for stage in quest.stages:
				_holder_stage(stage, {}, slots, path, sites)
	_spread_diverts(sites)
	for scene_id in sites.keys():
		_holder_scene(String(scene_id), sites[scene_id])


func _holder_stage(
	stage: WyrdStageDef,
	inherited: Dictionary,
	slots: Dictionary,
	path: String,
	sites: Dictionary
) -> void:
	if stage == null:
		return
	var excluded := inherited.duplicate()
	for entry in stage.variants:
		var variant := entry as WyrdVariantDef
		if variant != null and variant.state == &"empty" and slots.has(variant.slot):
			excluded[variant.slot] = true
	var here: Array = [{"excluded": excluded, "slots": slots}]
	for journal in stage.journals:
		_warn_holder_prose(journal.prose, "", here, path)
	for ref in stage.scenes:
		_add_holder_site(sites, str(ref["id"]), excluded, slots)
	for entry in stage.variants:
		var variant := entry as WyrdVariantDef
		if variant == null or variant.body == null:
			continue
		var child := inherited.duplicate()
		if variant.state == &"empty":
			child.erase(variant.slot)
		else:
			child = excluded.duplicate()
		_holder_stage(variant.body, child, slots, path, sites)


func _holder_scene(scene_id: String, site_map: Dictionary) -> void:
	if not _scenes.has(scene_id):
		return
	var located: Dictionary = _scenes[scene_id]
	var scene: WyrdSceneDef = located["scene"]
	var path := str(located["path"])
	var sites: Array = site_map.values()
	if sites.is_empty():
		return
	for item in scene.items:
		if item.line_def != null:
			_warn_holder_prose(item.line_def.prose, item.line_def.condition_text, sites, path)
		if item.choice != null:
			_warn_holder_prose(item.choice.label, item.choice.condition_text, sites, path)


func _warn_holder_prose(node: WyrdExprNode, condition: String, sites: Array, path: String) -> void:
	if node == null:
		return
	if node.kind == &"value" and node.payload is WyrdCompiledCondition:
		for slot_name in _holder_slots(node.payload as WyrdCompiledCondition):
			if _holder_exposed(sites, slot_name, condition):
				_diagnostics.add(
					WyrdDiagnostic.W_HOLDER_UNGUARDED,
					"holder(\"%s\") is interpolated where slot \"%s\" can be empty" % [slot_name, slot_name],
					path,
					node.line,
					node.col,
					WyrdDiagnostic.SEVERITY_WARNING
				)
	_warn_holder_prose(node.a, condition, sites, path)
	_warn_holder_prose(node.b, condition, sites, path)
	_warn_holder_prose(node.c, condition, sites, path)
	for kid in node.kids:
		_warn_holder_prose(kid, condition, sites, path)


func _holder_exposed(sites: Array, slot_name: String, condition: String) -> bool:
	if _implies_filled(condition, slot_name):
		return false
	for site in sites:
		var slots: Dictionary = site["slots"]
		var excluded: Dictionary = site["excluded"]
		if slots.has(slot_name) and not excluded.has(slot_name):
			return true
	return false


func _implies_filled(expr: String, slot_name: String) -> bool:
	var text := expr.strip_edges()
	if text.is_empty():
		return false
	var unwrapped := _unwrap_parens(text)
	if unwrapped != text:
		return _implies_filled(unwrapped, slot_name)
	var ands := _split_top(text, " and ")
	if ands.size() > 1:
		for part in ands:
			if _implies_filled(part, slot_name):
				return true
		return false
	var ors := _split_top(text, " or ")
	if ors.size() > 1:
		for part in ors:
			if not _implies_filled(part, slot_name):
				return false
		return true
	return text.replace(" ", "") == "filled(%s)" % slot_name


func _unwrap_parens(text: String) -> String:
	if text.length() < 2 or not text.begins_with("(") or not text.ends_with(")"):
		return text
	var depth := 0
	for i in text.length():
		var ch := text.substr(i, 1)
		if ch == "(":
			depth += 1
		elif ch == ")":
			depth -= 1
			if depth == 0 and i < text.length() - 1:
				return text
	return text.substr(1, text.length() - 2).strip_edges()


func _split_top(text: String, op: String) -> PackedStringArray:
	var parts := PackedStringArray()
	var depth := 0
	var start := 0
	var i := 0
	while i < text.length():
		var ch := text.substr(i, 1)
		if ch == "(":
			depth += 1
			i += 1
			continue
		if ch == ")":
			depth -= 1
			i += 1
			continue
		if depth == 0 and text.substr(i).begins_with(op):
			parts.append(text.substr(start, i - start).strip_edges())
			i += op.length()
			start = i
			continue
		i += 1
	parts.append(text.substr(start).strip_edges())
	return parts


func _holder_slots(compiled: WyrdCompiledCondition) -> PackedStringArray:
	var found := {}
	var stack: Array = []
	var code := compiled.code
	var ip := 0
	while ip < code.size():
		var op := code[ip]
		ip += 1
		if op == WyrdOpcodes.PUSH_CONST:
			stack.append(compiled.consts[code[ip]])
			ip += 1
		elif op == WyrdOpcodes.LOAD_FACT:
			stack.append(null)
			ip += 1
		elif op == WyrdOpcodes.PUSH_TRUE or op == WyrdOpcodes.PUSH_FALSE or op == WyrdOpcodes.PUSH_NIL:
			stack.append(null)
		elif op == WyrdOpcodes.LOAD_KEY:
			var count := code[ip]
			ip += 1
			for _i in count:
				if not stack.is_empty():
					stack.pop_back()
			stack.append(null)
		elif op == WyrdOpcodes.NEG or op == WyrdOpcodes.NOT:
			if not stack.is_empty():
				stack.pop_back()
			stack.append(null)
		elif op == WyrdOpcodes.ADD or op == WyrdOpcodes.SUB or op == WyrdOpcodes.MUL or op == WyrdOpcodes.DIV or op == WyrdOpcodes.EQ or op == WyrdOpcodes.NE or op == WyrdOpcodes.LT or op == WyrdOpcodes.LE or op == WyrdOpcodes.GT or op == WyrdOpcodes.GE:
			if not stack.is_empty():
				stack.pop_back()
			if not stack.is_empty():
				stack.pop_back()
			stack.append(null)
		elif op == WyrdOpcodes.IN_RANGE:
			for _i in 3:
				if not stack.is_empty():
					stack.pop_back()
			stack.append(null)
		elif op == WyrdOpcodes.IN_SET:
			var count := code[ip]
			ip += 1
			for _i in count + 1:
				if not stack.is_empty():
					stack.pop_back()
			stack.append(null)
		elif op == WyrdOpcodes.CALL:
			var name := String(compiled.consts[code[ip]])
			var argc := code[ip + 1]
			ip += 2
			var args: Array = []
			for _i in argc:
				if stack.is_empty():
					args.append(null)
				else:
					args.push_front(stack.pop_back())
			if name == "holder" and args.size() == 1 and (args[0] is String or args[0] is StringName):
				found[String(args[0])] = true
			stack.append(null)
		elif op == WyrdOpcodes.JUMP:
			ip += 1
		elif op == WyrdOpcodes.JUMP_IF_FALSE or op == WyrdOpcodes.JUMP_IF_TRUE:
			if not stack.is_empty():
				stack.pop_back()
			ip += 1
		else:
			break
	var names := PackedStringArray()
	for key in found.keys():
		names.append(String(key))
	names.sort()
	return names


func _add_holder_site(sites: Dictionary, scene_id: String, excluded: Dictionary, slots: Dictionary) -> void:
	if scene_id.is_empty():
		return
	if not sites.has(scene_id):
		sites[scene_id] = {}
	var bag: Dictionary = sites[scene_id]
	var key := "s:%s|e:%s" % [_dict_keys(slots), _dict_keys(excluded)]
	bag[key] = {"excluded": excluded.duplicate(), "slots": slots.duplicate()}


func _spread_diverts(sites: Dictionary) -> void:
	var growing := true
	var guard := 0
	while growing and guard < 32:
		guard += 1
		growing = false
		for scene_id in _scenes.keys():
			if not sites.has(scene_id):
				continue
			var scene: WyrdSceneDef = (_scenes[scene_id] as Dictionary)["scene"]
			for item in scene.items:
				if item.divert_kind != &"scene" or item.target.is_empty():
					continue
				if not sites.has(item.target):
					sites[item.target] = {}
				var dest: Dictionary = sites[item.target]
				var source: Dictionary = sites[scene_id]
				for key in source.keys():
					if dest.has(key):
						continue
					dest[key] = source[key]
					growing = true


func _slot_set(quest: WyrdQuestDef) -> Dictionary:
	var slots := {}
	for slot in quest.slots:
		if not slot.name.is_empty():
			slots[slot.name] = true
	return slots


func _dict_keys(bag: Dictionary) -> String:
	var names: Array = bag.keys()
	names.sort()
	var parts := PackedStringArray()
	for name in names:
		parts.append(String(name))
	return ",".join(parts)


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
