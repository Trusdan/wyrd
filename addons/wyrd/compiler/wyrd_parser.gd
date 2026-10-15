class_name WyrdParser
extends RefCounted

## Block parser for grammar v1, plus the checked [code]facts[/code] and draft [code]events[/code] blocks.
##
## @experimental
## [code]quest[/code] and [code]scene[/code] bodies are a generic statement-line tree.
## Their statements are not interpreted here. [code]await_host[/code] stays a
## line in that tree; the statement compiler reads the screen id and fields.

const _TYPES: PackedStringArray = ["bool", "int", "float", "symbol"]

var _source: WyrdSource
var _diagnostics: WyrdDiagnostics
var _tokens: Array[WyrdToken] = []
var _index: int = 0
var _file: WyrdNode


func parse(source: WyrdSource, diagnostics: WyrdDiagnostics) -> WyrdNode:
	return parse_tokens(source, WyrdLexer.new().tokenize(source, diagnostics), diagnostics)


func parse_tokens(source: WyrdSource, tokens: Array[WyrdToken], diagnostics: WyrdDiagnostics) -> WyrdNode:
	_source = source
	_diagnostics = diagnostics
	_tokens = tokens
	_index = 0
	_file = WyrdNode.new()
	_file.kind = &"file"
	_file.schema = WyrdFactSchema.new()
	_file.start_line = 1
	_file.start_col = 1
	var end_offset := source.text.length()
	_file.end_line = source.line_at(end_offset)
	_file.end_col = source.column_at(end_offset)
	var statements: Array[WyrdNode] = []
	while _has():
		_skip_newlines()
		if not _has():
			break
		var before := _index
		statements.append(_parse_statement())
		if _index == before:
			_advance()
	if statements.is_empty():
		diagnostics.add(
			WyrdDiagnostic.E_HEADER_MISSING,
			"missing language header",
			source.path,
			1,
			1
		)
		return _file
	_check_header(statements[0])
	for i in range(1, statements.size()):
		var block := statements[i]
		if block.keyword != "facts" and block.keyword != "events" and block.keyword != "quest" and block.keyword != "scene":
			diagnostics.add(
				WyrdDiagnostic.E_UNEXPECTED_TOKEN,
				"unexpected token \"%s\"" % _shown(block),
				source.path,
				block.start_line,
				block.start_col
			)
		_file.children.append(block)
		_extend(_file, block)
	return _file


func _check_header(node: WyrdNode) -> void:
	var int_ok := node.head.size() == 1 and node.head[0].kind == &"int" and node.head[0].text == "1"
	var ok := (
		node.keyword == "language"
		and int_ok
		and node.title.is_empty()
		and node.line_tag.is_empty()
		and node.children.is_empty()
	)
	if ok:
		return
	_diagnostics.add(
		WyrdDiagnostic.E_HEADER_INVALID,
		"header must be exactly \"language 1\"",
		_source.path,
		node.start_line,
		node.start_col
	)


func _parse_statement() -> WyrdNode:
	var line := _collect_line()
	var node := _node_from_line(line)
	if _peek_kind() == &"indent":
		_advance()
		if node.keyword == "facts":
			_parse_fact_body(node)
		elif node.keyword == "events":
			_parse_event_body(node)
		else:
			_parse_children(node)
		if _peek_kind() == &"dedent":
			_advance()
	if node.keyword == "facts":
		node.kind = &"facts"
		if not node.head.is_empty() or not node.title.is_empty() or not node.line_tag.is_empty():
			_diagnostics.add(
				WyrdDiagnostic.E_UNEXPECTED_TOKEN,
				"unexpected token \"%s\"" % _shown(node),
				_source.path,
				node.start_line,
				node.start_col
			)
	elif node.keyword == "events":
		node.kind = &"events"
		if not node.head.is_empty() or not node.title.is_empty() or not node.line_tag.is_empty():
			_diagnostics.add(
				WyrdDiagnostic.E_UNEXPECTED_TOKEN,
				"unexpected token \"%s\"" % _shown(node),
				_source.path,
				node.start_line,
				node.start_col
			)
	elif node.keyword == "quest":
		node.kind = &"quest"
	elif node.keyword == "scene":
		node.kind = &"scene"
	return node


