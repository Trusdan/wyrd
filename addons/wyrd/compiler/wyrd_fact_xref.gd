class_name WyrdFactXref
extends RefCounted

## Fact cross-reference for one pack (WFR1).
##
## @experimental
## Readers and writers reuse [WyrdDepIndex] pattern rules. [code]record deed[/code]
## is a fact write only when it has [code]reveals[/code]. Resolved facts are never "never set". Fact defaults are not
## in the grammar yet, so a stored fact that is read and not written has no default.
## [member events] records [code]on_event[/code] names ([code]role[/code] [code]invalidate[/code])
## and [code]on <event>[/code] handlers ([code]role[/code] [code]emit[/code]).
## A scene [code]learn[/code] warns [code]W_STALE_BELIEF[/code] when a contradicting belief remains.
## Prose may interpolate a belief or a held value as [code]W_CLAIM[/code].
## A world value behind a world gate is [code]E_FACT_LEAK[/code].

var facts: Array = []
var events: Array = []


func build(
	schema: WyrdFactSchema,
	units: Array,
	fact_paths: Dictionary,
	diagnostics: WyrdDiagnostics,
	declared_events: Dictionary = {}
) -> void:
	facts.clear()
	events.clear()
	if schema == null:
		return
	var readers := _readers(units)
	var writers := _writers(units)
	_leave_writers(writers, declared_events)
	var reader_index := _index(readers)
	var writer_index := _index(writers)
	for fact in schema.entries:
		var path := str(fact_paths.get(fact, ""))
		var source := fact.resolver if fact.origin == &"resolved" else "stored"
		var read_rows := _hits(reader_index, readers, fact.key)
		var write_rows := _hits(writer_index, writers, fact.key)
		facts.append({
			"col": fact.col,
			"doc": fact.doc,
			"file": path,
			"key": fact.key,
			"line": fact.line,
			"readers": read_rows,
			"source": source,
			"type": String(fact.type_name),
			"writers": write_rows,
		})
		if fact.invalidate == &"on_event" and not fact.invalidate_arg.is_empty():
			events.append({
				"col": fact.col,
				"fact": fact.key,
				"file": path,
				"line": fact.line,
				"name": fact.invalidate_arg,
				"role": "invalidate",
			})
		_lint(fact, path, read_rows.size(), write_rows.size(), diagnostics)
	_handler_events(units)
	_warn_interps(schema, units, writers, diagnostics)
	_warn_stale_beliefs(units, diagnostics)
	facts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["key"]) < str(b["key"]))
	events.sort_custom(_event_before)


func to_data() -> Dictionary:
	return {"events": events.duplicate(true), "facts": facts.duplicate(true)}


func render_table() -> String:
	var header := ["key", "type", "source", "writers", "readers", "doc"]
	var rows: Array = [header]
	for fact in facts:
		rows.append([
			str(fact["key"]),
			str(fact["type"]),
			str(fact["source"]),
			str((fact["writers"] as Array).size()),
			str((fact["readers"] as Array).size()),
			str(fact["doc"]),
		])
	var widths: Array[int] = [3, 4, 6, 7, 7, 3]
	for row in rows:
		var cells: Array = row
		for i in mini(cells.size(), widths.size()):
			widths[i] = maxi(widths[i], str(cells[i]).length())
	var lines: PackedStringArray = PackedStringArray()
	for row_at in rows.size():
		var cells: Array = rows[row_at]
		var parts: PackedStringArray = PackedStringArray()
		for i in cells.size():
			var cell := str(cells[i])
			if i + 1 < cells.size():
				cell = cell.rpad(widths[i])
			parts.append(cell)
		lines.append("  ".join(parts))
	if not events.is_empty():
		lines.append("")
		lines.append("events:")
		for event in events:
			lines.append("  %s" % str(event["name"]))
	return "\n".join(lines)


func _lint(fact: WyrdFact, path: String, read_count: int, write_count: int, diagnostics: WyrdDiagnostics) -> void:
	if read_count == 0 and write_count == 0:
		diagnostics.add(
			WyrdDiagnostic.W_FACT_UNUSED,
			"fact \"%s\" is never read or written" % fact.key,
			path,
			fact.line,
			fact.col,
			WyrdDiagnostic.SEVERITY_WARNING
		)
		return
	if fact.origin != &"stored":
		return
	if write_count > 0 and read_count == 0:
		diagnostics.add(
			WyrdDiagnostic.W_FACT_NEVER_READ,
			"stored fact \"%s\" is set but never read" % fact.key,
			path,
			fact.line,
			fact.col,
			WyrdDiagnostic.SEVERITY_WARNING
		)
	elif read_count > 0 and write_count == 0:
		diagnostics.add(
			WyrdDiagnostic.W_FACT_NEVER_SET,
			"stored fact \"%s\" is read but never set" % fact.key,
			path,
			fact.line,
			fact.col,
			WyrdDiagnostic.SEVERITY_WARNING
		)


