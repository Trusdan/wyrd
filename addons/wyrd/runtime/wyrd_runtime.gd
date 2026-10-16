class_name WyrdRuntime
extends RefCounted

## One narrative runtime. Tests each keep their own instance.
##
## @experimental
## S2a loads a manifest by compiling its [code].wyrd[/code] sources, then keeps
## a fact store, a condition table, and a fixed-work tick queue. S2b adds the
## deed log, relationship axes, and role slots. S2c runs slice effects, quests,
## and scenes. S2d saves that state and can record a decision trace.
## Callables stay in the registries.

const VERSION_PATH: String = "res://addons/wyrd/VERSION"
const _DEED_CALLS: PackedStringArray = ["deed_count", "deed_score", "affinity", "axis", "disposition", "reputation", "perceived", "slot_state"]
const _ROLE_CALLS: PackedStringArray = ["holder", "display_name", "filled", "known", "knows", "slot_state", "disposition"]
const _GROUPS_CHANGED: StringName = &"groups_changed"

var facts: WyrdFactStore
var events: WyrdEvents
var roles: WyrdRoles
var deeds: WyrdDeedLog
var social: WyrdSocial
var effects: WyrdEffects
var quests: WyrdQuestRunner
var dialogue: WyrdSceneRunner
var storylets: WyrdStoryletDeck
var trace: WyrdTrace

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
var _streams: Dictionary = {}
var _seed: int = 0
var _perception_key: String = ""
var _perception_value: Variant = null
var _minutes: int = 0
var _emit_seq: int = 0
var _collecting: bool = false
var _collected: Dictionary = {}
var _locals: Dictionary = {}
var _slot_traced: Dictionary = {}
## Agent to precedence list. Not saved. Dropped by [method invalidate_groups].
var _group_cache: Dictionary = {}
var _group_order: Callable = Callable()
## Replaces the statement score. Not saved. The game seed is not an input.
var _credibility: Callable = Callable()


func _init() -> void:
	facts = WyrdFactStore.new()
	events = WyrdEvents.new()
	roles = WyrdRoles.new()
	storylets = WyrdStoryletDeck.new()
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
	facts.on_belief = Callable(self, &"_trace_belief")
	facts.on_knowledge = Callable(self, &"_trace_knowledge")
	deeds.on_perceived = Callable(self, &"_on_perceived")
	facts.on_resolved = Callable(self, &"_on_resolved")
	facts.clock = Callable(self, &"now_minutes")
	facts.resolver_of = Callable(self, &"_resolver")
	events.on_emit = Callable(self, &"_on_emit")
	events.on_batch = Callable(self, &"_on_batch")
	_rpn.fact_reader = Callable(facts, &"get_in")
	deeds.clock = Callable(self, &"now_minutes")
	deeds.config_of = Callable(self, &"config")
	deeds.spatial_of = Callable(self, &"_spatial")
	deeds.on_compact = Callable(self, &"_on_compact")
	social.deeds = deeds
	social.config_of = Callable(self, &"config")
	social.members_of = Callable(self, &"_members")
	social.on_reputation = Callable(self, &"_trace_reputation")
	roles.social = social
	roles.deeds = deeds
	roles.facts = facts
	roles.clock = Callable(self, &"now_minutes")
	roles.config_of = Callable(self, &"config")
	roles.content_of = Callable(self, &"content")
	roles.world_of = Callable(self, &"_world")
	roles.eval_with = Callable(self, &"eval_with_locals")
	roles.trace_of = Callable(self, &"_trace_role")
	deeds.deed_recorded.connect(_on_deed)
	roles.role_holder_changed.connect(_on_role)
	roles.role_vacant.connect(_on_role_vacant)
	social.on_changed = Callable(self, &"_on_social")
	effects = WyrdEffects.new()
	effects.bind(self)
	quests = WyrdQuestRunner.new()
	quests.bind(self)
	roles.stage_of = Callable(quests, &"stage")
	roles.seed_of = Callable(self, &"game_seed")
	roles.election_of = Callable(self, &"_election")
	dialogue = WyrdSceneRunner.new()
	dialogue.bind(self)
	effects.outcome_changed.connect(quests.note_outcome)
	dialogue.scene_ended.connect(quests.on_scene_ended)
	roles.role_holder_changed.connect(dialogue.note_role)
	trace = WyrdTrace.new()


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
	if base == WyrdWorldAdapter:
		invalidate_groups()


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


## [param fn] receives [code](agent, groups)[/code] and returns the precedence list.
## The default list is [method WyrdWorldAdapter.groups_of]. Not saved.
func register_group_precedence(fn: Callable) -> void:
	_group_order = fn
	invalidate_groups()


