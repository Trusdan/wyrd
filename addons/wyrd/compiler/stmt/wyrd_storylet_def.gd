class_name WyrdStoryletDef
extends WyrdStmtSpan

## One compiled storylet. Ranking is a later slice.
##
## @experimental
## [member generic] is true when [code]when[/code] was omitted.
## [member specificity] counts top-level [code]and[/code] clauses.
## [member body_kind] is [code]line[/code], [code]set[/code], or [code]scene[/code].
## [member cooldown_minutes] is stored and not enforced here.
## [member priority] is stored and does not change [member specificity].

var id: String = ""
var scope_kind: StringName = &""
var scope_id: String = ""
var speaker: String = ""
var when_text: String = ""
var condition: WyrdCompiledCondition = null
var specificity: int = 0
var generic: bool = true
var priority: int = 0
var weight: int = 1
var cooldown_minutes: int = 0
var body_kind: StringName = &""
var lines: Array[WyrdLineDef] = []
var scene_id: String = ""


func scope_text() -> String:
	if scope_kind == &"bark":
		return "bark"
	if scope_kind == &"":
		return ""
	return "%s %s" % [String(scope_kind), scope_id]
