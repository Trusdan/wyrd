class_name WyrdRoles
extends RefCounted

## Role bindings and the quest-slot subset.
##
## @experimental
## A binding holds [code]holder[/code], [code]since[/code], [code]status[/code]
## ([code]default[/code], [code]successor[/code], [code]empty[/code]), and
## [code]history[/code]. [method assign] is host setup for the default holder.
## [method vacate] runs [code]relation(...)[/code] or [code]none[/code].
## [code]live[/code] follows the role. [code]locked_at[/code] freezes in
## [method enter_stage]. [code]cast[/code] freezes in [method begin_quest] to
## the current holder; casting proper is M4. Slot state [code]hostile[/code]
## means disposition toward [code]player[/code] is below the threshold.
## A secret holder's key [code]role.<id>.holder[/code] is in [code]known/[/code]
## only for agents passed to [method tell].

signal role_holder_changed(role_id: StringName, old_holder: StringName, new_holder: StringName)
signal role_vacant(role_id: StringName)

const PLAYER: StringName = &"player"
const EMPTY: StringName = &"empty"
const DEFAULT: StringName = &"default"
const SUCCESSOR: StringName = &"successor"
const HOSTILE: StringName = &"hostile"

var social: WyrdSocial
var deeds: WyrdDeedLog
var facts: WyrdFactStore
var clock: Callable = Callable()
var config_of: Callable = Callable()
var content_of: Callable = Callable()
var world_of: Callable = Callable()

var _slots: Dictionary = {}
var _bindings: Dictionary = {}
var _defs: Dictionary = {}
var _frozen: Dictionary = {}
var _told: Dictionary = {}
var _cast_noted: Dictionary = {}


func bind_content(content: WyrdContent) -> void:
	_slots.clear()
	_frozen.clear()
	if content == null:
		return
	var ids: Array = content.quests.keys()
	ids.sort()
	for quest_id in ids:
		var quest: WyrdQuestDef = content.quests[quest_id]
		for slot in quest.slots:
			var name := String(slot.name)
			if not _slots.has(name):
				_slots[name] = []
			(_slots[name] as Array).append({
				"mode": slot.mode,
				"quest": String(quest_id),
				"role": StringName(slot.role),
				"stage": slot.locked_stage,
			})


func clear() -> void:
	_bindings.clear()
	_frozen.clear()
	_told.clear()
	_cast_noted.clear()


func export_state() -> Dictionary:
	var bindings := {}
	var roles: Array = _bindings.keys()
	roles.sort()
	for role in roles:
		var row: Dictionary = _bindings[role]
		var history: Array = []
		for item in row["history"]:
			var prior: Dictionary = item
			history.append({
				"holder": String(prior.get("holder", "")),
				"reason": String(prior.get("reason", "")),
				"since": int(prior.get("since", 0)),
				"status": String(prior.get("status", "")),
				"until": int(prior.get("until", 0)),
			})
		bindings[String(role)] = {
			"history": history,
			"holder": String(row.get("holder", "")),
			"since": int(row.get("since", 0)),
			"status": String(row.get("status", "")),
		}
	var defs := {}
	var defined: Array = _defs.keys()
	defined.sort()
	for role in defined:
		var spec: Dictionary = _defs[role]
		var kinds: Array = []
		for kind in spec["kinds"]:
			kinds.append(String(kind))
		defs[String(role)] = {
			"kinds": kinds,
			"secret": bool(spec["secret"]),
			"strategy": String(spec["strategy"]),
			"threshold": int(spec["threshold"]),
		}
	var frozen := {}
	var locks: Array = _frozen.keys()
	locks.sort()
	for lock in locks:
		var parts := String(lock).split("\t")
		if parts.size() != 2:
			continue
		if not frozen.has(parts[0]):
			frozen[parts[0]] = {}
		var snap: Dictionary = _frozen[lock]
		(frozen[parts[0]] as Dictionary)[parts[1]] = {
			"holder": String(snap.get("holder", "")),
			"status": String(snap.get("status", "")),
		}
	var told := {}
	var secret_roles: Array = _told.keys()
	secret_roles.sort()
	for role in secret_roles:
		var agents: Array = (_told[role] as Dictionary).keys()
		agents.sort()
		var names: Array = []
		for agent in agents:
			names.append(String(agent))
		told[String(role)] = names
	return {"bindings": bindings, "defs": defs, "frozen": frozen, "told": told}


