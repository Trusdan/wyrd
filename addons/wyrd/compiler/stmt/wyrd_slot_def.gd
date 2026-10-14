class_name WyrdSlotDef
extends WyrdStmtSpan

## One quest slot.
##
## @experimental
## [member mode] is [code]live[/code], [code]locked_at[/code], or [code]cast[/code].
## [member cast_when] is type-checked only. Casting arrives in M4.

var name: String = ""
var role: String = ""
var mode: StringName = &""
var locked_stage: String = ""
var cast_when: WyrdCompiledCondition = null
var cast_text: String = ""