func _parse_children(node: WyrdNode) -> void:
	while _has():
		_skip_newlines()
		var kind := _peek_kind()
		if kind == &"dedent" or kind == &"eof" or kind == &"":
			break
		var before := _index
		var child := _parse_statement()
		node.children.append(child)
		_extend(node, child)
		if _index == before:
			_advance()


func _parse_fact_body(node: WyrdNode) -> void:
	while _has():
		_skip_newlines()
		var kind := _peek_kind()
		if kind == &"dedent" or kind == &"eof" or kind == &"":
			break
		var line := _collect_line()
		var child := _node_from_fact(line)
		for entry in child.entries:
			node.entries.append(entry)
		child.entries.clear()
		node.children.append(child)
		_extend(node, child)
		if _peek_kind() == &"indent":
			_diagnostics.add(
				WyrdDiagnostic.E_FACTS_SYNTAX,
				"a fact entry cannot contain a block",
				_source.path,
				child.start_line,
				child.start_col
			)
			_advance()
			_skip_nested()


func _parse_event_body(node: WyrdNode) -> void:
	var seen := {}
	while _has():
		_skip_newlines()
		var kind := _peek_kind()
		if kind == &"dedent" or kind == &"eof" or kind == &"":
			break
		var line := _collect_line()
		var event := _read_event(line)
		if event.name != "":
			if seen.has(event.name):
				_diagnostics.add(
					WyrdDiagnostic.E_EVENT_DUPLICATE,
					"duplicate event \"%s\"" % event.name,
					_source.path,
					event.line,
					event.col
				)
			else:
				seen[event.name] = true
				node.events.append(event)
		if _peek_kind() == &"indent":
			_diagnostics.add(
				WyrdDiagnostic.E_EVENT_ARG,
				"an event declaration cannot contain a block",
				_source.path,
				event.line,
				event.col
			)
			_advance()
			_skip_nested()


func _read_event(line: Array[WyrdToken]) -> WyrdEventDef:
	var event := WyrdEventDef.new()
	var cursor := _Cursor.new()
	cursor.items = line
	if line.is_empty():
		_event_error("expected an event name", cursor, 1, 1)
		return event
	event.line = line[0].line
	event.col = line[0].col
	if cursor.kind() != &"ident":
		_event_error("expected an event name", cursor, event.line, event.col)
		return event
	event.name = cursor.text()
	cursor.advance()
	if cursor.kind() != &"lparen":
		_event_error("expected \"(\" after the event name", cursor, event.line, event.col)
		event.name = ""
		return event
	cursor.advance()
	if cursor.kind() != &"rparen":
		if not _read_event_fields(cursor, event):
			event.name = ""
			return event
	else:
		cursor.advance()
	if cursor.has():
		_event_error("unexpected token \"%s\" in an event" % cursor.peek().display(), cursor, event.line, event.col)
		event.name = ""
	return event


