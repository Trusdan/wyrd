class_name WyrdEntityFilter
extends RefCounted

## Filter for a spatial query.
##
## @experimental
## [member tag] and [member kind] are empty when that field is unconstrained.
## Precision flags (precise versus coarse) are not part of this S0 sketch.

var tag: StringName = &""
var kind: StringName = &""


func _init(tag_name: StringName = &"", kind_name: StringName = &"") -> void:
	tag = tag_name
	kind = kind_name
