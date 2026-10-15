class_name WyrdLexer
extends RefCounted

## Lexer for grammar v1 sections 1–6.
##
## @experimental
## Indentation is two spaces. A tab is [code]E_TAB_INDENT[/code]. Indent may rise by
## one level at a time. Blank lines and comment-only lines are ignored.
## Inside a [code]facts[/code], [code]events[/code], or [code]role[/code] block, lines stay code. Elsewhere a line that starts
## with an identifier and a colon is prose: [code]{{[/code] is a literal [code]{[/code],
## a single [code]{[/code] opens an interpolation raw span, and a stray [code]}[/code]
## is literal. [code]}}[/code] is not an escape.
## Draft statement syntax, not a grammar v1 change: [code]on_empty[/code],
## [code]on_abort[/code], and [code]requires[/code] stay code when they open with a
## colon. A [code]when <cond>: <speaker>:[/code] line keeps the condition in code
## and the spoken text in prose. The first depth-zero [code]: <speaker> :[/code]
## ends that condition, so a ternary colon in it needs parentheses.

const _RESERVED: PackedStringArray = [
	"document",
	"publishes_by",
	"tier",
	"await_host",
	"believe",
	"declare",
	"retract",
]
const _CODE_COLON: PackedStringArray = ["on_abort", "on_empty", "requires"]

var _source: WyrdSource
var _diagnostics: WyrdDiagnostics
var _tokens: Array[WyrdToken] = []
var _indents: PackedInt32Array = PackedInt32Array()
var _kinds: PackedStringArray = PackedStringArray()
var _pending_kind: String = ""
var _saw_line: bool = false


func tokenize(source: WyrdSource, diagnostics: WyrdDiagnostics) -> Array[WyrdToken]:
	_source = source
	_diagnostics = diagnostics
	_tokens = []
	_indents = PackedInt32Array()
	_indents.append(0)
	_kinds = PackedStringArray()
	_kinds.append("file")
	_pending_kind = ""
	_saw_line = false
	var offset := 0
	while offset <= source.text.length():
		if offset == source.text.length():
			break
		var line_end := source.text.find("\n", offset)
		if line_end < 0:
			line_end = source.text.length()
		var line := source.text.substr(offset, line_end - offset)
		var line_no := source.line_at(offset)
		_lex_line(line, line_no)
		offset = line_end + 1
		if line_end == source.text.length():
			break
	while _indents.size() > 1:
		_indents.remove_at(_indents.size() - 1)
		_kinds.remove_at(_kinds.size() - 1)
		_emit(&"dedent", "", _end_line(), _end_col(), _end_line(), _end_col())
	_emit(&"eof", "", _end_line(), _end_col(), _end_line(), _end_col())
	return _tokens


func _lex_line(line: String, line_no: int) -> void:
	var index := 0
	var tab_at := -1
	while index < line.length() and (line[index] == " " or line[index] == "\t"):
		if line[index] == "\t" and tab_at < 0:
			tab_at = index
		index += 1
	var content := line.substr(index)
	if tab_at >= 0 and (content.is_empty() or content.begins_with("//")):
		_error(WyrdDiagnostic.E_TAB_INDENT, "tab indentation is not allowed", line_no, tab_at + 1)
		return
	if content.is_empty() or content.begins_with("//"):
		return
	var indent := index
	if tab_at >= 0:
		_error(WyrdDiagnostic.E_TAB_INDENT, "tab indentation is not allowed", line_no, tab_at + 1)
		indent = _indents[_indents.size() - 1]
	elif not _saw_line and indent != 0:
		if indent % 2 != 0:
			_error(WyrdDiagnostic.E_INDENT_WIDTH, "indentation must be a multiple of two spaces", line_no, 1)
		else:
			_error(WyrdDiagnostic.E_INDENT_JUMP, "indentation jumped more than one level", line_no, 1)
	else:
		_apply_indent(indent, line_no)
	_saw_line = true
	var origin := index + 1
	var parent := _kinds[_kinds.size() - 1]
	var code_block := parent == "facts" or parent == "events" or parent == "role"
	var first_ident := ""
	var code_colon := _CODE_COLON.has(_leading_ident(content))
	if not code_block and not code_colon and _speaker_colon(content) >= 0:
		first_ident = _lex_speaker_line(content, line_no, origin)
	elif not code_block and _when_speaker_colon(content) >= 0:
		first_ident = _lex_when_line(content, line_no, origin)
	else:
		first_ident = _lex_code_line(content, line_no, origin, not code_block)
	_pending_kind = first_ident
	_emit(&"newline", "", line_no, origin, line_no, origin)


