class_name WyrdFactStore
extends RefCounted

## Stored facts, resolver cache, and perspectives.
##
## @experimental
## World values are [method Object.set] and [method Object.get], implemented
## here as [method _set] and [method _get]. Godot already owns those names, so
## a perspective argument cannot be added and [code]set[/code] cannot return a
## bool. [method set_in] and [method get_in] take [code]world[/code],
## [code]known/<agent>[/code], [code]believed/<agent>[/code], or
## [code]held/<group>[/code]. Only schema-declared stored facts can be believed
## or held. A missing fact reads as null. Conditions treat that as false.
##
## [signal fact_changed] fires only for prefixes passed to [method subscribe].
## Callables on this object are the runtime's hooks. They are not saved.

signal fact_changed(key: StringName, old_value: Variant, new_value: Variant)

var on_keys: Callable = Callable()
var tracer: Callable = Callable()
## Called after a [code]believed/[/code] or [code]held/[/code] value changes.
## [code]op[/code] is [code]believe[/code], [code]unbelieve[/code], [code]declare[/code], or [code]retract[/code].
var on_belief: Callable = Callable()
var on_resolved: Callable = Callable()
var clock: Callable = Callable()
var resolver_of: Callable = Callable()

var _schema: WyrdFactSchema
var _world: Dictionary = {}
var _known: Dictionary = {}
var _believed: Dictionary = {}
var _held: Dictionary = {}
var _cache: Dictionary = {}
var _last: Dictionary = {}
var _reasons: Dictionary = {}
var _subs: PackedStringArray = PackedStringArray()
var _once: Dictionary = {}
var _quiet: bool = false


func bind_schema(schema: WyrdFactSchema) -> void:
	_schema = schema
	clear_values()


func export_state() -> Dictionary:
	return {
		"believed": _export_layers(_believed),
		"held": _export_layers(_held),
		"known": _export_layers(_known),
		"world": _export_bag(_world),
	}


func import_state(data: Dictionary) -> void:
	clear_values()
	_quiet = true
	var world: Dictionary = data.get("world", {})
	var world_keys: Array = world.keys()
	world_keys.sort()
	for key in world_keys:
		set_in(StringName(str(key)), _saved_value(String(key), world[key]))
	var known: Dictionary = data.get("known", {})
	var agents: Array = known.keys()
	agents.sort()
	for agent in agents:
		var bag: Variant = known[agent]
		if not (bag is Dictionary):
			continue
		var perspective := StringName("known/%s" % String(agent))
		var keys: Array = (bag as Dictionary).keys()
		keys.sort()
		for key in keys:
			var text := String(key)
			var value: Variant = _saved_value(text, (bag as Dictionary)[key])
			if _find(text) == null:
				remember(StringName(text), value, perspective)
			else:
				set_in(StringName(text), value, perspective)
	_import_beliefs(data.get("believed", {}), "believed")
	_import_beliefs(data.get("held", {}), "held")
	_quiet = false


func _import_beliefs(raw: Variant, layer: String) -> void:
	if not (raw is Dictionary):
		return
	var owners: Array = (raw as Dictionary).keys()
	owners.sort()
	for owner in owners:
		var bag: Variant = (raw as Dictionary)[owner]
		if not (bag is Dictionary):
			continue
		var perspective := StringName("%s/%s" % [layer, String(owner)])
		var keys: Array = (bag as Dictionary).keys()
		keys.sort()
		for key in keys:
			var text := String(key)
			set_in(StringName(text), _saved_value(text, (bag as Dictionary)[key]), perspective)


func _export_layers(layers: Dictionary) -> Dictionary:
	var out := {}
	var owners: Array = layers.keys()
	owners.sort()
	for owner in owners:
		var bag: Dictionary = layers[owner]
		if bag.is_empty():
			continue
		out[String(owner)] = _export_bag(bag)
	return out


func _export_bag(bag: Dictionary) -> Dictionary:
	var out := {}
	var keys: Array = bag.keys()
	keys.sort()
	for key in keys:
		out[String(key)] = _plain_fact(bag[key])
	return out


func _plain_fact(value: Variant) -> Variant:
	if value is StringName:
		return String(value)
	return value


func _saved_value(key: String, value: Variant) -> Variant:
	var fact := _find(key)
	if fact == null:
		return value if not (value is String) else value
	if fact.type_name == &"int" and typeof(value) == TYPE_FLOAT:
		return int(value)
	if fact.type_name == &"float" and typeof(value) == TYPE_INT:
		return float(value)
	if fact.type_name == &"symbol":
		return StringName(str(value))
	return value


