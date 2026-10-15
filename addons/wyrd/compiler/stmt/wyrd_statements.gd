class_name WyrdStatements
extends RefCounted

## Walks a block tree and emits quest, scene, and effect records.
##
## @experimental
## Conditions reuse [WyrdCondition]. Prose reuses [WyrdInterp].
## The statement grammar is draft, not frozen. See [code]docs/statements-draft.md[/code].

const _WAIT := WyrdCondition.CONTEXT_WAIT
const _STORY := WyrdCondition.CONTEXT_STORYLET
const _BARE_STATES: PackedStringArray = ["default", "successor", "empty", "hostile", "locked_gone"]
const _COND_STATES: PackedStringArray = ["unwilling", "barred"]
const _OUTCOMES: PackedStringArray = ["route_closed", "done", "failed"]
const _DEED_TYPES := {
	"actor": &"entity",
	"magnitude": &"float",
	"memorable": &"bool",
	"place": &"entity",
	"tags": &"set",
	"target": &"entity",
	"visibility": &"symbol",
}

var _lines: PackedStringArray = PackedStringArray()
var _diagnostics: WyrdDiagnostics
var _schema: WyrdFactSchema
var _path: String = ""
var _signatures: WyrdSignatures
var _line_ids: Dictionary = {}
var _labels: Dictionary = {}
var _label_uses: Array = []
var _track_labels: bool = false


func compile(source: WyrdSource, tree: WyrdNode, diagnostics: WyrdDiagnostics) -> WyrdFileDef:
	_lines = source.text.split("\n")
	_diagnostics = diagnostics
	_schema = tree.schema if tree.schema != null else WyrdFactSchema.new()
	_path = source.path
	_signatures = WyrdSignatures.new()
	_line_ids = {}
	_labels = {}
	_label_uses = []
	_track_labels = false
	var file := WyrdFileDef.new()
	file.take_span(tree)
	for child in tree.children:
		if child.keyword == "quest":
			var quest := _quest(child)
			file.quests.append(quest)
			WyrdStmtSpan.add_reads(file.reads, quest.reads)
		elif child.keyword == "scene":
			var scene := _scene(child)
			file.scenes.append(scene)
			WyrdStmtSpan.add_reads(file.reads, scene.reads)
	return file


func _quest(node: WyrdNode) -> WyrdQuestDef:
	var quest := WyrdQuestDef.new()
	quest.take_span(node)
	_line_id(node, false)
	var ident := _dotted_at(node.head, 0)
	quest.id = String(ident["name"])
	quest.title = node.title
	if quest.id.is_empty() or quest.title.is_empty() or int(ident["next"]) != node.head.size():
		_error(WyrdDiagnostic.E_STMT_UNKNOWN, "quest needs an id and a quoted title", node.start_line, node.start_col)
	for child in node.children:
		match child.keyword:
			"slot":
				_slot(child, quest)
			"on_empty":
				_on_empty(child, quest)
			"start":
				_start(child, quest)
			"requires":
				_requires(child, quest)
			"stage":
				_stage(child, quest)
			_:
				_unknown(child)
	_finish_quest(quest)
	return quest


func _finish_quest(quest: WyrdQuestDef) -> void:
	var stage_names := {}
	var slot_names := {}
	for stage in quest.stages:
		if not stage.id.is_empty():
			stage_names[stage.id] = true
	for slot in quest.slots:
		slot_names[slot.name] = true
		if slot.mode == &"locked_at" and not stage_names.has(slot.locked_stage):
			_error(
				WyrdDiagnostic.E_LOCKED_AT_STAGE,
				"locked_at stage \"%s\" is unknown" % slot.locked_stage,
				slot.line,
				slot.col
			)
	for stage in quest.stages:
		_finish_body(stage, stage_names, slot_names)


func _finish_body(stage: WyrdStageDef, stage_names: Dictionary, slot_names: Dictionary) -> void:
	for row in stage.transitions:
		var target := String(row["target"])
		if not stage_names.has(target):
			_error(WyrdDiagnostic.E_STAGE_UNKNOWN, "unknown stage \"%s\"" % target, int(row["line"]), int(row["col"]))
	for ref in stage.scenes:
		for slot in ref["with"]:
			var name := String(slot["name"])
			if not slot_names.has(name):
				_error(WyrdDiagnostic.E_SLOT_UNKNOWN, "unknown slot \"%s\"" % name, int(slot["line"]), int(slot["col"]))
	for variant in stage.variants:
		var slot_name := String(variant.slot)
		if not slot_names.has(slot_name):
			_error(WyrdDiagnostic.E_SLOT_UNKNOWN, "unknown slot \"%s\"" % slot_name, variant.line, variant.col)
		if variant.body != null:
			_finish_body(variant.body, stage_names, slot_names)


func _slot(node: WyrdNode, quest: WyrdQuestDef) -> void:
	_line_id(node, false)
	var items := node.head
	var slot := WyrdSlotDef.new()
	slot.take_span(node)
	if items.size() < 5 or items[0].kind != &"ident" or items[1].kind != &"eq":
		_unknown_msg(node, "slot needs <name> = <role> mode: ...")
		return
	slot.name = items[0].text
	var role := _dotted_at(items, 2)
	slot.role = String(role["name"])
	var i := int(role["next"])
	if slot.role.is_empty() or i >= items.size() or items[i].text != "mode" or i + 1 >= items.size() or items[i + 1].kind != &"colon":
		_unknown_msg(node, "slot needs <name> = <role> mode: ...")
		return
	i += 2
	if i >= items.size() or items[i].kind != &"ident":
		_unknown_msg(node, "slot needs a mode")
		return
	var mode := items[i].text
	if mode == "live" and i + 1 == items.size():
		slot.mode = &"live"
	elif mode == "locked_at":
		if not _call_shape(items, i, 1) or items[i + 2].kind != &"ident":
			_unknown_msg(node, "locked_at needs (<stage>)")
			return
		slot.mode = &"locked_at"
		slot.locked_stage = items[i + 2].text
	elif mode == "cast":
		var close := _closing(items, i + 1, &"lparen", &"rparen")
		if items.size() < i + 2 or items[i + 1].kind != &"lparen" or close < 0 or close + 1 != items.size():
			_unknown_msg(node, "cast needs (<condition>)")
			return
		slot.mode = &"cast"
		var span := _span_text(items, i + 2, close)
		slot.cast_text = span["text"]
		var compiled := _expr(span["text"], int(span["line"]), int(span["col"]), _WAIT, true, &"", slot.reads)
		slot.cast_when = compiled["compiled"]
	else:
		_unknown_msg(node, "unknown slot mode \"%s\"" % mode)
		return
	for prior in quest.slots:
		if prior.name == slot.name:
			_error(WyrdDiagnostic.E_SLOT_DUPLICATE, "duplicate slot \"%s\"" % slot.name, node.start_line, node.start_col)
			_no_block(node)
			return
	quest.slots.append(slot)
	WyrdStmtSpan.add_reads(quest.reads, slot.reads)
	_no_block(node)


