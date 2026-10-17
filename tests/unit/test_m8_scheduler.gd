extends GutTest

## Fixed-work scheduler: shares, carry-over, and frame-sized slices.


const _HARBOR := "res://example/content/gullhaven/harbor.wyrdmanifest.tres"
const _Election := preload("res://example/playtest/harbor_election.gd")


func _weights() -> PackedInt32Array:
	return PackedInt32Array([40, 12, 8, 4])


func test_shares_are_round_robin_and_sum_to_the_budget() -> void:
	var scheduler := WyrdScheduler.new()
	var order: Array[String] = []
	scheduler.rumor_handler = func(token: String) -> void: order.append(token)
	scheduler.publish_handler = func(token: String) -> void: order.append(token)
	scheduler.cache_handler = func(token: String) -> void: order.append(token)
	for index in 100:
		scheduler.watch(index)
		scheduler.push("rumor", "rumor")
		scheduler.push("publish", "publish")
		scheduler.push("cache_refresh", "cache_refresh")
	var waits: Array[int] = []
	var report: Dictionary = scheduler.run(64, _weights(), func(index: int) -> void:
		waits.append(index)
		order.append("waits")
	)
	var spent: PackedInt32Array = report["spent"]
	assert_eq(spent, PackedInt32Array([40, 12, 8, 4]))
	assert_eq(int(report["total"]), 64)
	assert_eq(waits.size(), 40)
	assert_eq(waits[0], 0)
	assert_eq(waits[39], 39)
	assert_eq(order.slice(0, 16), [
		"waits", "rumor", "publish", "cache_refresh",
		"waits", "rumor", "publish", "cache_refresh",
		"waits", "rumor", "publish", "cache_refresh",
		"waits", "rumor", "publish", "cache_refresh",
	])
	assert_eq(scheduler.carry("waits"), 60)
	assert_eq(scheduler.carry("rumor"), 88)
	assert_eq(scheduler.carry("publish"), 92)
	assert_eq(scheduler.carry("cache_refresh"), 96)


func test_unfinished_rumor_stays_in_order() -> void:
	var scheduler := WyrdScheduler.new()
	var ran: Array[String] = []
	scheduler.rumor_handler = func(token: String) -> void: ran.append(token)
	for token in ["a", "b", "c", "d"]:
		scheduler.push("rumor", token)
	scheduler.run(2, _weights(), func(_index: int) -> void: pass)
	assert_eq(ran, ["a", "b"])
	assert_eq(scheduler.carry_tokens("rumor"), PackedStringArray(["c", "d"]))
	scheduler.run(2, _weights(), func(_index: int) -> void: pass)
	assert_eq(ran, ["a", "b", "c", "d"])
	assert_eq(scheduler.carry("rumor"), 0)


func test_waits_match_the_old_tick_queue() -> void:
	var old := WyrdTickQueue.new()
	var scheduler := WyrdScheduler.new()
	for index in [5, 1, 3, 8, 2, 7]:
		old.watch(index)
		scheduler.watch(index)
	assert_eq(_drain(scheduler, 2), _drain_old(old, 2))
	assert_eq(_drain(scheduler, 0), _drain_old(old, 0))
	assert_eq(scheduler.dirty_count(), old.dirty_count())
	old.mark(PackedInt32Array([1, 9]))
	scheduler.mark(PackedInt32Array([1, 9]))
	old.unwatch(5)
	scheduler.unwatch(5)
	var ran := _drain(scheduler, 8)
	assert_eq(ran, _drain_old(old, 8))
	assert_eq(ran[0], 1)
	assert_eq(scheduler.dirty_count(), old.dirty_count())
	assert_eq(scheduler.is_dirty(5), old.is_dirty(5))


func test_runtime_waits_match_the_old_queue() -> void:
	var runtime := _harbor()
	var mirror := WyrdTickQueue.new()
	for index in runtime.condition_count():
		mirror.watch(index)
	var expected: Array[int] = []
	var budget := runtime.config().scheduler_work_per_tick
	mirror.tick(budget, func(index: int) -> void: expected.append(index))
	runtime.tick(0)
	assert_eq(runtime.last_rechecks(), expected.size())
	assert_gt(expected.size(), 0)
	for index in expected:
		assert_false(runtime.condition_dirty(index))
	if expected.size() < runtime.condition_count():
		assert_true(runtime.condition_dirty(expected.size()))


func test_slices_accumulate_to_whole_ticks() -> void:
	var runtime := _sample()
	for _frame in 15:
		runtime.tick(1.0 / 30.0)
	assert_eq(runtime.now_minutes(), 0)
	assert_gt(runtime.slice_remainder_units(), 0)
	for _frame in 15:
		runtime.tick(1.0 / 30.0)
	assert_eq(runtime.now_minutes(), 1)
	assert_eq(runtime.slice_remainder_units(), 0)
	runtime.config().scheduler_tick_minutes = 2
	runtime.tick(1)
	assert_eq(runtime.now_minutes(), 1)
	runtime.tick(1)
	assert_eq(runtime.now_minutes(), 3)


func test_thirty_and_one_fourty_four_fps_slices_match() -> void:
	var steady := _drive_minutes(60)
	var thirty := _drive_frames(30)
	var fast := _drive_frames(144)
	assert_eq(_hash(thirty), _hash(steady))
	assert_eq(_hash(fast), _hash(steady))
	assert_eq(thirty.now_minutes(), 60)
	assert_eq(fast.slice_remainder_units(), 0)
	assert_eq(thirty.scheduler().carry("rumor"), steady.scheduler().carry("rumor"))


