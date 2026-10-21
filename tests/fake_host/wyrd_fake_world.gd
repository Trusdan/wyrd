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
var _protected: Dictionary = {}
var _out_of_bounds: Dictionary = {}
## Called with the ids whose candidate facts may have changed. An empty list
## means anything may have changed. Not saved.
var changed: Callable = Callable()
var _bounds_pack: String = ""
var _bounds_id: String = ""
var _deny_exists: StringName = &""
## Pack string from the latest [method in_bounds] call. Tests read it.
## Assigning it reports a world change.
var bounds_pack: String:
	get:
		return _bounds_pack
	set(value):
		_bounds_pack = value
		_emit_change(PackedStringArray())
## Entity id from the latest [method in_bounds] call. Assigning it reports a world change.
var bounds_id: String:
	get:
		return _bounds_id
	set(value):
		_bounds_id = value
		_emit_change(PackedStringArray())
## When set, [method exists] is false for this id even though it stays a candidate.
## Assigning it reports the previous id and the new id.
var deny_exists: StringName:
	get:
		return _deny_exists
	set(value):
		var previous := _deny_exists
		var nxt := StringName(value)
		if previous == nxt:
			return
		_deny_exists = nxt
		var ids := PackedStringArray()
		if previous != &"":
			ids.append(String(previous))
		if nxt != &"":
			ids.append(String(nxt))
		_emit_change(ids)


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
	_emit_id(id)


func reports_changes() -> bool:
	return true


func set_attr(id: StringName, key: StringName, value: Variant) -> void:
	var record := _record(id)
	if record == null:
		push_error("WyrdFakeWorld.set_attr: unknown entity %s." % id)
		return
	record.attrs[key] = value
	_emit_id(id)


func exists(id: StringName) -> bool:
	if deny_exists != &"" and id == deny_exists:
		return false
	return _entities.has(id)


func set_protected(id: StringName, on: bool) -> void:
	_protected[id] = on
	_emit_id(id)


func set_out_of_bounds(id: StringName, on: bool) -> void:
	_out_of_bounds[id] = on
	_emit_id(id)


func is_protected(id: StringName) -> bool:
	return bool(_protected.get(id, false))


func in_bounds(id: StringName, pack: String) -> bool:
	_bounds_id = String(id)
	_bounds_pack = pack
	return not bool(_out_of_bounds.get(id, false))


func remove_entity(id: StringName) -> void:
	_entities.erase(id)
	_groups.erase(id)
	for faction in _members.keys():
		(_members[faction] as Dictionary).erase(id)
	_emit_id(id)


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
	_emit_change(PackedStringArray())


## Precedence order for [param agent]. [method members] is the other direction and sorts.
func set_groups(agent: StringName, groups: PackedStringArray) -> void:
	if agent == &"":
		push_error("WyrdFakeWorld.set_groups: missing agent")
		return
	var rows: Array = []
	for id in groups:
		rows.append(String(id))
	_groups[agent] = rows
	_emit_change(PackedStringArray())


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


func _emit_id(id: StringName) -> void:
	var ids := PackedStringArray()
	if id != &"":
		ids.append(String(id))
	_emit_change(ids)


func _emit_change(ids: PackedStringArray) -> void:
	if changed.is_valid():
		changed.call(ids)


func _record(id: StringName) -> EntityRecord:
	if not _entities.has(id):
		return null
	return _entities[id] as EntityRecord
