class_name WyrdDiagnostic
extends RefCounted

## One compiler diagnostic.
##
## @experimental
## [member code] is a [StringName] such as [code]E_HEADER_MISSING[/code].
## Formatted lines look like [code]path:line:col: error[CODE]: message[/code].

const SEVERITY_ERROR: StringName = &"error"

const E_HEADER_MISSING: StringName = &"E_HEADER_MISSING"
const E_HEADER_INVALID: StringName = &"E_HEADER_INVALID"
const E_TAB_INDENT: StringName = &"E_TAB_INDENT"
const E_INDENT_WIDTH: StringName = &"E_INDENT_WIDTH"
const E_INDENT_JUMP: StringName = &"E_INDENT_JUMP"
const E_RESERVED_WORD: StringName = &"E_RESERVED_WORD"
const E_UNTERMINATED_STRING: StringName = &"E_UNTERMINATED_STRING"
const E_BAD_ESCAPE: StringName = &"E_BAD_ESCAPE"
const E_LINE_TAG_POSITION: StringName = &"E_LINE_TAG_POSITION"
const E_LINE_TAG_FORMAT: StringName = &"E_LINE_TAG_FORMAT"
const E_UNEXPECTED_TOKEN: StringName = &"E_UNEXPECTED_TOKEN"
const E_FACTS_SYNTAX: StringName = &"E_FACTS_SYNTAX"
const E_FACTS_DUPLICATE: StringName = &"E_FACTS_DUPLICATE"

var severity: StringName = SEVERITY_ERROR
var code: StringName = &""
var message: String = ""
var path: String = ""
var line: int = 1
var col: int = 1


func _init(
	diagnostic_severity: StringName = SEVERITY_ERROR,
	diagnostic_code: StringName = &"",
	diagnostic_message: String = "",
	diagnostic_path: String = "",
	diagnostic_line: int = 1,
	diagnostic_col: int = 1
) -> void:
	severity = diagnostic_severity
	code = diagnostic_code
	message = diagnostic_message
	path = diagnostic_path
	line = diagnostic_line
	col = diagnostic_col


func format_line() -> String:
	return "%s:%d:%d: %s[%s]: %s" % [path, line, col, severity, code, message]
