class_name WyrdFakeWorld
extends WyrdWorldAdapter

## Scripted world adapter. Missing entities answer as absent.

class EntityRecord extends RefCounted:
	var kind: StringName = &""
	var display_name: String = ""
	var tags: PackedStringArray = PackedStringArray()
	var alive: bool = false
	var attrs: Dictionary = {}


var _entities: Dictionary = {}


func add_entity(
	id: StringName,
	entity_kind: StringName,
	entity_name: String,
	entity_tags: PackedStringArray,
	alive: bool
) -> void:
	var record := EntityRecord.new()
	record.kind = entity_kind
	record.display_name = entity_name
	record.tags = entity_tags
	record.alive = alive
	_entities[id] = record


func set_attr(id: StringName, key: StringName, value: Variant) -> void:
	var record := _record(id)
	if record == null:
		push_error("WyrdFakeWorld.set_attr: unknown entity %s." % id)
		return
	record.attrs[key] = value


func exists(id: StringName) -> bool:
	return _entities.has(id)


func kind(id: StringName) -> StringName:
	var record := _record(id)
	if record == null:
		return &""
	return record.kind


func tags(id: StringName) -> PackedStringArray:
	var record := _record(id)
	if record == null:
		return PackedStringArray()
	return record.tags.duplicate()


func attr(id: StringName, key: StringName) -> Variant:
	var record := _record(id)
	if record == null or not record.attrs.has(key):
		return null
	return record.attrs[key]


func is_alive(id: StringName) -> bool:
	var record := _record(id)
	if record == null:
		return false
	return record.alive


func display_name(id: StringName) -> String:
	var record := _record(id)
	if record == null:
		return ""
	return record.display_name


func _record(id: StringName) -> EntityRecord:
	if not _entities.has(id):
		return null
	return _entities[id] as EntityRecord
