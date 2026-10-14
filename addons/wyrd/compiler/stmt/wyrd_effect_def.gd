class_name WyrdEffectDef
extends WyrdStmtSpan

## One slice effect. Plain data, with type-checked expressions.
##
## @experimental
## [member kind] is [code]set[/code], [code]inc[/code], [code]record_deed[/code],
## [code]unlock_topic[/code], [code]do[/code], or [code]outcome[/code].
## [member args] holds named deed or command arguments.
## Command names are checked against [code]WyrdCommandSchema[/code] when the linker has one.

var kind: StringName = &""
var fact_key: String = ""
var target: WyrdCompiledCondition = null
var target_text: String = ""
var value: WyrdCompiledCondition = null
var value_text: String = ""
var verb: String = ""
var command: String = ""
var topic: String = ""
var branch: String = ""
var outcome: String = ""
var on_fail: String = ""
var args: Array = []
