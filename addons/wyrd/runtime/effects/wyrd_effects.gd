class_name WyrdEffects
extends RefCounted

## Runs the six slice effects.
##
## @experimental
## [code]set[/code] and [code]inc[/code] write stored facts and keep provenance
## [code]scene[/code], [code]choice[/code], and [code]time[/code] (game minutes).
## A [code]do[/code] failure returns its [code]on_fail[/code] target: a label in
## a scene, or a stage in a quest. Set literals in deed arguments are read from
## the stored argument text, because the expression emitter does not push a set
## value. Out-of-slice effects cannot appear here; the compiler rejects them.

signal topic_unlocked(topic: StringName)
signal outcome_changed(quest_id: String, branch: StringName, value: StringName)

var runtime: WyrdRuntime
var quest_id: String = ""
var scene_id: String = ""
var choice_id: String = ""
var provenance: Dictionary = {}


func bind(host: WyrdRuntime) -> void:
	runtime = host


func export_state() -> Dictionary:
	var out := {}
	var keys: Array = provenance.keys()
	keys.sort()
	for key in keys:
		var row: Dictionary = provenance[key]
		out[String(key)] = {
			"choice": String(row.get("choice", "")),
			"scene": String(row.get("scene", "")),
			"time": int(row.get("time", 0)),
		}
	return out


func import_state(data: Dictionary) -> void:
	provenance.clear()
	var keys: Array = data.keys()
	keys.sort()
	for key in keys:
		var row: Variant = data[key]
		if not (row is Dictionary):
			continue
		var item: Dictionary = row
		provenance[String(key)] = {
			"choice": String(item.get("choice", "")),
			"scene": String(item.get("scene", "")),
			"time": int(item.get("time", 0)),
		}


func clear() -> void:
	quest_id = ""
	scene_id = ""
	choice_id = ""
	provenance.clear()


func provenance_of(key: String) -> Dictionary:
	if not provenance.has(key):
		return {}
	return (provenance[key] as Dictionary).duplicate()


func run_all(rows: Array) -> String:
	for row in rows:
		var effect := row as WyrdEffectDef
		if effect == null:
			continue
		var divert := run_one(effect)
		if divert != "":
			return divert
	return ""


func run_one(effect: WyrdEffectDef) -> String:
	if effect == null or runtime == null:
		return ""
	match effect.kind:
		&"set":
			_write(effect, false)
		&"inc":
			_write(effect, true)
		&"record_deed":
			_deed(effect)
		&"unlock_topic":
			if effect.topic.is_empty():
				push_error("WyrdEffects: unlock topic needs an id")
			else:
				topic_unlocked.emit(StringName(effect.topic))
		&"do":
			return _command(effect)
		&"outcome":
			outcome_changed.emit(quest_id, StringName(effect.branch), StringName(effect.outcome))
		_:
			push_error("WyrdEffects: effect \"%s\" is not in this slice" % String(effect.kind))
	return ""


func _write(effect: WyrdEffectDef, is_inc: bool) -> void:
	var key := effect.fact_key
	if key.is_empty() or key.contains("{"):
		push_error("WyrdEffects: \"%s\" is not a concrete stored fact" % key)
		return
	var amount: Variant = runtime.eval_value(effect.value)
	var value := amount
	if is_inc:
		var current: Variant = runtime.facts.get_in(StringName(key))
		var base: Variant = 0 if current == null else current
		if amount == null or base == null:
			push_error("WyrdEffects: inc \"%s\" has no numeric value" % key)
			return
		value = base + amount
	if not runtime.facts.set_in(StringName(key), value):
		return
	provenance[key] = {"choice": choice_id, "scene": scene_id, "time": runtime.now_minutes()}


func _deed(effect: WyrdEffectDef) -> void:
	var args := _arg_map(effect)
	var actor := _name(_value(args, "actor"))
	if actor == &"":
		push_error("WyrdEffects: deed needs an actor")
		return
	var witnesses: Variant = null
	if args.has("witnesses"):
		var raw: Variant = _value(args, "witnesses")
		if raw is String or raw is StringName:
			witnesses = StringName(str(raw))
		else:
			witnesses = _strings(raw, _text(args, "witnesses"))
	runtime.deeds.record(
		StringName(effect.verb),
		actor,
		_name(_value(args, "target")),
		_name(_value(args, "place")),
		_strings(_value(args, "tags"), _text(args, "tags")),
		float(_value(args, "magnitude")) if args.has("magnitude") and _value(args, "magnitude") != null else 1.0,
		witnesses,
		_name(_value(args, "visibility")) if args.has("visibility") else &"public",
		bool(_value(args, "memorable")) if args.has("memorable") else false
	)


func _command(effect: WyrdEffectDef) -> String:
	var adapter := runtime.adapter(WyrdActionAdapter) as WyrdActionAdapter
	var cmd := WyrdCommand.new()
	cmd.name = StringName(effect.command)
	var args := _arg_map(effect)
	for name in args.keys():
		cmd.args[name] = _value(args, String(name))
	var result := WyrdCommandResult.failed(&"no_adapter")
	if adapter == null:
		push_error("WyrdEffects: no action adapter for \"%s\"" % effect.command)
	else:
		result = adapter.execute(cmd)
	var ok := result != null and result.is_ok()
	var reason := ""
	if result != null:
		reason = String(result.reason)
	if runtime != null:
		runtime.trace_add("command", {"name": String(effect.command), "ok": ok, "reason": reason})
	if ok:
		return ""
	if effect.on_fail.is_empty():
		push_error("WyrdEffects: \"%s\" failed with no on_fail" % effect.command)
		return ""
	return effect.on_fail


func _arg_map(effect: WyrdEffectDef) -> Dictionary:
	var out := {}
	var positional := 0
	for row in effect.args:
		var spec: Dictionary = row
		var name := String(spec.get("name", ""))
		if name.is_empty():
			name = "#%d" % positional
			positional += 1
		out[name] = {"text": String(spec.get("text", "")), "value": runtime.eval_value(spec.get("compiled"))}
	return out


func _value(args: Dictionary, name: String) -> Variant:
	if not args.has(name):
		return null
	return (args[name] as Dictionary)["value"]


func _text(args: Dictionary, name: String) -> String:
	if not args.has(name):
		return ""
	return String((args[name] as Dictionary)["text"])


func _name(value: Variant) -> StringName:
	if value == null:
		return &""
	return StringName(str(value))


func _strings(value: Variant, text: String) -> PackedStringArray:
	var rows := PackedStringArray()
	if value is PackedStringArray:
		return value
	if value is Array:
		for item in value:
			if item != null:
				rows.append(str(item))
		return rows
	var body := text.strip_edges()
	if body.begins_with("[") and body.ends_with("]") and body.length() >= 2:
		body = body.substr(1, body.length() - 2)
		for part in body.split(","):
			var item := part.strip_edges()
			if not item.is_empty():
				rows.append(item)
	return rows
