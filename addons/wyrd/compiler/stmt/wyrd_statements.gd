class_name WyrdStatements
extends RefCounted

## Walks a block tree and emits quest, scene, storylet, document, and effect records.
##
## @experimental
## Conditions reuse [WyrdCondition]. Prose reuses [WyrdInterp].
## The statement grammar is draft, not frozen. See [code]docs/statements-draft.md[/code].

const _WAIT := WyrdCondition.CONTEXT_WAIT
const _STORY := WyrdCondition.CONTEXT_STORYLET
const _ROLE_FIELDS := {
	"default_holder": true,
	"eligibility": true,
	"scope": true,
	"succession": true,
	"vacancy": true,
	"visibility": true,
}
const _BARE_STATES: PackedStringArray = ["default", "successor", "empty", "hostile", "locked_gone", "contested"]
const _COND_STATES: PackedStringArray = ["unwilling", "barred"]
const _OUTCOMES: PackedStringArray = ["route_closed", "done", "failed"]
const _DEED_TYPES := {
	"actor": &"entity",
	"magnitude": &"float",
	"memorable": &"bool",
	"place": &"entity",
	"statement": &"bool",
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
## Id sites for tag-lines. Not saved and not part of the pack hash.
var line_sites: Array = []
var _line_owner := ""
var _labels: Dictionary = {}
var _label_uses: Array = []
var _track_labels: bool = false
var _events: Dictionary = {}
var _event_fields: Dictionary = {}


func compile(
	source: WyrdSource,
	tree: WyrdNode,
	diagnostics: WyrdDiagnostics,
	events: Dictionary = {}
) -> WyrdFileDef:
	_lines = source.text.split("\n")
	_diagnostics = diagnostics
	_schema = tree.schema if tree.schema != null else WyrdFactSchema.new()
	_path = source.path
	_signatures = WyrdSignatures.new()
	_line_ids = {}
	line_sites = []
	_line_owner = ""
	_labels = {}
	_label_uses = []
	_track_labels = false
	_events = events
	_event_fields = {}
	var file := WyrdFileDef.new()
	file.take_span(tree)
	var seen_roles := {}
	var seen_storylets := {}
	var seen_sequences := {}
	var seen_documents := {}
	for child in tree.children:
		if child.keyword == "quest":
			var quest := _quest(child)
			file.quests.append(quest)
			WyrdStmtSpan.add_reads(file.reads, quest.reads)
		elif child.keyword == "scene":
			var scene := _scene(child)
			file.scenes.append(scene)
			WyrdStmtSpan.add_reads(file.reads, scene.reads)
		elif child.keyword == "role":
			var role := _compile_role(child)
			if role.id.is_empty():
				continue
			if seen_roles.has(role.id):
				_error(WyrdDiagnostic.E_ROLE_DUPLICATE, "duplicate role \"%s\"" % role.id, role.line, role.col)
				continue
			seen_roles[role.id] = true
			file.roles.append(role)
			WyrdStmtSpan.add_reads(file.reads, role.reads)
		elif child.keyword == "storylet":
			var storylet := _storylet(child)
			if storylet.id.is_empty():
				continue
			if seen_storylets.has(storylet.id):
				_error(WyrdDiagnostic.E_STORYLET_DUPLICATE, "duplicate storylet \"%s\"" % storylet.id, storylet.line, storylet.col)
				continue
			seen_storylets[storylet.id] = true
			file.storylets.append(storylet)
			WyrdStmtSpan.add_reads(file.reads, storylet.reads)
		elif child.keyword == "sequence":
			var sequence := _sequence(child)
			if sequence.id.is_empty():
				continue
			if seen_sequences.has(sequence.id):
				_error(WyrdDiagnostic.E_SEQUENCE_DUPLICATE, "duplicate sequence \"%s\"" % sequence.id, sequence.line, sequence.col)
				continue
			seen_sequences[sequence.id] = true
			file.sequences.append(sequence)
			WyrdStmtSpan.add_reads(file.reads, sequence.reads)
		elif child.keyword == "document":
			var document := _compile_document(child)
			if document.id.is_empty():
				continue
			if seen_documents.has(document.id):
				_error(WyrdDiagnostic.E_DOCUMENT_DUPLICATE, "duplicate document \"%s\"" % document.id, document.line, document.col)
				continue
			seen_documents[document.id] = true
			file.documents.append(document)
			WyrdStmtSpan.add_reads(file.reads, document.reads)
	return file


func _compile_document(node: WyrdNode) -> WyrdDocumentDef:
	var document := WyrdDocumentDef.new()
	document.take_span(node)
	document.title = node.title
	var items := node.head
	var ident := _dotted_at(items, 0)
	document.id = String(ident["name"])
	var cursor := int(ident["next"])
	if document.id.is_empty():
		_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "document needs an id", node.start_line, node.start_col)
		document.id = ""
		return document
	if _header_periodic(items):
		return _compile_periodic_document(node, document, items, cursor)
	return _compile_readable_document(node, document, items, cursor)


func _header_periodic(items: Array[WyrdToken]) -> bool:
	for token in items:
		if token.kind != &"ident":
			continue
		if token.text == "publishes_by" or token.text == "every" or token.text == "delay":
			return true
	return false


func _compile_periodic_document(node: WyrdNode, document: WyrdDocumentDef, items: Array[WyrdToken], cursor: int) -> WyrdDocumentDef:
	if not node.line_tag.is_empty():
		_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "a line tag is not allowed on a document", node.start_line, node.start_col)
	if not _is_word(items, cursor, "publishes_by"):
		_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "document needs publishes_by", node.start_line, node.start_col)
		document.id = ""
		return document
	cursor += 1
	var group := _dotted_at(items, cursor)
	document.group = String(group["name"])
	cursor = int(group["next"])
	if document.group.is_empty():
		_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "document needs a group", node.start_line, node.start_col)
		document.id = ""
		return document
	if not _is_word(items, cursor, "every"):
		_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "document needs every", node.start_line, node.start_col)
		document.id = ""
		return document
	cursor += 1
	var period := _duration(items, cursor)
	cursor = int(period["next"])
	if not bool(period["ok"]):
		_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, String(period["message"]), int(period["line"]), int(period["col"]))
		document.id = ""
		return document
	document.period_minutes = int(period["minutes"])
	if document.period_minutes <= 0:
		_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "document period must be greater than zero", int(period["line"]), int(period["col"]))
		document.id = ""
		return document
	if not _is_word(items, cursor, "delay"):
		_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "document needs delay", node.start_line, node.start_col)
		document.id = ""
		return document
	cursor += 1
	var delay := _duration(items, cursor)
	cursor = int(delay["next"])
	if not bool(delay["ok"]):
		_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, String(delay["message"]), int(delay["line"]), int(delay["col"]))
		document.id = ""
		return document
	document.delay_minutes = int(delay["minutes"])
	if cursor != items.size():
		_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "unexpected token on a document", items[cursor].line, items[cursor].col)
		document.id = ""
		return document
	var seen := {}
	for child in node.children:
		if not child.line_tag.is_empty():
			_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "a line tag is not allowed on a document", child.start_line, child.start_col)
		var field := child.keyword
		if field == "fragment":
			_document_fragment(child, document)
			continue
		if field == "text" or field == "meta" or field == "page" or field == "on_read" or field == "on_first_read":
			_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "readable field \"%s\" is not valid on a periodic document" % field, child.start_line, child.start_col)
			continue
		if field != "claim" and field != "fact" and field != "verb":
			_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "unknown document field \"%s\"" % field, child.start_line, child.start_col)
			continue
		if seen.has(field):
			_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "duplicate document field \"%s\"" % field, child.start_line, child.start_col)
			continue
		seen[field] = true
		if not child.children.is_empty():
			_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "document field \"%s\" cannot contain a block" % field, child.start_line, child.start_col)
			continue
		var named := _dotted_at(child.head, 0)
		var key := String(named["name"])
		if key.is_empty() or int(named["next"]) != child.head.size():
			_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "document field \"%s\" needs a value" % field, child.start_line, child.start_col)
			continue
		if field == "verb":
			document.verb_filter = key
			continue
		_document_fact(child, document, field, key)
	return document


func _compile_readable_document(node: WyrdNode, document: WyrdDocumentDef, items: Array[WyrdToken], cursor: int) -> WyrdDocumentDef:
	var saved_owner := _line_owner
	_line_owner = document.id
	document.mode = ""
	document.line_id = _line_id(node, false)
	_note_line_site(node, false)
	document.tags = node.tags.duplicate()
	document.secrecy = node.secrecy
	if document.title.is_empty():
		_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "document needs a title", node.start_line, node.start_col)
	if cursor != items.size():
		_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "unexpected token on a document", items[cursor].line, items[cursor].col)
	var seen := {}
	var saw_page := false
	for child in node.children:
		var field := child.keyword
		if field == "text":
			if seen.has("text"):
				_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "duplicate document field \"text\"", child.start_line, child.start_col)
				continue
			seen["text"] = true
			document.mode = _document_text(child)
			continue
		if field == "meta":
			if seen.has("meta"):
				_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "duplicate document field \"meta\"", child.start_line, child.start_col)
				continue
			seen["meta"] = true
			_document_meta(child, document)
			continue
		if field == "page":
			saw_page = true
			_document_page(child, document)
			continue
		if field == "on_first_read" or field == "on_read":
			if seen.has(field):
				_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "duplicate document field \"%s\"" % field, child.start_line, child.start_col)
				continue
			seen[field] = true
			var effects: Array[WyrdEffectDef] = document.on_first_read if field == "on_first_read" else document.on_read
			_document_read_block(child, effects, document.reads)
			continue
		_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "unknown document field \"%s\"" % field, child.start_line, child.start_col)
	if not seen.has("text"):
		_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "document needs text:", node.start_line, node.start_col)
	if not saw_page:
		_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "document needs a page", node.start_line, node.start_col)
	_line_owner = saved_owner
	return document


