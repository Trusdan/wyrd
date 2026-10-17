class_name WyrdDeedLog
extends RefCounted

## Deed log with hour-bucketed decay. [method compact] merges interchangeable rows.
##
## @experimental
## Rows are parallel packed arrays. Indexes are by actor, target, and verb.
## [code]now[/code] is bucketed with [member WyrdConfig.hour_bucket_minutes].
## Memorable rows keep full magnitude. A half-life of 0 does not decay.
## Sums are rounded to 6 decimal places before they are returned.
## Witnesses [code]auto[/code] ask [method WyrdSpatialAdapter.witnesses_of].
## An explicit list is stored as given, sorted by id.
## Each witness stores a perception mode from [method WyrdSpatialAdapter.perceive]:
## [code]saw[/code], [code]heard[/code], or [code]inferred[/code]. An empty mode
## drops that witness. There is no rumour spread.

signal deed_recorded(deed: Dictionary)

const ROUND_SCALE: float = 1000000.0

var clock: Callable = Callable()
var config_of: Callable = Callable()
var spatial_of: Callable = Callable()
## Called once per stored witness: [code](agent, mode, verb)[/code]. Not saved.
var on_perceived: Callable = Callable()
## Called after [method compact]: [code]{before, after, merged, dropped}[/code]. Not saved.
var on_compact: Callable = Callable()

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
var _modes: PackedStringArray = PackedStringArray()
var _by_actor: Dictionary = {}
var _by_target: Dictionary = {}
var _by_verb: Dictionary = {}
## Bumps when the rows change. Combined with the decay bucket for relationship caches.
var _gen: int = 1


func export_state() -> Dictionary:
	var rows: Array = []
	for i in size():
		rows.append(_export_row(i))
	return {"next": _next, "rows": rows}


## Rows for [param actor], in log order. The array is the live index: do not mutate it.
func actor_indexes(actor: StringName) -> PackedInt32Array:
	var text := String(actor)
	if not _by_actor.has(text):
		return PackedInt32Array()
	return _by_actor[text]


## Changes when a row is added, replaced, or dropped, or when decay can move.
func weight_stamp() -> int:
	return WyrdHash.combine(_gen, _bucketed(_now()))


func import_state(data: Dictionary) -> void:
	clear()
	for item in data.get("rows", []):
		if item is Dictionary:
			_append_stored(item)
	var next := int(data.get("next", 1))
	_next = next if next > 0 else 1


## Merges rows that still count the same, and drops weight that has rounded to zero.
## Rows keep their minute, so a [code]within[/code] window does not grow. The newest id in a
## merged group is kept. [code]_next[/code] does not go backwards. Perception callbacks do not run.
func compact() -> int:
	var before := size()
	var plan := _compact_plan()
	var merged := int(plan["merged"])
	var dropped := int(plan["dropped"])
	if merged > 0 or dropped > 0:
		var next := _next
		var rows: Array = plan["rows"]
		clear()
		_next = next if next > 0 else 1
		for row in rows:
			_append_stored(row)
	var after := size()
	if on_compact.is_valid():
		on_compact.call({"after": after, "before": before, "dropped": dropped, "merged": merged})
	return after


## Defaults match [method _append_stored]: magnitude 1, memorable false, visibility
## public, minute 0, empty place and target, empty tags, and saw for every witness.
## Older saves that still write those fields load unchanged. Schema stays 2.
func _export_row(index: int) -> Dictionary:
	var row := {
		"actor": String(_actor[index]),
		"id": int(_id[index]),
		"verb": String(_verb[index]),
	}
	var magnitude := float(_magnitude[index])
	if magnitude != 1.0:
		row["magnitude"] = magnitude
	if _memorable[index] != 0:
		row["memorable"] = true
	var place := String(_place[index])
	if not place.is_empty():
		row["place"] = place
	var minute := int(_t[index])
	if minute != 0:
		row["t"] = minute
	var tag_n := int(_tag_n[index])
	if tag_n > 0:
		row["tags"] = _string_list(_slice(_tags, int(_tag_at[index]), tag_n))
	var target := String(_target[index])
	if not target.is_empty():
		row["target"] = target
	var wit_n := int(_wit_n[index])
	if wit_n > 0:
		var modes := _slice(_modes, int(_wit_at[index]), wit_n)
		var all_saw := true
		for mode in modes:
			if mode != "saw":
				all_saw = false
				break
		if not all_saw:
			row["perception"] = _string_list(modes)
		row["witnesses"] = _string_list(_slice(_witnesses, int(_wit_at[index]), wit_n))
	var visibility := String(_visibility[index])
	if visibility != "public":
		row["visibility"] = visibility
	return row


func _append_stored(row: Dictionary) -> void:
	var tags := _packed(row.get("tags", []))
	var witnesses := _packed(row.get("witnesses", []))
	var perception := _align_modes(witnesses, _packed(row.get("perception", [])))
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
	for i in witnesses.size():
		_witnesses.append(witnesses[i])
		_modes.append(perception[i])
	_index(_by_actor, StringName(_actor[index]), index)
	_index(_by_target, StringName(_target[index]), index)
	_index(_by_verb, StringName(_verb[index]), index)


