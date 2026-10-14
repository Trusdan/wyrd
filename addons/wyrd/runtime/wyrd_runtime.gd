class_name WyrdRuntime
extends RefCounted

## One narrative runtime. Tests each keep their own instance.
##
## @experimental
## S2a loads a manifest by compiling its [code].wyrd[/code] sources, then keeps
## a fact store, a condition table, and a fixed-work tick queue. S2b adds the
## deed log, relationship axes, and role slots. Quests, scenes, and saves are
## later slices. Callables stay in the registries.

const VERSION_PATH: String = "res://addons/wyrd/VERSION"
const _DEED_CALLS: PackedStringArray = ["deed_count", "deed_score", "affinity", "axis", "disposition", "slot_state"]
const _ROLE_CALLS: PackedStringArray = ["holder", "display_name", "filled", "known", "slot_state", "disposition"]

var facts: WyrdFactStore
var events: WyrdEvents
var roles: WyrdRoles
var deeds: WyrdDeedLog
var social: WyrdSocial

var _config: WyrdConfig
var _content: WyrdContent
var _queue: WyrdTickQueue
var _ctx: WyrdConditionCtx
var _rpn: WyrdRpnEval
var _signatures: WyrdSignatures
var _adapters: Dictionary = {}
var _functions: Dictionary = {}
var _flags: PackedByteArray = PackedByteArray()
var _always: PackedInt32Array = PackedInt32Array()
var _trace: Array[Dictionary] = []
var _seed: int = 0
var _minutes: int = 0


func _init() -> void:
	facts = WyrdFactStore.new()
	events = WyrdEvents.new()
	roles = WyrdRoles.new()
	deeds = WyrdDeedLog.new()
	social = WyrdSocial.new()
	_config = WyrdConfig.new()
	_queue = WyrdTickQueue.new()
	_ctx = WyrdConditionCtx.new()
	_rpn = WyrdRpnEval.new()
	_signatures = WyrdSignatures.new()
	_ctx.bind(self)
	facts.on_keys = Callable(self, &"_mark_keys")
	facts.tracer = Callable(self, &"note")
	facts.clock = Callable(self, &"now_minutes")
	facts.resolver_of = Callable(self, &"_resolver")
	events.on_emit = Callable(self, &"_on_emit")
	_rpn.fact_reader = Callable(facts, &"get_in")
	deeds.clock = Callable(self, &"now_minutes")
	deeds.config_of = Callable(self, &"config")
	deeds.spatial_of = Callable(self, &"_spatial")
	social.deeds = deeds
	social.config_of = Callable(self, &"config")
	roles.social = social
	roles.deeds = deeds
	roles.facts = facts
	roles.clock = Callable(self, &"now_minutes")
	roles.config_of = Callable(self, &"config")
	roles.content_of = Callable(self, &"content")
	roles.world_of = Callable(self, &"_world")
	deeds.deed_recorded.connect(_on_deed)
	roles.role_holder_changed.connect(_on_role)
	roles.role_vacant.connect(_on_role_vacant)
	social.on_changed = Callable(self, &"_on_social")


func get_version() -> String:
	return WyrdRuntime.read_version()


static func read_version() -> String:
	var file := FileAccess.open(VERSION_PATH, FileAccess.READ)
	if file == null:
		push_error("Missing version file at %s." % VERSION_PATH)
		return ""
	return file.get_as_text().strip_edges()


func config() -> WyrdConfig:
	return _config


func configure(next_config: WyrdConfig) -> void:
	if next_config == null:
		push_error("WyrdRuntime.configure: config is null")
		return
	_config = next_config


func register_adapter(base: Script, adapter: RefCounted) -> void:
	if base == null or adapter == null:
		push_error("WyrdRuntime.register_adapter: missing base or adapter")
		return
	var script := adapter.get_script() as Script
	if script == null or script.get_base_script() != base:
		push_error("WyrdRuntime.register_adapter: adapter is not a %s" % base.resource_path)
		return
	_adapters[base.resource_path] = adapter


func adapter(base: Script) -> RefCounted:
	if base == null or not _adapters.has(base.resource_path):
		return null
	return _adapters[base.resource_path] as RefCounted