func _call_shape(items: Array[WyrdToken], at: int, idents: int) -> bool:
	if at + 2 + idents >= items.size() or items[at + 1].kind != &"lparen":
		return false
	if items[at + 2 + idents].kind != &"rparen" or at + 3 + idents != items.size():
		return false
	for n in idents:
		if items[at + 2 + n].kind != &"ident":
			return false
	return true


func _on_empty(node: WyrdNode, quest: WyrdQuestDef) -> void:
	_line_id(node, false)
	var items := node.head
	if items.size() != 2 or items[0].kind != &"colon" or items[1].kind != &"ident":
		_unknown_msg(node, "on_empty needs a value")
		return
	if not quest.on_empty.is_empty():
		_unknown_msg(node, "duplicate statement \"on_empty\"")
		return
	quest.on_empty = items[1].text
	_no_block(node)


func _start(node: WyrdNode, quest: WyrdQuestDef) -> void:
	_line_id(node, false)
	if node.head.is_empty() or node.head[0].kind != &"ident" or node.head[0].text != "when":
		_unknown_msg(node, "start needs when <condition>")
		return
	if quest.start_when != null:
		_unknown_msg(node, "duplicate statement \"start when\"")
		return
	var span := _span_text(node.head, 1, node.head.size())
	quest.start_text = span["text"]
	var compiled := _expr(span["text"], int(span["line"]), int(span["col"]), _WAIT, true, &"", quest.reads)
	quest.start_when = compiled["compiled"]
	_no_block(node)


func _requires(node: WyrdNode, quest: WyrdQuestDef) -> void:
	_line_id(node, false)
	var items := node.head
	var open := _find(items, 0, &"lbracket", "")
	var close := _closing(items, open, &"lbracket", &"rbracket") if open >= 0 else -1
	if items.is_empty() or items[0].kind != &"colon" or close < 0 or close + 1 != items.size():
		_unknown_msg(node, "requires needs [pack.<id>, ...]")
		return
	var body := String(_span_text(items, open + 1, close)["text"])
	if body.is_empty():
		_unknown_msg(node, "requires needs [pack.<id>, ...]")
		return
	for piece in body.split(","):
		var pack := piece.strip_edges()
		if not _pack_ok(pack):
			_unknown_msg(node, "requires needs [pack.<id>, ...]")
			return
		quest.requires.append(pack)
	quest.requires_line = node.start_line
	quest.requires_col = node.start_col
	_no_block(node)


func _pack_ok(pack: String) -> bool:
	if pack.is_empty():
		return false
	for part in pack.split("."):
		if not _ident_ok(part):
			return false
	return true


func _stage(node: WyrdNode, quest: WyrdQuestDef) -> void:
	var stage := _stage_head(node)
	if stage.id.is_empty():
		return
	for prior in quest.stages:
		if prior.id == stage.id:
			_error(WyrdDiagnostic.E_STAGE_DUPLICATE, "duplicate stage \"%s\"" % stage.id, node.start_line, node.start_col)
	quest.stages.append(stage)
	for child in node.children:
		_stage_stmt(child, stage)
	WyrdStmtSpan.add_reads(quest.reads, stage.reads)


func _stage_head(node: WyrdNode) -> WyrdStageDef:
	var stage := WyrdStageDef.new()
	stage.take_span(node)
	_line_id(node, false)
	if node.head.size() != 1 or node.head[0].kind != &"ident":
		_unknown_msg(node, "stage needs an id")
		return stage
	stage.id = node.head[0].text
	return stage


func _stage_stmt(node: WyrdNode, stage: WyrdStageDef) -> void:
	match node.keyword:
		"waits_until":
			_waits(node, stage)
		"journal":
			_journal(node, stage)
		"scene":
			_scene_ref(node, stage)
		"->":
			_transition(node, stage)
		"~", "outcome":
			_keep_effect(node, stage.effects, stage.reads)
		"variant":
			_variant(node, stage)
		"await_host":
			_await_host(node, stage)
		"redirect":
			_unknown_msg(node, "redirect beat is only valid in a variant")
		_:
			_unknown(node)


func _waits(node: WyrdNode, stage: WyrdStageDef) -> void:
	_line_id(node, false)
	if stage.waits_until != null:
		_unknown_msg(node, "duplicate statement \"waits_until\"")
		return
	var span := _span_text(node.head, 0, node.head.size())
	stage.waits_text = span["text"]
	var compiled := _expr(span["text"], int(span["line"]), int(span["col"]), _WAIT, true, &"", stage.reads)
	stage.waits_until = compiled["compiled"]
	_no_block(node)