func _apply_indent(indent: int, line_no: int) -> void:
	if indent % 2 != 0:
		_error(WyrdDiagnostic.E_INDENT_WIDTH, "indentation must be a multiple of two spaces", line_no, 1)
		indent -= indent % 2
	var current := _indents[_indents.size() - 1]
	if indent > current:
		if indent - current != 2:
			_error(WyrdDiagnostic.E_INDENT_JUMP, "indentation jumped more than one level", line_no, 1)
		_indents.append(indent)
		_kinds.append(_pending_kind)
		_emit(&"indent", "", line_no, 1, line_no, indent + 1)
	elif indent < current:
		while _indents.size() > 1 and _indents[_indents.size() - 1] > indent:
			_indents.remove_at(_indents.size() - 1)
			_kinds.remove_at(_kinds.size() - 1)
			_emit(&"dedent", "", line_no, 1, line_no, 1)
		if _indents[_indents.size() - 1] != indent:
			_error(WyrdDiagnostic.E_INDENT_WIDTH, "indentation does not match an open block", line_no, 1)


func _leading_ident(content: String) -> String:
	var index := 0
	while index < content.length() and (content[index] == " " or content[index] == "\t"):
		index += 1
	if index >= content.length() or not _is_ident_start(content[index]):
		return ""
	var end := _ident_end(content, index)
	return content.substr(index, end - index)


func _speaker_colon(content: String) -> int:
	if content.is_empty() or not _is_ident_start(content[0]):
		return -1
	var name_end := _dotted_end(content, 0)
	if name_end < 0:
		return -1
	var cursor := name_end
	while cursor < content.length() and (content[cursor] == " " or content[cursor] == "\t"):
		cursor += 1
	if cursor < content.length() and content[cursor] == ":":
		return cursor
	return -1


func _lex_speaker_line(content: String, line_no: int, origin: int) -> String:
	var colon := _speaker_colon(content)
	var index := 0
	var first := ""
	while index < colon:
		if content[index] == ".":
			_emit_span(&"dot", ".", line_no, origin, index, index + 1)
			index += 1
			continue
		if not _is_ident_start(content[index]):
			break
		var end := _ident_end(content, index)
		var word := content.substr(index, end - index)
		if first.is_empty():
			first = word
		_emit_span(&"ident", word, line_no, origin, index, end)
		_check_reserved(word, line_no, origin + index)
		index = end
	_emit_span(&"colon", ":", line_no, origin, colon, colon + 1)
	var cursor := colon + 1
	while cursor < content.length() and (content[cursor] == " " or content[cursor] == "\t"):
		cursor += 1
	cursor = _read_prose(content, cursor, line_no, origin, false)
	_finish_suffix(content, cursor, line_no, origin)
	return first


func _lex_when_line(content: String, line_no: int, origin: int) -> String:
	var speaker_colon := _when_speaker_colon(content)
	var first := _lex_code_line(content.substr(0, speaker_colon + 1), line_no, origin)
	var cursor := speaker_colon + 1
	while cursor < content.length() and (content[cursor] == " " or content[cursor] == "\t"):
		cursor += 1
	cursor = _read_prose(content, cursor, line_no, origin, false)
	_finish_suffix(content, cursor, line_no, origin)
	return first


