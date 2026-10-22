class_name WyrdAIResult
extends RefCounted

## One AI answer. This release discards it after [method WyrdAI.deliver].
##
## @experimental

var ok: bool = false
var text: String = ""
var error: String = ""