func clear_values() -> void:
	_world.clear()
	_known.clear()
	_believed.clear()
	_held.clear()
	_cache.clear()
	_last.clear()
	_reasons.clear()


func subscribe(prefix: StringName) -> void:
	var text := String(prefix)
	if not _subs.has(text):
		_subs.append(text)


func get_in(key: StringName, perspective: StringName = &"world") -> Variant:
	var text := String(key)
	var kind := _kind(perspective)
	if kind == "known" or kind == "believed" or kind == "held":
		var bag := _layer_bag(_layers(kind), _who(perspective), false)
		if bag.has(text):
			return bag[text]
		return null
	if kind != "world":
		return null
	var fact := _find(text)
	if fact == null or fact.origin == &"stored":
		if _world.has(text):
			return _world[text]
		return null
	if text.contains("{"):
		return null
	return _resolved(fact, text)


func set_in(key: StringName, new_value: Variant, perspective: StringName = &"world") -> bool:
	var text := String(key)
	var kind := _kind(perspective)
	if kind != "world" and kind != "known" and kind != "believed" and kind != "held":
		_refuse("perspective", text, "unknown perspective %s" % String(perspective))
		return false
	if not _stored_key(text):
		return false
	var fact := _find(text)
	if not _type_ok(fact.type_name, new_value):
		_refuse("type", text, "expected %s" % String(fact.type_name))
		return false
	var stored := _coerce(fact.type_name, new_value)
	var bag := _world if kind == "world" else _layer_bag(_layers(kind), _who(perspective), true)
	var had := bag.has(text)
	var old_value: Variant = bag[text] if had else null
	if had and old_value == stored:
		return true
	bag[text] = stored
	_notify(PackedStringArray([text]))
	_emit(text, old_value, stored, had)
	if kind == "believed" or kind == "held":
		_log_belief("believe" if kind == "believed" else "declare", _who(perspective), text, stored)
	return true


## Removes one [code]believed/[/code] or [code]held/[/code] key. A missing key is a no-op.
func clear_in(key: StringName, perspective: StringName) -> bool:
	var text := String(key)
	var kind := _kind(perspective)
	if kind != "believed" and kind != "held":
		_refuse("perspective", text, "clear only removes believed/ or held/")
		return false
	if not _stored_key(text):
		return false
	var who := _who(perspective)
	var layers := _layers(kind)
	if not layers.has(who):
		return true
	var bag: Dictionary = layers[who]
	if not bag.has(text):
		return true
	var old_value: Variant = bag[text]
	bag.erase(text)
	if bag.is_empty():
		layers.erase(who)
	_notify(PackedStringArray([text]))
	_emit(text, old_value, null, true)
	_log_belief("unbelieve" if kind == "believed" else "retract", who, text, null)
	return true


func _stored_key(text: String) -> bool:
	if text.is_empty() or text.contains("{"):
		_refuse("key", text, "not a concrete fact key")
		return false
	var fact := _find(text)
	if fact == null:
		_refuse("unknown", text, "no schema entry")
		return false
	if fact.origin != &"stored":
		_refuse("resolved", text, "resolved facts are not writable")
		return false
	return true


## Writes a [code]known/[/code] value that is not a schema fact. Role reveals use this.
func remember(key: StringName, value: Variant, perspective: StringName) -> bool:
	var text := String(key)
	if _kind(perspective) != "known":
		_refuse("perspective", text, "remember only writes known/")
		return false
	if text.is_empty():
		_refuse("key", text, "not a concrete fact key")
		return false
	var stored: Variant = StringName(str(value)) if value is String or value is StringName else value
	var bag := _layer_bag(_known, _who(perspective), true)
	var had := bag.has(text)
	var old_value: Variant = bag[text] if had else null
	if had and old_value == stored:
		return true
	bag[text] = stored
	_notify(PackedStringArray([text]))
	_emit(text, old_value, stored, had)
	return true


