class_name WyrdStoryletDeck
extends RefCounted

## Seeded draw of a storylet line set. Not a director.
##
## @experimental
## A [code]line[/code] body and a [code]scene[/code] body write no row.
## A [code]set[/code] shuffles with [method WyrdRng.for_decision] on the
## [constant STREAM] stream, the storylet id, and the cycle number.
## The row stores that order, a cursor, and the cycle. The next cycle starts
## when the cursor reaches the end. Cooldown is not read here.

const STREAM: StringName = &"storylet_lines"

var _content: WyrdContent
var _seed: int = 0
var _rows: Dictionary = {}


func bind(content: WyrdContent) -> void:
	_content = content
	_rows.clear()


func clear() -> void:
	_rows.clear()


func set_seed(seed_value: int) -> void:
	_seed = seed_value


func draw(id: String) -> Dictionary:
	var story := _story(id)
	if story == null:
		if _content == null:
			push_error("Wyrd.storylets.draw: load content before drawing a storylet")
		else:
			push_error("Wyrd.storylets.draw: unknown storylet \"%s\"" % id)
		return {}
	if story.body_kind == &"line":
		if story.lines.is_empty():
			push_error("Wyrd.storylets.draw: storylet \"%s\" has no line" % id)
			return {}
		return _drawn(story, story.lines[0].line_id, 0)
	if story.body_kind == &"scene":
		return _drawn(story, "", 0)
	if story.body_kind != &"set":
		push_error("Wyrd.storylets.draw: storylet \"%s\" has no body" % id)
		return {}
	if story.lines.is_empty():
		push_error("Wyrd.storylets.draw: storylet \"%s\" has no lines" % id)
		return {}
	var row := _ensure(story)
	var order: PackedStringArray = row["order"]
	var cursor := int(row["cursor"])
	var line_id := String(order[cursor])
	row["cursor"] = cursor + 1
	return _drawn(story, line_id, int(row["cycle"]))


func export_state() -> Dictionary:
	if _rows.is_empty():
		return {}
	var names: Array = _rows.keys()
	names.sort()
	var out := {}
	for id in names:
		var row: Dictionary = _rows[id]
		var order: Array = []
		var packed: PackedStringArray = row.get("order", PackedStringArray())
		for line_id in packed:
			order.append(String(line_id))
		out[String(id)] = {
			"cursor": int(row.get("cursor", 0)),
			"cycle": int(row.get("cycle", 0)),
			"order": order,
		}
	return out


## Drops ids that are no longer in the set. Appends new ids in source order.
## The cursor is clamped to the new order. It is not remapped.
func import_state(data: Dictionary) -> void:
	_rows.clear()
	if _content == null:
		return
	for key in data.keys():
		var id := String(key)
		var story := _story(id)
		if story == null or story.body_kind != &"set":
			continue
		if not (data[key] is Dictionary):
			continue
		var raw: Dictionary = data[key]
		var source := PackedStringArray()
		for line in story.lines:
			if not line.line_id.is_empty():
				source.append(line.line_id)
		var order := PackedStringArray()
		var seen := {}
		var saved: Variant = raw.get("order", [])
		if saved is Array:
			for item in saved:
				var line_id := String(item)
				if not source.has(line_id) or seen.has(line_id):
					continue
				order.append(line_id)
				seen[line_id] = true
		for line_id in source:
			if seen.has(line_id):
				continue
			order.append(line_id)
			seen[line_id] = true
		if order.is_empty():
			continue
		var cursor := _whole(raw.get("cursor", 0))
		var cycle := _whole(raw.get("cycle", 0))
		if cycle < 0:
			cycle = 0
		if cursor < 0:
			cursor = 0
		if cursor > order.size():
			cursor = order.size()
		_rows[id] = {"cursor": cursor, "cycle": cycle, "order": order}


func _story(id: String) -> WyrdStoryletDef:
	if _content == null:
		return null
	var found: Variant = _content.storylets.get(id, null)
	if found is WyrdStoryletDef:
		return found
	return null


func _ensure(story: WyrdStoryletDef) -> Dictionary:
	var id := story.id
	if not _rows.has(id):
		var created := {"cursor": 0, "cycle": 0, "order": _shuffle(id, 0, story.lines)}
		_rows[id] = created
		return created
	var row: Dictionary = _rows[id]
	var order: PackedStringArray = row.get("order", PackedStringArray())
	if int(row.get("cursor", 0)) < order.size():
		return row
	var cycle := int(row.get("cycle", 0)) + 1
	var next := {"cursor": 0, "cycle": cycle, "order": _shuffle(id, cycle, story.lines)}
	_rows[id] = next
	return next


func _shuffle(id: String, cycle: int, lines: Array[WyrdLineDef]) -> PackedStringArray:
	var order := PackedStringArray()
	for line in lines:
		order.append(line.line_id)
	if order.size() < 2:
		return order
	var rng := WyrdRng.for_decision(_seed, STREAM, StringName(id), cycle)
	var index := order.size() - 1
	while index > 0:
		var swap_at := rng.randi_bounded(index + 1)
		var swap := order[index]
		order[index] = order[swap_at]
		order[swap_at] = swap
		index -= 1
	return order


func _drawn(story: WyrdStoryletDef, line_id: String, cycle: int) -> Dictionary:
	return {
		"body": String(story.body_kind),
		"cycle": cycle,
		"id": story.id,
		"line_id": line_id,
		"scene": story.scene_id,
	}


func _whole(value: Variant) -> int:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)
	return 0
