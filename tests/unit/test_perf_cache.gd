extends GutTest

## Caches and the sparse deed export stay aligned with the live log.


const _QUESTS := """
language 1
facts
  harbor.coins : int stored
quest open_now "Open Now"
  start when true
  stage wait
    waits_until false
quest open_coins "Open Coins"
  start when harbor.coins == 1
  stage wait
    waits_until false
quest stay_shut "Stay Shut"
  start when harbor.coins == 2
  stage wait
    waits_until false
quest roll_open "Roll Open"
  start when disposition(ferry_master, player) == 50
  stage wait
    waits_until false
quest touch "Touch"
  stage once
    ~ set harbor.coins = 0
    waits_until false
"""


func test_unrelated_deeds_do_not_move_player_reputation() -> void:
	var runtime := _open()
	var host := _host(runtime)
	host.world.add_member(&"harbor_guild", &"ferry_master")
	host.world.add_member(&"harbor_guild", &"dock_hand")
	for _i in 40:
		runtime.deeds.record(&"paid", &"dock_hand", &"ferry_master", &"gullhaven")
	assert_eq(runtime.social.disposition(&"ferry_master", &"player"), 50)
	assert_eq(runtime.social.reputation(&"player", &"harbor_guild"), 50.0)
	assert_eq(runtime.social.reputation(&"player", &"harbor_guild"), 50.0)
	runtime.config().set_axis_delta(&"paid", &"affinity", 40.0)
	runtime.deeds.record(&"paid", &"player", &"ferry_master", &"gullhaven")
	assert_eq(runtime.social.axis(&"ferry_master", &"player", &"affinity"), 40.0)
	assert_eq(runtime.social.reputation(&"player", &"harbor_guild"), 60.0)
	runtime.social.set_baseline(&"dock_hand", &"player", &"affinity", 20.0)
	assert_eq(runtime.social.reputation(&"player", &"harbor_guild"), 65.0)
	runtime.config().half_life_verbs = PackedStringArray(["paid"])
	runtime.config().half_life_minutes = PackedFloat64Array([60.0])
	var before := runtime.social.reputation(&"player", &"harbor_guild")
	runtime.tick(120)
	assert_gt(before, runtime.social.reputation(&"player", &"harbor_guild"))
	runtime.social.invalidate_members()
	var decayed := runtime.social.reputation(&"player", &"harbor_guild")
	runtime.social.members_of = func(_group: StringName) -> PackedStringArray:
		return PackedStringArray(["dock_hand"])
	assert_eq(runtime.social.reputation(&"player", &"harbor_guild"), 60.0)
	assert_gt(before, decayed)


func test_export_omits_loader_defaults() -> void:
	var runtime := _open()
	runtime.deeds.record(
		&"paid",
		&"player",
		&"ferry_master",
		&"gullhaven",
		PackedStringArray(["toll"]),
		1.0,
		PackedStringArray([&"ferry_master"]),
		&"public",
		false
	)
	var row: Dictionary = runtime.deeds.export_state()["rows"][0]
	assert_false(row.has("magnitude"))
	assert_false(row.has("memorable"))
	assert_false(row.has("visibility"))
	assert_false(row.has("perception"))
	assert_eq(row["place"], "gullhaven")
	assert_eq(row["tags"], ["toll"])
	assert_eq(row["witnesses"], ["ferry_master"])
	var restored := WyrdDeedLog.new()
	restored.import_state(runtime.deeds.export_state())
	var back := restored.row_at(0)
	assert_almost_eq(float(back["magnitude"]), 1.0, 0.000001)
	assert_eq(back["visibility"], &"public")
	assert_eq(back["perception"], PackedStringArray(["saw"]))
	assert_false(bool(back["memorable"]))
	var blank := WyrdDeedLog.new()
	blank.import_state({
		"next": 2,
		"rows": [{"actor": "player", "id": 1, "verb": "paid", "visibility": ""}],
	})
	var kept: Dictionary = blank.export_state()["rows"][0]
	assert_eq(kept["visibility"], "")
	assert_false(kept.has("magnitude"))
	_host(runtime).spatial.set_perception(&"ferry_master", &"heard", &"gullhaven")
	runtime.deeds.clear()
	runtime.deeds.record(
		&"paid",
		&"player",
		&"ferry_master",
		&"gullhaven",
		PackedStringArray(),
		2.0,
		PackedStringArray([&"ferry_master"]),
		&"secret",
		true
	)
	var loud: Dictionary = runtime.deeds.export_state()["rows"][0]
	assert_eq(float(loud["magnitude"]), 2.0)
	assert_true(bool(loud["memorable"]))
	assert_eq(loud["visibility"], "secret")
	assert_eq(loud["perception"], ["heard"])
	runtime.deeds.record(
		&"paid",
		&"player",
		&"ferry_master",
		&"gullhaven",
		PackedStringArray(),
		1.0,
		PackedStringArray([&"ferry_master"]),
		&"public",
		false
	)
	runtime.deeds.record(
		&"paid",
		&"player",
		&"ferry_master",
		&"gullhaven",
		PackedStringArray(),
		1.0,
		PackedStringArray([&"ferry_master"]),
		&"public",
		false
	)
	# The secret row stays. The two public rows share a minute and fold.
	assert_eq(runtime.deeds.compact(), 2)
	assert_almost_eq(runtime.deeds.score_matching(&"player", &"paid"), 4.0, 0.000001)