## [param fn] receives [code](listener, speaker)[/code] and returns the score.
## It replaces [method credibility_score]. Not saved.
func register_credibility(fn: Callable) -> void:
	_credibility = fn


## Default is [code]disposition(listener, speaker) / 100[/code]. An override is used raw.
func credibility_score(listener: StringName, speaker: StringName) -> float:
	if _credibility.is_valid():
		return float(_credibility.call(listener, speaker))
	return float(social.disposition(listener, speaker)) / 100.0


func credibility_threshold() -> float:
	if _config == null:
		return 0.5
	return _config.credibility_threshold


## Drops the membership cache and wakes conditions that read [code]group.membership[/code].
func invalidate_groups() -> void:
	_group_cache.clear()
	_clear_belief_cache()
	if social != null:
		social.invalidate_members()
	_mark_keys(PackedStringArray([&"group.membership"]))
	_mark_calls(PackedStringArray(["reputation"]))


## Cached precedence for [param agent]. An explicit belief still wins before this runs.
func group_precedence(agent: StringName) -> PackedStringArray:
	if _group_cache.has(agent):
		return _group_cache[agent] as PackedStringArray
	var listed := _adapter_groups(agent)
	var ordered := listed
	if _group_order.is_valid():
		ordered = _as_groups(_group_order.call(agent, listed))
	_group_cache[agent] = ordered
	return ordered


func host_functions() -> Dictionary:
	return _functions


func function_table() -> Dictionary:
	return _ctx.funcs()


func start_new_game(seed_value: int) -> void:
	_seed = seed_value
	_minutes = 0
	_trace.clear()
	_streams.clear()
	if trace != null:
		trace.events.clear()
	facts.clear_values()
	_group_cache.clear()
	_clear_belief_cache()
	deeds.clear()
	social.clear_state()
	roles.clear()
	_reset_event_memory()
	_arm_queue()
	_reset_play()
	roles.note_started()
	if storylets != null:
		storylets.set_seed(_seed)


func game_seed() -> int:
	return _seed


func play_minutes() -> int:
	return _minutes


func restore_clock(seed_value: int, minutes: int) -> void:
	_seed = seed_value
	_minutes = maxi(minutes, 0)
	if storylets != null:
		storylets.set_seed(_seed)


func rng_stream(name: StringName) -> WyrdRng:
	var key := String(name)
	if not _streams.has(key):
		var created := WyrdRng.new()
		created.seed_with(_seed, WyrdRng.stream_id(name))
		_streams[key] = created
	return _streams[key] as WyrdRng


func draw_u32(name: StringName) -> int:
	var value := rng_stream(name).next_u32()
	trace_add("draw", {"op": "u32", "stream": String(name), "value": value})
	return value


func export_rng() -> Dictionary:
	var out := {}
	var names: Array = _streams.keys()
	names.sort()
	for stream_name in names:
		out[String(stream_name)] = (_streams[stream_name] as WyrdRng).to_state()
	return out


func import_rng(data: Dictionary) -> bool:
	var built := {}
	for stream_name in data.keys():
		if not (data[stream_name] is Dictionary):
			return false
		var restored := WyrdRng.from_state(data[stream_name])
		if restored == null:
			return false
		built[String(stream_name)] = restored
	_streams = built
	return true


func now_minutes() -> int:
	var now := _minutes
	var clock := adapter(WyrdTimeAdapter)
	if clock is WyrdTimeAdapter:
		now = maxi(now, (clock as WyrdTimeAdapter).now_minutes())
	return now


func load_content(manifest: WyrdContentManifest) -> WyrdLoadReport:
	var report := WyrdLoadReport.new()
	_content = null
	if storylets != null:
		storylets.bind(null)
	_flags = PackedByteArray()
	_always = PackedInt32Array()
	_queue.clear()
	_reset_play()
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
	if storylets != null:
		storylets.bind(_content)
		storylets.set_seed(_seed)
	report.ok = true
	report.manifest_hash = _content.manifest_hash
	facts.bind_schema(_content.schema)
	roles.bind_content(_content)
	_reset_event_memory()
	_arm_queue()
	_reset_play()
	return report


func content() -> WyrdContent:
	return _content


