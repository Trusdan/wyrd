class_name WyrdWorldAdapter
extends RefCounted

## Host view of entities. Wyrd does not walk the scene tree.
##
## @experimental
## Default bodies report that they are not implemented. A host, or the fake host, overrides them.

func exists(id: StringName) -> bool:
	push_error("not implemented: WyrdWorldAdapter.exists(%s)" % id)
	return false


func kind(id: StringName) -> StringName:
	push_error("not implemented: WyrdWorldAdapter.kind(%s)" % id)
	return &""


func tags(id: StringName) -> PackedStringArray:
	push_error("not implemented: WyrdWorldAdapter.tags(%s)" % id)
	return PackedStringArray()


func attr(id: StringName, key: StringName) -> Variant:
	push_error("not implemented: WyrdWorldAdapter.attr(%s, %s)" % [id, key])
	return null


func is_alive(id: StringName) -> bool:
	push_error("not implemented: WyrdWorldAdapter.is_alive(%s)" % id)
	return false


func display_name(id: StringName) -> String:
	push_error("not implemented: WyrdWorldAdapter.display_name(%s)" % id)
	return ""


## Entity ids that belong to [param faction]. Order is not significant.
func members(faction: StringName) -> PackedStringArray:
	push_error("not implemented: WyrdWorldAdapter.members(%s)" % faction)
	return PackedStringArray()


## Entity ids that match [param filter]. An empty kind and tag means every entity
## the host is willing to offer. Order is not significant. Object and item
## casting is not a separate path.
func candidates(filter: WyrdEntityFilter) -> PackedStringArray:
	var kind := ""
	var tag := ""
	if filter != null:
		kind = String(filter.kind)
		tag = String(filter.tag)
	push_error("not implemented: WyrdWorldAdapter.candidates(%s, %s)" % [kind, tag])
	return PackedStringArray()
