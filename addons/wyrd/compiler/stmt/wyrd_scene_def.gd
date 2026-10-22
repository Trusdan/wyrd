class_name WyrdSceneDef
extends WyrdStmtSpan

## One compiled scene.
##
## @experimental
## [member on_abort] runs if the scene aborts. [member items] keeps source order.

var id: String = ""
var on_abort: Array[WyrdEffectDef] = []
var items: Array[WyrdSceneItem] = []
## Fact keys for the AI packet, in source order. Empty when the source lists none.
var ai_context: PackedStringArray = PackedStringArray()