func tick(game_minutes: int) -> void:
	if game_minutes < 0:
		push_error("Wyrd.tick: game minutes must be >= 0")
		return
	trace_add("tick", {"minutes": game_minutes})
	_minutes += game_minutes
	if _config != null and _config.compact_after > 0 and deeds.size() >= _config.compact_after:
		deeds.compact()
	facts.refresh_poll(now_minutes())
	facts.decay_evidence(now_minutes())
	if game_minutes > 0:
		_mark_calls(_DEED_CALLS)
	if not _always.is_empty():
		_queue.mark(_always)
	var budget := _config.scheduler_work_per_tick if _config != null else 0
	_queue.tick(budget, _recheck)
	if quests != null:
		quests.on_tick()
	if dialogue != null:
		dialogue.on_tick()


func condition_count() -> int:
	if _content == null:
		return 0
	return _content.conditions.size()


func condition_flags() -> PackedByteArray:
	return _flags.duplicate()


func eval_condition(index: int) -> bool:
	return _eval_at(index)


func eval_value(cond: WyrdCompiledCondition) -> Variant:
	if cond == null:
		return null
	var index := -1
	if _content != null:
		index = _content.index_of(cond)
	if index >= 0:
		_ctx.record_id = _content.records[index]
		_ctx.site = _content.sites[index]
	else:
		_ctx.record_id = ""
		_ctx.site = ""
	return _rpn.eval(cond, _locals, _ctx.funcs())


func eval_bool(cond: WyrdCompiledCondition) -> bool:
	return eval_value(cond) == true


func eval_with_locals(cond: WyrdCompiledCondition, locals: Dictionary) -> bool:
	var saved := _locals.duplicate()
	_locals = locals.duplicate()
	var ok := eval_bool(cond)
	_locals = saved
	return ok


func _trace_role(kind: String, fields: Dictionary) -> void:
	if kind == "slot_state":
		_trace_slot(fields)
		return
	if kind == "succession":
		_trace_succession(fields)
		return
	if kind == "cast":
		_trace_cast(fields)
		return
	trace_add(kind, fields)
	if trace == null or not trace.enabled:
		return
	var flag := "true" if bool(fields.get("ok", false)) else "false"
	print("wyrd %s role=%s entity=%s ok=%s" % [kind, str(fields.get("role", "")), str(fields.get("entity", "")), flag])


func _trace_slot(fields: Dictionary) -> void:
	if trace == null or not trace.enabled:
		return
	if not _trace_allows(fields):
		return
	var key := "%s\t%s" % [str(fields.get("quest", "")), str(fields.get("slot", ""))]
	var token := "%s\t%s" % [str(fields.get("state", "")), str(fields.get("reason", ""))]
	if str(_slot_traced.get(key, "")) == token:
		return
	_slot_traced[key] = token
	trace_add("slot_state", fields)
	print(
		"wyrd slot_state quest=%s role=%s slot=%s state=%s reason=%s"
		% [
			str(fields.get("quest", "")),
			str(fields.get("role", "")),
			str(fields.get("slot", "")),
			str(fields.get("state", "")),
			str(fields.get("reason", "")),
		]
	)


func _trace_cast(fields: Dictionary) -> void:
	if trace == null or not trace.enabled:
		return
	if not _trace_allows(fields):
		return
	trace_add("cast", fields)
	print(
		"wyrd cast quest=%s role=%s slot=%s entity=%s reason=%s"
		% [
			str(fields.get("quest", "")),
			str(fields.get("role", "")),
			str(fields.get("slot", "")),
			str(fields.get("entity", "")),
			str(fields.get("reason", "")),
		]
	)


func _trace_succession(fields: Dictionary) -> void:
	if trace == null or not trace.enabled:
		return
	if not _trace_allows(fields):
		return
	trace_add("succession", fields)
	print(
		"wyrd succession role=%s strategy=%s from=%s to=%s reason=%s"
		% [
			str(fields.get("role", "")),
			str(fields.get("strategy", "")),
			str(fields.get("from", "")),
			str(fields.get("to", "")),
			str(fields.get("reason", "")),
		]
	)


func _trace_belief(fields: Dictionary) -> void:
	_clear_belief_cache()
	if trace == null or not trace.enabled:
		return
	if not _trace_allows(fields):
		return
	var op := str(fields.get("op", ""))
	var perspective := "held" if op == "declare" or op == "retract" else "believed"
	var shown := "" if fields.get("value") == null else str(fields.get("value"))
	var row := {
		"key": str(fields.get("key", "")),
		"op": op,
		"perspective": perspective,
		"value": shown,
		"who": str(fields.get("who", "")),
	}
	trace_add("belief", row)
	print(
		"wyrd belief op=%s perspective=%s who=%s key=%s value=%s"
		% [row["op"], row["perspective"], row["who"], row["key"], row["value"]]
	)