func _warn_interps(schema: WyrdFactSchema, units: Array, writers: Array, diagnostics: WyrdDiagnostics) -> void:
	if schema == null:
		return
	for unit in units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		for quest in file.quests:
			for stage in quest.stages:
				_warn_stage(schema, stage, path, writers, diagnostics)
		for scene in file.scenes:
			for item in scene.items:
				if item.line_def != null:
					_warn_prose(schema, item.line_def.prose, path, writers, diagnostics, _gate_list(schema, item.line_def.condition_text))
				if item.choice != null:
					_warn_prose(schema, item.choice.label, path, writers, diagnostics, _gate_list(schema, item.choice.condition_text))


func _warn_stage(schema: WyrdFactSchema, stage: WyrdStageDef, path: String, writers: Array, diagnostics: WyrdDiagnostics) -> void:
	if stage == null:
		return
	for journal in stage.journals:
		_warn_prose(schema, journal.prose, path, writers, diagnostics, [])
	for variant in stage.variants:
		if variant.body != null:
			_warn_stage(schema, variant.body, path, writers, diagnostics)


func _warn_prose(
	schema: WyrdFactSchema,
	node: WyrdExprNode,
	path: String,
	writers: Array,
	diagnostics: WyrdDiagnostics,
	gates: Array
) -> void:
	if node == null:
		return
	if node.kind == &"if":
		var inner := gates.duplicate()
		if node.a != null:
			inner.append(node.a)
		_warn_prose(schema, node.b, path, writers, diagnostics, inner)
		_warn_prose(schema, node.c, path, writers, diagnostics, inner)
		return
	if node.kind == &"value" or node.kind == &"variants":
		_warn_value(schema, node, path, writers, diagnostics, gates)
	_warn_prose(schema, node.a, path, writers, diagnostics, gates)
	_warn_prose(schema, node.b, path, writers, diagnostics, gates)
	_warn_prose(schema, node.c, path, writers, diagnostics, gates)
	for kid in node.kids:
		_warn_prose(schema, kid, path, writers, diagnostics, gates)


func _warn_value(
	schema: WyrdFactSchema,
	node: WyrdExprNode,
	path: String,
	writers: Array,
	diagnostics: WyrdDiagnostics,
	gates: Array
) -> void:
	var found := _perspectives(node.a)
	for key in found["world"]:
		var text := String(key)
		if not _stored_concrete(schema, text):
			continue
		if not _written_before(writers, text, path, node.line, node.col):
			diagnostics.add(
				WyrdDiagnostic.W_INTERP_UNSET,
				"interpolation reads stored fact \"%s\" before it is set" % text,
				path,
				node.line,
				node.col,
				WyrdDiagnostic.SEVERITY_WARNING
			)
		if _world_gate(schema, gates, text):
			diagnostics.add(
				WyrdDiagnostic.E_FACT_LEAK,
				"player-visible text interpolates \"%s\" gated only by a world read" % text,
				path,
				node.line,
				node.col
			)
	for key in found["claim"]:
		var claim := String(key)
		if not _stored_concrete(schema, claim):
			continue
		diagnostics.add(
			WyrdDiagnostic.W_CLAIM,
			"interpolation presents \"%s\" as a claim" % claim,
			path,
			node.line,
			node.col,
			WyrdDiagnostic.SEVERITY_WARNING
		)


func _warn_stale_beliefs(units: Array, diagnostics: WyrdDiagnostics) -> void:
	var believed := {}
	var cleared := {}
	for unit in units:
		var file: WyrdFileDef = unit["file"]
		for quest in file.quests:
			for stage in quest.stages:
				_note_belief_stage(stage, believed, cleared)
		for scene in file.scenes:
			_note_belief_rows(scene.on_abort, believed, cleared)
			for item in scene.items:
				if item.choice != null:
					_note_belief_rows(item.choice.effects, believed, cleared)
	for unit in units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		for scene in file.scenes:
			_warn_scene_learns(scene.on_abort, path, believed, cleared, diagnostics)
			for item in scene.items:
				if item.choice != null:
					_warn_scene_learns(item.choice.effects, path, believed, cleared, diagnostics)


