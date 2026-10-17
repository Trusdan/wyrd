class_name WyrdScheduler
extends RefCounted

## Fixed-work queues for one game tick.
##
## @experimental
## Queues, in round-robin order: waits, rumor, publish, cache_refresh.
## A unit is one waiting-condition recheck, one rumor hop, one issue fragment,
## or one cache-entry rebuild. [code]run[/code] spends at most the tick budget.
## Each queue's config weight is its share of that budget. Share a queue cannot
## use moves to the earliest queue that still has work, so a waits-only tick
## still spends the whole budget. Unfinished items stay in queue order. The
## round-robin starts at waits every tick. Nothing here is saved.

const QUEUE_COUNT := 4


static func queues() -> PackedStringArray:
	return PackedStringArray(["waits", "rumor", "publish", "cache_refresh"])
## One game minute, in units. 720 divides a 30 fps slice and a 144 fps slice
## when one real second advances one game minute.
const SLICE_UNITS_PER_MINUTE := 720

var last_units: int = 0

var trace_hook: Callable = Callable()
var rumor_handler: Callable = Callable()
var publish_handler: Callable = Callable()
var cache_handler: Callable = Callable()

var _waits := WyrdTickQueue.new()
var _rumor: Array[String] = []
var _publish: Array[String] = []
var _cache: Array[String] = []


func clear() -> void:
	_waits.clear()
	_rumor.clear()
	_publish.clear()
	_cache.clear()
	last_units = 0


## Drops rumor, publish, and cache items. Waiting conditions stay.
func clear_carry() -> void:
	_rumor.clear()
	_publish.clear()
	_cache.clear()


func watch(index: int) -> void:
	_waits.watch(index)


func unwatch(index: int) -> void:
	_waits.unwatch(index)


func mark(indexes: PackedInt32Array) -> void:
	_waits.mark(indexes)


func dirty_count() -> int:
	return _waits.dirty_count()


func is_dirty(index: int) -> bool:
	return _waits.is_dirty(index)


func last_rechecks() -> int:
	return _waits.last_rechecks


func recheck_some(indexes: PackedInt32Array, eval_one: Callable) -> PackedInt32Array:
	return _waits.recheck_some(indexes, eval_one)


## Appends one rumor hop, issue fragment, or cache rebuild. Tokens stay in order.
func push(queue: String, token: String) -> void:
	match queue:
		"rumor":
			_rumor.append(token)
			_emit(queue, 0, _rumor.size())
		"publish":
			_publish.append(token)
			_emit(queue, 0, _publish.size())
		"cache_refresh":
			_cache.append(token)
			_emit(queue, 0, _cache.size())
		_:
			push_error("WyrdScheduler.push: unknown queue \"%s\"" % queue)


func carry(queue: String) -> int:
	match queue:
		"waits":
			return _waits.dirty_count()
		"rumor":
			return _rumor.size()
		"publish":
			return _publish.size()
		"cache_refresh":
			return _cache.size()
		_:
			return 0


func carry_tokens(queue: String) -> PackedStringArray:
	var items: Array[String] = []
	match queue:
		"rumor":
			items = _rumor
		"publish":
			items = _publish
		"cache_refresh":
			items = _cache
		_:
			return PackedStringArray()
	var out := PackedStringArray()
	for token in items:
		out.append(token)
	return out


## [param weights] match [method queues]. [param waits_eval] receives a condition index.
func run(budget: int, weights: PackedInt32Array, waits_eval: Callable) -> Dictionary:
	var cap := budget if budget > 0 else 0
	var shares: Array[int] = []
	var split := apportion(_weights(weights), cap)
	for index in split.size():
		shares.append(int(split[index]))
	var spent := PackedInt32Array([0, 0, 0, 0])
	var total := 0
	var guard := cap * 3 + 4
	while total < cap and guard > 0:
		guard -= 1
		var ran := false
		for index in QUEUE_COUNT:
			if total >= cap or shares[index] <= 0:
				continue
			if not _run_one(index, waits_eval):
				continue
			shares[index] -= 1
			spent[index] = int(spent[index]) + 1
			total += 1
			ran = true
		if ran:
			continue
		if not _spill_one(shares):
			break
	_waits.last_rechecks = int(spent[0])
	last_units = total
	var left := PackedInt32Array([
		_waits.dirty_count(),
		_rumor.size(),
		_publish.size(),
		_cache.size(),
	])
	var names := queues()
	for index in QUEUE_COUNT:
		if int(spent[index]) > 0 or int(left[index]) > 0:
			_emit(String(names[index]), int(spent[index]), int(left[index]))
	return {"carry": left, "spent": spent, "total": total}


static func apportion(weights: PackedInt32Array, budget: int) -> PackedInt32Array:
	var shares := PackedInt32Array()
	shares.resize(QUEUE_COUNT)
	if budget <= 0:
		return shares
	var sum := 0
	for index in QUEUE_COUNT:
		sum += _weight_at(weights, index)
	if sum <= 0:
		shares[0] = budget
		return shares
	var frac: Array[float] = []
	var used := 0
	for index in QUEUE_COUNT:
		var weight := _weight_at(weights, index)
		var exact := float(weight) * float(budget) / float(sum)
		var whole := int(floor(exact))
		shares[index] = whole
		frac.append(exact - float(whole))
		used += whole
	var left := budget - used
	while left > 0:
		var best := 0
		var best_frac := -1.0
		for index in frac.size():
			if frac[index] > best_frac:
				best = index
				best_frac = frac[index]
		shares[best] = int(shares[best]) + 1
		frac[best] = -1.0
		left -= 1
	return shares


func _weights(weights: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array([0, 0, 0, 0])
	for index in mini(weights.size(), out.size()):
		out[index] = maxi(int(weights[index]), 0)
	return out


static func _weight_at(weights: PackedInt32Array, index: int) -> int:
	if index < 0 or index >= weights.size():
		return 0
	return maxi(int(weights[index]), 0)


func _spill_one(shares: Array[int]) -> bool:
	var donor := -1
	for index in shares.size():
		if shares[index] > 0:
			donor = index
			break
	if donor < 0:
		return false
	var needy := -1
	for index in QUEUE_COUNT:
		if _has_work(index):
			needy = index
			break
	if needy < 0:
		return false
	shares[donor] -= 1
	shares[needy] += 1
	return true


func _has_work(index: int) -> bool:
	match index:
		0:
			return _waits.dirty_count() > 0
		1:
			return not _rumor.is_empty()
		2:
			return not _publish.is_empty()
		3:
			return not _cache.is_empty()
		_:
			return false


func _run_one(index: int, waits_eval: Callable) -> bool:
	match index:
		0:
			return _waits.tick(1, waits_eval) == 1
		1:
			return _take(_rumor, rumor_handler)
		2:
			return _take(_publish, publish_handler)
		3:
			return _take(_cache, cache_handler)
		_:
			return false


func _take(items: Array[String], handler: Callable) -> bool:
	if items.is_empty():
		return false
	var token := String(items.pop_front())
	if handler.is_valid():
		handler.call(token)
	return true


func _emit(queue: String, units: int, left: int) -> void:
	if not trace_hook.is_valid():
		return
	trace_hook.call({
		"carry": left,
		"key": queue,
		"queue": queue,
		"units": units,
	})
