class_name WyrdEvents
extends RefCounted

## Host entry for [code]Wyrd.events.emit[/code].
##
## @experimental
## [method emit] asks the runtime to type-check the payload, drop
## [code]on_event[/code] caches, and re-check dirty conditions before it
## returns. [method begin_batch] coalesces those re-checks until the matching
## [method end_batch]. The ring buffer is for the playtest. It is not saved.

var on_emit: Callable = Callable()
var on_batch: Callable = Callable()
var ring_limit: int = 32
var last_flush: int = 0
var last_wave: int = 0
var last_keys: PackedStringArray = PackedStringArray()
var recent: Array[Dictionary] = []

var _depth: int = 0


func emit(event_name: StringName, payload: Dictionary = {}) -> void:
	if on_emit.is_valid():
		on_emit.call(event_name, payload)


func begin_batch() -> void:
	var outer := _depth == 0
	_depth += 1
	if outer and on_batch.is_valid():
		on_batch.call(true)


func end_batch() -> void:
	if _depth <= 0:
		push_error("Wyrd.events.end_batch: no open batch")
		return
	_depth -= 1
	if _depth == 0 and on_batch.is_valid():
		on_batch.call(false)


func batching() -> bool:
	return _depth > 0


func reset_session() -> void:
	_depth = 0
	recent.clear()
	last_flush = 0
	last_wave = 0
	last_keys = PackedStringArray()


func clear_recent() -> void:
	recent.clear()


func remember(row: Dictionary) -> void:
	recent.append(row.duplicate(true))
	var cap := ring_limit if ring_limit > 0 else 0
	while recent.size() > cap:
		recent.remove_at(0)


func debug_dump() -> String:
	var lines := PackedStringArray()
	lines.append("batch_depth %d" % _depth)
	lines.append("flush %d" % last_wave)
	lines.append("rechecks %d" % last_flush)
	for key in last_keys:
		lines.append("invalidated %s" % String(key))
	for row in recent:
		lines.append("emit %s %s" % [str(row.get("name", "")), JSON.stringify(row.get("payload", {}))])
	return "\n".join(lines)
