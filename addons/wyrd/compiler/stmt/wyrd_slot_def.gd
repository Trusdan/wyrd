class_name WyrdSlotDef
extends WyrdStmtSpan

## One quest slot.
##
## @experimental
## [member mode] is [code]live[/code], [code]locked_at[/code], or [code]cast[/code].
## [member cast_when] filters [method WyrdWorldAdapter.candidates] at quest start.
## [code]candidate[/code] is the entity under test.

var name: String = ""
var role: String = ""
var mode: StringName = &""
var locked_stage: String = ""
var cast_when: WyrdCompiledCondition = null
var cast_text: String = ""