func _when_speaker_colon(content: String) -> int:
	var index := 0
	while index < content.length() and (content[index] == " " or content[index] == "\t"):
		index += 1
	if index >= content.length() or not _is_ident_start(content[index]):
		return -1
	var end := _ident_end(content, index)
	if content.substr(index, end - index) != "when":
		return -1
	index = end
	var depth := 0
	while index < content.length():
		if content.substr(index, 2) == "//":
			return -1
		var ch := content[index]
		if ch == "(" or ch == "[" or ch == "{":
			depth += 1
		elif ch == ")" or ch == "]" or ch == "}":
			depth = maxi(depth - 1, 0)
		elif ch == ":" and depth == 0:
			var after := _dotted_end(content, index + 1)
			if after >= 0:
				var cursor := after
				while cursor < content.length() and (content[cursor] == " " or content[cursor] == "\t"):
					cursor += 1
				if cursor < content.length() and content[cursor] == ":":
					return cursor
		index += 1
	return -1


func _dotted_end(content: String, start: int) -> int:
	var index := start
	while index < content.length() and (content[index] == " " or content[index] == "\t"):
		index += 1
	if index >= content.length() or not _is_ident_start(content[index]):
		return -1
	while true:
		index = _ident_end(content, index)
		if index < content.length() and content[index] == ".":
			if index + 1 < content.length() and _is_ident_start(content[index + 1]):
				index += 1
				continue
			return -1
		return index
	return -1


func _lex_code_line(content: String, line_no: int, origin: int, allow_await_host: bool = false) -> String:
	var first_ident := ""
	var index := 0
	while index < content.length():
		var ch := content[index]
		if ch == " " or ch == "\t":
			if ch == "\t":
				_error(WyrdDiagnostic.E_TAB_INDENT, "tab indentation is not allowed", line_no, origin + index)
			index += 1
			continue
		if ch == "/" and index + 1 < content.length() and content[index + 1] == "/":
			break
		if content.substr(index, 6) == "#line:":
			var tag_at := index
			index = _read_line_tag(content, index, line_no, origin)
			_finish_suffix(content, index, line_no, origin, tag_at)
			break
		if ch == "#":
			_error(WyrdDiagnostic.E_UNEXPECTED_TOKEN, "unexpected token \"#\"", line_no, origin + index)
			_emit_span(&"error", "#", line_no, origin, index, index + 1)
			index += 1
			continue
		if ch == "\"":
			index = _read_string(content, index, line_no, origin)
			continue
		if ch == "[":
			_emit_span(&"lbracket", "[", line_no, origin, index, index + 1)
			index = _read_prose(content, index + 1, line_no, origin, true)
			if index < content.length() and content[index] == "]":
				_emit_span(&"rbracket", "]", line_no, origin, index, index + 1)
				index += 1
			else:
				_error(WyrdDiagnostic.E_UNEXPECTED_TOKEN, "unexpected token \"[\"", line_no, origin + index)
			continue
		if ch == "$":
			if index + 1 < content.length() and _is_ident_start(content[index + 1]):
				var end := _ident_end(content, index + 1)
				_emit_span(&"ident", content.substr(index, end - index), line_no, origin, index, end)
				index = end
				continue
			_error(WyrdDiagnostic.E_UNEXPECTED_TOKEN, "unexpected token \"$\"", line_no, origin + index)
			_emit_span(&"error", "$", line_no, origin, index, index + 1)
			index += 1
			continue
		if _is_ident_start(ch):
			var end := _ident_end(content, index)
			var word := content.substr(index, end - index)
			var leading := first_ident.is_empty()
			if leading:
				first_ident = word
			_emit_span(&"ident", word, line_no, origin, index, end)
			_check_reserved(word, line_no, origin + index, leading and allow_await_host)
			index = end
			continue
		if _is_digit(ch):
			var end := index + 1
			while end < content.length() and _is_digit(content[end]):
				end += 1
			_emit_span(&"int", content.substr(index, end - index), line_no, origin, index, end)
			index = end
			continue
		if ch == "-" and index + 1 < content.length() and content[index + 1] == ">":
			_emit_span(&"arrow", "->", line_no, origin, index, index + 2)
			index += 2
			continue
		var mapped := _punct_kind(ch)
		if mapped != &"":
			_emit_span(mapped, ch, line_no, origin, index, index + 1)
			index += 1
			continue
		_error(WyrdDiagnostic.E_UNEXPECTED_TOKEN, "unexpected token \"%s\"" % ch, line_no, origin + index)
		_emit_span(&"error", ch, line_no, origin, index, index + 1)
		index += 1
	return first_ident


