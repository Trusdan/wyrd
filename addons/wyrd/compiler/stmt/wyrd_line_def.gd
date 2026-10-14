class_name WyrdLineDef
extends WyrdStmtSpan

## One spoken line or journal entry.
##
## @experimental
## [member kind] is [code]spoken[/code] or [code]journal[/code].
## [member tags] is reserved for the later voiced lint. This slice stores none.
## [member scene_id] is empty on a journal entry. The linker binds slot speakers.

var line_id: String = ""
var speaker: String = ""
var kind: StringName = &"spoken"
var prose: WyrdExprNode = null
var condition: WyrdCompiledCondition = null
var condition_text: String = ""
var tags: PackedStringArray = PackedStringArray()
var scene_id: String = ""