func _document_text(node: WyrdNode) -> String:
	if not node.children.is_empty():
		_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "document field \"text\" cannot contain a block", node.start_line, node.start_col)
	var items := node.head
	var cursor := 0
	if cursor < items.size() and items[cursor].kind == &"colon":
		cursor += 1
	if cursor >= items.size() or items[cursor].kind != &"ident" or (items[cursor].text != "live" and items[cursor].text != "frozen"):
		_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "text: needs live or frozen", node.start_line, node.start_col)
		return ""
	if cursor + 1 != items.size():
		_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "text: needs live or frozen", items[cursor + 1].line, items[cursor + 1].col)
		return ""
	return items[cursor].text


func _document_meta(node: WyrdNode, document: WyrdDocumentDef) -> void:
	if not node.children.is_empty():
		_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "document field \"meta\" cannot contain a block", node.start_line, node.start_col)
	var items := node.head
	if items.is_empty() or items[0].kind != &"lbrace":
		_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "meta needs a literal", node.start_line, node.start_col)
		return
	var cursor := 1
	while cursor < items.size() and items[cursor].kind != &"rbrace":
		if items[cursor].kind == &"comma":
			cursor += 1
			continue
		if items[cursor].kind != &"ident":
			_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "meta needs a literal", items[cursor].line, items[cursor].col)
			return
		var key := items[cursor].text
		cursor += 1
		if cursor >= items.size() or items[cursor].kind != &"colon":
			_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "meta needs a literal", node.start_line, node.start_col)
			return
		cursor += 1
		var parsed := _meta_literal(items, cursor)
		if not bool(parsed["ok"]):
			_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "meta needs a literal", int(parsed["line"]), int(parsed["col"]))
			return
		if document.meta.has(key):
			_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "duplicate meta key \"%s\"" % key, items[cursor - 2].line, items[cursor - 2].col)
		else:
			document.meta[key] = parsed["value"]
		cursor = int(parsed["next"])
	if cursor >= items.size() or items[cursor].kind != &"rbrace" or cursor + 1 != items.size():
		var at := items[mini(cursor, items.size() - 1)]
		_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "meta needs a literal", at.line, at.col)


func _meta_literal(items: Array[WyrdToken], start: int) -> Dictionary:
	var line := 1
	var col := 1
	if start < items.size():
		line = items[start].line
		col = items[start].col
	elif not items.is_empty():
		line = items[items.size() - 1].line
		col = items[items.size() - 1].col
	var bad := {"col": col, "line": line, "next": start, "ok": false, "value": null}
	if start >= items.size():
		return bad
	var token := items[start]
	if token.kind == &"string":
		return {"col": col, "line": line, "next": start + 1, "ok": true, "value": token.text}
	if token.kind == &"int":
		if start + 2 < items.size() and items[start + 1].kind == &"dot" and items[start + 2].kind == &"int":
			var number := float("%s.%s" % [token.text, items[start + 2].text])
			return {"col": col, "line": line, "next": start + 3, "ok": true, "value": number}
		return {"col": col, "line": line, "next": start + 1, "ok": true, "value": int(token.text)}
	if token.kind == &"minus" and start + 1 < items.size() and items[start + 1].kind == &"int":
		return {"col": col, "line": line, "next": start + 2, "ok": true, "value": -int(items[start + 1].text)}
	if token.kind == &"ident" and (token.text == "true" or token.text == "false"):
		return {"col": col, "line": line, "next": start + 1, "ok": true, "value": token.text == "true"}
	if token.kind == &"ident":
		return {"col": col, "line": line, "next": start + 1, "ok": true, "value": StringName(token.text)}
	return bad


func _document_page(node: WyrdNode, document: WyrdDocumentDef) -> void:
	var page := {
		"col": node.start_col,
		"condition": null,
		"condition_text": "",
		"line": node.start_line,
		"paragraphs": [],
	}
	var items := node.head
	if not items.is_empty():
		if not _is_word(items, 0, "when"):
			_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "page needs when", node.start_line, node.start_col)
		else:
			var span := _span_text(items, 1, items.size())
			page["condition_text"] = String(span["text"])
			var built := _expr(String(span["text"]), int(span["line"]), int(span["col"]), _STORY, true, &"", document.reads)
			page["condition"] = built["compiled"]
	if node.children.is_empty():
		_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "page needs a paragraph", node.start_line, node.start_col)
		document.pages.append(page)
		return
	for child in node.children:
		page["paragraphs"].append(_document_paragraph(child, document))
	document.pages.append(page)


func _document_paragraph(node: WyrdNode, document: WyrdDocumentDef) -> Dictionary:
	var line_id := _line_id(node, false)
	_note_line_site(node, false)
	var paragraph := {
		"col": node.start_col,
		"condition": null,
		"condition_text": "",
		"line": node.start_line,
		"line_id": line_id,
		"prose": null,
		"secrecy": node.secrecy,
		"tags": node.tags.duplicate(),
	}
	if not node.children.is_empty():
		_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "a paragraph cannot contain a block", node.start_line, node.start_col)
	if node.tags.has("voiced"):
		_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "voiced is not valid in a paragraph", node.start_line, node.start_col)
	var tokens: Array[WyrdToken] = []
	if node.keyword == "when":
		var colon := _depth_colon(node.head)
		if colon < 0:
			_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "when needs a condition", node.start_line, node.start_col)
		else:
			var span := _span_text(node.head, 0, colon)
			paragraph["condition_text"] = String(span["text"])
			if String(span["text"]).strip_edges().is_empty():
				_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "when needs a condition", node.start_line, node.start_col)
			else:
				var built := _expr(String(span["text"]), int(span["line"]), int(span["col"]), _STORY, true, &"", document.reads)
				paragraph["condition"] = built["compiled"]
			for i in range(colon + 1, node.head.size()):
				tokens.append(node.head[i])
	else:
		if node.lead != null:
			tokens.append(node.lead)
		for token in node.head:
			tokens.append(token)
	paragraph["prose"] = _interp(tokens, document.reads)
	_reject_paragraph_variants(paragraph["prose"])
	return paragraph


func _depth_colon(items: Array[WyrdToken]) -> int:
	var depth := 0
	for i in items.size():
		var kind := items[i].kind
		if kind == &"lparen" or kind == &"lbrace" or kind == &"lbracket":
			depth += 1
		elif kind == &"rparen" or kind == &"rbrace" or kind == &"rbracket":
			depth = maxi(depth - 1, 0)
		elif kind == &"colon" and depth == 0:
			return i
	return -1


func _reject_paragraph_variants(node: WyrdExprNode) -> void:
	if node == null:
		return
	if node.kind == &"variants":
		_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "variants are not valid in a paragraph", node.line, node.col)
	_reject_paragraph_variants(node.a)
	_reject_paragraph_variants(node.b)
	_reject_paragraph_variants(node.c)
	for kid in node.kids:
		_reject_paragraph_variants(kid)


func _document_read_block(node: WyrdNode, effects: Array[WyrdEffectDef], reads: Array[StringName]) -> void:
	_line_id(node, false)
	if not node.head.is_empty() and not (node.head.size() == 1 and node.head[0].kind == &"colon"):
		_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "on_read needs a block of effects" if node.keyword == "on_read" else "on_first_read needs a block of effects", node.start_line, node.start_col)
	for child in node.children:
		if child.keyword == "on_fail":
			_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "on_fail is not valid in a document", child.start_line, child.start_col)
			continue
		var effect := _effect(child)
		if effect == null:
			continue
		if not effect.on_fail.is_empty():
			_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "on_fail is not valid in a document", effect.line, effect.col)
		effects.append(effect)
		WyrdStmtSpan.add_reads(reads, effect.reads)
		for nested in child.children:
			if nested.keyword == "on_fail":
				_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "on_fail is not valid in a document", nested.start_line, nested.start_col)
			else:
				_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "unknown document field \"%s\"" % nested.keyword, nested.start_line, nested.start_col)


func _document_fact(node: WyrdNode, document: WyrdDocumentDef, field: String, key: String) -> void:
	var fact := _schema.lookup(key.split(".")) if _schema != null else null
	if fact == null:
		_error(WyrdDiagnostic.E_UNKNOWN_FACT, "unknown fact \"%s\"" % key, node.start_line, node.start_col)
		return
	if field == "fact" and (fact.origin != &"stored" or fact.type_name != &"symbol"):
		_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "document fact \"%s\" must be a stored symbol" % key, node.start_line, node.start_col)
		return
	if field == "claim":
		document.claim_key = key
	else:
		document.fact_key = key
	if not document.reads.has(StringName(key)):
		document.reads.append(StringName(key))


func _document_fragment(node: WyrdNode, document: WyrdDocumentDef) -> void:
	if node.head.is_empty() or not _is_word(node.head, 0, "when"):
		_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "fragment needs when", node.start_line, node.start_col)
		return
	var span := _span_text(node.head, 1, node.head.size())
	var built := _expr(String(span["text"]), int(span["line"]), int(span["col"]), _STORY, true, &"", document.reads)
	var slant := ""
	var found := false
	for child in node.children:
		if child.keyword != "slant" or found:
			_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "fragment needs one slant", child.start_line, child.start_col)
			continue
		found = true
		if not child.children.is_empty():
			_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "slant cannot contain a block", child.start_line, child.start_col)
			continue
		var named := _dotted_at(child.head, 0)
		slant = String(named["name"])
		if slant.is_empty() or int(named["next"]) != child.head.size():
			_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "slant needs a symbol", child.start_line, child.start_col)
			slant = ""
	if not found:
		_error(WyrdDiagnostic.E_DOCUMENT_SYNTAX, "fragment needs slant", node.start_line, node.start_col)
		return
	if slant.is_empty() or built["compiled"] == null:
		return
	document.fragments.append({"slant": slant, "when": built["compiled"]})


func _duration(items: Array[WyrdToken], start: int) -> Dictionary:
	var line := 1
	var col := 1
	if start < items.size():
		line = items[start].line
		col = items[start].col
	elif not items.is_empty():
		line = items[items.size() - 1].line
		col = items[items.size() - 1].col
	var missing := {
		"col": col,
		"line": line,
		"message": "duration needs a number and a unit",
		"minutes": -1,
		"next": start,
		"ok": false,
	}
	if start >= items.size() or items[start].kind != &"int":
		return missing
	var count := int(items[start].text)
	var unit_at := start + 1
	if unit_at >= items.size() or items[unit_at].kind != &"ident":
		missing["next"] = unit_at
		missing["line"] = items[start].line
		missing["col"] = items[start].col
		return missing
	var scale := _unit_scale(items[unit_at].text)
	if scale < 0:
		return {
			"col": items[unit_at].col,
			"line": items[unit_at].line,
			"message": "unknown duration unit \"%s\"" % items[unit_at].text,
			"minutes": -1,
			"next": unit_at + 1,
			"ok": false,
		}
	return {
		"col": items[start].col,
		"line": items[start].line,
		"message": "",
		"minutes": count * scale,
		"next": unit_at + 1,
		"ok": true,
	}