func _read_prose(content: String, start: int, line_no: int, origin: int, stop_at_bracket: bool) -> int:
	var index := start
	var buf := ""
	var buf_at := start
	while index < content.length():
		if content.substr(index, 2) == "//" or content.substr(index, 6) == "#line:":
			break
		if stop_at_bracket and content[index] == "]":
			break
		if content.substr(index, 2) == "{{":
			buf += "{"
			index += 2
			continue
		if content[index] == "{":
			_flush_prose(buf, line_no, origin, buf_at, index)
			buf = ""
			var raw_start := index + 1
			var cursor := raw_start
			# The first `}` closes the interpolation. The raw span is the text between.
			while cursor < content.length() and content[cursor] != "}" and content.substr(cursor, 2) != "//":
				cursor += 1
			var raw := content.substr(raw_start, cursor - raw_start)
			if cursor < content.length() and content[cursor] == "}":
				_emit_span(&"interp", raw, line_no, origin, index, cursor + 1)
				index = cursor + 1
			else:
				_error(WyrdDiagnostic.E_UNEXPECTED_TOKEN, "unexpected token \"{\"", line_no, origin + index)
				_emit_span(&"interp", raw, line_no, origin, index, cursor)
				index = cursor
			buf_at = index
			continue
		# A stray `}` is literal. `}}` is not an escape.
		buf += content[index]
		index += 1
	_flush_prose(buf, line_no, origin, buf_at, index)
	if not _tokens.is_empty() and _tokens[_tokens.size() - 1].kind == &"prose":
		_tokens[_tokens.size() - 1].text = _tokens[_tokens.size() - 1].text.rstrip(" \t")
		if _tokens[_tokens.size() - 1].text.is_empty():
			_tokens.remove_at(_tokens.size() - 1)
	return index


func _flush_prose(buf: String, line_no: int, origin: int, start: int, end: int) -> void:
	if buf.is_empty():
		return
	_emit_span(&"prose", buf, line_no, origin, start, end)


func _finish_suffix(content: String, index: int, line_no: int, origin: int, tag_at: int = -1) -> void:
	var cursor := index
	while cursor < content.length() and (content[cursor] == " " or content[cursor] == "\t"):
		if content[cursor] == "\t":
			_error(WyrdDiagnostic.E_TAB_INDENT, "tab indentation is not allowed", line_no, origin + cursor)
		cursor += 1
	if tag_at >= 0:
		if cursor < content.length() and content.substr(cursor, 2) != "//":
			_error(
				WyrdDiagnostic.E_LINE_TAG_POSITION,
				"line tag must be the last token on the line",
				line_no,
				origin + tag_at
			)
		return
	if cursor >= content.length() or content.substr(cursor, 2) == "//":
		return
	if content.substr(cursor, 6) == "#line:":
		var mark := cursor
		cursor = _read_line_tag(content, cursor, line_no, origin)
		_finish_suffix(content, cursor, line_no, origin, mark)
		return
	_error(WyrdDiagnostic.E_LINE_TAG_POSITION, "line tag must be the last token on the line", line_no, origin + cursor)