func _read_event_fields(cursor: _Cursor, event: WyrdEventDef) -> bool:
	var seen := {}
	while cursor.has():
		if cursor.kind() != &"ident":
			_event_error("expected a field name", cursor, event.line, event.col)
			return false
		var field_name := cursor.text()
		var field_line := cursor.line()
		var field_col := cursor.col()
		cursor.advance()
		if cursor.kind() != &"colon":
			_event_error("expected \":\" after the field name", cursor, event.line, event.col)
			return false
		cursor.advance()
		if cursor.kind() != &"ident" or not _TYPES.has(cursor.text()):
			if cursor.kind() == &"ident":
				_diagnostics.add(
					WyrdDiagnostic.E_EVENT_TYPE,
					"unknown event field type \"%s\"" % cursor.text(),
					_source.path,
					cursor.line(),
					cursor.col()
				)
			else:
				_event_error("expected a field type", cursor, event.line, event.col)
			return false
		if seen.has(field_name):
			_diagnostics.add(
				WyrdDiagnostic.E_EVENT_ARG,
				"duplicate field \"%s\"" % field_name,
				_source.path,
				field_line,
				field_col
			)
			return false
		seen[field_name] = true
		event.fields.append({"name": field_name, "type": cursor.text()})
		cursor.advance()
		if cursor.kind() == &"rparen":
			cursor.advance()
			return true
		if cursor.kind() != &"comma":
			_event_error("expected \",\" or \")\" in an event", cursor, event.line, event.col)
			return false
		cursor.advance()
	_event_error("expected \")\" in an event", cursor, event.line, event.col)
	return false


func _event_error(message: String, cursor: _Cursor, fallback_line: int, fallback_col: int) -> void:
	var line := fallback_line
	var col := fallback_col
	if cursor.has():
		line = cursor.line()
		col = cursor.col()
	elif not cursor.items.is_empty():
		line = cursor.items[cursor.items.size() - 1].end_line
		col = cursor.items[cursor.items.size() - 1].end_col
	_diagnostics.add(WyrdDiagnostic.E_EVENT_ARG, message, _source.path, line, col)


func _node_from_line(line: Array[WyrdToken]) -> WyrdNode:
	var node := WyrdNode.new()
	node.kind = &"line"
	var head: Array[WyrdToken] = []
	for token in line:
		if token.kind == &"line_tag":
			node.line_tag = token.text
		else:
			head.append(token)
	if not head.is_empty():
		node.start_line = head[0].line
		node.start_col = head[0].col
		node.end_line = head[head.size() - 1].end_line
		node.end_col = head[head.size() - 1].end_col
		node.keyword = head[0].display()
		if head[0].kind == &"string":
			node.title = head[0].text
		head.remove_at(0)
	elif not line.is_empty():
		node.start_line = line[0].line
		node.start_col = line[0].col
		node.end_line = line[line.size() - 1].end_line
		node.end_col = line[line.size() - 1].end_col
	for i in head.size():
		if head[i].kind == &"string" and node.title.is_empty():
			node.title = head[i].text
			head.remove_at(i)
			break
	node.head = head
	return node


func _node_from_fact(line: Array[WyrdToken]) -> WyrdNode:
	var node := _node_from_line(line)
	node.kind = &"fact"
	node.head = []
	var content: Array[WyrdToken] = []
	for token in line:
		if token.kind == &"line_tag":
			_diagnostics.add(
				WyrdDiagnostic.E_FACTS_SYNTAX,
				"a line tag is not allowed on a fact entry",
				_source.path,
				token.line,
				token.col
			)
		else:
			content.append(token)
	node.head = content
	if not content.is_empty():
		node.start_line = content[0].line
		node.start_col = content[0].col
		node.end_line = content[content.size() - 1].end_line
		node.end_col = content[content.size() - 1].end_col
	var fact := _read_fact(content, node.start_line, node.start_col)
	node.keyword = fact.key
	node.title = fact.doc
	if fact.valid:
		if _file.schema == null:
			_file.schema = WyrdFactSchema.new()
		_file.schema.add(fact, _diagnostics, _source.path)
		node.entries.append(fact)
	return node


