class_name WyrdInventoryAdapter
extends RefCounted

## Host view of carried items.
##
## @experimental
## [param filter] on [method items] is a tag. An empty tag asks for every item that holder carries.
## [method count] takes either an item id or a tag. Default bodies are not implemented.

func count(holder: StringName, item_or_tag: StringName) -> int:
	push_error("not implemented: WyrdInventoryAdapter.count(%s, %s)" % [holder, item_or_tag])
	return 0


func items(holder: StringName, filter: StringName) -> PackedStringArray:
	push_error("not implemented: WyrdInventoryAdapter.items(%s, %s)" % [holder, filter])
	return PackedStringArray()


func owner_of(item: StringName) -> StringName:
	push_error("not implemented: WyrdInventoryAdapter.owner_of(%s)" % item)
	return &""
