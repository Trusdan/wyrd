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
var _members: Dictionary = {}
var _groups: Dictionary = {}


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


func remove_entity(id: StringName) -> void:
	_entities.erase(id)
	_groups.erase(id)
	for faction in _members.keys():
		(_members[faction] as Dictionary).erase(id)


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


func add_member(faction: StringName, entity: StringName) -> void:
	if faction == &"" or entity == &"":
		push_error("WyrdFakeWorld.add_member: missing faction or entity")
		return
	if not _members.has(faction):
		_members[faction] = {}
	(_members[faction] as Dictionary)[entity] = true


## Precedence order for [param agent]. [method members] is the other direction and sorts.
func set_groups(agent: StringName, groups: PackedStringArray) -> void:
	if agent == &"":
		push_error("WyrdFakeWorld.set_groups: missing agent")
		return
	var rows: Array = []
	for id in groups:
		rows.append(String(id))
	_groups[agent] = rows


func groups_of(agent: StringName) -> PackedStringArray:
	var rows := PackedStringArray()
	if not _groups.has(agent):
		return rows
	for id in _groups[agent]:
		rows.append(String(id))
	return rows


func members(faction: StringName) -> PackedStringArray:
	var rows := PackedStringArray()
	if not _members.has(faction):
		return rows
	for id in (_members[faction] as Dictionary).keys():
		rows.append(String(id))
	rows.sort()
	return rows


func candidates(filter: WyrdEntityFilter) -> PackedStringArray:
	var rows := PackedStringArray()
	for id in _entities.keys():
		var record := _entities[id] as EntityRecord
		if record == null:
			continue
		if filter != null and filter.kind != &"" and record.kind != filter.kind:
			continue
		if filter != null and filter.tag != &"" and not record.tags.has(String(filter.tag)):
			continue
		rows.append(String(id))
	rows.sort()
	return rows


func _record(id: StringName) -> EntityRecord:
	if not _entities.has(id):
		return null
	return _entities[id] as EntityRecord