func _await_host(node: WyrdNode, stage: WyrdStageDef) -> void:
	_line_id(node, false)
	var items := node.head
	var close := _closing(items, 2, &"lbrace", &"rbrace") if items.size() >= 3 else -1
	var shape := (
		items.size() >= 4
		and items[0].kind == &"ident"
		and items[1].kind == &"ident"
		and items[1].text == "returns"
		and close >= 3
		and close + 1 == items.size()
	)
	if not shape:
		_unknown_msg(node, "await_host needs <screen_id> returns { <field>, ... }")
		return
	var fields := PackedStringArray()
	var i := 3
	while i < close:
		if items[i].kind != &"ident":
			_unknown_msg(node, "await_host needs <screen_id> returns { <field>, ... }")
			return
		fields.append(items[i].text)
		i += 1
		if i < close and items[i].kind == &"comma":
			i += 1
			if i >= close:
				_unknown_msg(node, "await_host needs <screen_id> returns { <field>, ... }")
				return
			continue
		if i != close:
			_unknown_msg(node, "await_host needs <screen_id> returns { <field>, ... }")
			return
	stage.hosts.append({
		"col": node.start_col,
		"fields": fields,
		"line": node.start_line,
		"screen": items[0].text,
	})
	_no_block(node)


func _journal(node: WyrdNode, stage: WyrdStageDef) -> void:
	if node.head.is_empty() or node.head[0].kind != &"colon":
		_unknown_msg(node, "journal text is prose after a colon")
		return
	var line_def := WyrdLineDef.new()
	line_def.take_span(node)
	line_def.kind = &"journal"
	line_def.line_id = _line_id(node, true)
	var tokens := _tail(node.head, 1)
	line_def.prose = _interp(tokens, line_def.reads)
	stage.journals.append(line_def)
	WyrdStmtSpan.add_reads(stage.reads, line_def.reads)
	_no_block(node)


func _scene_ref(node: WyrdNode, stage: WyrdStageDef) -> void:
	_line_id(node, false)
	var found := _dotted_at(node.head, 0)
	var scene_id := String(found["name"])
	var i := int(found["next"])
	if scene_id.is_empty():
		_unknown_msg(node, "scene reference needs a scene id")
		return
	var with_rows: Array = []
	if i < node.head.size():
		if node.head[i].text != "with":
			_unknown_msg(node, "scene reference needs with <slot>")
			return
		i += 1
		while i < node.head.size():
			if node.head[i].kind != &"ident":
				_unknown_msg(node, "scene reference needs with <slot>")
				return
			with_rows.append({"col": node.head[i].col, "line": node.head[i].line, "name": node.head[i].text})
			i += 1
			if i < node.head.size() and node.head[i].kind == &"comma":
				i += 1
				continue
			break
		if i != node.head.size():
			_unknown_msg(node, "scene reference needs with <slot>")
			return
	stage.scenes.append({
		"col": node.start_col,
		"end_col": node.end_col,
		"end_line": node.end_line,
		"id": scene_id,
		"line": node.start_line,
		"with": with_rows,
	})
	_no_block(node)


func _transition(node: WyrdNode, stage: WyrdStageDef) -> void:
	_line_id(node, false)
	var items := node.head
	if items.is_empty() or items[0].kind != &"ident":
		_unknown_msg(node, "stage transition needs a stage id")
		return
	var when: WyrdCompiledCondition = null
	var expr := ""
	if items.size() > 1:
		if items.size() < 3 or items[1].text != "when":
			_unknown_msg(node, "stage transition needs -> <stage> or -> <stage> when <condition>")
			return
		var span := _span_text(items, 2, items.size())
		expr = span["text"]
		var compiled := _expr(span["text"], int(span["line"]), int(span["col"]), _WAIT, true, &"", stage.reads)
		when = compiled["compiled"]
	stage.transitions.append({
		"col": items[0].col,
		"end_col": node.end_col,
		"end_line": node.end_line,
		"expr": expr,
		"line": items[0].line,
		"target": items[0].text,
		"when": when,
	})
	_no_block(node)


func _variant(node: WyrdNode, stage: WyrdStageDef) -> void:
	_line_id(node, false)
	var items := node.head
	var variant := WyrdVariantDef.new()
	variant.take_span(node)
	if items.size() < 3 or items[0].kind != &"ident" or items[1].kind != &"dot" or items[2].kind != &"ident":
		_unknown_msg(node, "variant needs <slot>.<state>:")
		return
	variant.slot = items[0].text
	var state := items[2].text
	var i := 3
	if _COND_STATES.has(state):
		var close := _closing(items, i, &"lparen", &"rparen")
		if i >= items.size() or items[i].kind != &"lparen" or close < 0:
			_error(WyrdDiagnostic.E_SLOT_STATE, "slot state \"%s\" needs a condition" % state, node.start_line, node.start_col)
			return
		var span := _span_text(items, i + 1, close)
		variant.condition_text = span["text"]
		var compiled := _expr(span["text"], int(span["line"]), int(span["col"]), _WAIT, true, &"", variant.reads)
		variant.condition = compiled["compiled"]
		i = close + 1
	elif _BARE_STATES.has(state):
		if i < items.size() and items[i].kind == &"lparen":
			_error(WyrdDiagnostic.E_SLOT_STATE, "slot state \"%s\" does not take a condition" % state, node.start_line, node.start_col)
			return
	else:
		_error(WyrdDiagnostic.E_SLOT_STATE, "unknown slot state \"%s\"" % state, items[2].line, items[2].col)
		return
	if i < items.size() and items[i].kind == &"colon":
		i += 1
	if i != items.size():
		_unknown_msg(node, "variant needs <slot>.<state>:")
		return
	variant.state = StringName(state)
	variant.body = WyrdStageDef.new()
	variant.body.take_span(node)
	for child in node.children:
		if child.keyword == "redirect":
			_redirect(child, variant)
		else:
			_stage_stmt(child, variant.body)
	WyrdStmtSpan.add_reads(variant.reads, variant.body.reads)
	stage.variants.append(variant)
	WyrdStmtSpan.add_reads(stage.reads, variant.reads)


func _redirect(node: WyrdNode, variant: WyrdVariantDef) -> void:
	_line_id(node, false)
	var items := node.head
	if items.size() < 4 or items[0].text != "beat" or items[2].text != "to":
		_unknown_msg(node, "redirect needs beat <beat> to <slot>")
		return
	var beat := items[1].text if items[1].kind == &"ident" else ""
	var slot := _dotted_at(items, 3)
	if beat.is_empty() or String(slot["name"]).is_empty() or int(slot["next"]) != items.size():
		_unknown_msg(node, "redirect needs beat <beat> to <slot>")
		return
	variant.redirects.append({
		"beat": beat,
		"col": node.start_col,
		"line": node.start_line,
		"slot": String(slot["name"]),
	})
	_no_block(node)


