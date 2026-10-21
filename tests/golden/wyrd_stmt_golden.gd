class_name WyrdStmtGolden
extends RefCounted

## JSON dump of compiled quest and scene statements.
##
## @experimental
## Condition bodies keep reads, specificity, and [code]uses_chance[/code].
## Opcode listings stay in the condition goldens.

const CASES_DIR := "res://tests/golden/statements"
const EXPECTED_DIR := "res://tests/golden/statements/expected"


static func compile(source: WyrdSource) -> Dictionary:
	var diagnostics := WyrdDiagnostics.new()
	var tree := WyrdParser.new().parse(source, diagnostics)
	var file := WyrdStatements.new().compile(source, tree, diagnostics)
	var quests: Array = []
	for quest in file.quests:
		quests.append(_quest(quest))
	var scenes: Array = []
	for scene in file.scenes:
		scenes.append(_scene(scene))
	var data := {
		"diagnostics": _diagnostics(diagnostics),
		"quests": quests,
		"reads": _reads(file.reads),
		"scenes": scenes,
	}
	if not file.storylets.is_empty():
		var storylets: Array = []
		for story in file.storylets:
			storylets.append(_storylet(story))
		data["storylets"] = storylets
	if not file.documents.is_empty():
		var documents: Array = []
		for document in file.documents:
			documents.append(_document(document))
		data["documents"] = documents
	return data


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


static func _quest(quest: WyrdQuestDef) -> Dictionary:
	var slots: Array = []
	for slot in quest.slots:
		var slot_row := {
			"cast": _cond(slot.cast_when),
			"cast_text": slot.cast_text,
			"locked_stage": slot.locked_stage,
			"mode": String(slot.mode),
			"name": slot.name,
			"reads": _reads(slot.reads),
			"role": slot.role,
			"span": slot.span_data(),
		}
		if not slot.kind.is_empty():
			slot_row["cast_tag"] = slot.cast_tag
			slot_row["kind"] = slot.kind
		slots.append(slot_row)
	var stages: Array = []
	for stage in quest.stages:
		stages.append(_stage(stage))
	return {
		"id": quest.id,
		"on_empty": quest.on_empty,
		"reads": _reads(quest.reads),
		"requires": _strings(quest.requires),
		"slots": slots,
		"span": quest.span_data(),
		"stages": stages,
		"start_text": quest.start_text,
		"start_when": _cond(quest.start_when),
		"title": quest.title,
	}


static func _stage(stage: WyrdStageDef) -> Dictionary:
	var journals: Array = []
	for journal in stage.journals:
		journals.append(_line(journal))
	var variants: Array = []
	for variant in stage.variants:
		variants.append(_variant(variant))
	var data := {
		"effects": _effects(stage.effects),
		"id": stage.id,
		"journals": journals,
		"reads": _reads(stage.reads),
		"scenes": stage.scenes,
		"span": stage.span_data(),
		"transitions": _transitions(stage.transitions),
		"variants": variants,
		"waits_text": stage.waits_text,
		"waits_until": _cond(stage.waits_until),
	}
	if stage.hosts.size() > 0:
		var hosts: Array = []
		for host in stage.hosts:
			var fields: Array = []
			var packed: PackedStringArray = host.get("fields", PackedStringArray())
			for field in packed:
				fields.append(String(field))
			hosts.append({"fields": fields, "line": int(host.get("line", 0)), "screen": String(host.get("screen", ""))})
		data["hosts"] = hosts
	return data


static func _variant(variant: WyrdVariantDef) -> Dictionary:
	return {
		"body": _stage(variant.body) if variant.body != null else null,
		"condition": _cond(variant.condition),
		"condition_text": variant.condition_text,
		"reads": _reads(variant.reads),
		"redirects": variant.redirects,
		"slot": variant.slot,
		"span": variant.span_data(),
		"state": String(variant.state),
	}


