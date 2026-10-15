class_name WyrdDeedLog
extends RefCounted

## Append-only deed log with hour-bucketed decay. No compaction.
##
## @experimental
## Rows are parallel packed arrays. Indexes are by actor, target, and verb.
## [code]now[/code] is bucketed with [member WyrdConfig.hour_bucket_minutes].
## Memorable rows keep full magnitude. A half-life of 0 does not decay.
## Sums are rounded to 6 decimal places before they are returned.
## Witnesses [code]auto[/code] ask [method WyrdSpatialAdapter.witnesses_of].
## An explicit list is stored as given, sorted by id.

signal deed_recorded(deed: Dictionary)

const ROUND_SCALE: float = 1000000.0

var clock: Callable = Callable()
var config_of: Callable = Callable()
var spatial_of: Callable = Callable()

var _next: int = 1
var _id: PackedInt32Array = PackedInt32Array()
var _t: PackedInt32Array = PackedInt32Array()
var _verb: PackedStringArray = PackedStringArray()
var _actor: PackedStringArray = PackedStringArray()
var _target: PackedStringArray = PackedStringArray()
var _place: PackedStringArray = PackedStringArray()
var _magnitude: PackedFloat64Array = PackedFloat64Array()
var _visibility: PackedStringArray = PackedStringArray()
var _memorable: PackedByteArray = PackedByteArray()
var _tag_at: PackedInt32Array = PackedInt32Array()
var _tag_n: PackedInt32Array = PackedInt32Array()
var _wit_at: PackedInt32Array = PackedInt32Array()
var _wit_n: PackedInt32Array = PackedInt32Array()
var _tags: PackedStringArray = PackedStringArray()
var _witnesses: PackedStringArray = PackedStringArray()
var _by_actor: Dictionary = {}
var _by_target: Dictionary = {}
var _by_verb: Dictionary = {}


func export_state() -> Dictionary:
	var rows: Array = []
	for i in size():
		var row := row_at(i)
		rows.append({
			"actor": String(row["actor"]),
			"id": int(row["id"]),
			"magnitude": float(row["magnitude"]),
			"memorable": bool(row["memorable"]),
			"place": String(row["place"]),
			"t": int(row["t"]),
			"tags": _string_list(row["tags"]),
			"target": String(row["target"]),
			"verb": String(row["verb"]),
			"visibility": String(row["visibility"]),
			"witnesses": _string_list(row["witnesses"]),
		})
	return {"next": _next, "rows": rows}


func import_state(data: Dictionary) -> void:
	clear()
	for item in data.get("rows", []):
		if not (item is Dictionary):
			continue
		var row: Dictionary = item
		var tags := _packed(row.get("tags", []))
		var witnesses := _packed(row.get("witnesses", []))
		var index := _id.size()
		_id.append(int(row.get("id", 0)))
		_t.append(int(row.get("t", 0)))
		_verb.append(String(row.get("verb", "")))
		_actor.append(String(row.get("actor", "")))
		_target.append(String(row.get("target", "")))
		_place.append(String(row.get("place", "")))
		_magnitude.append(float(row.get("magnitude", 1.0)))
		_visibility.append(String(row.get("visibility", "public")))
		_memorable.append(1 if bool(row.get("memorable", false)) else 0)
		_tag_at.append(_tags.size())
		_tag_n.append(tags.size())
		for tag in tags:
			_tags.append(tag)
		_wit_at.append(_witnesses.size())
		_wit_n.append(witnesses.size())
		for wit in witnesses:
			_witnesses.append(wit)
		_index(_by_actor, StringName(_actor[index]), index)
		_index(_by_target, StringName(_target[index]), index)
		_index(_by_verb, StringName(_verb[index]), index)
	var next := int(data.get("next", 1))
	_next = next if next > 0 else 1


func _string_list(value: Variant) -> Array:
	var rows: Array = []
	if value is PackedStringArray:
		for item in value:
			rows.append(String(item))
	elif value is Array:
		for item in value:
			rows.append(String(item))
	return rows


func _packed(value: Variant) -> PackedStringArray:
	var rows := PackedStringArray()
	if value is Array:
		for item in value:
			rows.append(String(item))
	return rows


func clear() -> void:
	_next = 1
	_id = PackedInt32Array()
	_t = PackedInt32Array()
	_verb = PackedStringArray()
	_actor = PackedStringArray()
	_target = PackedStringArray()
	_place = PackedStringArray()
	_magnitude = PackedFloat64Array()
	_visibility = PackedStringArray()
	_memorable = PackedByteArray()
	_tag_at = PackedInt32Array()
	_tag_n = PackedInt32Array()
	_wit_at = PackedInt32Array()
	_wit_n = PackedInt32Array()
	_tags = PackedStringArray()
	_witnesses = PackedStringArray()
	_by_actor.clear()
	_by_target.clear()
	_by_verb.clear()