func _scene(node: WyrdNode) -> WyrdSceneDef:
	var scene := WyrdSceneDef.new()
	scene.take_span(node)
	_line_id(node, false)
	var found := _dotted_at(node.head, 0)
	scene.id = String(found["name"])
	if scene.id.is_empty() or int(found["next"]) != node.head.size():
		_unknown_msg(node, "scene needs an id")
	_labels = {}
	_label_uses = []
	_track_labels = true
	for child in node.children:
		if child.keyword == "on_abort":
			_on_abort(child, scene)
		else:
			_scene_stmt(child, scene)
	for use in _label_uses:
		if not _labels.has(use["name"]):
			_error(WyrdDiagnostic.E_LABEL_UNKNOWN, "unknown label \"%s\"" % use["name"], int(use["line"]), int(use["col"]))
	_track_labels = false
	return scene


func _on_abort(node: WyrdNode, scene: WyrdSceneDef) -> void:
	_line_id(node, false)
	if not node.head.is_empty() and not (node.head.size() == 1 and node.head[0].kind == &"colon"):
		_unknown_msg(node, "on_abort needs a block of effects")
	for child in node.children:
		_keep_effect(child, scene.on_abort, scene.reads)


func _scene_stmt(node: WyrdNode, scene: WyrdSceneDef) -> void:
	match node.keyword:
		"*":
			_choice(node, scene)
		"->":
			_divert(node, scene)
		"-":
			_label(node, scene)
		"when":
			_when_line(node, scene)
		"on_empty", "requires":
			_unknown(node)
		_:
			var spoken := _speaker(node)
			if int(spoken["colon"]) >= 0:
				if not _shape_ok(String(spoken["name"])):
					_error(WyrdDiagnostic.E_SPEAKER_SHAPE, "invalid speaker \"%s\"" % node.keyword, node.start_line, node.start_col)
					return
				_spoken(node, scene, String(spoken["name"]), int(spoken["colon"]), "")
				return
			_unknown(node)


func _spoken(node: WyrdNode, scene: WyrdSceneDef, speaker: String, colon: int, condition_text: String) -> void:
	var line_def := WyrdLineDef.new()
	line_def.take_span(node)
	line_def.kind = &"spoken"
	line_def.speaker = speaker
	line_def.scene_id = scene.id
	line_def.line_id = _line_id(node, true)
	line_def.condition_text = condition_text
	if not condition_text.is_empty():
		var at := node.head[0] if not node.head.is_empty() else null
		var line := node.start_line if at == null else at.line
		var col := node.start_col if at == null else at.col
		var compiled := _expr(condition_text, line, col, _STORY, true, &"", line_def.reads)
		line_def.condition = compiled["compiled"]
	line_def.prose = _interp(_tail(node.head, colon + 1), line_def.reads)
	var item := WyrdSceneItem.new()
	item.kind = &"line"
	item.line_def = line_def
	item.take_span(node)
	WyrdStmtSpan.add_reads(item.reads, line_def.reads)
	scene.items.append(item)
	WyrdStmtSpan.add_reads(scene.reads, line_def.reads)
	_no_block(node)


func _when_line(node: WyrdNode, scene: WyrdSceneDef) -> void:
	var split := _when_split(node.head)
	if split < 0:
		_unknown_msg(node, "line condition needs when <cond>: <speaker>:")
		return
	var speaker := _dotted_at(node.head, split + 1)
	var name := String(speaker["name"])
	var colon := int(speaker["next"])
	if name.is_empty() or colon >= node.head.size() or node.head[colon].kind != &"colon":
		_unknown_msg(node, "line condition needs when <cond>: <speaker>:")
		return
	if not _shape_ok(name):
		_error(WyrdDiagnostic.E_SPEAKER_SHAPE, "invalid speaker \"%s\"" % name, node.head[split + 1].line, node.head[split + 1].col)
		return
	var span := _span_text(node.head, 0, split)
	_spoken(node, scene, name, colon, span["text"])


func _choice(node: WyrdNode, scene: WyrdSceneDef) -> void:
	var choice := WyrdChoiceDef.new()
	choice.take_span(node)
	choice.scene_id = scene.id
	var items := node.head
	var i := 0
	if i < items.size() and items[i].kind == &"lbrace":
		var close := _closing(items, i, &"lbrace", &"rbrace")
		if close < 0:
			_choice_error(node, "choice condition needs {<condition>}")
			return
		var span := _span_text(items, i + 1, close)
		choice.condition_text = span["text"]
		var compiled := _expr(span["text"], int(span["line"]), int(span["col"]), _STORY, true, &"", choice.reads)
		choice.condition = compiled["compiled"]
		i = close + 1
	var label_at := -1
	if i < items.size() and items[i].kind == &"lbracket":
		label_at = i
		var close := _closing(items, i, &"lbracket", &"rbracket")
		if close < 0:
			_choice_error(node, "choice label needs [<text>]")
			return
		choice.label = _interp(_slice(items, i + 1, close), choice.reads)
		i = close + 1
	if i < items.size() and items[i].kind == &"ident" and items[i].text == "disabled_when":
		if label_at < 0:
			_choice_error(node, "disabled_when follows the label")
			return
		if i + 1 >= items.size() or items[i + 1].kind != &"lbrace":
			_choice_error(node, "disabled_when needs {<condition>} \"<reason>\"")
			return
		var close := _closing(items, i + 1, &"lbrace", &"rbrace")
		if close < 0 or node.title.is_empty():
			_choice_error(node, "disabled_when needs {<condition>} \"<reason>\"")
			return
		choice.disabled_when = _span_text(items, i + 2, close)["text"]
		choice.disabled_reason = node.title
		i = close + 1
	elif not node.title.is_empty():
		_choice_error(node, "choice reason needs disabled_when")
		return
	if i >= items.size() or items[i].kind != &"arrow":
		_choice_error(node, "choice needs -> <target>")
		return
	var target := _dotted_at(items, i + 1)
	if String(target["name"]).is_empty() or int(target["next"]) != items.size() or String(target["name"]).contains("."):
		_choice_error(node, "choice needs -> <target>")
		return
	choice.target = String(target["name"])
	choice.line_id = _line_id(node, label_at >= 0)
	_note_label(choice.target, items[i + 1].line, items[i + 1].col)
	for child in node.children:
		_keep_effect(child, choice.effects, choice.reads)
	var item := WyrdSceneItem.new()
	item.kind = &"choice"
	item.choice = choice
	item.take_span(node)
	WyrdStmtSpan.add_reads(item.reads, choice.reads)
	scene.items.append(item)
	WyrdStmtSpan.add_reads(scene.reads, choice.reads)