func register_function(name: StringName, fn: Callable, arg_types: Array, return_type: StringName) -> bool:
	if not fn.is_valid():
		push_error("WyrdRuntime.register_function: \"%s\" has no callable" % String(name))
		return false
	if _functions.has(name) or _signatures.signature(name).size() > 0:
		var existing := _signatures.signature(name)
		if existing.is_empty() or not _signature_ok(existing, arg_types, return_type):
			push_error("WyrdRuntime.register_function: \"%s\" does not match its signature" % String(name))
			return false
		push_error("WyrdRuntime.register_function: \"%s\" is already registered" % String(name))
		return false
	var params: Array = []
	for i in arg_types.size():
		params.append({"name": StringName("arg%d" % i), "optional": false, "type": StringName(str(arg_types[i]))})
	if not _signatures.register(name, params, return_type):
		push_error("WyrdRuntime.register_function: \"%s\" was rejected" % String(name))
		return false
	_functions[name] = fn
	return true


func host_functions() -> Dictionary:
	return _functions


func function_table() -> Dictionary:
	return _ctx.funcs()


func start_new_game(seed_value: int) -> void:
	_seed = seed_value
	_minutes = 0
	_trace.clear()
	facts.clear_values()
	deeds.clear()
	social.clear_state()
	roles.clear()
	_arm_queue()


func game_seed() -> int:
	return _seed


func now_minutes() -> int:
	var now := _minutes
	var clock := adapter(WyrdTimeAdapter)
	if clock is WyrdTimeAdapter:
		now = maxi(now, (clock as WyrdTimeAdapter).now_minutes())
	return now


func load_content(manifest: WyrdContentManifest) -> WyrdLoadReport:
	var report := WyrdLoadReport.new()
	_content = null
	_flags = PackedByteArray()
	_always = PackedInt32Array()
	_queue.clear()
	facts.bind_schema(null)
	deeds.clear()
	social.clear_state()
	roles.bind_content(null)
	roles.clear()
	if manifest == null:
		report.diagnostics.add(WyrdDiagnostic.E_HEADER_MISSING, "missing content manifest", "", 1, 1)
		return report
	var files := PackedStringArray()
	for listed in manifest.files:
		files.append(_resolve(listed))
	if files.is_empty():
		report.diagnostics.add(WyrdDiagnostic.E_HEADER_MISSING, "content manifest has no files", manifest.resource_path, 1, 1)
		return report
	var commands: WyrdCommandSchema = null
	var skip_note := false
	var note := manifest.resource_path
	if not note.is_empty():
		var read := WyrdPack.read_commands(note.get_base_dir() + "/wyrd_commands.json", report.diagnostics)
		commands = read["schema"] as WyrdCommandSchema
		skip_note = bool(read["skip_note"])
	var pack := WyrdPack.compile(
		files,
		String(manifest.pack_id),
		manifest.language_version,
		commands,
		report.diagnostics,
		note,
		skip_note
	)
	if report.diagnostics.has_errors():
		return report
	_content = WyrdContent.from_pack(pack)
	report.ok = true
	report.manifest_hash = _content.manifest_hash
	facts.bind_schema(_content.schema)
	roles.bind_content(_content)
	_arm_queue()
	return report


func content() -> WyrdContent:
	return _content


func tick(game_minutes: int) -> void:
	if game_minutes < 0:
		push_error("Wyrd.tick: game minutes must be >= 0")
		return
	_minutes += game_minutes
	facts.refresh_poll(now_minutes())
	if game_minutes > 0:
		_mark_calls(_DEED_CALLS)
	if not _always.is_empty():
		_queue.mark(_always)
	var budget := _config.scheduler_work_per_tick if _config != null else 0
	_queue.tick(budget, _recheck)


func condition_count() -> int:
	if _content == null:
		return 0
	return _content.conditions.size()


func condition_flags() -> PackedByteArray:
	return _flags.duplicate()


func eval_condition(index: int) -> bool:
	return _eval_at(index)


func last_rechecks() -> int:
	return _queue.last_rechecks


