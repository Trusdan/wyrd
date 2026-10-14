class_name WyrdDiagnostics
extends RefCounted

## Collects compiler diagnostics in source order.
##
## @experimental

var items: Array[WyrdDiagnostic] = []


func add(
	code: StringName,
	message: String,
	source_path: String,
	line: int,
	col: int,
	severity: StringName = WyrdDiagnostic.SEVERITY_ERROR
) -> void:
	items.append(WyrdDiagnostic.new(severity, code, message, source_path, maxi(line, 1), maxi(col, 1)))


func has_errors() -> bool:
	for item in items:
		if item.severity == WyrdDiagnostic.SEVERITY_ERROR:
			return true
	return false


func format() -> String:
	if items.is_empty():
		return ""
	var lines: PackedStringArray = PackedStringArray()
	for item in items:
		lines.append(item.format_line())
	return "\n".join(lines) + "\n"