func _divert(node: WyrdNode, scene: WyrdSceneDef) -> void:
	_line_id(node, false)
	var items := node.head
	var item := WyrdSceneItem.new()
	item.kind = &"divert"
	item.take_span(node)
	if items.size() == 1 and items[0].text == "end":
		item.divert_kind = &"end"
		item.target = "end"
	elif not items.is_empty() and items[0].text == "scene":
		var scene_id := _dotted_at(items, 1)
		if String(scene_id["name"]).is_empty() or int(scene_id["next"]) != items.size():
			_unknown_msg(node, "divert needs -> scene <id>")
			return
		item.divert_kind = &"scene"
		item.target = String(scene_id["name"])
	else:
		var label := _dotted_at(items, 0)
		if String(label["name"]).is_empty() or int(label["next"]) != items.size() or String(label["name"]).contains("."):
			_unknown_msg(node, "divert needs a label, end, or scene <id>")
			return
		item.divert_kind = &"label"
		item.target = String(label["name"])
		_note_label(item.target, items[0].line, items[0].col)
	scene.items.append(item)
	WyrdStmtSpan.add_reads(scene.reads, item.reads)
	_no_block(node)


func _label(node: WyrdNode, scene: WyrdSceneDef) -> void:
	_line_id(node, false)
	var items := node.head
	if items.size() != 3 or items[0].kind != &"lparen" or items[1].kind != &"ident" or items[2].kind != &"rparen":
		_unknown_msg(node, "label needs - (<name>)")
		return
	var name := items[1].text
	if _labels.has(name):
		_error(WyrdDiagnostic.E_LABEL_DUPLICATE, "duplicate label \"%s\"" % name, node.start_line, node.start_col)
	else:
		_labels[name] = true
	var item := WyrdSceneItem.new()
	item.kind = &"label"
	item.label = name
	item.take_span(node)
	scene.items.append(item)
	_no_block(node)


func _keep_effect(node: WyrdNode, effects: Array[WyrdEffectDef], into: Array[StringName]) -> void:
	if node.keyword == "on_fail":
		_attach_on_fail(node, effects)
		return
	var effect := _effect(node)
	if effect == null:
		return
	effects.append(effect)
	WyrdStmtSpan.add_reads(into, effect.reads)
	for child in node.children:
		if child.keyword == "on_fail":
			_attach_on_fail(child, effects)
		else:
			_unknown(child)


func _attach_on_fail(node: WyrdNode, effects: Array[WyrdEffectDef]) -> void:
	_line_id(node, false)
	var items := node.head
	if items.size() < 2 or items[0].kind != &"arrow":
		_unknown_msg(node, "on_fail needs -> <target>")
		return
	var target := _dotted_at(items, 1)
	if String(target["name"]).is_empty() or int(target["next"]) != items.size():
		_unknown_msg(node, "on_fail needs -> <target>")
		return
	if effects.is_empty() or effects[effects.size() - 1].kind != &"do" or not effects[effects.size() - 1].on_fail.is_empty():
		_unknown_msg(node, "on_fail follows a do effect")
		return
	effects[effects.size() - 1].on_fail = String(target["name"])
	_note_label(String(target["name"]), items[1].line, items[1].col)
	_no_block(node)


func _effect(node: WyrdNode) -> WyrdEffectDef:
	_line_id(node, false)
	if node.keyword == "outcome":
		var bare := _outcome(node, node.head)
		if bare == null:
			_no_block(node)
		return bare
	if node.keyword != "~":
		_unknown(node)
		return null
	var items := node.head
	if items.is_empty() or items[0].kind != &"ident":
		_unknown_msg(node, "effect needs a name")
		return null
	if items[0].text == "set_disposition":
		_error(
			WyrdDiagnostic.E_NO_SET_DISPOSITION,
			"record deeds or use adjust baseline (§2.5)",
			items[0].line,
			items[0].col
		)
		_no_block(node)
		return null
	var rejected := _rejected(items)
	if not rejected.is_empty():
		_error(WyrdDiagnostic.E_EFFECT_NOT_IN_SLICE, "effect \"%s\" is not in this slice" % rejected, items[0].line, items[0].col)
		_no_block(node)
		return null
	var effect := WyrdEffectDef.new()
	effect.take_span(node)
	match items[0].text:
		"set":
			effect.kind = &"set"
			if not _assign(effect, items, false):
				_no_block(node)
				return null
		"inc":
			effect.kind = &"inc"
			if not _assign(effect, items, true):
				_no_block(node)
				return null
		"record":
			effect.kind = &"record_deed"
			if not _deed(effect, items):
				_no_block(node)
				return null
		"unlock":
			effect.kind = &"unlock_topic"
			if not _unlock(effect, items):
				_no_block(node)
				return null
		"do":
			effect.kind = &"do"
			if not _command(effect, items):
				_no_block(node)
				return null
		"outcome":
			var outcome := _outcome(node, _tail(items, 1))
			if outcome == null:
				_no_block(node)
			return outcome
		_:
			_error(WyrdDiagnostic.E_EFFECT_NOT_IN_SLICE, "effect \"%s\" is not in this slice" % items[0].text, items[0].line, items[0].col)
			_no_block(node)
			return null
	return effect


