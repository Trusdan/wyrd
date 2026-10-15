class_name WyrdConditionCtx
extends RefCounted

## Built-ins the slice evaluates. Callables live here and are never saved.
##
## @experimental
## [code]holder[/code], [code]deed_count[/code], [code]deed_score[/code],
## [code]known[/code], and the social reads use the runtime. [code]chance[/code]
## draws [method WyrdRng.for_decision] on stream [code]chance[/code] with key
## [code]<record>:<site>[/code]. [code]knows[/code], [code]believes[/code], and
## [code]held[/code] report M5 and return false. A compiled [code]known[/code]
## argument loads the fact; the key is the latest load in this evaluation.

var record_id: String = ""
var site: String = ""

var _runtime: WyrdRuntime
var _builtins: Dictionary = {}
var _m5: Dictionary = {}


func bind(runtime: WyrdRuntime) -> void:
	_runtime = runtime
	_builtins = {
		&"affinity": Callable(self, &"_affinity"),
		&"alive": Callable(self, &"_alive"),
		&"axis": Callable(self, &"_axis"),
		&"believes": Callable(self, &"_believes"),
		&"chance": Callable(self, &"_chance"),
		&"deed_count": Callable(self, &"_deed_count"),
		&"deed_score": Callable(self, &"_deed_score"),
		&"disposition": Callable(self, &"_disposition"),
		&"display_name": Callable(self, &"_display_name"),
		&"filled": Callable(self, &"_filled"),
		&"has_tag": Callable(self, &"_has_tag"),
		&"held": Callable(self, &"_held"),
		&"holder": Callable(self, &"_holder"),
		&"known": Callable(self, &"_known"),
		&"knows": Callable(self, &"_knows"),
		&"rel": Callable(self, &"_rel"),
		&"slot_state": Callable(self, &"_slot_state"),
	}


func funcs() -> Dictionary:
	var table := _builtins.duplicate()
	if _runtime != null:
		for name in _runtime.host_functions().keys():
			table[name] = _runtime.host_functions()[name]
	return table


func _holder(args: Array) -> Variant:
	if args.is_empty() or args[0] == null or _runtime == null:
		return null
	var found := _runtime.roles.holder(StringName(str(args[0])))
	if found == &"":
		return null
	return found


func _display_name(args: Array) -> Variant:
	if args.is_empty() or args[0] == null:
		return null
	var id := StringName(str(args[0]))
	if id == &"":
		return null
	var world := _world()
	if world == null:
		return null
	var shown := world.display_name(id)
	if shown.is_empty():
		return null
	return StringName(shown)


func _has_tag(args: Array) -> bool:
	if args.size() < 2 or args[0] == null or args[1] == null:
		return false
	var world := _world()
	if world == null:
		return false
	var want := String(args[1])
	for tag in world.tags(StringName(str(args[0]))):
		if String(tag) == want:
			return true
	return false


func _alive(args: Array) -> bool:
	if args.is_empty() or args[0] == null:
		return false
	var world := _world()
	if world == null:
		return false
	return world.is_alive(StringName(str(args[0])))


func _deed_count(args: Array) -> int:
	return int(_deeds(args, false))


func _deed_score(args: Array) -> float:
	return float(_deeds(args, true))


func _known(args: Array) -> bool:
	if args.size() < 2 or args[0] == null or _runtime == null:
		return false
	var agent := StringName(str(args[0]))
	var key := _known_key(args[1])
	if key == &"":
		return false
	if _runtime.roles.revealed(agent, key):
		return true
	return _runtime.facts.get_in(key, StringName("known/%s" % String(agent))) != null


func _affinity(args: Array) -> float:
	if not _pair(args):
		return 0.0
	return _runtime.social.affinity(StringName(str(args[0])), StringName(str(args[1])))


func _axis(args: Array) -> float:
	if args.size() < 3 or not _pair(args) or args[2] == null:
		return 0.0
	return _runtime.social.axis(StringName(str(args[0])), StringName(str(args[1])), StringName(str(args[2])))


func _disposition(args: Array) -> int:
	if not _pair(args):
		return 0
	return _runtime.social.disposition(StringName(str(args[0])), StringName(str(args[1])))


func _rel(args: Array) -> bool:
	if args.size() < 3 or not _pair(args) or args[2] == null:
		return false
	return _runtime.social.has_kind(StringName(str(args[0])), StringName(str(args[1])), StringName(str(args[2])))


func _filled(args: Array) -> bool:
	return _holder(args) != null


func _slot_state(args: Array) -> Variant:
	if args.is_empty() or args[0] == null or _runtime == null:
		return null
	var state := _runtime.roles.slot_state(StringName(str(args[0])))
	if state == &"":
		return null
	return state


func _deeds(args: Array, score: bool) -> Variant:
	if _runtime == null or args.is_empty() or args[0] == null:
		return 0.0 if score else 0
	var tags := PackedStringArray()
	if args.size() > 5:
		tags = _tags(args[5])
	var within: Variant = args[4] if args.size() > 4 else null
	var place: Variant = args[3] if args.size() > 3 else null
	var target: Variant = args[2] if args.size() > 2 else null
	var verb: Variant = args[1] if args.size() > 1 else null
	var actor := StringName(str(args[0]))
	if score:
		return _runtime.deeds.score_matching(actor, verb, target, place, within, tags)
	return _runtime.deeds.count_matching(actor, verb, target, place, within, tags)


func _tags(value: Variant) -> PackedStringArray:
	var rows := PackedStringArray()
	if value is PackedStringArray:
		return value
	if value is Array:
		for item in value:
			if item != null:
				rows.append(String(item))
	return rows


func _known_key(value: Variant) -> StringName:
	if (value is String or value is StringName) and String(value).contains("."):
		return StringName(str(value))
	if _runtime != null and not _runtime.loaded_fact_key().is_empty():
		return StringName(_runtime.loaded_fact_key())
	if value is String or value is StringName:
		return StringName(str(value))
	return &""


func _pair(args: Array) -> bool:
	return _runtime != null and args.size() >= 2 and args[0] != null and args[1] != null


func _chance(args: Array) -> bool:
	if _runtime == null or args.is_empty() or not (args[0] is float or typeof(args[0]) == TYPE_INT):
		return false
	var p := float(args[0])
	if p >= 1.0:
		return true
	if p <= 0.0:
		return false
	var bucket := 0
	var size := _runtime.config().hour_bucket_minutes
	if size > 0:
		bucket = int(_runtime.now_minutes() / float(size))
	var key := StringName("%s:%s" % [record_id, site])
	var rng := WyrdRng.for_decision(_runtime.game_seed(), &"chance", key, bucket)
	var hit := rng.randf() < p
	_runtime.trace_add("roll", {"key": String(key), "pass": hit, "stream": "chance"})
	return hit


func _knows(_args: Array) -> bool:
	_report(&"knows")
	return false


func _believes(_args: Array) -> bool:
	_report(&"believes")
	return false


func _held(_args: Array) -> bool:
	_report(&"held")
	return false


func _report(name: StringName) -> void:
	if _m5.has(name):
		return
	_m5[name] = true
	push_error("belief function \"%s\" is M5" % String(name))
	if _runtime != null:
		_runtime.note({"detail": "M5", "key": String(name), "kind": "m5"})


func _world() -> WyrdWorldAdapter:
	if _runtime == null:
		return null
	var found := _runtime.adapter(WyrdWorldAdapter)
	if found is WyrdWorldAdapter:
		return found as WyrdWorldAdapter
	return null