func _unit_scale(unit: String) -> int:
	match unit:
		"minute", "minutes":
			return 1
		"hour", "hours":
			return 60
		"day", "days":
			return 1440
		_:
			return -1


func _is_word(items: Array[WyrdToken], index: int, word: String) -> bool:
	return index >= 0 and index < items.size() and items[index].kind == &"ident" and items[index].text == word


func _compile_role(node: WyrdNode) -> WyrdRoleDef:
	var role := WyrdRoleDef.new()
	role.take_span(node)
	_line_id(node, false)
	if not node.line_tag.is_empty():
		_error(WyrdDiagnostic.E_ROLE_SYNTAX, "a line tag is not allowed on a role", node.start_line, node.start_col)
	if not node.title.is_empty():
		_error(WyrdDiagnostic.E_ROLE_SYNTAX, "a role has no title", node.start_line, node.start_col)
	var ident := _dotted_at(node.head, 0)
	role.id = String(ident["name"])
	if role.id.is_empty() or int(ident["next"]) != node.head.size():
		_error(WyrdDiagnostic.E_ROLE_SYNTAX, "role needs an id", node.start_line, node.start_col)
		role.id = ""
	var seen := {}
	for child in node.children:
		var field := child.keyword
		if not child.line_tag.is_empty():
			_error(WyrdDiagnostic.E_ROLE_SYNTAX, "a line tag is not allowed on a role", child.start_line, child.start_col)
		if not _ROLE_FIELDS.has(field):
			_error(WyrdDiagnostic.E_ROLE_SYNTAX, "unknown role field \"%s\"" % field, child.start_line, child.start_col)
			_role_block(child)
			continue
		if seen.has(field):
			_error(WyrdDiagnostic.E_ROLE_SYNTAX, "duplicate role field \"%s\"" % field, child.start_line, child.start_col)
			_role_block(child)
			continue
		seen[field] = true
		_role_field(child, role, field)
	return role


func _role_field(node: WyrdNode, role: WyrdRoleDef, field: String) -> void:
	_role_block(node)
	var items := node.head
	if items.is_empty() or items[0].kind != &"colon" or items.size() == 1:
		_error(WyrdDiagnostic.E_ROLE_SYNTAX, "role field \"%s\" needs a value" % field, node.start_line, node.start_col)
		return
	var span := _span_text(items, 1, items.size())
	var text := String(span["text"])
	var line := int(span["line"])
	var col := int(span["col"])
	if text.is_empty():
		_error(WyrdDiagnostic.E_ROLE_SYNTAX, "role field \"%s\" needs a value" % field, line, col)
		return
	match field:
		"scope":
			var parsed := WyrdRoleDef.parse_scope(text)
			if not bool(parsed["ok"]):
				_error(WyrdDiagnostic.E_ROLE_SYNTAX, String(parsed["error"]), line, col)
				return
			role.scope = String(parsed["scope"])
			role.scope_id = String(parsed["id"])
		"eligibility":
			role.eligibility_text = text
			role.eligibility = WyrdRoleDef.compile_eligibility(text, _schema, _diagnostics, _path, line, col)
			if role.eligibility != null:
				WyrdStmtSpan.add_reads(role.reads, role.eligibility.reads)
		"default_holder":
			var parsed := WyrdRoleDef.parse_holder(text)
			if not bool(parsed["ok"]):
				_error(WyrdDiagnostic.E_ROLE_SYNTAX, String(parsed["error"]), line, col)
				return
			role.default_holder = String(parsed["holder"])
		"visibility":
			var parsed := WyrdRoleDef.parse_visibility(text)
			if not bool(parsed["ok"]):
				_error(WyrdDiagnostic.E_ROLE_SYNTAX, String(parsed["error"]), line, col)
				return
			role.visibility = String(parsed["visibility"])
		"succession":
			var parsed := WyrdRoleDef.parse_succession(text)
			if not bool(parsed["ok"]):
				_error(WyrdDiagnostic.E_ROLE_SYNTAX, String(parsed["error"]), line, col)
				return
			role.succession_text = text
			role.strategy = String(parsed["strategy"])
			role.kinds = parsed["kinds"]
			role.succession_arg = String(parsed["arg"])
		"vacancy":
			var parsed := WyrdRoleDef.parse_vacancy(text)
			if not bool(parsed["ok"]):
				_error(WyrdDiagnostic.E_ROLE_SYNTAX, String(parsed["error"]), line, col)
				return
			role.vacancy = String(parsed["vacancy"])


func _role_block(node: WyrdNode) -> void:
	for child in node.children:
		_error(WyrdDiagnostic.E_ROLE_SYNTAX, "a role field cannot contain a block", child.start_line, child.start_col)


func _quest(node: WyrdNode) -> WyrdQuestDef:
	var quest := WyrdQuestDef.new()
	quest.take_span(node)
	_line_id(node, false)
	var ident := _dotted_at(node.head, 0)
	quest.id = String(ident["name"])
	quest.title = node.title
	if quest.id.is_empty() or quest.title.is_empty() or int(ident["next"]) != node.head.size():
		_error(WyrdDiagnostic.E_STMT_UNKNOWN, "quest needs an id and a quoted title", node.start_line, node.start_col)
	var saved_owner := _line_owner
	_line_owner = quest.id
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
			"on":
				_error(WyrdDiagnostic.E_STMT_UNKNOWN, "on <event> is only valid in a stage", child.start_line, child.start_col)
			_:
				_unknown(child)
	_line_owner = saved_owner
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
		_finish_body(stage, stage_names, slot_names, 1)


func _finish_body(stage: WyrdStageDef, stage_names: Dictionary, slot_names: Dictionary, depth: int) -> void:
	for row in stage.transitions:
		var target := String(row["target"])
		if not stage_names.has(target):
			_error(WyrdDiagnostic.E_STAGE_UNKNOWN, "unknown stage \"%s\"" % target, int(row["line"]), int(row["col"]))
	for handler in stage.handlers:
		for row in handler.transitions:
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
			_finish_body(variant.body, stage_names, slot_names, depth)
	_finish_regions(stage, slot_names, depth)


func _finish_regions(stage: WyrdStageDef, slot_names: Dictionary, depth: int) -> void:
	if stage == null:
		return
	for item in stage.regions:
		var region := item as WyrdRegionDef
		if region == null:
			continue
		var names := {}
		for child in region.stages:
			if not child.id.is_empty():
				names[child.id] = true
		for child in region.stages:
			if depth + 1 > 2 and not child.id.is_empty():
				_diagnostics.add(
					WyrdDiagnostic.W_SUBSTATE_DEPTH,
					"sub-state \"%s\" is nested past depth 2" % child.id,
					_path,
					child.line,
					child.col,
					WyrdDiagnostic.SEVERITY_WARNING
				)
			_finish_body(child, names, slot_names, depth + 1)


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
		var compiled := _expr(
			span["text"],
			int(span["line"]),
			int(span["col"]),
			_WAIT,
			true,
			&"",
			slot.reads,
			{"candidate": WyrdSignatures.T_ENTITY}
		)
		slot.cast_when = compiled["compiled"]
		if compiled["ast"] != null:
			_warn_slot_const("cast", compiled["ast"], int(span["line"]), int(span["col"]))
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
	_spatial_wait(stage)
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


func _region(node: WyrdNode, stage: WyrdStageDef) -> void:
	_line_id(node, false)
	var region := WyrdRegionDef.new()
	region.take_span(node)
	if not node.line_tag.is_empty():
		_error(WyrdDiagnostic.E_STMT_UNKNOWN, "a line tag is not allowed on a region", node.start_line, node.start_col)
	if not node.title.is_empty():
		_error(WyrdDiagnostic.E_STMT_UNKNOWN, "a region has no title", node.start_line, node.start_col)
	if node.head.size() != 1 or node.head[0].kind != &"ident":
		_unknown_msg(node, "region needs an id")
		return
	region.id = node.head[0].text
	for prior in stage.regions:
		var earlier := prior as WyrdRegionDef
		if earlier != null and earlier.id == region.id:
			_error(WyrdDiagnostic.E_STMT_UNKNOWN, "duplicate region \"%s\"" % region.id, node.start_line, node.start_col)
	if node.children.is_empty():
		_error(WyrdDiagnostic.E_STMT_UNKNOWN, "region \"%s\" needs a stage" % region.id, node.start_line, node.start_col)
	for child in node.children:
		if child.keyword != "stage":
			_unknown(child)
			continue
		var nested := _stage_head(child)
		if nested.id.is_empty():
			continue
		for prior_stage in region.stages:
			if prior_stage.id == nested.id:
				_error(WyrdDiagnostic.E_STAGE_DUPLICATE, "duplicate stage \"%s\"" % nested.id, child.start_line, child.start_col)
		for stmt in child.children:
			_stage_stmt(stmt, nested)
		_spatial_wait(nested)
		region.stages.append(nested)
		WyrdStmtSpan.add_reads(region.reads, nested.reads)
	stage.regions.append(region)
	WyrdStmtSpan.add_reads(stage.reads, region.reads)