func _note_belief_stage(stage: WyrdStageDef, believed: Dictionary, cleared: Dictionary) -> void:
	if stage == null:
		return
	_note_belief_rows(stage.effects, believed, cleared)
	for handler in stage.handlers:
		_note_belief_rows(handler.effects, believed, cleared)
	for variant in stage.variants:
		if variant.body != null:
			_note_belief_stage(variant.body, believed, cleared)


func _note_belief_rows(effects: Array, believed: Dictionary, cleared: Dictionary) -> void:
	for effect in effects:
		if effect == null:
			continue
		var row := effect as WyrdEffectDef
		if row.agent.is_empty() or row.fact_key.is_empty():
			continue
		var id := "%s\t%s" % [row.agent, row.fact_key]
		if row.kind == &"unbelieve":
			cleared[id] = true
		elif row.kind == &"believe":
			var values: Array = believed.get(id, [])
			values.append(row.value_text.strip_edges())
			believed[id] = values


func _warn_scene_learns(
	effects: Array,
	path: String,
	believed: Dictionary,
	cleared: Dictionary,
	diagnostics: WyrdDiagnostics
) -> void:
	for effect in effects:
		if effect == null:
			continue
		var row := effect as WyrdEffectDef
		if row.kind != &"learn" or row.agent.is_empty() or row.fact_key.is_empty():
			continue
		var id := "%s\t%s" % [row.agent, row.fact_key]
		if cleared.has(id):
			continue
		var learned := row.value_text.strip_edges()
		var conflict := false
		for value in believed.get(id, []):
			if String(value) != learned:
				conflict = true
				break
		if not conflict:
			continue
		diagnostics.add(
			WyrdDiagnostic.W_STALE_BELIEF,
			"learn writes known \"%s\" for %s while a contradicting belief remains" % [row.fact_key, row.agent],
			path,
			row.line,
			row.col,
			WyrdDiagnostic.SEVERITY_WARNING
		)


func _gate_list(schema: WyrdFactSchema, text: String) -> Array:
	var gate := _gate_ast(schema, text)
	if gate == null:
		return []
	return [gate]


func _gate_ast(schema: WyrdFactSchema, text: String) -> WyrdExprNode:
	if schema == null or text.strip_edges().is_empty():
		return null
	var scratch := WyrdDiagnostics.new()
	var compiler := WyrdCondition.new()
	compiler.compile(text, schema, scratch, "", 1, 1)
	return compiler.ast


func _world_gate(schema: WyrdFactSchema, gates: Array, key: String) -> bool:
	var gated := false
	var knows := false
	for gate in gates:
		if not (gate is WyrdExprNode):
			continue
		var found := _perspectives(gate)
		if found["world"].has(key) and _stored_concrete(schema, key):
			gated = true
		if found["knows"].has(key):
			knows = true
	return gated and not knows


func _stored_concrete(schema: WyrdFactSchema, key: String) -> bool:
	if schema == null or key.is_empty() or key.contains("{"):
		return false
	var fact := schema.lookup(PackedStringArray(key.split(".")))
	return fact != null and fact.origin == &"stored" and not fact.is_pattern()


func _perspectives(node: WyrdExprNode) -> Dictionary:
	var found := {"claim": {}, "knows": {}, "world": {}}
	_walk_perspective(node, "", found)
	return found


func _walk_perspective(node: WyrdExprNode, mode: String, found: Dictionary) -> void:
	if node == null:
		return
	if node.kind == &"call":
		var next := ""
		if node.text == "belief" or node.text == "believes" or node.text == "held":
			next = "claim"
		elif node.text == "knows" or node.text == "known":
			next = "knows"
		var slots := _call_slots(node)
		for i in slots.size():
			_walk_perspective(slots[i], next if i == 1 else "", found)
		return
	if node.kind == &"arg":
		_walk_perspective(node.a, mode, found)
		return
	if node.kind == &"fact":
		if mode != "" and not node.text.contains("{"):
			found[mode][node.text] = true
		elif mode == "" and not node.text.contains("{"):
			found["world"][node.text] = true
		return
	_walk_perspective(node.a, "", found)
	_walk_perspective(node.b, "", found)
	_walk_perspective(node.c, "", found)
	for kid in node.kids:
		_walk_perspective(kid, "", found)


func _call_slots(node: WyrdExprNode) -> Array:
	var rows: Array = []
	if node.payload is Array:
		for item in node.payload:
			if item is WyrdExprNode:
				rows.append(item)
		if not rows.is_empty():
			return rows
	for kid in node.kids:
		if kid.a != null:
			rows.append(kid.a)
	return rows


