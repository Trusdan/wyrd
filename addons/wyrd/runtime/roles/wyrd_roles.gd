class_name WyrdRoles
extends RefCounted

## Slot and role holders until the role runner exists.
##
## @experimental
## [method assign] records the default holder a test or host set up.
## [method holder] resolves a slot name through the loaded quest, then the
## role. Succession, secrecy, and slot state are later. [method clear] drops
## holders on a new game and keeps the slot map from the loaded content.

var _slots: Dictionary = {}
var _holders: Dictionary = {}


func bind_content(content: WyrdContent) -> void:
	_slots.clear()
	if content == null:
		return
	for quest_id in content.quests.keys():
		var quest: WyrdQuestDef = content.quests[quest_id]
		for slot in quest.slots:
			_slots[StringName(slot.name)] = StringName(slot.role)


func assign(role: StringName, entity: StringName) -> void:
	_holders[role] = entity


func holder(slot_or_role: StringName) -> StringName:
	var role := slot_or_role
	if _slots.has(slot_or_role):
		role = _slots[slot_or_role] as StringName
	if _holders.has(role):
		return _holders[role] as StringName
	return &""


func clear() -> void:
	_holders.clear()