func _sequence(node: WyrdNode) -> WyrdSequenceDef:
	var sequence := WyrdSequenceDef.new()
	sequence.take_span(node)
	_line_id(node, false)
	if not node.line_tag.is_empty():
		_error(WyrdDiagnostic.E_SEQUENCE_SYNTAX, "a line tag is not allowed on a sequence", node.start_line, node.start_col)
	if not node.title.is_empty():
		_error(WyrdDiagnostic.E_SEQUENCE_SYNTAX, "a sequence has no title", node.start_line, node.start_col)
	var ident := _dotted_at(node.head, 0)
	sequence.id = String(ident["name"])
	var i := int(ident["next"])
	if sequence.id.is_empty():
		_error(WyrdDiagnostic.E_SEQUENCE_SYNTAX, "sequence needs an id", node.start_line, node.start_col)
		sequence.id = ""
		return sequence
	if i >= node.head.size() or node.head[i].kind != &"ident":
		_error(WyrdDiagnostic.E_SEQUENCE_SYNTAX, "sequence needs ordered or any(<n> of <m>)", node.start_line, node.start_col)
		sequence.id = ""
		return sequence
	var items := node.head
	if items[i].text == "ordered":
		sequence.mode = &"ordered"
		i += 1
	elif items[i].text == "any":
		sequence.mode = &"any"
		i = _sequence_any(items, i, sequence)
		if i < 0:
			sequence.id = ""
			return sequence
	else:
		_error(WyrdDiagnostic.E_SEQUENCE_SYNTAX, "sequence needs ordered or any(<n> of <m>)", items[i].line, items[i].col)
		sequence.id = ""
		return sequence
	if i >= items.size() or items[i].text != "within":
		_error(WyrdDiagnostic.E_SEQUENCE_SYNTAX, "sequence needs within <duration>", node.start_line, node.start_col)
		sequence.id = ""
		return sequence
	i += 1
	var minutes := _sequence_duration(items, i)
	if minutes < 0:
		sequence.id = ""
		return sequence
	sequence.within_minutes = minutes
	i += 2
	if i < items.size():
		if items[i].text != "reset" or i + 1 >= items.size() or items[i + 1].text != "on":
			_error(WyrdDiagnostic.E_SEQUENCE_SYNTAX, "sequence reset needs reset on <event or condition>", items[i].line, items[i].col)
			return sequence
		i += 2
		if i >= items.size():
			_error(WyrdDiagnostic.E_SEQUENCE_SYNTAX, "sequence reset needs an event or a condition", items[i - 1].line, items[i - 1].col)
			return sequence
		_sequence_reset(sequence, items, i)
	for child in node.children:
		_sequence_step(child, sequence)
	if sequence.steps.is_empty():
		_error(WyrdDiagnostic.E_SEQUENCE_SYNTAX, "sequence \"%s\" needs a step" % sequence.id, node.start_line, node.start_col)
	if sequence.mode == &"any":
		if sequence.need < 1 or sequence.total < 1 or sequence.need > sequence.total:
			_error(
				WyrdDiagnostic.E_SEQUENCE_SYNTAX,
				"any(%d of %d) needs a count from 1 to %d" % [sequence.need, sequence.total, sequence.total],
				node.start_line,
				node.start_col
			)
		elif sequence.steps.size() > 1 and sequence.steps.size() != sequence.total:
			_error(
				WyrdDiagnostic.E_SEQUENCE_SYNTAX,
				"any of %d needs %d steps" % [sequence.total, sequence.total],
				node.start_line,
				node.start_col
			)
	else:
		sequence.need = sequence.steps.size()
		sequence.total = sequence.steps.size()
	return sequence


func _sequence_any(items: Array[WyrdToken], i: int, sequence: WyrdSequenceDef) -> int:
	if i + 5 >= items.size() or items[i + 1].kind != &"lparen" or items[i + 2].kind != &"int" or items[i + 3].text != "of" or items[i + 4].kind != &"int" or items[i + 5].kind != &"rparen":
		var line := items[i].line
		var col := items[i].col
		_error(WyrdDiagnostic.E_SEQUENCE_SYNTAX, "any needs (<n> of <m>)", line, col)
		return -1
	sequence.need = int(items[i + 2].text)
	sequence.total = int(items[i + 4].text)
	return i + 6


func _sequence_duration(items: Array[WyrdToken], i: int) -> int:
	if i >= items.size():
		var line := 1
		var col := 1
		if i > 0:
			line = items[i - 1].line
			col = items[i - 1].col
		_error(WyrdDiagnostic.E_SEQUENCE_SYNTAX, "within needs a duration", line, col)
		return -1
	if items[i].kind == &"minus":
		_error(WyrdDiagnostic.E_SEQUENCE_SYNTAX, "within cannot be negative", items[i].line, items[i].col)
		return -1
	if i + 1 >= items.size() or items[i].kind != &"int" or items[i + 1].kind != &"ident":
		_error(WyrdDiagnostic.E_SEQUENCE_SYNTAX, "within needs a duration", items[i].line, items[i].col)
		return -1
	var scale := 0
	match items[i + 1].text:
		"m":
			scale = 1
		"h":
			scale = 60
		"d":
			scale = WyrdCondition.MINUTES_PER_DAY
		_:
			_error(WyrdDiagnostic.E_SEQUENCE_SYNTAX, "within unit must be m, h, or d", items[i + 1].line, items[i + 1].col)
			return -1
	return int(items[i].text) * scale


func _sequence_reset(sequence: WyrdSequenceDef, items: Array[WyrdToken], i: int) -> void:
	if i + 1 == items.size() and items[i].kind == &"ident":
		var name := items[i].text
		var event: WyrdEventDef = _events.get(name) as WyrdEventDef
		if event == null:
			_error(WyrdDiagnostic.E_EVENT_UNKNOWN, "unknown event \"%s\"" % name, items[i].line, items[i].col)
			return
		sequence.reset_event = name
		sequence.reset_text = name
		return
	var span := _span_text(items, i, items.size())
	sequence.reset_text = span["text"]
	if sequence.reset_text.is_empty():
		_error(WyrdDiagnostic.E_SEQUENCE_SYNTAX, "sequence reset needs an event or a condition", int(span["line"]), int(span["col"]))
		return
	var compiled := _expr(span["text"], int(span["line"]), int(span["col"]), _WAIT, true, &"", sequence.reads, {}, false)
	sequence.reset_cond = compiled["compiled"]


func _sequence_step(node: WyrdNode, sequence: WyrdSequenceDef) -> void:
	if node.keyword != "on":
		_error(WyrdDiagnostic.E_SEQUENCE_SYNTAX, "a sequence step is on <event> where <condition>", node.start_line, node.start_col)
		return
	for child in node.children:
		_error(WyrdDiagnostic.E_SEQUENCE_SYNTAX, "a sequence step is only a match", child.start_line, child.start_col)
	var items := node.head
	var limit := items.size()
	if limit > 0 and items[limit - 1].kind == &"colon":
		limit -= 1
	var shape := limit >= 3 and items[0].kind == &"ident" and items[1].text == "where"
	if not shape:
		_error(WyrdDiagnostic.E_SEQUENCE_SYNTAX, "a sequence step needs on <event> where <condition>", node.start_line, node.start_col)
		return
	var step := WyrdOnEventDef.new()
	step.take_span(node)
	step.event_name = items[0].text
	var event: WyrdEventDef = _events.get(step.event_name) as WyrdEventDef
	if event == null:
		_error(WyrdDiagnostic.E_EVENT_UNKNOWN, "unknown event \"%s\"" % step.event_name, items[0].line, items[0].col)
	var span := _span_text(items, 2, limit)
	step.where_text = span["text"]
	var saved := _event_fields.duplicate()
	_event_fields = {}
	if event != null:
		for field in event.fields:
			_event_fields[str(field["name"])] = StringName(str(field["type"]))
	var compiled := _expr(span["text"], int(span["line"]), int(span["col"]), _WAIT, true, &"", step.reads, {}, false)
	step.where_cond = compiled["compiled"]
	_event_fields = saved
	sequence.steps.append(step)
	WyrdStmtSpan.add_reads(sequence.reads, step.reads)


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
		"on":
			_on_event(node, stage)
		"region":
			_region(node, stage)
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
	var compiled := _expr(span["text"], int(span["line"]), int(span["col"]), _WAIT, true, &"", stage.reads, {}, true)
	stage.waits_until = compiled["compiled"]
	_no_block(node)


func _on_event(node: WyrdNode, stage: WyrdStageDef) -> void:
	_line_id(node, false)
	var items := node.head
	var limit := items.size()
	if limit > 0 and items[limit - 1].kind == &"colon":
		limit -= 1
	var shape := limit >= 3 and items[0].kind == &"ident" and items[1].text == "where"
	if not shape:
		_unknown_msg(node, "on needs <event> where <condition>")
		return
	var handler := WyrdOnEventDef.new()
	handler.take_span(node)
	handler.event_name = items[0].text
	var event: WyrdEventDef = _events.get(handler.event_name) as WyrdEventDef
	if event == null:
		_error(WyrdDiagnostic.E_EVENT_UNKNOWN, "unknown event \"%s\"" % handler.event_name, items[0].line, items[0].col)
	var span := _span_text(items, 2, limit)
	handler.where_text = span["text"]
	var saved := _event_fields.duplicate()
	_event_fields = {}
	if event != null:
		for field in event.fields:
			_event_fields[str(field["name"])] = StringName(str(field["type"]))
	var compiled := _expr(span["text"], int(span["line"]), int(span["col"]), _WAIT, true, &"", handler.reads, {}, true)
	handler.where_cond = compiled["compiled"]
	for child in node.children:
		match child.keyword:
			"~", "outcome":
				_keep_effect(child, handler.effects, handler.reads)
			"->":
				_handler_transition(child, handler)
			_:
				_error(
					WyrdDiagnostic.E_STMT_UNKNOWN,
					"on <event> only nests effects and transitions",
					child.start_line,
					child.start_col
				)
	_event_fields = saved
	stage.handlers.append(handler)
	WyrdStmtSpan.add_reads(stage.reads, handler.reads)