func import_state(data: Dictionary) -> void:
	_bindings.clear()
	_defs.clear()
	_frozen.clear()
	_told.clear()
	_cast_noted.clear()
	var bindings: Dictionary = data.get("bindings", {})
	for role in bindings.keys():
		var row: Dictionary = bindings[role]
		var history: Array = []
		for item in row.get("history", []):
			if not (item is Dictionary):
				continue
			var prior: Dictionary = item
			history.append({
				"holder": StringName(str(prior.get("holder", ""))),
				"reason": StringName(str(prior.get("reason", ""))),
				"since": int(prior.get("since", 0)),
				"status": StringName(str(prior.get("status", ""))),
				"until": int(prior.get("until", 0)),
			})
		_bindings[StringName(str(role))] = {
			"history": history,
			"holder": StringName(str(row.get("holder", ""))),
			"since": int(row.get("since", 0)),
			"status": StringName(str(row.get("status", "empty"))),
		}
	var defs: Dictionary = data.get("defs", {})
	for role in defs.keys():
		var spec: Dictionary = defs[role]
		var kinds := PackedStringArray()
		for kind in spec.get("kinds", []):
			kinds.append(String(kind))
		_defs[StringName(str(role))] = {
			"kinds": kinds,
			"secret": bool(spec.get("secret", false)),
			"strategy": StringName(str(spec.get("strategy", "none"))),
			"threshold": int(spec.get("threshold", -1)),
		}
	var frozen: Dictionary = data.get("frozen", {})
	for quest_id in frozen.keys():
		var slots: Dictionary = frozen[quest_id]
		for slot_name in slots.keys():
			var snap: Dictionary = slots[slot_name]
			_frozen[_freeze_key(String(quest_id), String(slot_name))] = {
				"holder": StringName(str(snap.get("holder", ""))),
				"status": StringName(str(snap.get("status", ""))),
			}
	var told: Dictionary = data.get("told", {})
	for role in told.keys():
		var bag := {}
		for agent in told[role]:
			bag[StringName(str(agent))] = true
		_told[StringName(str(role))] = bag


func define(role: StringName, succession: String = "none", secret: bool = false, hostile_threshold: int = -1) -> void:
	var text := succession.strip_edges()
	var strategy := &"none"
	var kinds := PackedStringArray()
	if text.is_empty() or text == "none":
		strategy = &"none"
	elif text.begins_with("relation(") and text.ends_with(")"):
		strategy = &"relation"
		var inner := text.substr("relation(".length(), text.length() - "relation(".length() - 1)
		for part in inner.split("|"):
			var kind := part.strip_edges()
			if not kind.is_empty():
				kinds.append(kind)
		if kinds.is_empty():
			push_error("WyrdRoles.define: relation needs a kind")
			return
	else:
		push_error("WyrdRoles.define: succession \"%s\" is not relation(...) or none" % text)
		return
	_defs[role] = {
		"kinds": kinds,
		"secret": secret,
		"strategy": strategy,
		"threshold": hostile_threshold,
	}


func assign(role: StringName, entity: StringName) -> void:
	if role == &"" or entity == &"":
		push_error("WyrdRoles.assign: missing role or entity")
		return
	var prior := _binding(role)
	var old: StringName = prior["holder"]
	if old == entity and prior["status"] != EMPTY:
		return
	if old != &"":
		_push_history(prior, &"assign")
	prior["holder"] = entity
	prior["since"] = _now()
	prior["status"] = DEFAULT
	_bindings[role] = prior
	_refresh_told(role)
	if old != entity:
		role_holder_changed.emit(role, old, entity)


