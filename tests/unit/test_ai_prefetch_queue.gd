extends GutTest

## The sixth queue does not change the five-queue split, and it keeps no tokens.


func test_queues_name_six_ending_in_ai_prefetch() -> void:
	var names := WyrdScheduler.queues()
	assert_eq(names.size(), 6)
	assert_eq(WyrdScheduler.QUEUE_COUNT, 6)
	assert_eq(String(names[5]), "ai_prefetch")
	assert_eq(names, PackedStringArray(["waits", "rumor", "publish", "cache_refresh", "generate", "ai_prefetch"]))


func test_zero_sixth_weight_matches_the_five_queue_split() -> void:
	var weights := PackedInt32Array([40, 12, 8, 4, 0, 0])
	for budget in range(0, 257):
		_assert_split(weights, budget)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for _draw in 200:
		var drawn := PackedInt32Array()
		for _index in 5:
			drawn.append(rng.randi_range(0, 40))
		drawn.append(0)
		_assert_split(drawn, rng.randi_range(0, 256))


func test_share_zero_spills_only_when_earlier_queues_are_idle() -> void:
	var busy := WyrdScheduler.new()
	var stolen := [0]
	for index in 20:
		busy.watch(index)
	busy.ai_prefetch_has_work = func() -> bool: return true
	busy.ai_prefetch_unit = func() -> void: stolen[0] = int(stolen[0]) + 1
	busy.ai_prefetch_carry = func() -> int: return 4
	var blocked: Dictionary = busy.run(8, PackedInt32Array([40, 12, 8, 4, 0, 0]), func(_index: int) -> void: pass)
	assert_eq(int(stolen[0]), 0)
	assert_eq(int(blocked["ai_prefetch_spent"]), 0)
	assert_gt(int((blocked["spent"] as PackedInt32Array)[0]), 0)
	var idle := WyrdScheduler.new()
	var left := [5]
	idle.ai_prefetch_has_work = func() -> bool: return int(left[0]) > 0
	idle.ai_prefetch_unit = func() -> void: left[0] = int(left[0]) - 1
	idle.ai_prefetch_carry = func() -> int: return int(left[0])
	var spilled: Dictionary = idle.run(3, PackedInt32Array([40, 12, 8, 4, 0, 0]), func(_index: int) -> void: pass)
	assert_eq(int(left[0]), 2)
	assert_eq(int(spilled["ai_prefetch_spent"]), 3)
	assert_eq(int(spilled["ai_prefetch_carry"]), 2)
	assert_eq(spilled["spent"], PackedInt32Array([0, 0, 0, 0]))
	assert_eq(int(spilled["generate_spent"]), 0)
	assert_eq(int(spilled["total"]), 3)
	var shared := WyrdScheduler.new()
	var calls := [0]
	for index in 80:
		shared.watch(index)
	shared.ai_prefetch_has_work = func() -> bool: return true
	shared.ai_prefetch_unit = func() -> void: calls[0] = int(calls[0]) + 1
	shared.ai_prefetch_carry = func() -> int: return 1
	var weights := PackedInt32Array([40, 12, 8, 4, 0, 16])
	var share := int(WyrdScheduler.apportion(weights, 80)[5])
	var report: Dictionary = shared.run(80, weights, func(_index: int) -> void: pass)
	assert_gt(share, 0)
	assert_eq(int(calls[0]), share)
	assert_eq(int(report["ai_prefetch_spent"]), share)
	assert_eq(int(report["generate_spent"]), 0)
	var saved: PackedInt32Array = report["spent"]
	assert_eq(saved.size(), 4)
	assert_eq(int(saved[0]) + share, 80)


func test_unset_callables_keep_no_tokens_and_log_nothing() -> void:
	var scheduler := WyrdScheduler.new()
	var rows: Array = []
	scheduler.trace_hook = func(fields: Dictionary) -> void: rows.append(fields)
	var report: Dictionary = scheduler.run(4, PackedInt32Array([1, 0, 0, 0, 0, 0]), func(_index: int) -> void: pass)
	assert_eq(scheduler.carry("ai_prefetch"), 0)
	assert_false(scheduler.ai_prefetch_has_work.is_valid())
	assert_eq(int(report["ai_prefetch_spent"]), 0)
	assert_eq(int(report["ai_prefetch_carry"]), 0)
	assert_eq(int(report["generate_spent"]), 0)
	assert_true(report.has("spent"))
	assert_true(report.has("carry"))
	assert_true(report.has("total"))
	for row in rows:
		assert_ne(str((row as Dictionary).get("queue", "")), "ai_prefetch")
	scheduler.push("ai_prefetch", "token")
	assert_false(scheduler.export_carry().has("ai_prefetch"))
	assert_eq(scheduler.carry_tokens("ai_prefetch"), PackedStringArray())


func _assert_split(weights: PackedInt32Array, budget: int) -> void:
	var got := WyrdScheduler.apportion(weights, budget)
	var old := _apportion5(weights, budget)
	assert_eq(PackedInt32Array([got[0], got[1], got[2], got[3], got[4]]), old, "budget %d" % budget)
	assert_eq(int(got[5]), 0, "budget %d" % budget)


## The five-queue algorithm, copied here so this file does not call the old code.
func _apportion5(weights: PackedInt32Array, budget: int) -> PackedInt32Array:
	var shares := PackedInt32Array()
	shares.resize(5)
	if budget <= 0:
		return shares
	var sum := 0
	for index in 5:
		sum += maxi(int(weights[index]), 0)
	if sum <= 0:
		shares[0] = budget
		return shares
	var frac: Array[float] = []
	var used := 0
	for index in 5:
		var weight := maxi(int(weights[index]), 0)
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