func size() -> int:
	return _id.size()


func index_size(which: StringName, key: StringName) -> int:
	var table := _index_table(which)
	if table.is_empty() or not table.has(String(key)):
		return 0
	return (table[String(key)] as PackedInt32Array).size()


func record(
	verb: StringName,
	actor: StringName,
	target: StringName = &"",
	place: StringName = &"",
	tags: PackedStringArray = PackedStringArray(),
	magnitude: float = 1.0,
	witnesses: Variant = null,
	visibility: StringName = &"public",
	memorable: bool = false
) -> int:
	if verb == &"" or actor == &"":
		push_error("WyrdDeedLog.record: verb and actor are required")
		return -1
	var row := _id.size()
	var stamp := _now()
	var shown := visibility if visibility != &"" else &"public"
	var tag_rows := _sorted(tags)
	var wit_rows := _witness_list(actor, target, place, witnesses)
	_id.append(_next)
	_next += 1
	_t.append(stamp)
	_verb.append(String(verb))
	_actor.append(String(actor))
	_target.append(String(target))
	_place.append(String(place))
	_magnitude.append(magnitude)
	_visibility.append(String(shown))
	_memorable.append(1 if memorable else 0)
	_tag_at.append(_tags.size())
	_tag_n.append(tag_rows.size())
	for tag in tag_rows:
		_tags.append(tag)
	_wit_at.append(_witnesses.size())
	_wit_n.append(wit_rows.size())
	for wit in wit_rows:
		_witnesses.append(wit)
	_index(_by_actor, actor, row)
	_index(_by_target, target, row)
	_index(_by_verb, verb, row)
	var deed := row_at(row)
	deed_recorded.emit(deed)
	return int(deed["id"])


func count_matching(
	actor: StringName,
	verb: Variant = null,
	target: Variant = null,
	place: Variant = null,
	within: Variant = null,
	tags: PackedStringArray = PackedStringArray()
) -> int:
	return _scan(actor, verb, target, place, within, tags, false)


func score_matching(
	actor: StringName,
	verb: Variant = null,
	target: Variant = null,
	place: Variant = null,
	within: Variant = null,
	tags: PackedStringArray = PackedStringArray()
) -> float:
	return float(_scan(actor, verb, target, place, within, tags, true))


func verb_at(index: int) -> StringName:
	return StringName(_verb[index])


func actor_at(index: int) -> StringName:
	return StringName(_actor[index])


func target_at(index: int) -> StringName:
	return StringName(_target[index])


func witnessed(index: int, agent: StringName) -> bool:
	return _has_in(_witnesses, _wit_at[index], _wit_n[index], String(agent))


func weight_at(index: int) -> float:
	if _memorable[index] != 0:
		return _magnitude[index]
	var life := _half_life(StringName(_verb[index]))
	if life <= 0.0:
		return _magnitude[index]
	var age := float(_bucketed(_now()) - int(_t[index]))
	if age <= 0.0:
		return _magnitude[index]
	return _magnitude[index] * pow(0.5, age / life)


func row_at(index: int) -> Dictionary:
	return {
		"actor": StringName(_actor[index]),
		"id": int(_id[index]),
		"magnitude": _magnitude[index],
		"memorable": _memorable[index] != 0,
		"place": StringName(_place[index]),
		"t": int(_t[index]),
		"tags": _slice(_tags, _tag_at[index], _tag_n[index]),
		"target": StringName(_target[index]),
		"verb": StringName(_verb[index]),
		"visibility": StringName(_visibility[index]),
		"witnesses": _slice(_witnesses, _wit_at[index], _wit_n[index]),
	}


static func round_sum(value: float) -> float:
	return round(value * ROUND_SCALE) / ROUND_SCALE


func _scan(
	actor: StringName,
	verb: Variant,
	target: Variant,
	place: Variant,
	within: Variant,
	tags: PackedStringArray,
	as_score: bool
) -> Variant:
	var verb_name := _opt_name(verb)
	var target_name := _opt_name(target)
	var place_name := _opt_name(place)
	var now := _now()
	var rows := _candidates(actor, verb_name, target_name)
	var count := 0
	var total := 0.0
	for index in rows:
		if not _hit(int(index), actor, verb_name, target_name, place_name, within, tags, now):
			continue
		count += 1
		if as_score:
			total += weight_at(int(index))
	if as_score:
		return round_sum(total)
	return count


