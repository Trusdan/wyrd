class_name WyrdFactStore
extends RefCounted

## Stored facts, resolver cache, and perspectives.
##
## @experimental
## World values are [method Object.set] and [method Object.get], implemented
## here as [method _set] and [method _get]. Godot already owns those names, so
## a perspective argument cannot be added and [code]set[/code] cannot return a
## bool. [method set_in] and [method get_in] take [code]world[/code] or
## [code]known/<agent>[/code]. [code]believed/[/code] and [code]held/[/code]
## stay empty (M5). A missing fact reads as null. Conditions treat that as false.
##
## [signal fact_changed] fires only for prefixes passed to [method subscribe].
## Callables on this object are the runtime's hooks. They are not saved.

signal fact_changed(key: StringName, old_value: Variant, new_value: Variant)

var on_keys: Callable = Callable()
var tracer: Callable = Callable()
var clock: Callable = Callable()
var resolver_of: Callable = Callable()

var _schema: WyrdFactSchema
var _world: Dictionary = {}
var _known: Dictionary = {}
var _believed: Dictionary = {}
var _held: Dictionary = {}
var _cache: Dictionary = {}
var _last: Dictionary = {}
var _subs: PackedStringArray = PackedStringArray()
var _once: Dictionary = {}


func bind_schema(schema: WyrdFactSchema) -> void:
	_schema = schema
	clear_values()


func clear_values() -> void:
	_world.clear()
	_known.clear()
	_believed.clear()
	_held.clear()
	_cache.clear()
	_last.clear()


func subscribe(prefix: StringName) -> void:
	var text := String(prefix)
	if not _subs.has(text):
		_subs.append(text)


func get_in(key: StringName, perspective: StringName = &"world") -> Variant:
	var text := String(key)
	var kind := _kind(perspective)
	if kind != "world" and kind != "known":
		return null
	if kind == "known":
		var bag := _known_bag(perspective, false)
		if bag.is_empty() and not _known.has(_agent(perspective)):
			return null
		if bag.has(text):
			return bag[text]
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
	if kind == "m5":
		_refuse("m5", text, "perspective %s is M5" % String(perspective))
		return false
	if kind != "world" and kind != "known":
		_refuse("perspective", text, "unknown perspective %s" % String(perspective))
		return false
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
	if not _type_ok(fact.type_name, new_value):
		_refuse("type", text, "expected %s" % String(fact.type_name))
		return false
	var stored := _coerce(fact.type_name, new_value)
	var bag := _world if kind == "world" else _known_bag(perspective, true)
	var had := bag.has(text)
	var old_value: Variant = bag[text] if had else null
	if had and old_value == stored:
		return true
	bag[text] = stored
	_notify(PackedStringArray([text]))
	_emit(text, old_value, stored, had)
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
	var bag := _known_bag(perspective, true)
	var had := bag.has(text)
	var old_value: Variant = bag[text] if had else null
	if had and old_value == stored:
		return true
	bag[text] = stored
	_notify(PackedStringArray([text]))
	_emit(text, old_value, stored, had)
	return true


func invalidate(prefix: StringName) -> void:
	var text := String(prefix)
	if text.is_empty():
		return
	var dropped := PackedStringArray()
	var doomed := PackedStringArray()
	for cached in _cache.keys():
		var cached_key := str(cached)
		if _prefix_hit(cached_key, text):
			doomed.append(cached_key)
	for cached_key in doomed:
		_remember(cached_key)
		_cache.erase(cached_key)
		dropped.append(cached_key)
	if _schema != null:
		for fact in _schema.entries:
			if fact.origin != &"resolved":
				continue
			var hit := _prefix_hit(fact.key, text)
			if not hit and fact.is_pattern():
				hit = _matches(fact, text)
			if hit and not dropped.has(fact.key):
				dropped.append(fact.key)
	_notify(dropped)


func invalidate_event(event_name: StringName) -> void:
	if _schema == null:
		return
	var keys := PackedStringArray()
	for fact in _schema.entries:
		if fact.invalidate == &"on_event" and StringName(fact.invalidate_arg) == event_name:
			keys.append(fact.key)
	for key in keys:
		invalidate(StringName(key))


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
	if text.begins_with("known/"):
		return "known" if not _agent(perspective).is_empty() else "bad"
	if text.begins_with("believed/") or text.begins_with("held/"):
		return "m5"
	return "bad"


func _agent(perspective: StringName) -> String:
	var text := String(perspective)
	if not text.begins_with("known/"):
		return ""
	return text.substr(6)


func _known_bag(perspective: StringName, create: bool) -> Dictionary:
	var agent := _agent(perspective)
	if agent.is_empty():
		return {}
	if not _known.has(agent):
		if not create:
			return {}
		var created := {}
		_known[agent] = created
		return created
	return _known[agent]


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