func test_a_jump_matches_one_minute_steps() -> void:
	var jumped := _sample()
	var stepped := _sample()
	jumped.facts.set(&"player.coins", 3)
	stepped.facts.set(&"player.coins", 3)
	jumped.tick(60)
	for _minute in 60:
		stepped.tick(1)
	assert_eq(jumped.now_minutes(), 60)
	assert_eq(_hash(jumped), _hash(stepped))


func test_frame_warning_does_not_change_the_work() -> void:
	var runtime := _sample()
	runtime.config().scheduler_frame_warn_usec = 1
	runtime.config().scheduler_work_per_tick = 4
	runtime.config().scheduler_share_waits = 0
	runtime.config().scheduler_share_rumor = 0
	runtime.config().scheduler_share_publish = 0
	runtime.config().scheduler_share_cache = 4
	runtime.trace.enabled = true
	runtime.scheduler().cache_handler = func(_token: String) -> void:
		var spin := 0
		for i in 30000:
			spin += i
	for index in 10:
		runtime.scheduler().push("cache_refresh", "row-%d" % index)
	runtime.trace.clear()
	runtime.tick(0)
	assert_eq(runtime.scheduler().carry("cache_refresh"), 6)
	var warned := false
	for row in runtime.trace.snapshot():
		if String(row.get("kind", "")) != "scheduler" or String(row.get("queue", "")) != "frame":
			continue
		warned = true
		assert_gt(int(row.get("us", 0)), 1)
		assert_eq(int(row.get("units", 0)), 4)
	assert_true(warned, "expected a soft frame warning")


func test_scheduler_lines_filter_and_stay_out_of_saves() -> void:
	var runtime := _sample()
	runtime.trace.enabled = true
	runtime.trace.prefix = "rumor"
	runtime.scheduler().push("rumor", "hop")
	runtime.scheduler().push("publish", "issue")
	var kinds: Array[String] = []
	for row in runtime.trace.snapshot():
		if String(row.get("kind", "")) == "scheduler":
			kinds.append(String(row.get("queue", "")))
	assert_eq(kinds, ["rumor"])
	for _frame in 15:
		runtime.tick(1.0 / 30.0)
	var saved := runtime.save_state()
	assert_eq(int(saved["schema_version"]), 2)
	assert_false(saved.has("scheduler"))
	runtime.trace.clear()
	var loaded := _sample()
	loaded.trace.enabled = true
	var report := loaded.load_state(saved)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(loaded.slice_remainder_units(), 0)
	assert_eq(loaded.scheduler().carry("rumor"), 0)
	for row in loaded.trace.snapshot():
		assert_ne(String(row.get("kind", "")), "scheduler")


func _drain(scheduler: WyrdScheduler, budget: int) -> Array[int]:
	var ran: Array[int] = []
	scheduler.run(budget, _weights(), func(index: int) -> void: ran.append(index))
	return ran


func _drain_old(queue: WyrdTickQueue, budget: int) -> Array[int]:
	var ran: Array[int] = []
	queue.tick(budget, func(index: int) -> void: ran.append(index))
	return ran


func _drive_frames(fps: int) -> WyrdRuntime:
	var runtime := _sample()
	runtime.facts.set(&"player.coins", 4)
	for _hop in 5:
		runtime.scheduler().push("rumor", "hop")
	var frames := 60 * fps
	for _frame in frames:
		runtime.tick(1.0 / float(fps))
	return runtime


func _drive_minutes(count: int) -> WyrdRuntime:
	var runtime := _sample()
	runtime.facts.set(&"player.coins", 4)
	for _hop in 5:
		runtime.scheduler().push("rumor", "hop")
	for _minute in count:
		runtime.tick(1)
	return runtime


func _hash(runtime: WyrdRuntime) -> int:
	var digest := WyrdHash.of_int(runtime.now_minutes())
	digest = WyrdHash.combine(digest, runtime.play_minutes())
	digest = WyrdHash.combine(digest, runtime.slice_remainder_units())
	var flags := runtime.condition_flags()
	for index in flags.size():
		digest = WyrdHash.combine(digest, int(flags[index]))
	var saved := JSON.stringify(runtime.save_state())
	for index in saved.length():
		digest = WyrdHash.combine(digest, saved.unicode_at(index))
	for queue in WyrdScheduler.queues():
		var name := String(queue)
		digest = WyrdHash.combine(digest, runtime.scheduler().carry(name))
		for token in runtime.scheduler().carry_tokens(name):
			for index in token.length():
				digest = WyrdHash.combine(digest, token.unicode_at(index))
	return digest


func _harbor() -> WyrdRuntime:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	runtime.register_adapter(WyrdElectionAdapter, _Election.new())
	var report := runtime.load_content(load(_HARBOR) as WyrdContentManifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(11)
	return runtime


func _sample() -> WyrdRuntime:
	var path := "user://wyrd_m8_scheduler.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("""
language 1
facts
  player.coins : int stored
scene room
  when player.coins > 0: narrator: Paid. #line:paid
  when chance(0.5): narrator: Half. #line:half
  -> end
""")
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"sample"
	manifest.files = PackedStringArray([path])
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(11)
	return runtime