func _written_before(writers: Array, key: String, path: String, line: int, col: int) -> bool:
	for row in writers:
		var reads: Array = row["reads"]
		if reads.is_empty() or String(reads[0]) != key:
			continue
		var file := str(row["file"])
		var at_line := int(row["line"])
		var at_col := int(row["col"])
		if file < path or (file == path and (at_line < line or (at_line == line and at_col < col))):
			return true
	return false


func _readers(units: Array) -> Array:
	var rows: Array = []
	for unit in units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		for quest in file.quests:
			_push(rows, _cond_reads(quest.start_when), "quest", quest.id, path, quest.line, quest.col)
			for slot in quest.slots:
				_push(rows, _cond_reads(slot.cast_when), "slot", "%s.%s" % [quest.id, slot.name], path, slot.line, slot.col)
			for stage in quest.stages:
				_stage_readers(rows, stage, "%s.%s" % [quest.id, stage.id], path)
		for scene in file.scenes:
			_scene_readers(rows, scene, path)
		for role in file.roles:
			_push(rows, _cond_reads(role.eligibility), "eligibility", role.id, path, role.line, role.col)
	return rows


func _handler_events(units: Array) -> void:
	for unit in units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		if file == null:
			continue
		for quest in file.quests:
			for stage in quest.stages:
				_handler_stage(stage, path)


func _handler_stage(stage: WyrdStageDef, path: String) -> void:
	if stage == null:
		return
	for handler in stage.handlers:
		events.append({
			"col": handler.col,
			"fact": "",
			"file": path,
			"line": handler.line,
			"name": handler.event_name,
			"role": "emit",
		})
	for variant in stage.variants:
		if variant.body != null:
			_handler_stage(variant.body, path)


func _stage_readers(rows: Array, stage: WyrdStageDef, id: String, path: String) -> void:
	_push(rows, _cond_reads(stage.waits_until), "stage", id, path, stage.line, stage.col)
	for handler in stage.handlers:
		if handler.where_cond != null:
			_push(rows, handler.where_cond.reads, "stage", id, path, handler.line, handler.col)
		for effect in handler.effects:
			_effect_reader(rows, effect, id, path)
	for row in stage.transitions:
		var when: Variant = row["when"]
		if when is WyrdCompiledCondition:
			var at_line := int(row["line"])
			var at_col := int(row["col"])
			_push(rows, (when as WyrdCompiledCondition).reads, "stage", id, path, at_line, at_col)
	for journal in stage.journals:
		_push(rows, journal.reads, "line", journal.line_id, path, journal.line, journal.col)
	for effect in stage.effects:
		_effect_reader(rows, effect, id, path)
	for variant in stage.variants:
		var variant_id := "%s.%s.%s" % [id, variant.slot, String(variant.state)]
		_push(rows, _cond_reads(variant.condition), "variant", variant_id, path, variant.line, variant.col)
		if variant.body != null:
			_stage_readers(rows, variant.body, variant_id, path)


func _scene_readers(rows: Array, scene: WyrdSceneDef, path: String) -> void:
	for effect in scene.on_abort:
		_effect_reader(rows, effect, scene.id, path)
	for item in scene.items:
		if item.line_def != null:
			var spoken := item.line_def
			_push(rows, spoken.reads, "line", spoken.line_id, path, spoken.line, spoken.col)
		if item.choice != null:
			var choice := item.choice
			var reads: Array[StringName] = []
			WyrdStmtSpan.add_reads(reads, _cond_reads(choice.condition))
			_prose_reads(choice.label, reads)
			_push(rows, reads, "choice", choice.line_id, path, choice.line, choice.col)
			for effect in choice.effects:
				_effect_reader(rows, effect, choice.line_id if not choice.line_id.is_empty() else scene.id, path)


func _effect_reader(rows: Array, effect: WyrdEffectDef, id: String, path: String) -> void:
	if effect.kind == &"set" or effect.kind == &"inc" or effect.kind == &"believe" or effect.kind == &"declare" or effect.kind == &"learn":
		_push(rows, _cond_reads(effect.value), "effect", id, path, effect.line, effect.col)
		return
	if effect.kind == &"unbelieve" or effect.kind == &"retract":
		return
	_push(rows, effect.reads, "effect", id, path, effect.line, effect.col)