func _trace_knowledge(fields: Dictionary) -> void:
	if trace == null or not trace.enabled:
		return
	if not _trace_allows(fields):
		return
	var shown := "" if fields.get("value") == null else str(fields.get("value"))
	var row := {
		"key": str(fields.get("key", "")),
		"op": str(fields.get("op", "")),
		"perspective": "known",
		"value": shown,
		"who": str(fields.get("who", "")),
	}
	trace_add("knowledge", row)
	print(
		"wyrd knowledge op=%s perspective=%s who=%s key=%s value=%s"
		% [row["op"], row["perspective"], row["who"], row["key"], row["value"]]
	)


## Remembers the fact a deed is about to reveal, so each perception line can name it.
func perception_claim(key: String, value: Variant) -> void:
	_perception_key = key
	_perception_value = value


func clear_perception_claim() -> void:
	_perception_key = ""
	_perception_value = null


## One line per listener, including a rejection. [param who] is the listener.
func trace_credibility(
	listener: StringName,
	speaker: StringName,
	verb: StringName,
	key: String,
	value: Variant,
	score: float,
	accepted: bool
) -> void:
	if trace == null or not trace.enabled:
		return
	var shown := "" if value == null else str(value)
	var fields := {
		"accepted": "true" if accepted else "false",
		"key": key,
		"listener": String(listener),
		"score": _score_text(score),
		"speaker": String(speaker),
		"value": shown,
		"verb": String(verb),
		"who": String(listener),
	}
	if not _trace_allows(fields):
		return
	trace_add("credibility", fields)
	print(
		"wyrd credibility listener=%s speaker=%s verb=%s key=%s value=%s score=%s accepted=%s"
		% [
			fields["listener"],
			fields["speaker"],
			fields["verb"],
			fields["key"],
			fields["value"],
			fields["score"],
			fields["accepted"],
		]
	)


func _on_compact(info: Dictionary) -> void:
	if int(info.get("before", 0)) != int(info.get("after", 0)):
		_mark_calls(_DEED_CALLS)
	if trace == null or not trace.enabled:
		return
	var fields := {
		"after": int(info.get("after", 0)),
		"before": int(info.get("before", 0)),
		"dropped": int(info.get("dropped", 0)),
		"merged": int(info.get("merged", 0)),
	}
	if not _trace_allows(fields):
		return
	trace_add("compact", fields)
	print(
		"wyrd compact before=%s after=%s merged=%s dropped=%s"
		% [str(fields["before"]), str(fields["after"]), str(fields["merged"]), str(fields["dropped"])]
	)


func _trace_reputation(subject: StringName, group: StringName, value: float, members: int) -> void:
	if trace == null or not trace.enabled:
		return
	var fields := {
		"group": String(group),
		"key": String(group),
		"members": members,
		"subject": String(subject),
		"value": value,
		"who": String(subject),
	}
	if not _trace_allows(fields):
		return
	trace_add("reputation", fields)
	print(
		"wyrd reputation subject=%s group=%s value=%s members=%s"
		% [fields["subject"], fields["group"], str(fields["value"]), str(fields["members"])]
	)


func trace_belief_lookup(agent: StringName, key: StringName, value: Variant, source: String) -> void:
	if trace == null or not trace.enabled:
		return
	var shown := "" if value == null else str(value)
	var fields := {
		"agent": String(agent),
		"key": String(key),
		"source": source,
		"value": shown,
		"who": String(agent),
	}
	if not _trace_allows(fields):
		return
	trace_add("belief_lookup", fields)
	print(
		"wyrd belief_lookup agent=%s key=%s value=%s source=%s"
		% [fields["agent"], fields["key"], fields["value"], fields["source"]]
	)


func trace_conflict(
	agent: StringName,
	key: StringName,
	hit: bool,
	source: String,
	value: Variant,
	against: String
) -> void:
	if trace == null or not trace.enabled:
		return
	var shown := "" if value == null else str(value)
	var fields := {
		"against": against,
		"agent": String(agent),
		"conflicted": "true" if hit else "false",
		"key": String(key),
		"source": source,
		"value": shown,
		"who": String(agent),
	}
	if not _trace_allows(fields):
		return
	trace_add("conflict", fields)
	print(
		"wyrd conflict agent=%s key=%s conflicted=%s source=%s value=%s against=%s"
		% [fields["agent"], fields["key"], fields["conflicted"], fields["source"], fields["value"], fields["against"]]
	)


func _score_text(score: float) -> String:
	return "%.4f" % score