## Drops cached concrete keys under [param prefix]. A pattern key such as
## [code]npc.{id}.alive[/code] drops every cached concrete key of that pattern.
## [param reason] is the event name recorded for the playtest, or empty.
func invalidate(prefix: StringName, reason: StringName = &"") -> PackedStringArray:
	var text := String(prefix)
	var dropped := PackedStringArray()
	if text.is_empty():
		return dropped
	var doomed := {}
	for cached in _cache.keys():
		var cached_key := str(cached)
		if _prefix_hit(cached_key, text) or _pattern_covers(text, cached_key):
			doomed[cached_key] = true
	var names: Array = doomed.keys()
	names.sort()
	for cached_key in names:
		var key := String(cached_key)
		_remember(key)
		_cache.erase(key)
		dropped.append(key)
		_note_reason(key, reason)
	if _schema != null:
		for fact in _schema.entries:
			if fact.origin != &"resolved":
				continue
			var hit := _prefix_hit(fact.key, text)
			if not hit and fact.is_pattern():
				hit = _matches(fact, text) or fact.key == text or fact.key.begins_with(text + ".")
			if hit:
				_note_reason(fact.key, reason)
				if not dropped.has(fact.key):
					dropped.append(fact.key)
	_notify(dropped)
	return dropped


## Drops every [code]on_event[/code] fact bound to [param event_name], including
## every concrete cache of a pattern fact. The returned keys are sorted.
func invalidate_event(event_name: StringName) -> PackedStringArray:
	var found := {}
	if _schema == null:
		return PackedStringArray()
	for fact in _schema.entries:
		if fact.invalidate != &"on_event" or StringName(fact.invalidate_arg) != event_name:
			continue
		for key in invalidate(StringName(fact.key), event_name):
			found[String(key)] = true
		_note_reason(fact.key, event_name)
	return _sorted_keys(found)


## [code]mode[/code] is the schema invalidation ([code]on_event[/code], [code]poll[/code],
## [code]per_query[/code], [code]manual[/code]) or [code]absent[/code]. [code]event[/code]
## is the last invalidate reason. [code]cached[/code] is false for [code]per_query[/code].
func cache_view(key: String) -> Dictionary:
	var fact := _find(key)
	var mode := "absent"
	if fact != null and fact.origin == &"resolved":
		mode = String(fact.invalidate) if fact.invalidate != &"" else "manual"
	var event := String(_reasons.get(key, ""))
	if event.is_empty() and fact != null:
		event = String(_reasons.get(fact.key, ""))
	return {"cached": _cache.has(key), "event": event, "mode": mode}


func refresh_poll(now: int) -> void:
	var doomed := PackedStringArray()
	for cached in _cache.keys():
		var row: Dictionary = _cache[cached]
		if str(row.get("mode", "")) != "poll":
			continue
		var every := int(row.get("every", 0))
		if every > 0 and now - int(row.get("at", 0)) >= every:
			doomed.append(str(cached))
	if doomed.is_empty():
		return
	for cached_key in doomed:
		_remember(cached_key)
		_cache.erase(cached_key)
	_notify(doomed)


func _get(property: StringName) -> Variant:
	return get_in(property, &"world")


func _set(property: StringName, value: Variant) -> bool:
	set_in(property, value, &"world")
	return true


func _resolved(fact: WyrdFact, concrete: String) -> Variant:
	if fact.invalidate != &"per_query" and _cache.has(concrete):
		return (_cache[concrete] as Dictionary)["value"]
	var resolved := _call_resolver(fact, concrete)
	if on_resolved.is_valid():
		on_resolved.call(concrete, resolved)
	if fact.invalidate == &"per_query":
		return resolved
	var had := _last.has(concrete)
	var old_value: Variant = _last[concrete] if had else null
	_cache[concrete] = {
		"at": _now(),
		"every": _poll_every(fact),
		"mode": String(fact.invalidate) if fact.invalidate != &"" else "manual",
		"value": resolved,
	}
	if had:
		_last.erase(concrete)
		if old_value != resolved:
			_emit(concrete, old_value, resolved, true)
	return resolved


func _call_resolver(fact: WyrdFact, concrete: String) -> Variant:
	var dot := fact.resolver.find(".")
	if dot <= 0:
		_once_error(fact.resolver, "resolver \"%s\" is missing an adapter" % fact.resolver)
		return null
	var head := fact.resolver.substr(0, dot)
	var method := fact.resolver.substr(dot + 1)
	var adapter: Object = resolver_of.call(head) if resolver_of.is_valid() else null
	if adapter == null or not adapter.has_method(method):
		_once_error(fact.resolver, "resolver \"%s\" is not on an adapter" % fact.resolver)
		return null
	var parts := concrete.split(".")
	if parts.size() != fact.segments.size():
		return null
	var args: Array = []
	for i in fact.segments.size():
		if fact.segments[i].begins_with("{"):
			args.append(StringName(parts[i]))
	return adapter.callv(method, args)


func _find(concrete: String) -> WyrdFact:
	if _schema == null or concrete.is_empty():
		return null
	return _schema.lookup(concrete.split("."))