func vacate(role: StringName, reason: StringName) -> void:
	var prior := _binding(role)
	var old: StringName = prior["holder"]
	if old == &"":
		return
	_push_history(prior, reason)
	var next := _successor(role, old)
	if next == &"":
		prior["holder"] = &""
		prior["since"] = _now()
		prior["status"] = EMPTY
		_bindings[role] = prior
		_refresh_told(role)
		role_vacant.emit(role)
		return
	prior["holder"] = next
	prior["since"] = _now()
	prior["status"] = SUCCESSOR
	_bindings[role] = prior
	_refresh_told(role)
	role_holder_changed.emit(role, old, next)
	if deeds != null:
		deeds.record(&"role_changed", old, next, &"", PackedStringArray(), 1.0, null, &"public", false)


func tell(role: StringName, agent: StringName) -> void:
	if role == &"" or agent == &"":
		push_error("WyrdRoles.tell: missing role or agent")
		return
	if not _told.has(role):
		_told[role] = {}
	(_told[role] as Dictionary)[agent] = true
	_write_known(role, agent)


func holder(slot_or_role: StringName) -> StringName:
	var name := String(slot_or_role)
	if _slots.has(name):
		return _resolved(_primary(name), name)["holder"]
	return _binding(slot_or_role)["holder"]


func slot_holder(quest_id: String, slot_name: StringName) -> StringName:
	return _resolved(quest_id, String(slot_name))["holder"]


func slot_state(slot_name: StringName, quest_id: String = "") -> StringName:
	var quest := quest_id if not quest_id.is_empty() else _primary(String(slot_name))
	var resolved: Dictionary = _resolved(quest, String(slot_name))
	var who: StringName = resolved["holder"]
	var status: StringName = resolved["status"]
	if who == &"" or status == EMPTY:
		return EMPTY
	if _hostile(resolved["role"], who):
		return HOSTILE
	if status == SUCCESSOR:
		return SUCCESSOR
	return DEFAULT


func binding_status(role: StringName) -> StringName:
	return _binding(role)["status"]


func binding_since(role: StringName) -> int:
	return int(_binding(role)["since"])


func history(role: StringName) -> Array:
	return (_binding(role)["history"] as Array).duplicate(true)


func revealed(agent: StringName, key: StringName) -> bool:
	var role := _role_of_key(key)
	if role == &"":
		return false
	if bool(_spec(role)["secret"]):
		return _is_told(role, agent)
	return _binding(role)["holder"] != &""


func begin_quest(quest_id: String) -> void:
	var quest := _quest(quest_id)
	if quest == null:
		return
	for slot in quest.slots:
		if slot.mode != &"cast":
			continue
		var key := _freeze_key(quest_id, slot.name)
		if _frozen.has(key):
			continue
		var live := _binding(StringName(slot.role))
		_frozen[key] = {"holder": live["holder"], "status": live["status"]}
		if _cast_noted.has(slot.name):
			continue
		_cast_noted[slot.name] = true
		push_warning("cast slot \"%s\" binds once to the current holder; casting is M4" % slot.name)


func enter_stage(quest_id: String, stage_id: String) -> void:
	var quest := _quest(quest_id)
	if quest == null:
		return
	for slot in quest.slots:
		if slot.mode != &"locked_at" or slot.locked_stage != stage_id:
			continue
		var key := _freeze_key(quest_id, slot.name)
		if _frozen.has(key):
			continue
		var live := _binding(StringName(slot.role))
		_frozen[key] = {"holder": live["holder"], "status": live["status"]}


func _resolved(quest_id: String, slot_name: String) -> Dictionary:
	var row := _slot_row(quest_id, slot_name)
	var role: StringName = row.get("role", StringName(slot_name))
	var key := _freeze_key(quest_id, slot_name)
	if quest_id != "" and _frozen.has(key):
		var snap: Dictionary = _frozen[key]
		return {"holder": snap["holder"], "role": role, "status": snap["status"]}
	var live := _binding(role)
	return {"holder": live["holder"], "role": role, "status": live["status"]}


