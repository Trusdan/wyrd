class_name WyrdVariantDef
extends WyrdStmtSpan

## One slot-state variant inside a stage.
##
## @experimental
## [member body] holds the same statements as a stage.
## [member redirects] is parsed only. Resolving a redirect arrives in M4.
## [member condition] is set for [code]unwilling[/code] and [code]barred[/code].

var slot: String = ""
var state: StringName = &""
var condition: WyrdCompiledCondition = null
var condition_text: String = ""
var body: WyrdStageDef = null
var redirects: Array = []
