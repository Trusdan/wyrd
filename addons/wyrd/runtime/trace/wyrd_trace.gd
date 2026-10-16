class_name WyrdTrace
extends RefCounted

## Debug record of host answers and Wyrd decisions.
##
## @experimental
## Turn [member enabled] on before play. [method replay] drives the recorded
## inputs ([code]open_scene[/code], [code]advance[/code], [code]choose[/code],
## [code]abort[/code], [code]tick[/code], [code]emit[/code],
## [code]complete_host[/code], [code]draw[/code], [code]batch_begin[/code],
## [code]batch_end[/code], [code]emit_rejected[/code]) on another runtime. Host
## answers and decisions are compared with [method diff]. A different host
## answer shows up there.

var enabled: bool = false
## When set, a line is kept when its quest, role, slot, who, key, scope,
## speaker, or path equals this text or begins with it. Empty keeps every line.
## Belief, knowledge, credibility, event witness, and evidence lines use who and key.
## A credibility line's who is the listener. An evidence line's who is empty.
## A director line and a why_not line use scope, speaker, and key. Key is the scope id.
## A region line uses quest and path. A sequence line's key is the sequence id.
## A voice line's key is the name-free line id, and its who is the holder.
var prefix: String = ""
var events: Array[Dictionary] = []


func clear() -> void:
	events.clear()


func add(kind: String, fields: Dictionary) -> void:
	if not enabled:
		return
	var row := {"kind": kind}
	var keys: Array = fields.keys()
	keys.sort()
	for key in keys:
		row[String(key)] = _plain(fields[key])
	events.append(row)


func snapshot() -> Array:
	return events.duplicate(true)


static func replay(runtime: WyrdRuntime, recorded: Array) -> void:
	for item in recorded:
		if not (item is Dictionary):
			continue
		var row: Dictionary = item
		match String(row.get("kind", "")):
			"abort":
				runtime.dialogue.abort(StringName(str(row.get("reason", ""))))
			"batch_begin":
				runtime.events.begin_batch()
			"batch_end":
				runtime.events.end_batch()
			"advance":
				runtime.dialogue.advance()
			"choose":
				runtime.dialogue.choose(int(row.get("index", -1)))
			"complete_host":
				runtime.quests.complete_host_step(String(row.get("quest", "")), _dict(row.get("values", {})))
			"draw":
				runtime.draw_u32(StringName(str(row.get("stream", ""))))
			"emit", "emit_rejected":
				runtime.events.emit(StringName(str(row.get("name", ""))), _dict(row.get("payload", {})))
			"open_scene":
				runtime.dialogue.open_scene(String(row.get("id", "")))
			"tick":
				runtime.tick(int(row.get("minutes", 0)))
			_:
				pass


static func diff(expected: Array, actual: Array) -> PackedStringArray:
	var rows := PackedStringArray()
	var count := mini(expected.size(), actual.size())
	for i in count:
		if JSON.stringify(expected[i]) == JSON.stringify(actual[i]):
			continue
		var kind := ""
		if expected[i] is Dictionary:
			kind = String((expected[i] as Dictionary).get("kind", ""))
		rows.append("%d %s" % [i, kind])
		if rows.size() >= 8:
			return rows
	if expected.size() != actual.size():
		rows.append("length %d/%d" % [expected.size(), actual.size()])
	return rows


static func _dict(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	return {}


static func _plain(value: Variant) -> Variant:
	if value == null or value is bool or typeof(value) == TYPE_INT or value is float or value is String:
		return value
	if value is StringName:
		return String(value)
	if value is PackedStringArray:
		var packed: Array = []
		for item in value:
			packed.append(String(item))
		return packed
	if value is Array:
		var rows: Array = []
		for item in value:
			rows.append(_plain(item))
		return rows
	if value is Dictionary:
		var out := {}
		var keys: Array = value.keys()
		keys.sort()
		for key in keys:
			out[String(key)] = _plain(value[key])
		return out
	return str(value)