func _rejected(items: Array[WyrdToken]) -> String:
	var first := items[0].text
	var second := items[1].text if items.size() > 1 and items[1].kind == &"ident" else ""
	if first == "lock" and second == "topic":
		return "lock topic"
	if first == "start" and second == "quest":
		return "start quest"
	if first == "advance":
		return "advance"
	if first == "assign" and second == "role":
		return "assign role"
	if first == "vacate" and second == "role":
		return "vacate role"
	if first == "adjust" and second == "baseline":
		return "adjust baseline"
	if first == "create" and second == "document":
		return "create document"
	if first == "record" and second != "deed":
		return "record"
	if first == "unlock" and second != "topic":
		return "unlock"
	return ""


func _assign(effect: WyrdEffectDef, items: Array[WyrdToken], is_inc: bool) -> bool:
	var sep := _find(items, 1, &"ident", "by") if is_inc else _find(items, 1, &"eq", "")
	if sep < 0:
		_unknown_msg_at(effect, "set needs <fact> = <expr>" if not is_inc else "inc needs <fact> by <expr>")
		return false
	var target_span := _span_text(items, 1, sep)
	var value_span := _span_text(items, sep + 1, items.size())
	effect.target_text = target_span["text"]
	effect.value_text = value_span["text"]
	var target := _expr(target_span["text"], int(target_span["line"]), int(target_span["col"]), _STORY, false, &"", effect.reads)
	effect.target = target["compiled"]
	var fact := _stored_fact(target["ast"], effect)
	var expected: StringName = fact.type_name if fact != null else &""
	if is_inc and fact != null and fact.type_name != &"int" and fact.type_name != &"float":
		_error(WyrdDiagnostic.E_WRITE_TYPE, "inc needs an int or float fact", effect.line, effect.col)
		expected = &""
	var value := _expr(value_span["text"], int(value_span["line"]), int(value_span["col"]), _STORY, false, expected, effect.reads)
	effect.value = value["compiled"]
	if fact != null and value["ast"] != null and expected != &"" and not _fits((value["ast"] as WyrdExprNode).type_name, fact.type_name):
		_error(
			WyrdDiagnostic.E_WRITE_TYPE,
			"cannot write %s to %s fact \"%s\"" % [(value["ast"] as WyrdExprNode).type_name, fact.type_name, fact.key],
			int(value_span["line"]),
			int(value_span["col"])
		)
	return true


func _stored_fact(ast: WyrdExprNode, effect: WyrdEffectDef) -> WyrdFact:
	if ast == null or ast.type_name == &"error":
		return null
	if ast.kind != &"fact":
		_error(WyrdDiagnostic.E_UNKNOWN_FACT, "unknown fact \"%s\"" % ast.text, ast.line, ast.col)
		return null
	var fact := _schema.lookup(_segments(ast.text))
	if fact == null:
		return null
	effect.fact_key = fact.key
	if fact.origin != &"stored":
		_error(WyrdDiagnostic.E_WRITE_RESOLVED, "cannot write resolved fact \"%s\"" % fact.key, ast.line, ast.col)
		return null
	return fact


func _deed(effect: WyrdEffectDef, items: Array[WyrdToken]) -> bool:
	if items.size() < 4 or items[1].text != "deed" or items[2].kind != &"ident" or items[3].kind != &"lparen":
		_unknown_msg_at(effect, "record deed needs <verb>(...)")
		return false
	var close := _closing(items, 3, &"lparen", &"rparen")
	if close < 0 or close + 1 != items.size():
		_unknown_msg_at(effect, "record deed needs <verb>(...)")
		return false
	effect.verb = items[2].text
	var seen := {}
	var rows := _arg_rows(items, 4, close)
	for row in rows:
		var name := String(row["name"])
		if name.is_empty():
			_error(WyrdDiagnostic.E_ARG_NAME, "deed arguments are named", int(row["line"]), int(row["col"]))
			continue
		if not _DEED_TYPES.has(name) and name != "witnesses":
			_error(WyrdDiagnostic.E_ARG_NAME, "deed has no argument \"%s\"" % name, int(row["line"]), int(row["col"]))
			continue
		if seen.has(name):
			_error(WyrdDiagnostic.E_ARG_NAME, "deed argument \"%s\" is duplicated" % name, int(row["line"]), int(row["col"]))
			continue
		seen[name] = true
		var expected: StringName = &"symbol" if name == "witnesses" and _witness_auto(items, int(row["from"]), int(row["to"])) else _DEED_TYPES.get(name, &"set")
		if name == "witnesses" and expected != &"symbol":
			expected = &"set"
		var compiled := _expr(String(row["text"]), int(row["line"]), int(row["col"]), _STORY, false, expected, effect.reads)
		var got: StringName = &"error"
		if compiled["ast"] != null:
			got = (compiled["ast"] as WyrdExprNode).type_name
		if not _fits(got, expected):
			_error(
				WyrdDiagnostic.E_ARG_TYPE,
				"deed argument \"%s\" expects %s, got %s" % [name, expected, got],
				int(row["line"]),
				int(row["col"])
			)
		effect.args.append({"compiled": compiled["compiled"], "name": name, "text": String(row["text"])})
	if not seen.has("actor"):
		_error(WyrdDiagnostic.E_ARG_TYPE, "deed missing argument \"actor\"", effect.line, effect.col)
	return true


func _witness_auto(items: Array[WyrdToken], start: int, end: int) -> bool:
	return end == start + 1 and items[start].kind == &"ident" and items[start].text == "auto"


func _unlock(effect: WyrdEffectDef, items: Array[WyrdToken]) -> bool:
	if items.size() < 2 or items[1].text != "topic":
		_unknown_msg_at(effect, "unlock needs topic <id>")
		return false
	var topic := _dotted_at(items, 2)
	if String(topic["name"]).is_empty() or int(topic["next"]) != items.size():
		_unknown_msg_at(effect, "unlock needs topic <id>")
		return false
	effect.topic = String(topic["name"])
	return true