func _read_line_tag(content: String, index: int, line_no: int, origin: int) -> int:
	var cursor := index + 6
	var id_start := cursor
	while cursor < content.length() and _is_tag_char(content[cursor]):
		cursor += 1
	var ident := content.substr(id_start, cursor - id_start)
	var ended := cursor >= content.length() or content[cursor] == " " or content[cursor] == "\t" or content.substr(cursor, 2) == "//"
	if ident.is_empty() or not ended:
		_error(
			WyrdDiagnostic.E_LINE_TAG_FORMAT,
			"line tag id must match [A-Za-z0-9_]+",
			line_no,
			origin + index
		)
		while cursor < content.length() and content[cursor] != " " and content[cursor] != "\t" and content.substr(cursor, 2) != "//":
			cursor += 1
		ident = content.substr(id_start, cursor - id_start)
	_emit_span(&"line_tag", ident, line_no, origin, index, cursor)
	return cursor


func _read_string(content: String, index: int, line_no: int, origin: int) -> int:
	var cursor := index + 1
	var buf := ""
	while cursor < content.length():
		if content[cursor] == "\\":
			if cursor + 1 >= content.length():
				_error(WyrdDiagnostic.E_BAD_ESCAPE, "unknown string escape \"\\\\\"", line_no, origin + cursor)
				cursor += 1
				break
			var escaped := content[cursor + 1]
			if escaped == "\\" or escaped == "\"":
				buf += escaped
			else:
				_error(
					WyrdDiagnostic.E_BAD_ESCAPE,
					"unknown string escape \"\\%s\"" % escaped,
					line_no,
					origin + cursor
				)
				buf += escaped
			cursor += 2
			continue
		if content[cursor] == "\"":
			_emit_span(&"string", buf, line_no, origin, index, cursor + 1)
			return cursor + 1
		buf += content[cursor]
		cursor += 1
	_error(WyrdDiagnostic.E_UNTERMINATED_STRING, "unterminated string", line_no, origin + index)
	_emit_span(&"string", buf, line_no, origin, index, cursor)
	return cursor


func _check_reserved(word: String, line_no: int, col: int, statement_ok: bool = false) -> void:
	if statement_ok and word == "await_host":
		return
	if _RESERVED.has(word):
		_error(WyrdDiagnostic.E_RESERVED_WORD, "reserved word \"%s\"" % word, line_no, col)


func _emit_span(kind: StringName, text: String, line_no: int, origin: int, start: int, end: int) -> void:
	_emit(kind, text, line_no, origin + start, line_no, origin + end)


func _emit(kind: StringName, text: String, line_no: int, col: int, end_line: int, end_col: int) -> void:
	_tokens.append(WyrdToken.new(kind, text, line_no, col, end_line, end_col))


func _error(code: StringName, message: String, line_no: int, col: int) -> void:
	_diagnostics.add(code, message, _source.path, line_no, col)


func _end_line() -> int:
	return _source.line_at(_source.text.length())


func _end_col() -> int:
	return _source.column_at(_source.text.length())


func _ident_end(content: String, index: int) -> int:
	var cursor := index + 1
	while cursor < content.length() and _is_ident_cont(content[cursor]):
		cursor += 1
	return cursor


func _punct_kind(ch: String) -> StringName:
	match ch:
		".":
			return &"dot"
		":":
			return &"colon"
		"*":
			return &"star"
		"~":
			return &"tilde"
		"=":
			return &"eq"
		"(":
			return &"lparen"
		")":
			return &"rparen"
		"{":
			return &"lbrace"
		"}":
			return &"rbrace"
		",":
			return &"comma"
		">":
			return &"gt"
		"<":
			return &"lt"
		"+":
			return &"plus"
		"-":
			return &"minus"
		"/":
			return &"slash"
		"?":
			return &"question"
		"|":
			return &"pipe"
		_:
			return &""


func _is_ident_start(ch: String) -> bool:
	return (ch >= "A" and ch <= "Z") or (ch >= "a" and ch <= "z") or ch == "_"


func _is_ident_cont(ch: String) -> bool:
	return _is_ident_start(ch) or _is_digit(ch)


func _is_digit(ch: String) -> bool:
	return ch >= "0" and ch <= "9"


func _is_tag_char(ch: String) -> bool:
	return _is_ident_cont(ch)
