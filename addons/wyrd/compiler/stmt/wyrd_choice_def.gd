class_name WyrdChoiceDef
extends WyrdStmtSpan

## One scene choice.
##
## @experimental
## [member disabled_when] and [member disabled_reason] are parsed only.
## The reason is a quoted string and is not interpolated.
## [member tags] holds names from [code]#tag:[/code]. [code]voiced[/code] is the
## recording tag.

var line_id: String = ""
var label: WyrdExprNode = null
var condition: WyrdCompiledCondition = null
var condition_text: String = ""
var target: String = ""
var effects: Array[WyrdEffectDef] = []
var disabled_when: String = ""
var disabled_reason: String = ""
var tags: PackedStringArray = PackedStringArray()
var scene_id: String = ""