func _kind(perspective: StringName) -> String:
	var text := String(perspective)
	if text == "world":
		return "world"
	var slash := text.find("/")
	if slash <= 0:
		return "bad"
	var head := text.substr(0, slash)
	if text.substr(slash + 1).is_empty():
		return "bad"
	if head == "known" or head == "believed" or head == "held":
		return head
	return "bad"


func _who(perspective: StringName) -> String:
	var text := String(perspective)
	var slash := text.find("/")
	if slash < 0:
		return ""
	return text.substr(slash + 1)


func _layers(kind: String) -> Dictionary:
	if kind == "known":
		return _known
	if kind == "believed":
		return _believed
	return _held


func _layer_bag(layers: Dictionary, who: String, create: bool) -> Dictionary:
	if who.is_empty():
		return {}
	if not layers.has(who):
		if not create:
			return {}
		var created := {}
		layers[who] = created
		return created
	return layers[who]


func _log_belief(op: String, who: String, key: String, value: Variant) -> void:
	if _quiet or not on_belief.is_valid():
		return
	on_belief.call({"key": key, "op": op, "value": value, "who": who})


func _type_ok(type_name: StringName, new_value: Variant) -> bool:
	match String(type_name):
		"bool":
			return new_value is bool
		"int":
			return typeof(new_value) == TYPE_INT
		"float":
			return new_value is float or typeof(new_value) == TYPE_INT
		"symbol":
			return new_value is String or new_value is StringName
		_:
			return false


func _coerce(type_name: StringName, new_value: Variant) -> Variant:
	if type_name == &"float" and typeof(new_value) == TYPE_INT:
		return float(new_value)
	if type_name == &"symbol":
		return StringName(str(new_value))
	return new_value


func _emit(key: String, old_value: Variant, new_value: Variant, had_old: bool) -> void:
	if had_old and old_value == new_value:
		return
	if not _subscribed(key):
		return
	fact_changed.emit(StringName(key), old_value if had_old else null, new_value)


func _subscribed(key: String) -> bool:
	for prefix in _subs:
		if prefix.is_empty() or key == prefix or key.begins_with(prefix + "."):
			return true
	return false


func _notify(keys: PackedStringArray) -> void:
	if keys.is_empty() or not on_keys.is_valid():
		return
	on_keys.call(keys)


func _remember(key: String) -> void:
	if _cache.has(key):
		_last[key] = (_cache[key] as Dictionary)["value"]


func _now() -> int:
	if clock.is_valid():
		return int(clock.call())
	return 0


func _poll_every(fact: WyrdFact) -> int:
	if fact.invalidate != &"poll" or not fact.invalidate_arg.is_valid_int():
		return 0
	return int(fact.invalidate_arg)


func _prefix_hit(key: String, prefix: String) -> bool:
	return key == prefix or key.begins_with(prefix + ".")


## True when [param prefix] is a pattern fact key, or a parent of one, and
## [param concrete] is a cached value of that pattern.
func _pattern_covers(prefix: String, concrete: String) -> bool:
	if _schema == null or concrete.contains("{"):
		return false
	for fact in _schema.entries:
		if fact.origin != &"resolved" or not fact.is_pattern():
			continue
		if fact.key != prefix and not fact.key.begins_with(prefix + "."):
			continue
		if _matches(fact, concrete):
			return true
	return false


func _note_reason(key: String, reason: StringName) -> void:
	if reason != &"":
		_reasons[key] = String(reason)


func _sorted_keys(found: Dictionary) -> PackedStringArray:
	var names: Array = found.keys()
	names.sort()
	var out := PackedStringArray()
	for name in names:
		out.append(String(name))
	return out


func _matches(fact: WyrdFact, concrete: String) -> bool:
	var parts := concrete.split(".")
	if parts.size() != fact.segments.size():
		return false
	for i in parts.size():
		var segment := fact.segments[i]
		if segment.begins_with("{"):
			continue
		if segment != parts[i]:
			return false
	return true


func _refuse(kind: String, key: String, detail: String) -> void:
	push_error("WyrdFactStore: %s (%s)." % [detail, key])
	_trace(kind, key, detail)


func _once_error(resolver: String, detail: String) -> void:
	if _once.has(resolver):
		return
	_once[resolver] = true
	push_error("WyrdFactStore: %s." % detail)
	_trace("resolver", resolver, detail)


func _trace(kind: String, key: String, detail: String) -> void:
	if tracer.is_valid():
		tracer.call({"detail": detail, "key": key, "kind": kind})
