class_name WyrdSocial
extends RefCounted

## Relationship baselines, deed axes, and disposition.
##
## @experimental
## Kinds and baselines are stored. Axes add a configured verb delta times the
## deed's decayed weight. A deed counts for [code]axis(observer, subject)[/code]
## when [code]subject[/code] did it and [code]observer[/code] was the target or
## a witness. A kind the observer holds toward the subject multiplies that
## delta by [method WyrdConfig.kind_scale]. Several matching kinds multiply.
## The baseline is not scaled. The default disposition is
## [code]disposition_default + affinity / 2[/code], clamped to 0..100. A host
## may [method register_formula]; the callable receives [code](a, b, axes)[/code]
## and is not saved. [method reputation] is the mean disposition of a group's
## members toward the subject. It is derived, not saved.

var deeds: WyrdDeedLog
var config_of: Callable = Callable()
var formula: Callable = Callable()
var on_changed: Callable = Callable()
## [code](group) -> PackedStringArray[/code]. Not saved.
var members_of: Callable = Callable()
## [code](subject, group, value, members)[/code]. Not saved.
var on_reputation: Callable = Callable()

var _kinds: Dictionary = {}
var _baseline: Dictionary = {}


func export_state() -> Dictionary:
	var kinds: Array = []
	var sources: Array = _kinds.keys()
	sources.sort()
	for source in sources:
		var outgoing: Dictionary = _kinds[source]
		var targets: Array = outgoing.keys()
		targets.sort()
		for target in targets:
			var bag: Dictionary = outgoing[target]
			var names: Array = bag.keys()
			names.sort()
			for kind in names:
				kinds.append({"kind": String(kind), "source": String(source), "target": String(target)})
	var baselines: Array = []
	var edges: Array = _baseline.keys()
	edges.sort()
	for edge in edges:
		var parts := String(edge).split("\t")
		if parts.size() != 3:
			continue
		baselines.append({
			"axis": parts[2],
			"source": parts[0],
			"target": parts[1],
			"value": float(_baseline[edge]),
		})
	return {"baselines": baselines, "kinds": kinds}


func import_state(data: Dictionary) -> void:
	clear_state()
	for item in data.get("kinds", []):
		if item is Dictionary:
			var row: Dictionary = item
			set_kind(StringName(str(row.get("source", ""))), StringName(str(row.get("target", ""))), StringName(str(row.get("kind", ""))))
	for item in data.get("baselines", []):
		if item is Dictionary:
			var row: Dictionary = item
			set_baseline(
				StringName(str(row.get("source", ""))),
				StringName(str(row.get("target", ""))),
				StringName(str(row.get("axis", ""))),
				float(row.get("value", 0.0))
			)


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


## A missing kind is a no-op.
func clear_kind(source: StringName, target: StringName, kind: StringName) -> void:
	if not has_kind(source, target, kind):
		return
	var outgoing: Dictionary = _kinds[source]
	var bag: Dictionary = outgoing[target]
	bag.erase(kind)
	if bag.is_empty():
		outgoing.erase(target)
	if outgoing.is_empty():
		_kinds.erase(source)
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


## A missing baseline is a no-op. Absence is the same as a baseline of 0.
func clear_baseline(source: StringName, target: StringName, axis_name: StringName) -> void:
	var key := _edge(source, target, axis_name)
	if not _baseline.has(key):
		return
	_baseline.erase(key)
	_touch()


func _touch() -> void:
	if on_changed.is_valid():
		on_changed.call()


func axis(source: StringName, target: StringName, axis_name: StringName) -> float:
	var total := _base(source, target, axis_name)
	if deeds != null and source != &"" and target != &"":
		var cfg := _config()
		var scale := _kind_scale(source, target, axis_name)
		for i in deeds.size():
			if deeds.actor_at(i) != target:
				continue
			if deeds.target_at(i) != source and not deeds.witnessed(i, source):
				continue
			var delta := 0.0
			if cfg != null:
				delta = cfg.axis_delta(deeds.verb_at(i), axis_name)
			total += delta * deeds.weight_at(i) * scale
	return WyrdDeedLog.round_sum(total)


## Mean disposition of [param group]'s members toward [param subject].
## The subject is skipped. Duplicate members count once. No members returns 0.
func reputation(subject: StringName, group: StringName) -> float:
	if subject == &"" or group == &"":
		return 0.0
	var listed := PackedStringArray()
	if members_of.is_valid():
		var raw: Variant = members_of.call(group)
		if raw is PackedStringArray:
			listed = raw
		elif raw is Array:
			for item in raw:
				if item != null:
					listed.append(String(item))
	var seen := {}
	var total := 0.0
	var count := 0
	for member in listed:
		var who := StringName(String(member))
		if who == &"" or who == subject or seen.has(who):
			continue
		seen[who] = true
		total += float(disposition(who, subject))
		count += 1
	var value := 0.0 if count == 0 else WyrdDeedLog.round_sum(total / float(count))
	if on_reputation.is_valid():
		on_reputation.call(subject, group, value, count)
	return value


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


func _kind_scale(observer: StringName, subject: StringName, axis_name: StringName) -> float:
	var cfg := _config()
	if cfg == null:
		return 1.0
	var scale := 1.0
	for row in cfg.scales_for(axis_name):
		var spec: Dictionary = row
		if has_kind(observer, subject, spec["kind"]):
			scale *= float(spec["scale"])
	return scale


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