func _leave_writers(rows: Array, declared_events: Dictionary) -> void:
	var names: Array = declared_events.keys()
	names.sort()
	for name in names:
		var event := declared_events[name] as WyrdEventDef
		if event == null or event.leaves_key.is_empty():
			continue
		rows.append({
			"col": event.leaves_col if event.leaves_col > 0 else event.col,
			"file": event.source_path,
			"id": event.name,
			"kind": "event",
			"line": event.leaves_line if event.leaves_line > 0 else event.line,
			"reads": [StringName(event.leaves_key)],
		})


func _writers(units: Array) -> Array:
	var rows: Array = []
	for unit in units:
		var path := str(unit["path"])
		var file: WyrdFileDef = unit["file"]
		for quest in file.quests:
			for stage in quest.stages:
				_stage_writers(rows, stage, "%s.%s" % [quest.id, stage.id], path)
		for scene in file.scenes:
			for effect in scene.on_abort:
				_write(rows, effect, scene.id, path)
			for item in scene.items:
				if item.choice == null:
					continue
				var id := item.choice.line_id if not item.choice.line_id.is_empty() else scene.id
				for effect in item.choice.effects:
					_write(rows, effect, id, path)
	return rows


func _stage_writers(rows: Array, stage: WyrdStageDef, id: String, path: String) -> void:
	for effect in stage.effects:
		_write(rows, effect, id, path)
	for handler in stage.handlers:
		for effect in handler.effects:
			_write(rows, effect, id, path)
	for variant in stage.variants:
		if variant.body == null:
			continue
		var variant_id := "%s.%s.%s" % [id, variant.slot, String(variant.state)]
		_stage_writers(rows, variant.body, variant_id, path)


func _write(rows: Array, effect: WyrdEffectDef, id: String, path: String) -> void:
	if effect.kind != &"set" and effect.kind != &"inc" and effect.kind != &"believe" and effect.kind != &"declare" and effect.kind != &"learn" and effect.kind != &"record_deed":
		return
	if effect.fact_key.is_empty():
		return
	rows.append({
		"col": effect.col,
		"file": path,
		"id": id,
		"kind": "effect",
		"line": effect.line,
		"reads": [StringName(effect.fact_key)],
	})


func _index(rows: Array) -> WyrdDepIndex:
	var conds: Array[WyrdCompiledCondition] = []
	for row in rows:
		var compiled := WyrdCompiledCondition.new()
		var reads: Array[StringName] = []
		for item in row["reads"]:
			reads.append(StringName(item))
		compiled.reads = reads
		conds.append(compiled)
	var index := WyrdDepIndex.new()
	index.build(conds)
	return index


func _hits(index: WyrdDepIndex, rows: Array, key: String) -> Array:
	var found: Array = []
	if index == null:
		return found
	for hit in index.affected([StringName(key)]):
		var row: Dictionary = rows[int(hit)]
		found.append({
			"col": int(row["col"]),
			"file": str(row["file"]),
			"id": str(row["id"]),
			"kind": str(row["kind"]),
			"line": int(row["line"]),
		})
	found.sort_custom(_site_before)
	return found


func _push(rows: Array, reads: Array[StringName], kind: String, id: String, path: String, line: int, col: int) -> void:
	if reads.is_empty():
		return
	rows.append({
		"col": col,
		"file": path,
		"id": id,
		"kind": kind,
		"line": line,
		"reads": reads,
	})


func _cond_reads(cond: WyrdCompiledCondition) -> Array[StringName]:
	if cond == null:
		return []
	return cond.reads


func _prose_reads(node: WyrdExprNode, into: Array[StringName]) -> void:
	if node == null:
		return
	if node.payload is WyrdCompiledCondition:
		WyrdStmtSpan.add_reads(into, (node.payload as WyrdCompiledCondition).reads)
	_prose_reads(node.a, into)
	_prose_reads(node.b, into)
	_prose_reads(node.c, into)
	for kid in node.kids:
		_prose_reads(kid, into)


static func _site_before(a: Dictionary, b: Dictionary) -> bool:
	if str(a["file"]) != str(b["file"]):
		return str(a["file"]) < str(b["file"])
	if int(a["line"]) != int(b["line"]):
		return int(a["line"]) < int(b["line"])
	if int(a["col"]) != int(b["col"]):
		return int(a["col"]) < int(b["col"])
	if str(a["kind"]) != str(b["kind"]):
		return str(a["kind"]) < str(b["kind"])
	return str(a["id"]) < str(b["id"])


static func _event_before(a: Dictionary, b: Dictionary) -> bool:
	if str(a["name"]) != str(b["name"]):
		return str(a["name"]) < str(b["name"])
	if str(a["file"]) != str(b["file"]):
		return str(a["file"]) < str(b["file"])
	return int(a["line"]) < int(b["line"])