func test_belief_lookup_follows_the_next_write() -> void:
	var runtime := _boot(_QUESTS)
	var host := _host(runtime)
	var believes: Callable = runtime.function_table()[&"believes"]
	var agent := &"ferry_master"
	var key := &"harbor.coins"
	runtime.facts.set_in(key, 1, &"believed/ferry_master")
	assert_true(bool(believes.call([agent, key])))
	assert_true(bool(believes.call([agent, key])))
	runtime.facts.set_in(key, 0, &"believed/ferry_master")
	assert_false(bool(believes.call([agent, key])))
	runtime.facts.clear_in(key, &"believed/ferry_master")
	host.world.set_groups(agent, PackedStringArray(["harbor_guild"]))
	runtime.invalidate_groups()
	runtime.facts.set_in(key, 1, &"held/harbor_guild")
	assert_true(bool(believes.call([agent, key])))
	runtime.facts.set_in(key, 1, &"believed/ferry_master")
	runtime.facts.set_in(key, 0, &"held/harbor_guild")
	assert_true(bool(believes.call([agent, key])))
	runtime.facts.set_in(key, 0, &"believed/ferry_master")
	assert_false(bool(believes.call([agent, key])))


func test_pure_start_wakes_when_the_fact_matches() -> void:
	var runtime := _boot(_QUESTS)
	_drain(runtime)
	assert_eq(runtime.quests.status("open_now"), &"active")
	assert_eq(runtime.quests.status("roll_open"), &"active")
	assert_eq(runtime.quests.status("open_coins"), &"dormant")
	assert_eq(runtime.quests.status("stay_shut"), &"dormant")
	runtime.facts.set(&"harbor.coins", 1)
	runtime.tick(0)
	assert_eq(runtime.quests.status("open_coins"), &"active")
	assert_eq(runtime.quests.status("stay_shut"), &"dormant")
	var saved := runtime.save_state()
	var fresh := _boot(_QUESTS)
	assert_true(fresh.load_state(saved).ok)
	assert_eq(fresh.quests.status("open_coins"), &"active")
	assert_eq(fresh.quests.status("stay_shut"), &"dormant")
	fresh.facts.set(&"harbor.coins", 2)
	fresh.tick(0)
	assert_eq(fresh.quests.status("stay_shut"), &"active")


func _drain(runtime: WyrdRuntime) -> void:
	var guard := 0
	var limit := runtime.condition_count() + 4
	while guard < limit:
		runtime.tick(0)
		guard += 1
		if runtime.last_rechecks() == 0:
			break


func _open() -> WyrdRuntime:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	runtime.set_meta(&"host", host)
	runtime.start_new_game(4)
	return runtime


func _boot(body: String) -> WyrdRuntime:
	var runtime := _open()
	var path := "user://wyrd_perf_cache.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(body)
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(4)
	return runtime


func _host(runtime: WyrdRuntime) -> WyrdFakeHost:
	return runtime.get_meta(&"host") as WyrdFakeHost
