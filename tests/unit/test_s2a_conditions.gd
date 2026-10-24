extends GutTest

const _HARBOR := "res://example/content/gullhaven/harbor.wyrdmanifest.tres"
const _Election := preload("res://example/playtest/harbor_election.gd")
const _Harness := preload("res://tests/scenario/s2c_harness.gd")


func test_harbor_conditions_follow_facts_and_the_fake_host() -> void:
	var opened := _harbor()
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.world.add_entity(&"player", &"person", "Player", PackedStringArray([&"local"]), true)
	host.world.add_entity(&"ferry_master", &"person", "dock_clerk", PackedStringArray(), true)
	host.clock.season_name = &"storm"
	runtime.roles.assign(&"ferry_master", &"ferry_master")
	runtime.facts.set(&"player.coins", 2)
	runtime.facts.set(&"ferry.toll_coins", 0)
	runtime.facts.set(&"tavern.stew_bowls", 1)
	runtime.facts.set(&"harbor.room_taken", true)
	runtime.facts.set(&"world.storm_heard", true)
	runtime.tick(0)
	assert_eq(_flag(runtime, "ferry_toll", "start"), 0)
	assert_eq(_flag(runtime, "ferry_toll.lookout", "cast"), 1)
	assert_eq(_flag(runtime, "ferry_toll.pay_toll", "waits"), 1)
	assert_eq(_flag(runtime, "ferry_toll.pay_toll", "transition.cross"), 1)
	assert_eq(_flag(runtime, "a_stew", "when"), 1)
	assert_eq(_flag(runtime, "a_key", "when"), 1)
	assert_eq(_flag(runtime, "a_alive", "when"), 1)
	assert_eq(_flag(runtime, "a_season", "when"), 1)
	assert_eq(_flag(runtime, "c_local", "choice"), 1)
	assert_eq(_flag(runtime, "a_cross", "when"), 1)
	runtime.facts.set(&"player.coins", 1)
	runtime.facts.set(&"harbor.room_taken", false)
	runtime.tick(0)
	assert_eq(_flag(runtime, "ferry_toll.pay_toll", "waits"), 0)
	assert_eq(_flag(runtime, "a_key", "when"), 0)
	assert_eq(_flag(runtime, "a_cross", "when"), 0)
	assert_eq(_flag(runtime, "a_stew", "when"), 1)
	_assert_matches_scan(runtime)


func test_dirty_rechecks_match_a_full_scan() -> void:
	var opened := _harbor()
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.facts.set(&"player.coins", 2)
	runtime.facts.set(&"ferry.toll_coins", 0)
	runtime.tick(0)
	var total := runtime.condition_count()
	var ran := runtime.last_rechecks()
	while ran < total:
		runtime.tick(0)
		var step := runtime.last_rechecks()
		assert_gt(step, 0)
		ran += step
	assert_eq(ran, total)
	runtime.tick(0)
	assert_eq(runtime.last_rechecks(), 0)
	var before := runtime.condition_flags()
	runtime.facts.set(&"player.coins", 2)
	runtime.tick(0)
	assert_eq(runtime.last_rechecks(), 0)
	assert_eq(runtime.condition_flags(), before)
	runtime.facts.set(&"player.coins", 5)
	var expected := runtime.content().deps.affected([&"player.coins"]).size()
	runtime.tick(0)
	assert_eq(runtime.last_rechecks(), expected)
	assert_gt(expected, 0)
	assert_lt(expected, total)
	_assert_matches_scan(runtime)
	runtime.config().scheduler_work_per_tick = 1
	runtime.facts.set(&"player.coins", 0)
	runtime.facts.set(&"tavern.stew_bowls", 3)
	ran = 0
	for _i in total + 2:
		runtime.tick(0)
		ran += runtime.last_rechecks()
		if runtime.last_rechecks() == 0:
			break
	assert_gt(ran, 1)
	assert_lt(ran, total)
	_assert_matches_scan(runtime)


func test_holder_chance_and_belief() -> void:
	var opened := _pack(_BUILTINS)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.world.add_entity(&"clerk", &"person", "dock_clerk", PackedStringArray([&"local"]), true)
	runtime.roles.assign(&"ferry", &"clerk")
	runtime.tick(0)
	assert_eq(_flag(runtime, "named", "when"), 1)
	assert_eq(_flag(runtime, "tagged", "when"), 1)
	assert_eq(_flag(runtime, "living", "when"), 1)
	assert_eq(_flag(runtime, "sure", "when"), 1)
	assert_eq(_flag(runtime, "never", "when"), 0)
	assert_eq(_flag(runtime, "belief", "when"), 0)
	runtime.eval_condition(_at(runtime, "belief", "when"))
	var other := _pack(_BUILTINS)
	var second: WyrdRuntime = other["runtime"]
	second.tick(0)
	assert_eq(_flag(second, "half", "when"), _flag(runtime, "half", "when"))
	second.start_new_game(99)
	second.tick(0)
	var flipped := false
	for seed_value in [1, 2, 3, 4, 5, 6, 7, 8]:
		var probe := _pack(_BUILTINS)
		var sampled: WyrdRuntime = probe["runtime"]
		sampled.start_new_game(seed_value)
		sampled.tick(0)
		if _flag(sampled, "half", "when") != _flag(runtime, "half", "when"):
			flipped = true
			break
	assert_true(flipped)


const _BUILTINS := """
language 1
facts
  player.coins : int stored
scene room
  when holder(ferry).name == dock_clerk: narrator: Named. #line:named
  when has_tag(clerk, local): narrator: Tagged. #line:tagged
  when alive(clerk): narrator: Living. #line:living
  when chance(1): narrator: Sure. #line:sure
  when chance(0): narrator: Never. #line:never
  when chance(0.5): narrator: Half. #line:half
  when knows(player, player.coins): narrator: Hidden. #line:belief
  -> end
"""


func _harbor() -> Dictionary:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	runtime.register_adapter(WyrdElectionAdapter, _Election.new())
	var report := runtime.load_content(load(_HARBOR) as WyrdContentManifest)
	assert_true(report.ok, report.diagnostics.format())
	_Harness.new().register_host_decides(runtime)
	runtime.start_new_game(11)
	return {"host": host, "runtime": runtime}


func _pack(body: String) -> Dictionary:
	var path := "user://wyrd_s2a_cond_%d.wyrd" % body.hash()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(body)
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
	return {"host": host, "runtime": runtime}


func _flag(runtime: WyrdRuntime, record: String, site: String) -> int:
	var at := _at(runtime, record, site)
	assert_gte(at, 0, "%s:%s" % [record, site])
	return int(runtime.condition_flags()[at])


func _at(runtime: WyrdRuntime, record: String, site: String) -> int:
	var content := runtime.content()
	for i in content.conditions.size():
		if content.records[i] == record and content.sites[i] == site:
			return i
	return -1


func _assert_matches_scan(runtime: WyrdRuntime) -> void:
	var flags := runtime.condition_flags()
	assert_eq(flags.size(), runtime.condition_count())
	for i in flags.size():
		var live := 1 if runtime.eval_condition(i) else 0
		var where: Dictionary = runtime.content().condition_at(i)
		assert_eq(int(flags[i]), live, "%s:%s" % [where.get("record", ""), where.get("site", "")])