func _handler_transition(node: WyrdNode, handler: WyrdOnEventDef) -> void:
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
		var compiled := _expr(span["text"], int(span["line"]), int(span["col"]), _WAIT, true, &"", handler.reads, {}, true)
		when = compiled["compiled"]
	handler.transitions.append({
		"col": items[0].col,
		"end_col": node.end_col,
		"end_line": node.end_line,
		"expr": expr,
		"line": items[0].line,
		"target": items[0].text,
		"when": when,
	})
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
	line_def.tags = node.tags.duplicate()
	line_def.secrecy = node.secrecy
	line_def.prose = _interp(tokens, line_def.reads)
	_take_variants(node, line_def)
	stage.journals.append(line_def)
	WyrdStmtSpan.add_reads(stage.reads, line_def.reads)


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
		var bindings := {}
		if state == "unwilling":
			bindings["$h"] = WyrdSignatures.T_ENTITY
		var compiled := _expr(span["text"], int(span["line"]), int(span["col"]), _WAIT, true, &"", variant.reads, bindings)
		variant.condition = compiled["compiled"]
		_warn_slot_const(state, compiled["ast"], int(span["line"]), int(span["col"]))
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
	_spatial_wait(variant.body)
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
	var saved_owner := _line_owner
	_line_owner = scene.id
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
	_line_owner = saved_owner
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
		"on":
			_error(WyrdDiagnostic.E_STMT_UNKNOWN, "on <event> is only valid in a stage", node.start_line, node.start_col)
		"~":
			_scene_effect(node, scene)
		"on_fail":
			_unknown_msg(node, "on_fail belongs on the do line")
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
	line_def.tags = node.tags.duplicate()
	line_def.secrecy = node.secrecy
	line_def.prose = _interp(_tail(node.head, colon + 1), line_def.reads)
	_take_variants(node, line_def)
	var item := WyrdSceneItem.new()
	item.kind = &"line"
	item.line_def = line_def
	item.take_span(node)
	WyrdStmtSpan.add_reads(item.reads, line_def.reads)
	scene.items.append(item)
	WyrdStmtSpan.add_reads(scene.reads, line_def.reads)


func _when_line(node: WyrdNode, scene: WyrdSceneDef) -> void:
	if _when_effect(node.head):
		_unknown_msg(node, "when is not valid on an effect")
		return
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
	var saw_disabled := false
	while i < items.size() and _disabled_word(items[i]):
		if items[i].text == "disabled_when":
			_diagnostics.add(
				WyrdDiagnostic.W_DISABLED_WHEN_DEPRECATED,
				"disabled_when is deprecated; use show_disabled_when",
				_path,
				items[i].line,
				items[i].col,
				WyrdDiagnostic.SEVERITY_WARNING
			)
		if saw_disabled:
			_choice_error(node, "a choice has one show_disabled_when")
			return
		saw_disabled = true
		if label_at < 0:
			_choice_error(node, "show_disabled_when follows the label")
			return
		if i + 1 >= items.size() or items[i + 1].kind != &"lbrace":
			_choice_error(node, "show_disabled_when needs {<condition>} \"<reason>\"")
			return
		var close := _closing(items, i + 1, &"lbrace", &"rbrace")
		if close < 0 or node.title.is_empty():
			_choice_error(node, "show_disabled_when needs {<condition>} \"<reason>\"")
			return
		var span := _span_text(items, i + 2, close)
		choice.disabled_when = span["text"]
		choice.disabled_reason = node.title
		var compiled := _expr(span["text"], int(span["line"]), int(span["col"]), _STORY, true, &"", choice.reads)
		choice.disabled_condition = compiled["compiled"]
		i = close + 1
	if not saw_disabled and not node.title.is_empty():
		_choice_error(node, "choice reason needs show_disabled_when")
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
	choice.tags = node.tags.duplicate()
	choice.secrecy = node.secrecy
	_lint_voiced(choice.label, choice.tags, choice.line, choice.col)
	_note_label(choice.target, items[i + 1].line, items[i + 1].col)
	var saw_check := false
	for index in node.children.size():
		var child: WyrdNode = node.children[index]
		if child.keyword != "check":
			_keep_effect(child, choice.effects, choice.reads)
			continue
		if saw_check:
			_check_error(child, "a choice has one check")
			continue
		if index != 0:
			_check_error(child, "check must be the first line of a choice")
			continue
		saw_check = true
		_choice_check(child, choice)
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


func _scene_effect(node: WyrdNode, scene: WyrdSceneDef) -> void:
	var effect := _effect(node)
	if effect == null:
		return
	for child in node.children:
		if child.keyword == "on_fail":
			_unknown_msg(child, "on_fail belongs on the do line")
		else:
			_unknown(child)
	var item := WyrdSceneItem.new()
	item.kind = &"effect"
	item.effect = effect
	item.take_span(node)
	WyrdStmtSpan.add_reads(item.reads, effect.reads)
	scene.items.append(item)
	WyrdStmtSpan.add_reads(scene.reads, effect.reads)


func _when_effect(items: Array[WyrdToken]) -> bool:
	var depth := 0
	for i in items.size():
		var kind := items[i].kind
		if kind == &"lparen" or kind == &"lbrace" or kind == &"lbracket":
			depth += 1
		elif kind == &"rparen" or kind == &"rbrace" or kind == &"rbracket":
			depth = maxi(depth - 1, 0)
		elif depth == 0 and kind == &"colon":
			if i + 1 < items.size() and items[i + 1].kind == &"tilde":
				return true
	return false


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
		"lock":
			if items.size() < 2 or items[1].text != "topic":
				_error(WyrdDiagnostic.E_EFFECT_NOT_IN_SLICE, "effect \"%s\" is not in this slice" % items[0].text, items[0].line, items[0].col)
				_no_block(node)
				return null
			effect.kind = &"lock_topic"
			if not _lock(effect, items):
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
		"believe":
			effect.kind = &"believe"
			if not _belief(effect, items, true):
				_no_block(node)
				return null
		"unbelieve":
			effect.kind = &"unbelieve"
			if not _belief(effect, items, false):
				_no_block(node)
				return null
		"declare":
			effect.kind = &"declare"
			if not _belief(effect, items, true):
				_no_block(node)
				return null
		"retract":
			effect.kind = &"retract"
			if not _belief(effect, items, false):
				_no_block(node)
				return null
		"learn":
			effect.kind = &"learn"
			if not _belief(effect, items, true):
				_no_block(node)
				return null
		"forget":
			effect.kind = &"forget"
			if not _belief(effect, items, false):
				_no_block(node)
				return null
		"start":
			if items.size() < 2 or items[1].text != "quest":
				_error(WyrdDiagnostic.E_EFFECT_NOT_IN_SLICE, "effect \"%s\" is not in this slice" % items[0].text, items[0].line, items[0].col)
				_no_block(node)
				return null
			effect.kind = &"start_quest"
			if not _start_quest(effect, items):
				_no_block(node)
				return null
		"advance":
			effect.kind = &"advance"
			if not _advance_to(effect, items):
				_no_block(node)
				return null
		"assign":
			if items.size() < 2 or items[1].text != "role":
				_error(WyrdDiagnostic.E_EFFECT_NOT_IN_SLICE, "effect \"%s\" is not in this slice" % items[0].text, items[0].line, items[0].col)
				_no_block(node)
				return null
			effect.kind = &"assign_role"
			if not _assign_role(effect, items):
				_no_block(node)
				return null
		"vacate":
			if items.size() < 2 or items[1].text != "role":
				_error(WyrdDiagnostic.E_EFFECT_NOT_IN_SLICE, "effect \"%s\" is not in this slice" % items[0].text, items[0].line, items[0].col)
				_no_block(node)
				return null
			effect.kind = &"vacate_role"
			if not _vacate_role(effect, items):
				_no_block(node)
				return null
		"adjust":
			if items.size() < 2 or items[1].text != "baseline":
				_error(WyrdDiagnostic.E_EFFECT_NOT_IN_SLICE, "effect \"%s\" is not in this slice" % items[0].text, items[0].line, items[0].col)
				_no_block(node)
				return null
			effect.kind = &"adjust_baseline"
			if not _adjust_baseline(effect, items):
				_no_block(node)
				return null
		"create":
			effect.kind = &"create_document"
			if not _create_document(effect, items):
				_no_block(node)
				return null
		_:
			_error(WyrdDiagnostic.E_EFFECT_NOT_IN_SLICE, "effect \"%s\" is not in this slice" % items[0].text, items[0].line, items[0].col)
			_no_block(node)
			return null
	return effect


func _create_document(effect: WyrdEffectDef, items: Array[WyrdToken]) -> bool:
	var message := "create document needs <doc_id> copy <copy_id>"
	if items.size() < 3 or items[1].kind != &"ident" or items[1].text != "document":
		_unknown_msg_at(effect, message)
		return false
	var named := _dotted_at(items, 2)
	var doc := String(named["name"])
	var cursor := int(named["next"])
	if doc.is_empty() or not _is_word(items, cursor, "copy"):
		_unknown_msg_at(effect, message)
		return false
	cursor += 1
	var copy := ""
	if cursor < items.size() and items[cursor].kind == &"string":
		copy = items[cursor].text
		cursor += 1
	else:
		var copy_named := _dotted_at(items, cursor)
		copy = String(copy_named["name"])
		cursor = int(copy_named["next"])
	if copy.is_empty() or cursor != items.size():
		_unknown_msg_at(effect, message)
		return false
	effect.document_id = doc
	effect.copy_id = copy
	return true


func _rejected(items: Array[WyrdToken]) -> String:
	var first := items[0].text
	var second := items[1].text if items.size() > 1 and items[1].kind == &"ident" else ""
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


