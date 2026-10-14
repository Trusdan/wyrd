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