func _successor(role: StringName, old: StringName) -> StringName:
	var spec := _spec(role)
	if spec["strategy"] != &"relation" or social == null:
		return &""
	var kinds: PackedStringArray = spec["kinds"]
	for kind in kinds:
		for candidate in social.targets(old, StringName(kind)):
			var id := StringName(candidate)
			if id == old or id == &"":
				continue
			if _alive(id):
				return id
	return &""


func _hostile(role: StringName, who: StringName) -> bool:
	if social == null or who == &"":
		return false
	return social.disposition(who, PLAYER) < _threshold(role)


func _threshold(role: StringName) -> int:
	var over := int(_spec(role)["threshold"])
	if over >= 0:
		return over
	var cfg := _config()
	if cfg == null:
		return 20
	return cfg.hostile_threshold


func _alive(id: StringName) -> bool:
	var world := _world()
	if world == null:
		return true
	return world.is_alive(id)


func _binding(role: StringName) -> Dictionary:
	if not _bindings.has(role):
		return {"history": [], "holder": &"", "since": 0, "status": EMPTY}
	return _bindings[role]


func _push_history(prior: Dictionary, reason: StringName) -> void:
	(prior["history"] as Array).append({
		"holder": prior["holder"],
		"reason": reason,
		"since": int(prior["since"]),
		"status": prior["status"],
		"until": _now(),
	})


func _spec(role: StringName) -> Dictionary:
	if _defs.has(role):
		return _defs[role]
	return {"kinds": PackedStringArray(), "secret": false, "strategy": &"none", "threshold": -1}


func _is_told(role: StringName, agent: StringName) -> bool:
	if not _told.has(role):
		return false
	return (_told[role] as Dictionary).has(agent)


func _refresh_told(role: StringName) -> void:
	if not _told.has(role) or facts == null:
		return
	for agent in (_told[role] as Dictionary).keys():
		_write_known(role, StringName(str(agent)))


func _write_known(role: StringName, agent: StringName) -> void:
	if facts == null:
		return
	facts.remember(
		_known_key(role),
		_binding(role)["holder"],
		StringName("known/%s" % String(agent))
	)


func _known_key(role: StringName) -> StringName:
	return StringName("role.%s.holder" % String(role))


func _role_of_key(key: StringName) -> StringName:
	var text := String(key)
	if not text.begins_with("role.") or not text.ends_with(".holder"):
		return &""
	var inner := text.substr(5, text.length() - 12)
	if inner.is_empty():
		return &""
	return StringName(inner)


func _primary(slot_name: String) -> String:
	if not _slots.has(slot_name):
		return ""
	var rows: Array = _slots[slot_name]
	if rows.is_empty():
		return ""
	return str((rows[0] as Dictionary)["quest"])


func _slot_row(quest_id: String, slot_name: String) -> Dictionary:
	if not _slots.has(slot_name):
		return {}
	for item in _slots[slot_name]:
		var row: Dictionary = item
		if str(row["quest"]) == quest_id:
			return row
	return {}


func _freeze_key(quest_id: String, slot_name: String) -> String:
	return "%s\t%s" % [quest_id, slot_name]


func _quest(quest_id: String) -> WyrdQuestDef:
	if not content_of.is_valid():
		return null
	var content: Variant = content_of.call()
	if content == null or not (content is WyrdContent):
		return null
	var pack := content as WyrdContent
	if not pack.quests.has(quest_id):
		return null
	return pack.quests[quest_id] as WyrdQuestDef


func _now() -> int:
	if clock.is_valid():
		return int(clock.call())
	return 0


func _config() -> WyrdConfig:
	if not config_of.is_valid():
		return null
	var cfg: Variant = config_of.call()
	if cfg is WyrdConfig:
		return cfg as WyrdConfig
	return null


func _world() -> WyrdWorldAdapter:
	if not world_of.is_valid():
		return null
	var found: Variant = world_of.call()
	if found is WyrdWorldAdapter:
		return found as WyrdWorldAdapter
	return null