func _belief(effect: WyrdEffectDef, items: Array[WyrdToken], has_value: bool) -> bool:
	var who_noun := "group" if effect.kind == &"declare" or effect.kind == &"retract" else "agent"
	var shape := "%s needs <%s> <fact>%s" % [String(effect.kind), who_noun, " = <expr>" if has_value else ""]
	var who := _dotted_at(items, 1)
	var name := String(who["name"])
	var at := int(who["next"])
	if name.is_empty() or not _shape_ok(name):
		_unknown_msg_at(effect, shape)
		return false
	effect.agent = name
	if at >= items.size():
		_unknown_msg_at(effect, shape)
		return false
	var fact_end := items.size()
	var value_at := -1
	if has_value:
		var sep := _find(items, at, &"eq", "")
		if sep <= at:
			_unknown_msg_at(effect, shape)
			return false
		fact_end = sep
		value_at = sep + 1
		if value_at >= items.size():
			_unknown_msg_at(effect, shape)
			return false
	elif _find(items, at, &"eq", "") >= 0:
		_unknown_msg_at(effect, shape)
		return false
	var target_span := _span_text(items, at, fact_end)
	if String(target_span["text"]).is_empty():
		_unknown_msg_at(effect, shape)
		return false
	effect.target_text = target_span["text"]
	var target := _expr(target_span["text"], int(target_span["line"]), int(target_span["col"]), _STORY, false, &"", effect.reads)
	effect.target = target["compiled"]
	var fact := _stored_fact(target["ast"], effect)
	if not has_value:
		return true
	var value_span := _span_text(items, value_at, items.size())
	effect.value_text = value_span["text"]
	var expected: StringName = fact.type_name if fact != null else &""
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
	var reveals: Dictionary = {}
	var claim: Dictionary = {}
	var rows := _arg_rows(items, 4, close)
	for row in rows:
		var name := String(row["name"])
		if name.is_empty():
			_error(WyrdDiagnostic.E_ARG_NAME, "deed arguments are named", int(row["line"]), int(row["col"]))
			continue
		if not _DEED_TYPES.has(name) and name != "witnesses" and name != "reveals" and name != "claim":
			_error(WyrdDiagnostic.E_ARG_NAME, "deed has no argument \"%s\"" % name, int(row["line"]), int(row["col"]))
			continue
		if seen.has(name):
			_error(WyrdDiagnostic.E_ARG_NAME, "deed argument \"%s\" is duplicated" % name, int(row["line"]), int(row["col"]))
			continue
		seen[name] = true
		if name == "reveals":
			reveals = row
			continue
		if name == "claim":
			claim = row
			continue
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
	_reveal_args(effect, reveals, claim)
	return true


func _reveal_args(effect: WyrdEffectDef, reveals: Dictionary, claim: Dictionary) -> void:
	if reveals.is_empty() and claim.is_empty():
		return
	if reveals.is_empty():
		_error(WyrdDiagnostic.E_ARG_TYPE, "deed argument \"claim\" needs reveals", int(claim["line"]), int(claim["col"]))
		return
	if claim.is_empty():
		_error(WyrdDiagnostic.E_ARG_TYPE, "deed missing argument \"claim\"", int(reveals["line"]), int(reveals["col"]))
	var target := _expr(String(reveals["text"]), int(reveals["line"]), int(reveals["col"]), _STORY, false, &"", effect.reads)
	var fact := _stored_fact(target["ast"], effect)
	if claim.is_empty():
		return
	var value_type: StringName = fact.type_name if fact != null else &""
	var value := _expr(String(claim["text"]), int(claim["line"]), int(claim["col"]), _STORY, false, value_type, effect.reads)
	effect.value = value["compiled"]
	effect.value_text = String(claim["text"])
	if fact != null and value["ast"] != null and value_type != &"" and not _fits((value["ast"] as WyrdExprNode).type_name, fact.type_name):
		_error(
			WyrdDiagnostic.E_WRITE_TYPE,
			"cannot write %s to %s fact \"%s\"" % [(value["ast"] as WyrdExprNode).type_name, fact.type_name, fact.key],
			int(claim["line"]),
			int(claim["col"])
		)


func _witness_auto(items: Array[WyrdToken], start: int, end: int) -> bool:
	return end == start + 1 and items[start].kind == &"ident" and items[start].text == "auto"


func _start_quest(effect: WyrdEffectDef, items: Array[WyrdToken]) -> bool:
	var ident := _dotted_at(items, 2)
	var name := String(ident["name"])
	if name.is_empty() or int(ident["next"]) != items.size() or not _shape_ok(name):
		_unknown_msg_at(effect, "start quest needs a quest id")
		return false
	effect.quest = name
	return true


func _advance_to(effect: WyrdEffectDef, items: Array[WyrdToken]) -> bool:
	var quest := _dotted_at(items, 1)
	var name := String(quest["name"])
	var at := int(quest["next"])
	var stage_name := ""
	if not name.is_empty() and _shape_ok(name) and at < items.size() and items[at].text == "to":
		var stage := _dotted_at(items, at + 1)
		stage_name = String(stage["name"])
		if not stage_name.is_empty() and _shape_ok(stage_name) and int(stage["next"]) == items.size():
			effect.quest = name
			effect.stage = stage_name
			return true
	_unknown_msg_at(effect, "advance needs <quest> to <stage>")
	return false


func _assign_role(effect: WyrdEffectDef, items: Array[WyrdToken]) -> bool:
	var role := _dotted_at(items, 2)
	var name := String(role["name"])
	var at := int(role["next"])
	if name.is_empty() or not _shape_ok(name) or at >= items.size() or items[at].text != "to":
		_unknown_msg_at(effect, "assign role needs <role> to <entity>")
		return false
	var entity_span := _span_text(items, at + 1, items.size())
	if String(entity_span["text"]).is_empty():
		_unknown_msg_at(effect, "assign role needs <role> to <entity>")
		return false
	effect.role = name
	effect.entity_text = String(entity_span["text"])
	var expected := _command_expected(items, at + 1, items.size())
	var entity := _expr(effect.entity_text, int(entity_span["line"]), int(entity_span["col"]), _STORY, false, expected, effect.reads)
	effect.entity = entity["compiled"]
	return true


func _vacate_role(effect: WyrdEffectDef, items: Array[WyrdToken]) -> bool:
	var role := _dotted_at(items, 2)
	var name := String(role["name"])
	if name.is_empty() or not _shape_ok(name) or int(role["next"]) != items.size():
		_unknown_msg_at(effect, "vacate role needs a role id")
		return false
	effect.role = name
	return true


func _adjust_baseline(effect: WyrdEffectDef, items: Array[WyrdToken]) -> bool:
	var axis := _dotted_at(items, 2)
	var name := String(axis["name"])
	var at := int(axis["next"])
	if name.is_empty() or not _shape_ok(name) or at >= items.size() or items[at].kind != &"lparen":
		_unknown_msg_at(effect, "adjust baseline needs <axis>(a, b) by <n>")
		return false
	var close := _closing(items, at, &"lparen", &"rparen")
	if close < 0 or close + 1 >= items.size() or items[close + 1].text != "by" or close + 2 >= items.size():
		_unknown_msg_at(effect, "adjust baseline needs <axis>(a, b) by <n>")
		return false
	var comma := _find(items, at + 1, &"comma", "")
	var later := _find(items, comma + 1, &"comma", "") if comma >= 0 else -1
	if comma < 0 or comma >= close or (later >= 0 and later < close):
		_unknown_msg_at(effect, "adjust baseline needs <axis>(a, b) by <n>")
		return false
	var a_span := _span_text(items, at + 1, comma)
	var b_span := _span_text(items, comma + 1, close)
	var value_span := _span_text(items, close + 2, items.size())
	if String(a_span["text"]).is_empty() or String(b_span["text"]).is_empty() or String(value_span["text"]).is_empty():
		_unknown_msg_at(effect, "adjust baseline needs <axis>(a, b) by <n>")
		return false
	effect.axis = name
	effect.a_text = String(a_span["text"])
	effect.b_text = String(b_span["text"])
	effect.value_text = String(value_span["text"])
	var a_expected := _command_expected(items, at + 1, comma)
	var b_expected := _command_expected(items, comma + 1, close)
	var a_expr := _expr(effect.a_text, int(a_span["line"]), int(a_span["col"]), _STORY, false, a_expected, effect.reads)
	var b_expr := _expr(effect.b_text, int(b_span["line"]), int(b_span["col"]), _STORY, false, b_expected, effect.reads)
	var value := _expr(effect.value_text, int(value_span["line"]), int(value_span["col"]), _STORY, false, &"", effect.reads)
	effect.a = a_expr["compiled"]
	effect.b = b_expr["compiled"]
	effect.value = value["compiled"]
	var ast := value["ast"] as WyrdExprNode
	if ast != null and ast.type_name != &"error" and ast.type_name != &"int" and ast.type_name != &"float":
		_error(WyrdDiagnostic.E_WRITE_TYPE, "adjust baseline needs an int or float", int(value_span["line"]), int(value_span["col"]))
	return true


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


func _lock(effect: WyrdEffectDef, items: Array[WyrdToken]) -> bool:
	if items.size() < 2 or items[1].text != "topic":
		_unknown_msg_at(effect, "lock topic needs a topic id")
		return false
	var topic := _dotted_at(items, 2)
	if String(topic["name"]).is_empty() or int(topic["next"]) != items.size():
		_unknown_msg_at(effect, "lock topic needs a topic id")
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


func _warn_slot_const(state: String, ast: WyrdExprNode, line: int, col: int) -> void:
	var folded: Variant = WyrdCondition.const_bool(ast)
	if folded == null:
		return
	var code := WyrdDiagnostic.W_SLOT_COND_ALWAYS if bool(folded) else WyrdDiagnostic.W_SLOT_COND_NEVER
	var how := "always true" if bool(folded) else "never true"
	_diagnostics.add(
		code,
		"%s condition is %s" % [state, how],
		_path,
		line,
		col,
		WyrdDiagnostic.SEVERITY_WARNING
	)