func _trace_allows(fields: Dictionary) -> bool:
	if trace == null or trace.prefix.is_empty():
		return true
	var prefix := trace.prefix
	for name in ["quest", "role", "slot", "who", "key"]:
		var value := str(fields.get(name, ""))
		if value == prefix or value.begins_with(prefix):
			return true
	return false


func condition_dirty(index: int) -> bool:
	if index < 0:
		return false
	return _queue.is_dirty(index)


func condition_flag(index: int) -> int:
	if index < 0 or index >= _flags.size():
		return 0
	return int(_flags[index])


func locals_empty() -> bool:
	return _locals.is_empty()


func can_save() -> bool:
	return dialogue == null or dialogue.can_save()


func save_state() -> Dictionary:
	if not can_save():
		push_error("Wyrd.save_state: a scene is open")
		return {}
	return WyrdSave.capture(self)


func load_state(data: Dictionary) -> WyrdLoadReport:
	if not can_save():
		push_error("Wyrd.load_state: a scene is open")
		var refused := WyrdLoadReport.new()
		refused.diagnostics.add(WyrdDiagnostic.E_SAVE_OPEN, "a scene is open", "", 1, 1)
		return refused
	_clear_belief_cache()
	var report := WyrdSave.apply(self, data)
	if report.ok:
		_reset_event_memory()
		_clear_belief_cache()
	return report


func last_rechecks() -> int:
	return _queue.last_rechecks


func watch_condition(index: int) -> void:
	_queue.watch(index)


func unwatch_condition(index: int) -> void:
	_queue.unwatch(index)


func note(row: Dictionary) -> void:
	_trace.append(row)


func trace_add(kind: String, fields: Dictionary) -> void:
	if trace == null or not trace.enabled:
		return
	trace.add(kind, fields)


func _on_resolved(key: String, value: Variant) -> void:
	trace_add("resolver", {"key": key, "value": value})


func trace_log() -> Array[Dictionary]:
	return _trace.duplicate()


func _reset_play() -> void:
	_slot_traced.clear()
	if storylets != null:
		storylets.clear()
	if effects != null:
		effects.clear()
	if dialogue != null:
		dialogue.force_close()
	if quests != null:
		quests.reset()


func _recheck(index: int) -> void:
	var value := _eval_at(index)
	if index >= 0 and index < _flags.size():
		_flags[index] = 1 if value else 0
	if value and quests != null:
		quests.note_ready(index)


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
	_content.index_calls(_tracked_calls())
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


func bind_locals(values: Dictionary) -> void:
	_locals = values.duplicate()


func clear_locals() -> void:
	_locals.clear()


func debug_dump() -> String:
	var lines := PackedStringArray()
	if events != null:
		lines.append(events.debug_dump())
	lines.append("dirty %d" % _queue.dirty_count())
	if _content != null and _content.schema != null:
		for fact in _content.schema.entries:
			if fact.origin != &"resolved":
				continue
			var view := facts.cache_view(fact.key)
			lines.append("cache %s %s %s" % [fact.key, str(view.get("mode", "")), str(view.get("event", ""))])
	return "\n".join(lines)


func _mark_keys(keys: PackedStringArray) -> void:
	if _content == null or _content.deps == null or keys.is_empty():
		return
	var names: Array[StringName] = []
	for key in keys:
		names.append(StringName(key))
	var hits := _content.deps.affected(names)
	_queue.mark(hits)
	if _collecting:
		for index in hits:
			_collected[int(index)] = true


func _on_batch(opening: bool) -> void:
	if opening:
		_collecting = true
		_collected.clear()
		trace_add("batch_begin", {"time": now_minutes()})
		return
	var ran := _flush_collected()
	trace_add("batch_end", {"rechecks": _as_ints(ran), "time": now_minutes()})
	if quests != null:
		quests.on_tick()
	_collecting = false
	_collected.clear()


func _on_emit(event_name: StringName, payload: Dictionary) -> void:
	var problem := _payload_problem(event_name, payload)
	var shown := _payload_strings(payload)
	if problem != "":
		push_error("Wyrd.events.emit: %s" % problem)
		trace_add("emit_rejected", {
			"name": String(event_name),
			"payload": shown,
			"reason": problem,
			"time": now_minutes(),
		})
		return
	var normalized := _normalize_payload(event_name, payload)
	_emit_seq += 1
	var emit_id := _emit_seq
	var owned := not _collecting
	if owned:
		_collecting = true
		_collected.clear()
	if event_name == _GROUPS_CHANGED:
		invalidate_groups()
	var keys := facts.invalidate_event(event_name)
	if events != null:
		events.last_keys = keys
		events.remember({
			"id": emit_id,
			"keys": _key_list(keys),
			"name": String(event_name),
			"payload": _payload_strings(normalized),
			"time": now_minutes(),
		})
	_apply_event_act(event_name, payload, normalized)
	if quests != null:
		quests.on_world_event(emit_id, event_name, normalized)
	var in_batch := events != null and events.batching()
	if in_batch or not owned:
		trace_add("emit", {
			"id": emit_id,
			"keys": keys,
			"name": String(event_name),
			"payload": normalized,
			"rechecks": [],
			"time": now_minutes(),
		})
		return
	var ran := _flush_collected()
	trace_add("emit", {
		"id": emit_id,
		"keys": keys,
		"name": String(event_name),
		"payload": normalized,
		"rechecks": _as_ints(ran),
		"time": now_minutes(),
	})
	if quests != null:
		quests.on_tick()
	_collecting = false
	_collected.clear()