static func _scene(scene: WyrdSceneDef) -> Dictionary:
	var items: Array = []
	for item in scene.items:
		items.append(_item(item))
	return {
		"id": scene.id,
		"items": items,
		"on_abort": _effects(scene.on_abort),
		"reads": _reads(scene.reads),
		"span": scene.span_data(),
	}


static func _item(item: WyrdSceneItem) -> Dictionary:
	var data := {
		"divert_kind": String(item.divert_kind),
		"kind": String(item.kind),
		"label": item.label,
		"reads": _reads(item.reads),
		"span": item.span_data(),
		"target": item.target,
	}
	if item.line_def != null:
		data["line"] = _line(item.line_def)
	if item.choice != null:
		data["choice"] = _choice(item.choice)
	if item.effect != null:
		data["effect"] = _effect(item.effect)
	return data


static func _storylet(story: WyrdStoryletDef) -> Dictionary:
	var line_ids: Array = []
	for line_def in story.lines:
		line_ids.append(line_def.line_id)
	var data := {
		"body": String(story.body_kind),
		"effects": _effects(story.effects),
		"id": story.id,
		"line_ids": line_ids,
		"reads": _reads(story.reads),
		"scene": story.scene_id,
		"scope": story.scope_text(),
		"span": story.span_data(),
		"speaker": story.speaker,
	}
	return data


static func _line(line: WyrdLineDef) -> Dictionary:
	return {
		"condition": _cond(line.condition),
		"condition_text": line.condition_text,
		"id": line.line_id,
		"kind": String(line.kind),
		"prose": _prose(line.prose),
		"reads": _reads(line.reads),
		"scene_id": line.scene_id,
		"span": line.span_data(),
		"speaker": line.speaker,
		"tags": _strings(line.tags),
	}


static func _choice(choice: WyrdChoiceDef) -> Dictionary:
	var data := {
		"condition": _cond(choice.condition),
		"condition_text": choice.condition_text,
		"disabled_reason": choice.disabled_reason,
		"disabled_when": choice.disabled_when,
		"effects": _effects(choice.effects),
		"id": choice.line_id,
		"label": _prose(choice.label),
		"reads": _reads(choice.reads),
		"scene_id": choice.scene_id,
		"span": choice.span_data(),
		"tags": _strings(choice.tags),
		"target": choice.target,
	}
	if choice.disabled_condition != null:
		data["disabled_condition"] = _cond(choice.disabled_condition)
	if not choice.check_skill.is_empty():
		var args: Array = []
		for arg in choice.check_args:
			args.append({"name": String(arg["name"]), "text": String(arg["text"])})
		data["check"] = {
			"args": args,
			"on_fail": choice.check_on_fail,
			"skill": choice.check_skill,
		}
	return data


static func _effects(effects: Array) -> Array:
	var rows: Array = []
	for effect in effects:
		rows.append(_effect(effect))
	return rows


static func _effect(effect: WyrdEffectDef) -> Dictionary:
	var args: Array = []
	for arg in effect.args:
		args.append({
			"compiled": _cond(arg["compiled"]),
			"name": String(arg["name"]),
			"text": String(arg["text"]),
		})
	var data := {
		"agent": effect.agent,
		"args": args,
		"branch": effect.branch,
		"command": effect.command,
		"fact_key": effect.fact_key,
		"kind": String(effect.kind),
		"on_fail": effect.on_fail,
		"outcome": effect.outcome,
		"reads": _reads(effect.reads),
		"span": effect.span_data(),
		"target": _cond(effect.target),
		"target_text": effect.target_text,
		"topic": effect.topic,
		"value": _cond(effect.value),
		"value_text": effect.value_text,
		"verb": effect.verb,
	}
	if effect.kind == &"start_quest" or effect.kind == &"advance":
		data["quest"] = effect.quest
	if effect.kind == &"advance":
		data["stage"] = effect.stage
	if effect.kind == &"assign_role" or effect.kind == &"vacate_role":
		data["role"] = effect.role
	if effect.kind == &"assign_role":
		data["entity"] = _cond(effect.entity)
		data["entity_text"] = effect.entity_text
	if effect.kind == &"adjust_baseline":
		data["a"] = _cond(effect.a)
		data["a_text"] = effect.a_text
		data["axis"] = effect.axis
		data["b"] = _cond(effect.b)
		data["b_text"] = effect.b_text
	if effect.kind == &"create_document":
		data["copy"] = effect.copy_id
		data["document"] = effect.document_id
	return data


