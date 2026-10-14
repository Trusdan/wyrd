class_name WyrdFakeInventory
extends WyrdInventoryAdapter

## Scripted inventory. Unset questions return an empty answer.

var _counts: Dictionary = {}
var _items: Dictionary = {}
var _owners: Dictionary = {}


func set_count(holder: StringName, item_or_tag: StringName, amount: int) -> void:
	_counts[_pair(holder, item_or_tag)] = amount


func set_items(holder: StringName, filter: StringName, item_ids: PackedStringArray) -> void:
	_items[_pair(holder, filter)] = item_ids


func set_owner(item: StringName, owner: StringName) -> void:
	_owners[item] = owner


func count(holder: StringName, item_or_tag: StringName) -> int:
	var key := _pair(holder, item_or_tag)
	if not _counts.has(key):
		return 0
	return _counts[key] as int


func items(holder: StringName, filter: StringName) -> PackedStringArray:
	var key := _pair(holder, filter)
	if not _items.has(key):
		return PackedStringArray()
	return (_items[key] as PackedStringArray).duplicate()


func owner_of(item: StringName) -> StringName:
	if not _owners.has(item):
		return &""
	return _owners[item] as StringName


static func _pair(a: StringName, b: StringName) -> String:
	return "%s\t%s" % [String(a), String(b)]