## Writes [code]leaves[/code] evidence and one witness layer per mode.
## [code]saw[/code] learns the fact. [code]heard[/code] and [code]inferred[/code] believe it.
func _apply_event_act(event_name: StringName, payload: Dictionary, normalized: Dictionary) -> void:
	if _content == null or not _content.events.has(String(event_name)):
		return
	var event := _content.events[String(event_name)] as WyrdEventDef
	if event == null:
		return
	var key := event.leaves_key
	var value: Variant = null
	if not key.is_empty():
		value = event.leaves_value
		if event.leaves_kind == &"symbol":
			value = StringName(str(value))
		if not facts.set_in(StringName(key), value, &"world"):
			return
		value = facts.get_in(StringName(key), &"world")
		var until := -1
		if event.decays_minutes > 0:
			until = now_minutes() + event.decays_minutes
		facts.note_evidence(
			key,
			value,
			_event_place(normalized),
			until,
			event.name,
			_event_actor(normalized),
			_event_target(normalized)
		)
		_trace_evidence(event.name, key, value, until)
	if not _has_witnesses(payload):
		return
	for pair in _event_witnesses(payload, normalized):
		var who := pair["id"] as StringName
		var mode := pair["mode"] as StringName
		if key.is_empty():
			_trace_event_witness(who, mode, event.name, "", null)
			continue
		_write_event_witness(who, mode, event.name, key, value)


## A later spatial perceive of evidence still at [param place].
## The world fact and its deadline stay. [code]saw[/code] learns it. [code]heard[/code]
## and [code]inferred[/code] believe it.
func notice_evidence(observer: StringName, place: StringName) -> void:
	var spatial := adapter(WyrdSpatialAdapter) as WyrdSpatialAdapter
	for row in facts.evidence_rows():
		if String(row.get("place", "")) != String(place):
			continue
		var mode := &"saw"
		if spatial != null:
			mode = spatial.perceive(
				observer,
				StringName(str(row.get("actor", ""))),
				StringName(str(row.get("target", ""))),
				place
			)
		var mode_name := String(mode)
		if mode_name.is_empty():
			continue
		if not _witness_mode_ok(mode_name, "Wyrd.notice_evidence"):
			continue
		_write_event_witness(
			observer,
			StringName(mode_name),
			String(row.get("event", "")),
			String(row.get("key", "")),
			row.get("value")
		)


func _write_event_witness(
	who: StringName,
	mode: StringName,
	event_name: String,
	key: String,
	value: Variant
) -> void:
	var layer := "known" if String(mode) == "saw" else "believed"
	facts.set_in(StringName(key), value, StringName("%s/%s" % [layer, String(who)]))
	_trace_event_witness(who, mode, event_name, key, value)


func _event_witnesses(payload: Dictionary, normalized: Dictionary) -> Array:
	var spec: Variant = _witness_spec(payload)
	if spec is String or spec is StringName:
		if String(spec) == "auto":
			return _auto_witnesses(normalized)
		push_error("Wyrd.events.emit: witnesses must be \"auto\" or a list of {id, mode}")
		return []
	if spec is Array:
		var out: Array = []
		for item in spec:
			if not (item is Dictionary):
				push_error("Wyrd.events.emit: witnesses must be \"auto\" or a list of {id, mode}")
				continue
			var row: Dictionary = item
			var id_text := ""
			if row.has("id"):
				id_text = String(row["id"])
			elif row.has(&"id"):
				id_text = String(row[&"id"])
			var mode: Variant = null
			if row.has("mode"):
				mode = row["mode"]
			elif row.has(&"mode"):
				mode = row[&"mode"]
			if id_text.is_empty() or mode == null:
				push_error("Wyrd.events.emit: a witness needs id and mode")
				continue
			var mode_name := String(mode)
			if mode_name.is_empty():
				continue
			if not _witness_mode_ok(mode_name, "Wyrd.events.emit"):
				continue
			out.append({"id": StringName(id_text), "mode": StringName(mode_name)})
		return out
	push_error("Wyrd.events.emit: witnesses must be \"auto\" or a list of {id, mode}")
	return []