static func _document(document: WyrdDocumentDef) -> Dictionary:
	var pages: Array = []
	for page in document.pages:
		var paragraphs: Array = []
		for paragraph in page.get("paragraphs", []):
			paragraphs.append({
				"condition": _cond(paragraph.get("condition")),
				"condition_text": str(paragraph.get("condition_text", "")),
				"line_id": str(paragraph.get("line_id", "")),
				"prose": _prose(paragraph.get("prose") as WyrdExprNode),
				"secrecy": str(paragraph.get("secrecy", "")),
				"tags": _packed(paragraph.get("tags", PackedStringArray())),
			})
		pages.append({
			"condition": _cond(page.get("condition")),
			"condition_text": str(page.get("condition_text", "")),
			"paragraphs": paragraphs,
		})
	var data := {
		"fact_key": document.fact_key,
		"fragments": document.fragments.size(),
		"group": document.group,
		"id": document.id,
		"line_id": document.line_id,
		"meta": document.meta.duplicate(true),
		"mode": document.mode,
		"on_first_read": _effects(document.on_first_read),
		"on_read": _effects(document.on_read),
		"pages": pages,
		"period_minutes": document.period_minutes,
		"secrecy": document.secrecy,
		"tags": _packed(document.tags),
		"title": document.title,
	}
	if document.period_minutes > 0:
		data["publish"] = _publish(document)
	return data


static func _publish(document: WyrdDocumentDef) -> Dictionary:
	var fragments: Array = []
	for fragment in document.fragments:
		fragments.append({
			"slant": str(fragment.get("slant", "")),
			"when": _cond(fragment.get("when")),
		})
	return {
		"claim_key": document.claim_key,
		"delay_minutes": document.delay_minutes,
		"fact_key": document.fact_key,
		"fragments": fragments,
		"group": document.group,
		"period_minutes": document.period_minutes,
		"verb_filter": document.verb_filter,
	}


static func _transitions(rows: Array) -> Array:
	var out: Array = []
	for row in rows:
		out.append({
			"col": int(row["col"]),
			"expr": String(row["expr"]),
			"line": int(row["line"]),
			"target": String(row["target"]),
			"when": _cond(row["when"]),
		})
	return out


static func _prose(node: WyrdExprNode) -> Variant:
	if node == null:
		return null
	return _expr_node(node)


static func _expr_node(node: WyrdExprNode) -> Dictionary:
	var data := {"col": node.col, "kind": String(node.kind), "line": node.line}
	if node.text != "":
		data["text"] = node.text
	if node.payload is WyrdCompiledCondition:
		data["compiled"] = _cond(node.payload)
	if node.b != null:
		data["then"] = _expr_node(node.b)
	if node.c != null:
		data["else"] = _expr_node(node.c)
	if not node.kids.is_empty():
		var kids: Array = []
		for kid in node.kids:
			kids.append(_expr_node(kid))
		data["kids"] = kids
	return data


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


static func _packed(values: PackedStringArray) -> Array:
	var rows: Array = []
	for value in values:
		rows.append(String(value))
	return rows


static func _reads(reads: Array) -> Array:
	var rows: Array = []
	for item in reads:
		rows.append(String(item))
	return rows


static func _strings(values: PackedStringArray) -> Array:
	var rows: Array = []
	for item in values:
		rows.append(item)
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