func _read_fact(line: Array[WyrdToken], fallback_line: int, fallback_col: int) -> WyrdFact:
	var fact := WyrdFact.new()
	fact.line = fallback_line
	fact.col = fallback_col
	var cursor := _Cursor.new()
	cursor.items = line
	if not _read_key(cursor, fact):
		return fact
	fact.line = line[0].line
	fact.col = line[0].col
	if cursor.kind() != &"colon":
		_fact_error("expected \":\" after the fact key", cursor, fallback_line, fallback_col)
		return fact
	cursor.advance()
	if cursor.kind() != &"ident" or not _TYPES.has(cursor.text()):
		if cursor.kind() == &"ident":
			_fact_error("unknown fact type \"%s\"" % cursor.text(), cursor, fallback_line, fallback_col)
		else:
			_fact_error("expected a fact type", cursor, fallback_line, fallback_col)
		return fact
	fact.type_name = StringName(cursor.text())
	cursor.advance()
	if cursor.text() == "stored":
		fact.origin = &"stored"
		cursor.advance()
	elif cursor.text() == "source":
		cursor.advance()
		fact.origin = &"resolved"
		if cursor.kind() != &"colon":
			_fact_error("expected \":\" after \"source\"", cursor, fallback_line, fallback_col)
			return fact
		cursor.advance()
		if not _read_resolver(cursor, fact, fallback_line, fallback_col):
			return fact
	else:
		_fact_error("expected \"stored\" or \"source\"", cursor, fallback_line, fallback_col)
		return fact
	if cursor.text() == "invalidate":
		if not _read_invalidate(cursor, fact, fallback_line, fallback_col):
			return fact
	if cursor.text() == "doc":
		if not _read_doc(cursor, fact, fallback_line, fallback_col):
			return fact
	if cursor.has():
		_fact_error("unexpected token \"%s\" in a fact entry" % cursor.peek().display(), cursor, fallback_line, fallback_col)
		return fact
	fact.valid = true
	return fact


func _read_key(cursor: _Cursor, fact: WyrdFact) -> bool:
	if not _read_segment(cursor, fact):
		_fact_error("expected a fact key", cursor, fact.line, fact.col)
		return false
	while cursor.kind() == &"dot":
		cursor.advance()
		if not _read_segment(cursor, fact):
			_fact_error("expected a fact key", cursor, fact.line, fact.col)
			return false
	fact.key = ".".join(fact.segments)
	return true


func _read_segment(cursor: _Cursor, fact: WyrdFact) -> bool:
	if cursor.kind() == &"ident":
		fact.segments.append(cursor.text())
		cursor.advance()
		return true
	if cursor.kind() != &"lbrace":
		return false
	cursor.advance()
	if cursor.kind() != &"ident":
		return false
	var name := cursor.text()
	cursor.advance()
	if cursor.kind() != &"rbrace":
		return false
	cursor.advance()
	fact.segments.append("{%s}" % name)
	return true


func _read_resolver(cursor: _Cursor, fact: WyrdFact, fallback_line: int, fallback_col: int) -> bool:
	if cursor.kind() != &"ident":
		_fact_error("expected a resolver", cursor, fallback_line, fallback_col)
		return false
	var parts: PackedStringArray = PackedStringArray()
	parts.append(cursor.text())
	cursor.advance()
	while cursor.kind() == &"dot":
		cursor.advance()
		if cursor.kind() != &"ident":
			_fact_error("expected a resolver", cursor, fallback_line, fallback_col)
			return false
		parts.append(cursor.text())
		cursor.advance()
	fact.resolver = ".".join(parts)
	return true