func _expr(
	text: String,
	line: int,
	col: int,
	context: StringName,
	require_bool: bool,
	expected: StringName,
	into: Array[StringName],
	bindings: Dictionary = {},
	allow_spatial: bool = false
) -> Dictionary:
	if text.strip_edges().is_empty():
		_error(WyrdDiagnostic.E_EXPR_SYNTAX, "expected an expression", line, col)
		return {"ast": null, "compiled": null}
	var compiler := WyrdCondition.new()
	var compiled := compiler.compile(
		text,
		_schema,
		_diagnostics,
		_path,
		line,
		col,
		context,
		WyrdCondition.MINUTES_PER_DAY,
		_signatures,
		require_bool,
		expected,
		_event_fields,
		bindings,
		allow_spatial
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


func _take_variants(node: WyrdNode, line_def: WyrdLineDef, story: bool = false) -> void:
	var seen := {}
	for child in node.children:
		if child.keyword != "variant":
			if story:
				_story_error(child, "a storylet line cannot contain a block")
				_no_story_block(child)
			else:
				_unknown(child)
			continue
		var variant := _variant_line(child, line_def)
		if variant == null:
			continue
		if seen.has(variant.holder):
			_error(
				WyrdDiagnostic.E_VARIANT_SYNTAX,
				"duplicate variant for \"%s\"" % variant.holder,
				child.start_line,
				child.start_col
			)
			continue
		seen[variant.holder] = true
		line_def.variants.append(variant)
		WyrdStmtSpan.add_reads(line_def.reads, variant.reads)
	_bind_slot(line_def)
	_lint_voiced(line_def.prose, line_def.tags, line_def.line, line_def.col)
	for item in line_def.variants:
		var variant := item as WyrdLineDef
		if variant == null:
			continue
		_lint_voiced(variant.prose, variant.tags, variant.line, variant.col)


func _variant_line(node: WyrdNode, parent: WyrdLineDef) -> WyrdLineDef:
	var items := node.head
	if items.size() < 2 or items[0].kind != &"ident" or items[1].kind != &"colon":
		_error(WyrdDiagnostic.E_VARIANT_SYNTAX, "variant needs <holder>: <prose>", node.start_line, node.start_col)
		_no_block(node)
		return null
	if items.size() == 2:
		_error(WyrdDiagnostic.E_VARIANT_SYNTAX, "variant needs <holder>: <prose>", node.start_line, node.start_col)
		_no_block(node)
		return null
	var variant := WyrdLineDef.new()
	variant.take_span(node)
	variant.kind = &"variant"
	variant.holder = items[0].text
	variant.speaker = parent.speaker
	variant.scene_id = parent.scene_id
	variant.line_id = _line_id(node, true)
	variant.tags = node.tags.duplicate()
	variant.secrecy = node.secrecy
	variant.prose = _interp(_tail(items, 2), variant.reads)
	if not node.children.is_empty():
		_error(WyrdDiagnostic.E_VARIANT_SYNTAX, "a variant line cannot contain a block", node.start_line, node.start_col)
		_no_block(node)
	return variant


func _bind_slot(line_def: WyrdLineDef) -> void:
	var spans: Array = []
	WyrdLineDef.collect_variants(line_def.prose, spans)
	if spans.size() > 1:
		var extra := spans[1] as WyrdExprNode
		_error(
			WyrdDiagnostic.E_VARIANT_SYNTAX,
			"a line holds one {holder|variants} span",
			extra.line if extra != null else line_def.line,
			extra.col if extra != null else line_def.col
		)
	if not spans.is_empty():
		var first := spans[0] as WyrdExprNode
		var slot := WyrdLineDef.holder_slot(first)
		if slot.is_empty():
			_error(
				WyrdDiagnostic.E_VARIANT_SYNTAX,
				"variants need holder(<name>)",
				first.line if first != null else line_def.line,
				first.col if first != null else line_def.col
			)
		else:
			line_def.variant_slot = slot
	if not line_def.variants.is_empty() and line_def.variant_slot.is_empty():
		_error(
			WyrdDiagnostic.E_VARIANT_SYNTAX,
			"variant lines need {holder(<name>)|variants} on the line",
			line_def.line,
			line_def.col
		)


func _lint_voiced(prose: WyrdExprNode, tags: PackedStringArray, line: int, col: int) -> void:
	if not tags.has("voiced"):
		return
	if WyrdLineDef.has_variable_text(prose):
		_error(
			WyrdDiagnostic.E_VOICED_VARIABLE,
			"a voiced line cannot interpolate variable text",
			line,
			col
		)


func _line_id(node: WyrdNode, required: bool) -> String:
	if required:
		_note_line_site(node, true)
	if node.line_tag.is_empty():
		if required:
			_error(WyrdDiagnostic.E_LINE_ID_MISSING, "missing #line: id; run tag-lines (S1d)", node.start_line, node.start_col)
		return ""
	if _line_ids.has(node.line_tag):
		_error(WyrdDiagnostic.E_LINE_ID_DUPLICATE, "duplicate #line: id \"%s\"" % node.line_tag, node.start_line, node.start_col)
	else:
		_line_ids[node.line_tag] = true
	return node.line_tag


func _note_line_site(node: WyrdNode, required: bool) -> void:
	line_sites.append({
		"line": node.start_line,
		"owner": _line_owner,
		"required": required,
		"tag": node.line_tag,
	})


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


const _STORYLET_FIELDS := {
	"cooldown": true,
	"priority": true,
	"scope": true,
	"secrecy": true,
	"speaker": true,
	"speaker_cooldown": true,
	"weight": true,
	"when": true,
}


func _storylet(node: WyrdNode) -> WyrdStoryletDef:
	var story := WyrdStoryletDef.new()
	story.take_span(node)
	if not node.line_tag.is_empty():
		_story_error(node, "a line tag is not allowed on a storylet")
	if not node.title.is_empty():
		_story_error(node, "a storylet has no title")
	var ident := _dotted_at(node.head, 0)
	story.id = String(ident["name"])
	if story.id.is_empty() or int(ident["next"]) != node.head.size():
		_story_error(node, "storylet needs an id")
		story.id = ""
	var saved_owner := _line_owner
	_line_owner = story.id
	var seen := {}
	var bodies := 0
	for child in node.children:
		var field := child.keyword
		if field == "~":
			_storylet_effect(child, story)
			continue
		if field == "on_fail":
			_story_error(child, "on_fail is not valid in a storylet")
			_no_story_block(child)
			continue
		if field == "lines" and seen.has("lines"):
			_story_error(child, "duplicate storylet field \"lines\"")
			_no_story_block(child)
			continue
		if field == "-" or field == "->" or field == "lines":
			if bodies > 0:
				_story_error(child, "a storylet has one body")
				_no_story_block(child)
				continue
			bodies += 1
			if field == "-":
				story.body_kind = &"line"
				_storylet_line(child, story)
			elif field == "->":
				_storylet_scene(child, story)
			else:
				seen["lines"] = true
				story.body_kind = &"set"
				_storylet_set(child, story)
			continue
		if not _STORYLET_FIELDS.has(field):
			_story_error(child, "unknown storylet field \"%s\"" % field)
			_no_story_block(child)
			continue
		if seen.has(field):
			_story_error(child, "duplicate storylet field \"%s\"" % field)
			_no_story_block(child)
			continue
		seen[field] = true
		_storylet_field(child, story, field)
	if not seen.has("scope"):
		_story_error(node, "storylet needs a scope")
	if not seen.has("speaker"):
		_story_error(node, "storylet needs a speaker")
	if bodies == 0:
		_story_error(node, "a storylet needs a line, a lines set, or -> scene <id>")
	for line_def in story.lines:
		line_def.speaker = story.speaker
		for item in line_def.variants:
			var variant := item as WyrdLineDef
			if variant != null:
				variant.speaker = story.speaker
	if not story.id.is_empty():
		var flag := "true" if story.generic else "false"
		_diagnostics.add(
			WyrdDiagnostic.I_STORYLET_SCORE,
			"storylet \"%s\" specificity %d priority %d generic=%s" % [story.id, story.specificity, story.priority, flag],
			_path,
			story.line,
			story.col,
			WyrdDiagnostic.SEVERITY_INFO
		)
	_line_owner = saved_owner
	return story


func _storylet_effect(node: WyrdNode, story: WyrdStoryletDef) -> void:
	var effect := _effect(node)
	if effect == null:
		return
	var reject := false
	if not effect.on_fail.is_empty():
		_story_error(node, "on_fail is not valid in a storylet")
		reject = true
	for child in node.children:
		if child.keyword == "on_fail":
			_story_error(child, "on_fail is not valid in a storylet")
		else:
			_story_error(child, "unknown storylet field \"%s\"" % child.keyword)
		reject = true
	if reject:
		return
	story.effects.append(effect)
	WyrdStmtSpan.add_reads(story.reads, effect.reads)


func _storylet_field(node: WyrdNode, story: WyrdStoryletDef, field: String) -> void:
	if not node.line_tag.is_empty():
		_story_error(node, "a line tag is not allowed on %s" % field)
	_no_story_block(node)
	match field:
		"scope":
			_storylet_scope(node, story)
		"speaker":
			_storylet_speaker(node, story)
		"when":
			_storylet_when(node, story)
		"priority":
			_storylet_priority(node, story)
		"weight":
			_storylet_weight(node, story)
		"cooldown":
			_storylet_cooldown(node, story)
		"speaker_cooldown":
			_storylet_speaker_cooldown(node, story)
		"secrecy":
			_storylet_secrecy(node, story)


func _storylet_scope(node: WyrdNode, story: WyrdStoryletDef) -> void:
	var at := _colon_at(node)
	if at < 0 or at >= node.head.size() or node.head[at].kind != &"ident":
		_story_error(node, "scope needs a kind")
		return
	var kind := node.head[at].text
	var rest := at + 1
	if kind == "bark":
		if rest != node.head.size():
			_story_error(node, "bark scope takes no id")
			return
		story.scope_kind = &"bark"
		return
	if kind != "topic" and kind != "event" and kind != "beat":
		_story_error(node, "unknown scope \"%s\"" % kind)
		return
	var found := _dotted_at(node.head, rest)
	var name := String(found["name"])
	if name.is_empty() or int(found["next"]) != node.head.size():
		_story_error(node, "scope %s needs an id" % kind)
		return
	if kind == "beat" and not name.contains("."):
		_story_error(node, "beat scope needs <quest>.<stage>")
		return
	if kind == "event" and not _events.has(name):
		_error(WyrdDiagnostic.E_EVENT_UNKNOWN, "unknown event \"%s\"" % name, node.head[rest].line, node.head[rest].col)
	story.scope_kind = StringName(kind)
	story.scope_id = name


func _storylet_speaker(node: WyrdNode, story: WyrdStoryletDef) -> void:
	var at := _colon_at(node)
	var found := _dotted_at(node.head, at if at >= 0 else node.head.size())
	var name := String(found["name"])
	if at < 0 or name.is_empty() or int(found["next"]) != node.head.size() or not _shape_ok(name):
		_story_error(node, "speaker needs a slot, an entity, or any")
		return
	story.speaker = name


func _storylet_when(node: WyrdNode, story: WyrdStoryletDef) -> void:
	story.generic = false
	var at := _colon_at(node)
	if at < 0:
		_story_error(node, "when needs a condition")
		return
	var span := _span_text(node.head, at, node.head.size())
	if str(span["text"]).is_empty():
		_story_error(node, "when needs a condition")
		return
	story.when_text = str(span["text"])
	var compiled := _expr(story.when_text, int(span["line"]), int(span["col"]), _STORY, true, &"", story.reads)
	story.condition = compiled["compiled"]
	if story.condition != null:
		story.specificity = story.condition.specificity
		_storylet_clauses(story, compiled["ast"] as WyrdExprNode)


func _storylet_clauses(story: WyrdStoryletDef, ast: WyrdExprNode) -> void:
	if ast == null or ast.kind == &"error":
		return
	var emitter := WyrdEmitter.new()
	for part in WyrdStoryletTie.and_parts(ast):
		story.clause_text.append(WyrdStoryletTie.render(part))
		story.clauses.append(emitter.emit(part))


func _storylet_priority(node: WyrdNode, story: WyrdStoryletDef) -> void:
	var parsed := _signed_int(node)
	if not bool(parsed["ok"]):
		_story_error(node, "priority needs an integer")
		return
	story.priority = int(parsed["value"])


func _storylet_weight(node: WyrdNode, story: WyrdStoryletDef) -> void:
	var parsed := _signed_int(node)
	if not bool(parsed["ok"]):
		_story_error(node, "weight needs an integer")
		return
	if int(parsed["value"]) < 0:
		_story_error(node, "weight cannot be negative")
		return
	story.weight = int(parsed["value"])


func _storylet_cooldown(node: WyrdNode, story: WyrdStoryletDef) -> void:
	var minutes := _duration_minutes(node, "cooldown")
	if minutes < 0:
		return
	story.cooldown_minutes = minutes


func _storylet_secrecy(node: WyrdNode, story: WyrdStoryletDef) -> void:
	var at := _colon_at(node)
	var found := _dotted_at(node.head, at if at >= 0 else node.head.size())
	var name := String(found["name"])
	if at < 0 or name.is_empty() or int(found["next"]) != node.head.size() or name.contains("."):
		_story_error(node, "secrecy needs a name")
		return
	story.secrecy = name


func _storylet_speaker_cooldown(node: WyrdNode, story: WyrdStoryletDef) -> void:
	var minutes := _duration_minutes(node, "speaker_cooldown")
	if minutes < 0:
		return
	story.speaker_cooldown_minutes = minutes


func _duration_minutes(node: WyrdNode, label: String) -> int:
	var at := _colon_at(node)
	if at >= 0 and at < node.head.size() and node.head[at].kind == &"minus":
		_story_error(node, "%s cannot be negative" % label)
		return -1
	if at < 0 or at + 1 >= node.head.size() or node.head[at].kind != &"int" or node.head[at + 1].kind != &"ident" or at + 2 != node.head.size():
		_story_error(node, "%s needs a duration" % label)
		return -1
	var scale := 0
	match node.head[at + 1].text:
		"m":
			scale = 1
		"h":
			scale = 60
		"d":
			scale = WyrdCondition.MINUTES_PER_DAY
		_:
			_story_error(node, "%s unit must be m, h, or d" % label)
			return -1
	return int(node.head[at].text) * scale


func _spatial_wait(stage: WyrdStageDef) -> void:
	if stage == null or stage.waits_until == null or not stage.waits_until.uses_spatial:
		return
	if not stage.handlers.is_empty():
		return
	var span: Dictionary = stage.waits_until.source_span
	_error(
		WyrdDiagnostic.E_SPATIAL_CONTEXT,
		"waits_until nearby, can_perceive, or can_reach needs an on <event> handler",
		int(span.get("line", stage.line)),
		int(span.get("col", stage.col))
	)


func _storylet_set(node: WyrdNode, story: WyrdStoryletDef) -> void:
	if not node.line_tag.is_empty():
		_story_error(node, "a line tag is not allowed on lines")
	if node.head.size() != 1 or node.head[0].kind != &"colon":
		_story_error(node, "lines takes no arguments")
	if node.children.is_empty():
		_story_error(node, "a line set needs at least one line")
	for child in node.children:
		if child.keyword != "-":
			_story_error(child, "a line set holds prose lines")
			_no_story_block(child)
			continue
		_storylet_line(child, story)


func _storylet_line(node: WyrdNode, story: WyrdStoryletDef) -> void:
	if not node.head.is_empty() and node.head[0].kind == &"lparen":
		_story_error(node, "a storylet line is prose, not a label")
		for child in node.children:
			_no_story_block(child)
		return
	var line_def := WyrdLineDef.new()
	line_def.take_span(node)
	line_def.kind = &"storylet"
	line_def.speaker = story.speaker
	line_def.line_id = _line_id(node, true)
	line_def.tags = node.tags.duplicate()
	line_def.secrecy = node.secrecy
	if node.head.is_empty():
		_story_error(node, "a storylet line needs prose")
	else:
		line_def.prose = _interp(node.head, line_def.reads)
	_take_variants(node, line_def, true)
	WyrdStmtSpan.add_reads(story.reads, line_def.reads)
	story.lines.append(line_def)


func _storylet_scene(node: WyrdNode, story: WyrdStoryletDef) -> void:
	if not node.line_tag.is_empty():
		_story_error(node, "a line tag is not allowed on a storylet divert")
	_no_story_block(node)
	var items := node.head
	if items.is_empty() or items[0].kind != &"ident" or items[0].text != "scene":
		_story_error(node, "storylet divert needs -> scene <id>")
		return
	var found := _dotted_at(items, 1)
	if String(found["name"]).is_empty() or int(found["next"]) != items.size():
		_story_error(node, "storylet divert needs -> scene <id>")
		return
	story.body_kind = &"scene"
	story.scene_id = String(found["name"])


func _colon_at(node: WyrdNode) -> int:
	if node.head.is_empty() or node.head[0].kind != &"colon":
		return -1
	return 1


func _signed_int(node: WyrdNode) -> Dictionary:
	var at := _colon_at(node)
	if at < 0 or at >= node.head.size():
		return {"ok": false, "value": 0}
	var sign := 1
	if node.head[at].kind == &"minus":
		sign = -1
		at += 1
	if at >= node.head.size() or node.head[at].kind != &"int" or at + 1 != node.head.size():
		return {"ok": false, "value": 0}
	return {"ok": true, "value": sign * int(node.head[at].text)}


func _story_error(node: WyrdNode, message: String) -> void:
	_diagnostics.add(WyrdDiagnostic.E_STORYLET_SYNTAX, message, _path, node.start_line, node.start_col)


func _no_story_block(node: WyrdNode) -> void:
	if node.children.is_empty():
		return
	_story_error(node, "a storylet field cannot contain a block")
	for child in node.children:
		_no_story_block(child)


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


func _disabled_word(token: WyrdToken) -> bool:
	return token.kind == &"ident" and (token.text == "show_disabled_when" or token.text == "disabled_when")


func _choice_check(node: WyrdNode, choice: WyrdChoiceDef) -> void:
	var items := node.head
	if items.size() < 3 or items[0].kind != &"ident" or items[1].kind != &"lparen":
		_check_error(node, "check needs <skill>(...) on_fail -> <target>")
		return
	var close := _closing(items, 1, &"lparen", &"rparen")
	if close < 0:
		_check_error(node, "check needs <skill>(...) on_fail -> <target>")
		return
	var skill := items[0].text
	var args: Array = []
	var reads: Array[StringName] = []
	var seen := {}
	for row in _arg_rows(items, 2, close):
		var name := String(row["name"])
		if not name.is_empty() and seen.has(name):
			_error(WyrdDiagnostic.E_ARG_NAME, "command argument \"%s\" is duplicated" % name, int(row["line"]), int(row["col"]))
			continue
		if not name.is_empty():
			seen[name] = true
		var expected := _command_expected(items, int(row["from"]), int(row["to"]))
		var compiled := _expr(String(row["text"]), int(row["line"]), int(row["col"]), _STORY, false, expected, reads)
		args.append({"compiled": compiled["compiled"], "name": name, "text": String(row["text"])})
	var on_fail := ""
	var fail_line := 0
	var fail_col := 0
	var i := close + 1
	if i < items.size():
		if i + 2 >= items.size() or items[i].text != "on_fail" or items[i + 1].kind != &"arrow":
			_check_error(node, "check needs <skill>(...) on_fail -> <target>")
			return
		var target := _dotted_at(items, i + 2)
		if String(target["name"]).is_empty() or int(target["next"]) != items.size() or String(target["name"]).contains("."):
			_check_error(node, "check needs <skill>(...) on_fail -> <target>")
			return
		on_fail = String(target["name"])
		fail_line = items[i + 2].line
		fail_col = items[i + 2].col
	for child in node.children:
		if child.keyword != "on_fail":
			_unknown(child)
			continue
		if not on_fail.is_empty():
			_check_error(child, "check has one on_fail")
			continue
		var child_items := child.head
		if child_items.size() < 2 or child_items[0].kind != &"arrow":
			_check_error(child, "check needs on_fail -> <target>")
			continue
		var child_target := _dotted_at(child_items, 1)
		if String(child_target["name"]).is_empty() or int(child_target["next"]) != child_items.size() or String(child_target["name"]).contains("."):
			_check_error(child, "check needs on_fail -> <target>")
			continue
		on_fail = String(child_target["name"])
		fail_line = child_items[1].line
		fail_col = child_items[1].col
	if on_fail.is_empty():
		_check_error(node, "check needs on_fail -> <target>")
		return
	choice.check_skill = skill
	choice.check_args = args
	choice.check_on_fail = on_fail
	choice.check_line = items[0].line
	choice.check_col = items[0].col
	WyrdStmtSpan.add_reads(choice.reads, reads)
	_note_label(on_fail, fail_line, fail_col)


func _check_error(node: WyrdNode, message: String) -> void:
	_error(WyrdDiagnostic.E_CHECK_SYNTAX, message, node.start_line, node.start_col)
	_no_block(node)


func _choice_error(node: WyrdNode, message: String) -> void:
	_error(WyrdDiagnostic.E_CHOICE_SYNTAX, message, node.start_line, node.start_col)
	_no_block(node)


func _error(code: StringName, message: String, line: int, col: int) -> void:
	_diagnostics.add(code, message, _path, line, col)
