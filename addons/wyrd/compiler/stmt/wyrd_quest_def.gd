class_name WyrdQuestDef
extends WyrdStmtSpan

## One compiled quest.
##
## @experimental
## [member title] is a quoted title and is not interpolated.
## [member requires] is parsed only. Pack ids are not resolved until PR 5.
## [member on_empty] is the only quest-level slot-state default in this slice.

var id: String = ""
var title: String = ""
var slots: Array[WyrdSlotDef] = []
var on_empty: String = ""
var start_when: WyrdCompiledCondition = null
var start_text: String = ""
var requires: PackedStringArray = PackedStringArray()
var stages: Array[WyrdStageDef] = []