func _compact_plan() -> Dictionary:
	var count := size()
	var latest := {}
	for i in count:
		var verb := String(_verb[i])
		var at := int(_wit_at[i])
		for offset in int(_wit_n[i]):
			latest["%s\t%s" % [_witnesses[at + offset], verb]] = i
	var drop := {}
	var tiny := 0.0
	var tiny_rows: Array = []
	for i in count:
		if round_sum(weight_at(i)) != 0.0:
			continue
		if _protects_mode(i, latest):
			continue
		tiny += weight_at(i)
		tiny_rows.append(i)
	if round_sum(tiny) == 0.0:
		for i in tiny_rows:
			drop[int(i)] = true
	var groups := {}
	for i in count:
		if drop.has(i):
			continue
		var key := _compact_key(i)
		var bucket: Array = groups.get(key, [])
		bucket.append(i)
		groups[key] = bucket
	var rows: Array = []
	var merged := 0
	for i in count:
		if drop.has(i):
			continue
		var bucket: Array = groups[_compact_key(i)]
		var last := int(bucket[bucket.size() - 1])
		if last != i:
			continue
		if bucket.size() == 1:
			rows.append(row_at(i))
			continue
		var combined := row_at(i)
		var magnitude := 0.0
		var kept_id := 0
		for member in bucket:
			var index := int(member)
			magnitude += float(_magnitude[index])
			kept_id = maxi(kept_id, int(_id[index]))
		combined["magnitude"] = round_sum(magnitude)
		combined["id"] = kept_id
		rows.append(combined)
		merged += bucket.size() - 1
	return {"dropped": drop.size(), "merged": merged, "rows": rows}


func _protects_mode(index: int, latest: Dictionary) -> bool:
	var verb := String(_verb[index])
	var at := int(_wit_at[index])
	for offset in int(_wit_n[index]):
		var key := "%s\t%s" % [_witnesses[at + offset], verb]
		if int(latest.get(key, -1)) == index:
			return true
	return false


func _compact_key(index: int) -> String:
	var tags := _slice(_tags, int(_tag_at[index]), int(_tag_n[index]))
	var wit := ""
	var at := int(_wit_at[index])
	for offset in int(_wit_n[index]):
		if offset > 0:
			wit += ","
		wit += "%s=%s" % [_witnesses[at + offset], _modes[at + offset]]
	return "%s\t%s\t%s\t%s\t%s\t%d\t%d\t%s\t%s" % [
		_verb[index],
		_actor[index],
		_target[index],
		_place[index],
		_visibility[index],
		int(_memorable[index]),
		int(_t[index]),
		",".join(tags),
		wit,
	]


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
	if value is PackedStringArray:
		return value
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
	_modes = PackedStringArray()
	_by_actor.clear()
	_by_target.clear()
	_by_verb.clear()
	_gen += 1


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
	var perceived := _perceived(actor, target, place, witnesses)
	var wit_rows: PackedStringArray = perceived["witnesses"]
	var mode_rows: PackedStringArray = perceived["modes"]
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
	for i in wit_rows.size():
		_witnesses.append(wit_rows[i])
		_modes.append(mode_rows[i])
		if on_perceived.is_valid():
			on_perceived.call(StringName(wit_rows[i]), StringName(mode_rows[i]), verb)
	_index(_by_actor, actor, row)
	_index(_by_target, target, row)
	_index(_by_verb, verb, row)
	_gen += 1
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


func witnesses_at(index: int) -> PackedStringArray:
	return _slice(_witnesses, int(_wit_at[index]), int(_wit_n[index]))


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
		"perception": _slice(_modes, _wit_at[index], _wit_n[index]),
		"visibility": StringName(_visibility[index]),
		"witnesses": _slice(_witnesses, _wit_at[index], _wit_n[index]),
	}


## Latest mode for [param agent] on [param verb], or empty when they never perceived it.
func mode_of(agent: StringName, verb: StringName) -> StringName:
	if agent == &"" or verb == &"":
		return &""
	var who := String(agent)
	for index in range(size() - 1, -1, -1):
		if StringName(_verb[index]) != verb:
			continue
		var at := int(_wit_at[index])
		for offset in int(_wit_n[index]):
			if _witnesses[at + offset] == who:
				return StringName(_modes[at + offset])
	return &""


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


func _perceived(actor: StringName, target: StringName, place: StringName, witnesses: Variant) -> Dictionary:
	var ids := _witness_list(actor, target, place, witnesses)
	var kept := PackedStringArray()
	var modes := PackedStringArray()
	var spatial := _spatial()
	for id in ids:
		var mode := &"saw"
		if spatial != null:
			mode = _perception_mode(spatial.perceive(StringName(id), actor, target, place))
		if mode == &"":
			continue
		kept.append(String(id))
		modes.append(String(mode))
	return {"modes": modes, "witnesses": kept}


func _perception_mode(raw: StringName) -> StringName:
	var text := String(raw)
	if text == "saw" or text == "heard" or text == "inferred":
		return StringName(text)
	if text.is_empty():
		return &""
	push_error("WyrdDeedLog.record: perception \"%s\" is not saw, heard, or inferred" % text)
	return &"saw"


func _align_modes(witnesses: PackedStringArray, perception: PackedStringArray) -> PackedStringArray:
	var modes := perception.duplicate()
	while modes.size() < witnesses.size():
		modes.append("saw")
	if modes.size() > witnesses.size():
		modes.resize(witnesses.size())
	return modes


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