func _auto_witnesses(normalized: Dictionary) -> Array:
	var spatial := adapter(WyrdSpatialAdapter) as WyrdSpatialAdapter
	if spatial == null:
		return []
	var actor := StringName(_event_actor(normalized))
	var target := StringName(_event_target(normalized))
	var place := StringName(_event_place(normalized))
	var out: Array = []
	for observer in spatial.witnesses_of(actor, target, place):
		var mode := spatial.perceive(StringName(String(observer)), actor, target, place)
		var mode_name := String(mode)
		if mode_name.is_empty():
			continue
		if not _witness_mode_ok(mode_name, "Wyrd.events.emit"):
			continue
		out.append({"id": StringName(String(observer)), "mode": StringName(mode_name)})
	return out


func _witness_mode_ok(mode_name: String, site: String) -> bool:
	if mode_name == "saw" or mode_name == "heard" or mode_name == "inferred":
		return true
	push_error("%s: unknown witness mode \"%s\"" % [site, mode_name])
	return false


func _has_witnesses(payload: Dictionary) -> bool:
	return payload.has("witnesses") or payload.has(&"witnesses")


func _witness_spec(payload: Dictionary) -> Variant:
	if payload.has("witnesses"):
		return payload["witnesses"]
	return payload[&"witnesses"]


func _event_actor(payload: Dictionary) -> String:
	if payload.has("actor"):
		return String(payload["actor"])
	return ""


func _event_target(payload: Dictionary) -> String:
	if payload.has("target"):
		return String(payload["target"])
	if payload.has("object"):
		return String(payload["object"])
	return ""


func _event_place(payload: Dictionary) -> String:
	if payload.has("place"):
		return String(payload["place"])
	return _event_target(payload)


func _trace_event_witness(
	agent: StringName,
	mode: StringName,
	event_name: String,
	key: String,
	value: Variant
) -> void:
	if trace == null or not trace.enabled:
		return
	var shown := ""
	if value != null:
		shown = str(value)
	var fields := {
		"agent": String(agent),
		"event": event_name,
		"key": key,
		"mode": String(mode),
		"value": shown,
		"who": String(agent),
	}
	if not _trace_allows(fields):
		return
	trace_add("event_witness", fields)
	print(
		"wyrd event_witness agent=%s mode=%s event=%s key=%s value=%s"
		% [fields["agent"], fields["mode"], fields["event"], fields["key"], fields["value"]]
	)


func _trace_evidence(event_name: String, key: String, value: Variant, until: int) -> void:
	if trace == null or not trace.enabled:
		return
	var until_text := ""
	if until >= 0:
		until_text = str(until)
	var fields := {
		"event": event_name,
		"key": key,
		"until": until_text,
		"value": str(value),
		"who": "",
	}
	if not _trace_allows(fields):
		return
	trace_add("evidence", fields)
	print(
		"wyrd evidence event=%s key=%s value=%s until=%s"
		% [fields["event"], fields["key"], fields["value"], fields["until"]]
	)


func _flush_collected() -> PackedInt32Array:
	var indexes := PackedInt32Array()
	var pending: Array = _collected.keys()
	pending.sort()
	for key in pending:
		indexes.append(int(key))
	_collected.clear()
	var ran := _queue.recheck_some(indexes, Callable(self, &"_recheck"))
	if events != null:
		events.last_flush = ran.size()
		events.last_wave = 1
	return ran


func _reset_event_memory() -> void:
	_emit_seq = 0
	_collecting = false
	_collected.clear()
	_locals.clear()
	if events != null:
		events.reset_session()
	if quests != null:
		quests.clear_event_fires()


func _payload_problem(event_name: StringName, payload: Dictionary) -> String:
	if _content == null or not _content.events.has(String(event_name)):
		return "unknown event \"%s\"" % String(event_name)
	var event := _content.events[String(event_name)] as WyrdEventDef
	if event == null:
		return "unknown event \"%s\"" % String(event_name)
	var incoming := _payload_strings(payload)
	incoming.erase("witnesses")
	var declared := {}
	for field in event.fields:
		declared[str(field.get("name", ""))] = str(field.get("type", ""))
	var names: Array = incoming.keys()
	names.sort()
	for name in names:
		if not declared.has(String(name)):
			return "unknown field \"%s\"" % String(name)
		if not _field_ok(String(declared[String(name)]), incoming[name]):
			return "field \"%s\" is not %s" % [String(name), String(declared[String(name)])]
	var required: Array = declared.keys()
	required.sort()
	for name in required:
		if not incoming.has(String(name)):
			return "missing field \"%s\"" % String(name)
	return ""


