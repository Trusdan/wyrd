class_name WyrdSceneItem
extends WyrdStmtSpan

## One ordered scene step: a line, choice, divert, or label.
##
## @experimental
## [member kind] is [code]line[/code], [code]choice[/code], [code]divert[/code], or [code]label[/code].
## [member divert_kind] is [code]label[/code], [code]end[/code], or [code]scene[/code].

var kind: StringName = &""
var line_def: WyrdLineDef = null
var choice: WyrdChoiceDef = null
var divert_kind: StringName = &""
var target: String = ""
var label: String = ""
