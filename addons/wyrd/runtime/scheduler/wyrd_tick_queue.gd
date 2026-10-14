class_name WyrdTickQueue
extends RefCounted

## Per-tick work list for waiting conditions.
##
## @experimental
## A fixed budget, from [member WyrdConfig.scheduler_work_per_tick], re-checks
## dirty indexes in ascending order. The rest stay dirty. The queue is rebuilt
## from the content index and is never saved.

var last_rechecks: int = 0

var _dirty: Dictionary = {}
var _waiting: Dictionary = {}


func clear() -> void:
	_dirty.clear()
	_waiting.clear()
	last_rechecks = 0


func watch(index: int) -> void:
	_waiting[index] = true
	_dirty[index] = true


func unwatch(index: int) -> void:
	_waiting.erase(index)
	_dirty.erase(index)


func mark(indexes: PackedInt32Array) -> void:
	for index in indexes:
		var at := int(index)
		if _waiting.has(at):
			_dirty[at] = true


func dirty_count() -> int:
	return _dirty.size()


func is_dirty(index: int) -> bool:
	return _dirty.has(index)


## [param eval_one] receives a condition index and returns nothing.
func tick(budget: int, eval_one: Callable) -> int:
	var keys: Array = _dirty.keys()
	keys.sort()
	var ran := 0
	var cap := budget if budget > 0 else 0
	for key in keys:
		if ran >= cap:
			break
		var index := int(key)
		_dirty.erase(index)
		if eval_one.is_valid():
			eval_one.call(index)
		ran += 1
	last_rechecks = ran
	return ran