func _command(effect: WyrdEffectDef, items: Array[WyrdToken]) -> bool:
	if items.size() < 3 or items[1].kind != &"ident" or items[2].kind != &"lparen":
		_unknown_msg_at(effect, "do needs <command>(...)")
		return false
	var close := _closing(items, 2, &"lparen", &"rparen")
	if close < 0:
		_unknown_msg_at(effect, "do needs <command>(...)")
		return false
	effect.command = items[1].text
	var seen := {}
	for row in _arg_rows(items, 3, close):
		var name := String(row["name"])
		if not name.is_empty() and seen.has(name):
			_error(WyrdDiagnostic.E_ARG_NAME, "command argument \"%s\" is duplicated" % name, int(row["line"]), int(row["col"]))
			continue
		if not name.is_empty():
			seen[name] = true
		var expected := _command_expected(items, int(row["from"]), int(row["to"]))
		var compiled := _expr(String(row["text"]), int(row["line"]), int(row["col"]), _STORY, false, expected, effect.reads)
		effect.args.append({"compiled": compiled["compiled"], "name": name, "text": String(row["text"])})
	var i := close + 1
	if i < items.size():
		if i + 2 >= items.size() or items[i].text != "on_fail" or items[i + 1].kind != &"arrow":
			_unknown_msg_at(effect, "do on_fail needs -> <target>")
			return false
		var target := _dotted_at(items, i + 2)
		if String(target["name"]).is_empty() or int(target["next"]) != items.size():
			_unknown_msg_at(effect, "do on_fail needs -> <target>")
			return false
		effect.on_fail = String(target["name"])
		_note_label(effect.on_fail, items[i + 2].line, items[i + 2].col)
	return true


func _command_expected(items: Array[WyrdToken], start: int, end: int) -> StringName:
	if not _pure_path(items, start, end):
		return &""
	var segments := PackedStringArray()
	for i in range(start, end):
		if items[i].kind == &"ident":
			segments.append(items[i].text)
	if _schema.lookup(segments) != null:
		return &""
	return WyrdSignatures.T_ENTITY


func _outcome(node: WyrdNode, items: Array[WyrdToken]) -> WyrdEffectDef:
	if items.size() != 3 or items[0].kind != &"ident" or items[1].kind != &"eq" or items[2].kind != &"ident":
		_unknown_msg(node, "outcome needs <branch> = route_closed, done, or failed")
		return null
	if not _OUTCOMES.has(items[2].text):
		_error(WyrdDiagnostic.E_EFFECT_NOT_IN_SLICE, "effect \"%s\" is not in this slice" % items[2].text, items[2].line, items[2].col)
		return null
	var effect := WyrdEffectDef.new()
	effect.take_span(node)
	effect.kind = &"outcome"
	effect.branch = items[0].text
	effect.outcome = items[2].text
	return effect


func _arg_rows(items: Array[WyrdToken], start: int, end: int) -> Array:
	var rows: Array = []
	var i := start
	while i < end:
		var name := ""
		var value_at := i
		if items[i].kind == &"ident" and i + 1 < end and items[i + 1].kind == &"colon":
			name = items[i].text
			value_at = i + 2
		var j := value_at
		var depth := 0
		while j < end:
			var kind := items[j].kind
			if kind == &"lparen" or kind == &"lbrace" or kind == &"lbracket":
				depth += 1
			elif kind == &"rparen" or kind == &"rbrace" or kind == &"rbracket":
				depth -= 1
			elif depth == 0 and kind == &"comma":
				break
			j += 1
		var span := _span_text(items, value_at, j)
		rows.append({
			"col": int(span["col"]),
			"from": value_at,
			"line": int(span["line"]),
			"name": name,
			"text": span["text"],
			"to": j,
		})
		i = j + 1 if j < end and items[j].kind == &"comma" else end
	return rows


func _pure_path(items: Array[WyrdToken], start: int, end: int) -> bool:
	if start >= end or items[start].kind != &"ident":
		return false
	var want_ident := true
	for i in range(start, end):
		var kind := items[i].kind
		if want_ident and kind != &"ident":
			return false
		if not want_ident and kind != &"dot":
			return false
		want_ident = not want_ident
	return not want_ident


func _expr(
	text: String,
	line: int,
	col: int,
	context: StringName,
	require_bool: bool,
	expected: StringName,
	into: Array[StringName]
) -> Dictionary:
	if text.strip_edges().is_empty():
		_error(WyrdDiagnostic.E_EXPR_SYNTAX, "expected an expression", line, col)
		return {"ast": null, "compiled": null}
	var compiler := WyrdCondition.new()
	var compiled := compiler.compile(
		text, _schema, _diagnostics, _path, line, col, context, WyrdCondition.MINUTES_PER_DAY, _signatures, require_bool, expected
	)
	WyrdStmtSpan.add_reads(into, compiled.reads)
	return {"ast": compiler.ast, "compiled": compiled}


func _interp(tokens: Array[WyrdToken], into: Array[StringName]) -> WyrdExprNode:
	var root := WyrdInterp.new().compile_line(
		tokens, _schema, _diagnostics, _path, _STORY, WyrdCondition.MINUTES_PER_DAY, _signatures
	)
	_gather(root, into)
	return root


func _gather(node: WyrdExprNode, into: Array[StringName]) -> void:
	if node == null:
		return
	if node.payload is WyrdCompiledCondition:
		WyrdStmtSpan.add_reads(into, (node.payload as WyrdCompiledCondition).reads)
	_gather(node.a, into)
	_gather(node.b, into)
	_gather(node.c, into)
	for kid in node.kids:
		_gather(kid, into)


func _line_id(node: WyrdNode, required: bool) -> String:
	if node.line_tag.is_empty():
		if required:
			_error(WyrdDiagnostic.E_LINE_ID_MISSING, "missing #line: id; run tag-lines (S1d)", node.start_line, node.start_col)
		return ""
	if _line_ids.has(node.line_tag):
		_error(WyrdDiagnostic.E_LINE_ID_DUPLICATE, "duplicate #line: id \"%s\"" % node.line_tag, node.start_line, node.start_col)
	else:
		_line_ids[node.line_tag] = true
	return node.line_tag