func _hit(
	index: int,
	actor: StringName,
	verb: StringName,
	target: StringName,
	place: StringName,
	within: Variant,
	tags: PackedStringArray,
	now: int
) -> bool:
	if actor != &"" and _actor[index] != String(actor):
		return false
	if verb != &"" and _verb[index] != String(verb):
		return false
	if target != &"" and _target[index] != String(target):
		return false
	if place != &"" and _place[index] != String(place):
		return false
	if within != null and now - int(_t[index]) > int(within):
		return false
	for tag in tags:
		if not _has_in(_tags, _tag_at[index], _tag_n[index], tag):
			return false
	return true


func _candidates(actor: StringName, verb: StringName, target: StringName) -> PackedInt32Array:
	var best := PackedInt32Array()
	var chosen := false
	if actor != &"":
		best = _copy_index(_by_actor, actor)
		chosen = true
	if verb != &"":
		var rows := _copy_index(_by_verb, verb)
		if not chosen or rows.size() < best.size():
			best = rows
			chosen = true
	if target != &"":
		var rows := _copy_index(_by_target, target)
		if not chosen or rows.size() < best.size():
			best = rows
			chosen = true
	if chosen:
		return best
	best.resize(_id.size())
	for i in _id.size():
		best[i] = i
	return best


func _witness_list(actor: StringName, target: StringName, place: StringName, witnesses: Variant) -> PackedStringArray:
	if witnesses == null:
		return PackedStringArray()
	if witnesses is StringName or witnesses is String:
		if String(witnesses) != "auto":
			push_error("WyrdDeedLog.record: witnesses must be auto or a list")
			return PackedStringArray()
		var spatial := _spatial()
		if spatial == null:
			return PackedStringArray()
		return _sorted(spatial.witnesses_of(actor, target, place))
	if witnesses is PackedStringArray:
		return _sorted(witnesses)
	if witnesses is Array:
		var rows := PackedStringArray()
		for item in witnesses:
			if item != null:
				rows.append(String(item))
		return _sorted(rows)
	push_error("WyrdDeedLog.record: witnesses must be auto or a list")
	return PackedStringArray()


func _sorted(values: PackedStringArray) -> PackedStringArray:
	var copy := values.duplicate()
	copy.sort()
	return copy


func _index(table: Dictionary, key: StringName, row: int) -> void:
	if key == &"":
		return
	var text := String(key)
	var rows := PackedInt32Array()
	if table.has(text):
		rows = table[text]
	rows.append(row)
	table[text] = rows


func _copy_index(table: Dictionary, key: StringName) -> PackedInt32Array:
	var text := String(key)
	if not table.has(text):
		return PackedInt32Array()
	return (table[text] as PackedInt32Array).duplicate()


func _index_table(which: StringName) -> Dictionary:
	match String(which):
		"actor":
			return _by_actor
		"target":
			return _by_target
		"verb":
			return _by_verb
		_:
			return {}


func _slice(pool: PackedStringArray, at: int, count: int) -> PackedStringArray:
	var rows := PackedStringArray()
	for i in count:
		rows.append(pool[at + i])
	return rows


func _has_in(pool: PackedStringArray, at: int, count: int, needle: String) -> bool:
	for i in count:
		if pool[at + i] == needle:
			return true
	return false


func _opt_name(value: Variant) -> StringName:
	if value == null:
		return &""
	return StringName(str(value))


func _now() -> int:
	if clock.is_valid():
		return int(clock.call())
	return 0


func _bucketed(now: int) -> int:
	var size := _bucket()
	if size <= 0:
		return now
	return int(now / float(size)) * size


func _bucket() -> int:
	var cfg := _config()
	if cfg == null:
		return 60
	return maxi(cfg.hour_bucket_minutes, 0)


func _half_life(verb: StringName) -> float:
	var cfg := _config()
	if cfg == null:
		return 0.0
	return cfg.half_life_for(verb)


func _config() -> WyrdConfig:
	if not config_of.is_valid():
		return null
	var cfg: Variant = config_of.call()
	if cfg is WyrdConfig:
		return cfg as WyrdConfig
	return null


func _spatial() -> WyrdSpatialAdapter:
	if not spatial_of.is_valid():
		return null
	var found: Variant = spatial_of.call()
	if found is WyrdSpatialAdapter:
		return found as WyrdSpatialAdapter
	return null
