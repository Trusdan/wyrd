class_name WyrdLoadReport
extends RefCounted

## Result of loading a content manifest. Named in the save/load design.
##
## @experimental
## [member ok] is false when the compiler reported any error. Warnings stay in
## [member diagnostics] and do not refuse the load. [member manifest_hash] is 0
## when the load was refused.

var ok: bool = false
var diagnostics: WyrdDiagnostics
var manifest_hash: int = 0


func _init() -> void:
	diagnostics = WyrdDiagnostics.new()


func error_count() -> int:
	var count := 0
	if diagnostics == null:
		return 0
	for item in diagnostics.items:
		if item.severity == WyrdDiagnostic.SEVERITY_ERROR:
			count += 1
	return count