func _read_invalidate(cursor: _Cursor, fact: WyrdFact, fallback_line: int, fallback_col: int) -> bool:
	cursor.advance()
	if cursor.kind() != &"colon":
		_fact_error("expected \":\" after \"invalidate\"", cursor, fallback_line, fallback_col)
		return false
	cursor.advance()
	var clause := cursor.text()
	if clause == "per_query":
		fact.invalidate = &"per_query"
		cursor.advance()
		return true
	if clause != "on_event" and clause != "poll":
		_fact_error("unknown invalidate clause", cursor, fallback_line, fallback_col)
		return false
	cursor.advance()
	if cursor.kind() != &"lparen":
		_fact_error("expected \"(\" in an invalidate clause", cursor, fallback_line, fallback_col)
		return false
	cursor.advance()
	if clause == "on_event":
		if cursor.kind() != &"ident":
			_fact_error("expected an event name", cursor, fallback_line, fallback_col)
			return false
		fact.invalidate = &"on_event"
		fact.invalidate_arg = cursor.text()
		cursor.advance()
	else:
		if cursor.kind() != &"int":
			_fact_error("expected a poll interval", cursor, fallback_line, fallback_col)
			return false
		fact.invalidate = &"poll"
		fact.invalidate_arg = cursor.text()
		cursor.advance()
	if cursor.kind() != &"rparen":
		_fact_error("expected \")\" in an invalidate clause", cursor, fallback_line, fallback_col)
		return false
	cursor.advance()
	return true


func _read_doc(cursor: _Cursor, fact: WyrdFact, fallback_line: int, fallback_col: int) -> bool:
	cursor.advance()
	if cursor.kind() != &"colon":
		_fact_error("expected \":\" after \"doc\"", cursor, fallback_line, fallback_col)
		return false
	cursor.advance()
	if cursor.kind() != &"string":
		_fact_error("expected a doc string", cursor, fallback_line, fallback_col)
		return false
	fact.doc = cursor.text()
	cursor.advance()
	return true


func _fact_error(message: String, cursor: _Cursor, fallback_line: int, fallback_col: int) -> void:
	var line := fallback_line
	var col := fallback_col
	if cursor.has():
		line = cursor.line()
		col = cursor.col()
	elif not cursor.items.is_empty():
		line = cursor.items[cursor.items.size() - 1].end_line
		col = cursor.items[cursor.items.size() - 1].end_col
	_diagnostics.add(WyrdDiagnostic.E_FACTS_SYNTAX, message, _source.path, line, col)


func _collect_line() -> Array[WyrdToken]:
	var line: Array[WyrdToken] = []
	while _has():
		var kind := _peek_kind()
		if kind == &"newline" or kind == &"indent" or kind == &"dedent":
			break
		line.append(_advance())
	if _peek_kind() == &"newline":
		_advance()
	return line


func _skip_nested() -> void:
	var depth := 1
	while _has() and depth > 0:
		var kind := _peek_kind()
		_advance()
		if kind == &"indent":
			depth += 1
		elif kind == &"dedent":
			depth -= 1


func _shown(node: WyrdNode) -> String:
	if not node.keyword.is_empty():
		return node.keyword
	if not node.line_tag.is_empty():
		return "#line:%s" % node.line_tag
	if not node.title.is_empty():
		return "\"%s\"" % node.title
	return "newline"


func _extend(parent: WyrdNode, child: WyrdNode) -> void:
	if child.end_line > parent.end_line or (child.end_line == parent.end_line and child.end_col > parent.end_col):
		parent.end_line = child.end_line
		parent.end_col = child.end_col


func _skip_newlines() -> void:
	while _peek_kind() == &"newline":
		_advance()


func _has() -> bool:
	return _index < _tokens.size() and _tokens[_index].kind != &"eof"


func _peek_kind() -> StringName:
	if _index >= _tokens.size():
		return &"eof"
	return _tokens[_index].kind


func _advance() -> WyrdToken:
	var token := _tokens[_index]
	_index += 1
	return token


class _Cursor:
	extends RefCounted

	var items: Array[WyrdToken] = []
	var index: int = 0

	func has() -> bool:
		return index < items.size()

	func kind() -> StringName:
		if not has():
			return &"eof"
		return items[index].kind

	func text() -> String:
		if not has():
			return ""
		return items[index].text

	func line() -> int:
		if not has():
			return 1
		return items[index].line

	func col() -> int:
		if not has():
			return 1
		return items[index].col

	func peek() -> WyrdToken:
		return items[index]

	func advance() -> void:
		index += 1