func _normalize_payload(event_name: StringName, payload: Dictionary) -> Dictionary:
	var event := _content.events[String(event_name)] as WyrdEventDef
	var incoming := _payload_strings(payload)
	var out := {}
	if event == null:
		return out
	for field in event.fields:
		var name := str(field.get("name", ""))
		out[name] = _coerce_field(str(field.get("type", "")), incoming.get(name))
	return out


func _payload_strings(payload: Dictionary) -> Dictionary:
	var out := {}
	for key in payload.keys():
		out[String(key)] = payload[key]
	return out


func _field_ok(type_name: String, value: Variant) -> bool:
	match type_name:
		"bool":
			return value is bool
		"int":
			return typeof(value) == TYPE_INT
		"float":
			return value is float or typeof(value) == TYPE_INT
		"symbol":
			return value is String or value is StringName
		_:
			return false


func _coerce_field(type_name: String, value: Variant) -> Variant:
	if type_name == "symbol":
		return StringName(str(value))
	if type_name == "float" and typeof(value) == TYPE_INT:
		return float(value)
	return value


func _as_ints(values: PackedInt32Array) -> Array:
	var rows: Array = []
	for value in values:
		rows.append(int(value))
	return rows


func _key_list(keys: PackedStringArray) -> Array:
	var rows: Array = []
	for key in keys:
		rows.append(String(key))
	return rows


func loaded_fact_key() -> String:
	return _rpn.last_fact_key


func _on_deed(_deed: Dictionary) -> void:
	_mark_calls(_DEED_CALLS)


func _on_perceived(agent: StringName, mode: StringName, verb: StringName) -> void:
	if trace == null or not trace.enabled:
		return
	var shown := ""
	if not _perception_key.is_empty() and _perception_value != null:
		shown = str(_perception_value)
	var fields := {
		"agent": String(agent),
		"key": _perception_key,
		"mode": String(mode),
		"value": shown,
		"verb": String(verb),
		"who": String(agent),
	}
	if not _trace_allows(fields):
		return
	trace_add("perception", fields)
	print(
		"wyrd perception agent=%s mode=%s verb=%s key=%s value=%s"
		% [fields["agent"], fields["mode"], fields["verb"], fields["key"], fields["value"]]
	)


func _on_role(_role: StringName, _old_holder: StringName, _new_holder: StringName) -> void:
	_mark_calls(_ROLE_CALLS)


func _on_role_vacant(_role: StringName) -> void:
	_mark_calls(_ROLE_CALLS)


func _on_social() -> void:
	_mark_calls(_DEED_CALLS)


func _members(group: StringName) -> PackedStringArray:
	var world := adapter(WyrdWorldAdapter)
	if world is WyrdWorldAdapter:
		return (world as WyrdWorldAdapter).members(group)
	return PackedStringArray()


func _adapter_groups(agent: StringName) -> PackedStringArray:
	var world := adapter(WyrdWorldAdapter)
	if world is WyrdWorldAdapter:
		return (world as WyrdWorldAdapter).groups_of(agent)
	return PackedStringArray()


func _as_groups(value: Variant) -> PackedStringArray:
	if value is PackedStringArray:
		return value
	var rows := PackedStringArray()
	if value is Array:
		for item in value:
			if item != null:
				rows.append(String(item))
	return rows


func _mark_calls(names: PackedStringArray) -> void:
	if _content == null or names.is_empty():
		return
	var hits := _content.indexes_for_calls(names)
	if not hits.is_empty():
		_queue.mark(hits)


func _tracked_calls() -> PackedStringArray:
	var names := _DEED_CALLS.duplicate()
	for name in _ROLE_CALLS:
		if not names.has(name):
			names.append(name)
	return names


func _clear_belief_cache() -> void:
	if _ctx != null:
		_ctx.clear_belief_cache()


func _spatial() -> WyrdSpatialAdapter:
	var found := adapter(WyrdSpatialAdapter)
	if found is WyrdSpatialAdapter:
		return found as WyrdSpatialAdapter
	return null


func _election() -> WyrdElectionAdapter:
	var found := adapter(WyrdElectionAdapter)
	if found is WyrdElectionAdapter:
		return found as WyrdElectionAdapter
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