func _note_label(name: String, line: int, col: int) -> void:
	if not _track_labels or name == "end" or name.is_empty():
		return
	_label_uses.append({"col": col, "line": line, "name": name})


func _speaker(node: WyrdNode) -> Dictionary:
	var parts := PackedStringArray()
	if _shape_ok(node.keyword):
		parts.append(node.keyword)
	var i := 0
	while i < node.head.size() and node.head[i].kind == &"dot":
		i += 1
		if i < node.head.size() and node.head[i].kind == &"ident":
			parts.append(node.head[i].text)
			i += 1
		else:
			break
	var colon := i if i < node.head.size() and node.head[i].kind == &"colon" else -1
	return {"colon": colon, "name": ".".join(parts)}


func _when_split(items: Array[WyrdToken]) -> int:
	var depth := 0
	for i in items.size():
		var kind := items[i].kind
		if kind == &"lparen" or kind == &"lbrace" or kind == &"lbracket":
			depth += 1
		elif kind == &"rparen" or kind == &"rbrace" or kind == &"rbracket":
			depth = maxi(depth - 1, 0)
		elif depth == 0 and kind == &"colon":
			var speaker := _dotted_at(items, i + 1)
			var next := int(speaker["next"])
			if String(speaker["name"]) != "" and next < items.size() and items[next].kind == &"colon":
				return i
	return -1


func _dotted_at(items: Array[WyrdToken], start: int) -> Dictionary:
	if start >= items.size() or items[start].kind != &"ident":
		return {"name": "", "next": start}
	var parts := PackedStringArray()
	var i := start
	while i < items.size() and items[i].kind == &"ident":
		parts.append(items[i].text)
		i += 1
		if i < items.size() and items[i].kind == &"dot":
			i += 1
			if i >= items.size() or items[i].kind != &"ident":
				return {"name": "", "next": i}
			continue
		break
	return {"name": ".".join(parts), "next": i}


func _span_text(items: Array[WyrdToken], start: int, end: int) -> Dictionary:
	if start < 0 or start >= end or start >= items.size():
		var line := 1
		var col := 1
		if start >= 0 and start < items.size():
			line = items[start].line
			col = items[start].col
		return {"col": col, "line": line, "text": ""}
	var first := items[start]
	var last := items[end - 1]
	var raw := ""
	var idx := first.line - 1
	if first.line == last.line and idx >= 0 and idx < _lines.size():
		var row := _lines[idx]
		var a := clampi(first.col - 1, 0, row.length())
		var b := clampi(last.end_col - 1, a, row.length())
		raw = row.substr(a, b - a)
	var skip := 0
	while skip < raw.length() and (raw[skip] == " " or raw[skip] == "\t"):
		skip += 1
	return {"col": first.col + skip, "line": first.line, "text": raw.substr(skip).strip_edges()}


func _closing(items: Array[WyrdToken], open_at: int, open: StringName, close: StringName) -> int:
	if open_at >= items.size() or items[open_at].kind != open:
		return -1
	var depth := 0
	for i in range(open_at, items.size()):
		if items[i].kind == open:
			depth += 1
		elif items[i].kind == close:
			depth -= 1
			if depth == 0:
				return i
	return -1


func _find(items: Array[WyrdToken], start: int, kind: StringName, word: String) -> int:
	var depth := 0
	for i in range(start, items.size()):
		var token_kind := items[i].kind
		if depth == 0 and token_kind == kind and (word.is_empty() or items[i].text == word):
			return i
		if token_kind == &"lparen" or token_kind == &"lbrace" or token_kind == &"lbracket":
			depth += 1
		elif token_kind == &"rparen" or token_kind == &"rbrace" or token_kind == &"rbracket":
			depth = maxi(depth - 1, 0)
	return -1


func _tail(items: Array[WyrdToken], start: int) -> Array[WyrdToken]:
	var out: Array[WyrdToken] = []
	for i in range(start, items.size()):
		out.append(items[i])
	return out


func _slice(items: Array[WyrdToken], start: int, end: int) -> Array[WyrdToken]:
	var out: Array[WyrdToken] = []
	for i in range(start, end):
		out.append(items[i])
	return out


func _segments(key: String) -> PackedStringArray:
	var parts := PackedStringArray()
	for part in key.split("."):
		parts.append(part)
	return parts


func _fits(actual: StringName, expected: StringName) -> bool:
	if actual == &"error" or expected == &"":
		return true
	if actual == expected:
		return true
	return actual == &"int" and expected == &"float"


func _shape_ok(name: String) -> bool:
	if name.is_empty() or name.contains(" "):
		return false
	for part in name.split("."):
		if part.is_empty() or not _ident_ok(part):
			return false
	return true


func _ident_ok(part: String) -> bool:
	var first := part[0]
	if not ((first >= "A" and first <= "Z") or (first >= "a" and first <= "z") or first == "_"):
		return false
	for i in part.length():
		var ch := part[i]
		var ok := (ch >= "A" and ch <= "Z") or (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_"
		if not ok:
			return false
	return true


func _no_block(node: WyrdNode) -> void:
	for child in node.children:
		_unknown(child)


func _unknown(node: WyrdNode) -> void:
	_line_id(node, false)
	_error(WyrdDiagnostic.E_STMT_UNKNOWN, "unknown statement \"%s\"" % node.keyword, node.start_line, node.start_col)
	_no_block(node)


func _unknown_msg(node: WyrdNode, message: String) -> void:
	_error(WyrdDiagnostic.E_STMT_UNKNOWN, message, node.start_line, node.start_col)
	_no_block(node)


func _unknown_msg_at(effect: WyrdEffectDef, message: String) -> void:
	_error(WyrdDiagnostic.E_STMT_UNKNOWN, message, effect.line, effect.col)


func _choice_error(node: WyrdNode, message: String) -> void:
	_error(WyrdDiagnostic.E_CHOICE_SYNTAX, message, node.start_line, node.start_col)
	_no_block(node)


func _error(code: StringName, message: String, line: int, col: int) -> void:
	_diagnostics.add(code, message, _path, line, col)
