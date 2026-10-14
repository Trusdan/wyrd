class_name WyrdSocial
extends RefCounted

## Relationship baselines, deed axes, and disposition.
##
## @experimental
## Kinds and baselines are stored. Axes add a configured verb delta times the
## deed's decayed weight. A deed counts for [code]axis(observer, subject)[/code]
## when [code]subject[/code] did it and [code]observer[/code] was the target or
## a witness. The default disposition is [code]disposition_default + affinity / 2[/code],
## clamped to 0..100. A host may [method register_formula]; the callable receives
## [code](a, b, axes)[/code] and is not saved. Reputation and kind-scaled deltas
## are M5.

var deeds: WyrdDeedLog
var config_of: Callable = Callable()
var formula: Callable = Callable()
var on_changed: Callable = Callable()

var _kinds: Dictionary = {}
var _baseline: Dictionary = {}


func clear_state() -> void:
	_kinds.clear()
	_baseline.clear()


func register_formula(fn: Callable) -> void:
	if not fn.is_valid():
		push_error("WyrdSocial.register_formula: missing callable")
		return
	formula = fn
	_touch()


func set_kind(source: StringName, target: StringName, kind: StringName) -> void:
	if source == &"" or target == &"" or kind == &"":
		push_error("WyrdSocial.set_kind: missing source, target, or kind")
		return
	if not _kinds.has(source):
		_kinds[source] = {}
	var outgoing: Dictionary = _kinds[source]
	if not outgoing.has(target):
		outgoing[target] = {}
	(outgoing[target] as Dictionary)[kind] = true
	_touch()


func has_kind(source: StringName, target: StringName, kind: StringName) -> bool:
	if not _kinds.has(source):
		return false
	var outgoing: Dictionary = _kinds[source]
	if not outgoing.has(target):
		return false
	return (outgoing[target] as Dictionary).has(kind)


func targets(source: StringName, kind: StringName) -> PackedStringArray:
	var rows := PackedStringArray()
	if not _kinds.has(source):
		return rows
	var outgoing: Dictionary = _kinds[source]
	for target in outgoing.keys():
		if (outgoing[target] as Dictionary).has(kind):
			rows.append(String(target))
	rows.sort()
	return rows


func set_baseline(source: StringName, target: StringName, axis_name: StringName, value: float) -> void:
	_baseline[_edge(source, target, axis_name)] = value
	_touch()


func _touch() -> void:
	if on_changed.is_valid():
		on_changed.call()


func axis(source: StringName, target: StringName, axis_name: StringName) -> float:
	var total := _base(source, target, axis_name)
	if deeds != null and source != &"" and target != &"":
		var cfg := _config()
		for i in deeds.size():
			if deeds.actor_at(i) != target:
				continue
			if deeds.target_at(i) != source and not deeds.witnessed(i, source):
				continue
			var delta := 0.0
			if cfg != null:
				delta = cfg.axis_delta(deeds.verb_at(i), axis_name)
			total += delta * deeds.weight_at(i)
	return WyrdDeedLog.round_sum(total)


func affinity(source: StringName, target: StringName) -> float:
	return axis(source, target, &"affinity")


func disposition(source: StringName, target: StringName) -> int:
	var axes := _axes(source, target)
	var raw := 0
	if formula.is_valid():
		raw = int(formula.call(source, target, axes))
	else:
		var base := 50
		var cfg := _config()
		if cfg != null:
			base = cfg.disposition_default
		raw = int(round(float(base) + float(axes[&"affinity"]) / 2.0))
	return clampi(raw, 0, 100)


func _axes(source: StringName, target: StringName) -> Dictionary:
	var names := PackedStringArray(["affinity"])
	var cfg := _config()
	if cfg != null:
		for axis_name in cfg.axis_names:
			if not names.has(axis_name):
				names.append(axis_name)
	var axes := {}
	for axis_name in names:
		axes[StringName(axis_name)] = axis(source, target, StringName(axis_name))
	return axes


func _base(source: StringName, target: StringName, axis_name: StringName) -> float:
	var key := _edge(source, target, axis_name)
	if not _baseline.has(key):
		return 0.0
	return float(_baseline[key])


func _edge(source: StringName, target: StringName, axis_name: StringName) -> String:
	return "%s\t%s\t%s" % [String(source), String(target), String(axis_name)]


func _config() -> WyrdConfig:
	if not config_of.is_valid():
		return null
	var cfg: Variant = config_of.call()
	if cfg is WyrdConfig:
		return cfg as WyrdConfig
	return null