func watch_condition(index: int) -> void:
	_queue.watch(index)


func unwatch_condition(index: int) -> void:
	_queue.unwatch(index)


func note(row: Dictionary) -> void:
	_trace.append(row)


func trace_log() -> Array[Dictionary]:
	return _trace.duplicate()


func _recheck(index: int) -> void:
	var value := _eval_at(index)
	if index >= 0 and index < _flags.size():
		_flags[index] = 1 if value else 0


func _eval_at(index: int) -> bool:
	if _content == null or index < 0 or index >= _content.conditions.size():
		return false
	_ctx.record_id = _content.records[index]
	_ctx.site = _content.sites[index]
	var result: Variant = _rpn.eval(_content.conditions[index], {}, _ctx.funcs())
	return result == true


func _arm_queue() -> void:
	_queue.clear()
	_always = PackedInt32Array()
	if _content == null:
		_flags = PackedByteArray()
		return
	_flags = PackedByteArray()
	_flags.resize(_content.conditions.size())
	for i in _content.conditions.size():
		_queue.watch(i)
		if _reads_per_query(_content.conditions[i]):
			_always.append(i)


func _reads_per_query(cond: WyrdCompiledCondition) -> bool:
	if cond == null or _content == null or _content.schema == null:
		return false
	for read in cond.reads:
		var fact := _content.schema.lookup(String(read).split("."))
		if fact != null and fact.invalidate == &"per_query":
			return true
	return false


func _mark_keys(keys: PackedStringArray) -> void:
	if _content == null or _content.deps == null or keys.is_empty():
		return
	var names: Array[StringName] = []
	for key in keys:
		names.append(StringName(key))
	_queue.mark(_content.deps.affected(names))


func _on_emit(event_name: StringName, _payload: Dictionary) -> void:
	facts.invalidate_event(event_name)


func loaded_fact_key() -> String:
	return _rpn.last_fact_key


func _on_deed(_deed: Dictionary) -> void:
	_mark_calls(_DEED_CALLS)


func _on_role(_role: StringName, _old_holder: StringName, _new_holder: StringName) -> void:
	_mark_calls(_ROLE_CALLS)


func _on_role_vacant(_role: StringName) -> void:
	_mark_calls(_ROLE_CALLS)


func _on_social() -> void:
	_mark_calls(_DEED_CALLS)


func _mark_calls(names: PackedStringArray) -> void:
	if _content == null or names.is_empty():
		return
	var hits := PackedInt32Array()
	for i in _content.conditions.size():
		var cond := _content.conditions[i]
		if cond == null:
			continue
		for item in cond.consts:
			if item is StringName and names.has(String(item)):
				hits.append(i)
				break
	if not hits.is_empty():
		_queue.mark(hits)


func _spatial() -> WyrdSpatialAdapter:
	var found := adapter(WyrdSpatialAdapter)
	if found is WyrdSpatialAdapter:
		return found as WyrdSpatialAdapter
	return null


func _world() -> WyrdWorldAdapter:
	var found := adapter(WyrdWorldAdapter)
	if found is WyrdWorldAdapter:
		return found as WyrdWorldAdapter
	return null


func _resolver(head: String) -> Object:
	match head:
		"world":
			return adapter(WyrdWorldAdapter)
		"time":
			return adapter(WyrdTimeAdapter)
		"inventory":
			return adapter(WyrdInventoryAdapter)
		"spatial":
			return adapter(WyrdSpatialAdapter)
		"action":
			return adapter(WyrdActionAdapter)
		_:
			return null


func _signature_ok(sig: Dictionary, arg_types: Array, return_type: StringName) -> bool:
	if StringName(sig["return"]) != return_type:
		return false
	var params: Array = sig["params"]
	if arg_types.size() != params.size():
		return false
	for i in arg_types.size():
		var param: Dictionary = params[i]
		if StringName(str(arg_types[i])) != param["type"]:
			return false
	return true


func _resolve(path: String) -> String:
	var text := path.replace("\\", "/")
	if text.begins_with("res://") or text.begins_with("user://") or text.begins_with("/"):
		return text
	return "res://" + text.trim_prefix("./")
