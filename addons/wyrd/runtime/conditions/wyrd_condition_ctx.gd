class_name WyrdConditionCtx
extends RefCounted

## Built-ins the slice evaluates. Callables live here and are never saved.
##
## @experimental
## [code]holder[/code] and [code]display_name[/code] use the role stub.
## [code]deed_count[/code] is 0 until the deed log exists. [code]chance[/code]
## draws [method WyrdRng.for_decision] on stream [code]chance[/code] with key
## [code]<record>:<site>[/code]. [code]knows[/code], [code]believes[/code], and
## [code]held[/code] report M5 and return false.

var record_id: String = ""
var site: String = ""

var _runtime: WyrdRuntime
var _builtins: Dictionary = {}
var _m5: Dictionary = {}


func bind(runtime: WyrdRuntime) -> void:
	_runtime = runtime
	_builtins = {
		&"alive": Callable(self, &"_alive"),
		&"believes": Callable(self, &"_believes"),
		&"chance": Callable(self, &"_chance"),
		&"deed_count": Callable(self, &"_deed_count"),
		&"display_name": Callable(self, &"_display_name"),
		&"has_tag": Callable(self, &"_has_tag"),
		&"held": Callable(self, &"_held"),
		&"holder": Callable(self, &"_holder"),
		&"knows": Callable(self, &"_knows"),
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


func _deed_count(_args: Array) -> int:
	return 0


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
	return rng.randf() < p


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
