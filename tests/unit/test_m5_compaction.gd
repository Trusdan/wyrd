extends GutTest

## Deed compaction keeps scores within rounding and does not move perception.


const _ROUND := 0.000001

const _BODY := """
language 1
facts
  player.coins : int stored
quest harbor_guild "The Harbor Guild"
  stage post
    waits_until false
"""


func test_same_minute_rows_merge_and_a_later_minute_does_not() -> void:
	var runtime := _open()
	_arm(runtime)
	var first := runtime.deeds.record(
		&"paid", &"player", &"ferry_master", &"gullhaven",
		PackedStringArray(["toll"]), 1.0, PackedStringArray([&"ferry_master", &"dock_apprentice"])
	)
	var second := runtime.deeds.record(
		&"paid", &"player", &"ferry_master", &"gullhaven",
		PackedStringArray(["toll"]), 1.0, PackedStringArray([&"dock_apprentice", &"ferry_master"])
	)
	assert_eq(first, 1)
	assert_eq(second, 2)
	assert_eq(runtime.deeds.count_matching(&"player", &"paid"), 2)
	assert_almost_eq(runtime.deeds.score_matching(&"player", &"paid"), 2.0, _ROUND)
	assert_almost_eq(runtime.social.axis(&"ferry_master", &"player", &"affinity"), 40.0, _ROUND)
	assert_eq(runtime.social.disposition(&"ferry_master", &"player"), 70)
	assert_almost_eq(runtime.social.reputation(&"player", &"harbor_guild"), 70.0, _ROUND)
	assert_eq(runtime.deeds.mode_of(&"dock_apprentice", &"paid"), &"saw")
	var before := runtime.deeds.export_state()
	runtime.trace.enabled = true
	assert_eq(runtime.deeds.compact(), 1)
	assert_eq(runtime.deeds.count_matching(&"player", &"paid"), 1)
	assert_almost_eq(runtime.deeds.score_matching(&"player", &"paid"), 2.0, _ROUND)
	assert_almost_eq(runtime.social.axis(&"ferry_master", &"player", &"affinity"), 40.0, _ROUND)
	assert_eq(runtime.social.disposition(&"ferry_master", &"player"), 70)
	assert_almost_eq(runtime.social.reputation(&"player", &"harbor_guild"), 70.0, _ROUND)
	assert_eq(runtime.deeds.mode_of(&"dock_apprentice", &"paid"), &"saw")
	assert_eq(runtime.deeds.mode_of(&"ferry_master", &"paid"), &"saw")
	assert_eq(int(runtime.deeds.row_at(0)["id"]), 2)
	assert_almost_eq(float(runtime.deeds.row_at(0)["magnitude"]), 2.0, _ROUND)
	assert_eq(runtime.deeds.record(&"arrived", &"player", &"ferry_master", &"gullhaven"), 3)
	var line: Dictionary = _rows(runtime, "compact")[0]
	assert_eq(int(line["before"]), 2)
	assert_eq(int(line["after"]), 1)
	assert_eq(int(line["merged"]), 1)
	assert_eq(int(line["dropped"]), 0)
	runtime.deeds.compact()
	assert_eq(runtime.deeds.size(), 2)
	assert_eq(_rows(runtime, "compact").size(), 2)
	runtime.tick(80)
	var late := runtime.deeds.record(&"paid", &"player", &"ferry_master", &"gullhaven", PackedStringArray(["toll"]))
	assert_gt(late, 0)
	var sized := runtime.deeds.size()
	runtime.deeds.compact()
	assert_eq(runtime.deeds.size(), sized)
	assert_eq(runtime.deeds.count_matching(&"player", &"paid", null, null, 30), 1)
	runtime.deeds.record(&"paid", &"player", &"dock_apprentice", &"gullhaven", PackedStringArray(["toll"]))
	runtime.deeds.record(&"paid", &"player", &"ferry_master", &"gullhaven", PackedStringArray(), 1.0, PackedStringArray(), &"secret")
	var split := runtime.deeds.size()
	runtime.deeds.compact()
	assert_eq(runtime.deeds.size(), split)
	assert_false(_same(before, runtime.deeds.export_state()))
	var untouched := _open()
	untouched.deeds.record(&"arrived", &"ferry_master", &"player", &"gullhaven")
	var exported := untouched.deeds.export_state()
	untouched.deeds.compact()
	assert_true(_same(exported, untouched.deeds.export_state()))


func test_decay_stays_within_rounding_and_zero_weight_can_drop() -> void:
	var kept := _open()
	var folded := _open()
	for runtime in [kept, folded]:
		_arm(runtime)
		runtime.deeds.record(&"paid", &"player", &"ferry_master", &"gullhaven", PackedStringArray(["toll"]), 1.0, PackedStringArray([&"dock_apprentice"]))
		runtime.deeds.record(&"paid", &"player", &"ferry_master", &"gullhaven", PackedStringArray(["toll"]), 1.0, PackedStringArray([&"dock_apprentice"]))
	folded.deeds.compact()
	assert_eq(folded.deeds.size(), 1)
	assert_eq(kept.deeds.size(), 2)
	kept.tick(120)
	folded.tick(120)
	_assert_same_scores(kept, folded)
	var aged := _open()
	_arm(aged)
	aged.deeds.record(&"paid", &"player", &"ferry_master", &"gullhaven")
	aged.tick(1260)
	assert_almost_eq(aged.deeds.score_matching(&"player", &"paid"), 0.0, _ROUND)
	assert_eq(aged.deeds.compact(), 0)
	var pair := _open()
	_arm(pair)
	pair.deeds.record(&"paid", &"player", &"ferry_master", &"gullhaven")
	pair.deeds.record(&"paid", &"player", &"dock_apprentice", &"gullhaven")
	pair.tick(1260)
	var paired := pair.deeds.score_matching(&"player", &"paid")
	assert_eq(pair.deeds.compact(), 2)
	assert_almost_eq(pair.deeds.score_matching(&"player", &"paid"), paired, _ROUND)
	var heard := _open()
	_arm(heard)
	_host(heard).spatial.set_perception(&"dock_apprentice", &"heard")
	heard.deeds.record(&"paid", &"player", &"ferry_master", &"gullhaven", PackedStringArray(), 1.0, PackedStringArray([&"dock_apprentice"]))
	heard.tick(1260)
	assert_eq(heard.deeds.compact(), 1)
	assert_eq(heard.deeds.mode_of(&"dock_apprentice", &"paid"), &"heard")
	var replaced := _open()
	_arm(replaced)
	_host(replaced).spatial.set_perception(&"dock_apprentice", &"heard")
	replaced.deeds.record(&"paid", &"player", &"ferry_master", &"gullhaven", PackedStringArray(), 1.0, PackedStringArray([&"dock_apprentice"]))
	replaced.tick(1260)
	_host(replaced).spatial.set_perception(&"dock_apprentice", &"saw")
	replaced.deeds.record(&"paid", &"player", &"ferry_master", &"gullhaven", PackedStringArray(), 1.0, PackedStringArray([&"dock_apprentice"]))
	assert_eq(replaced.deeds.mode_of(&"dock_apprentice", &"paid"), &"saw")
	assert_eq(replaced.deeds.compact(), 1)
	assert_eq(replaced.deeds.mode_of(&"dock_apprentice", &"paid"), &"saw")


func test_memorable_rows_add_and_tick_threshold_is_opt_in() -> void:
	var runtime := _open()
	runtime.deeds.record(&"paid", &"player", &"ferry_master", &"gullhaven", PackedStringArray(), 1.0, null, &"public", true)
	runtime.deeds.record(&"paid", &"player", &"ferry_master", &"gullhaven", PackedStringArray(), 1.0, null, &"public", true)
	runtime.config().half_life_verbs = PackedStringArray(["paid"])
	runtime.config().half_life_minutes = PackedFloat64Array([60.0])
	runtime.tick(120)
	assert_eq(runtime.deeds.compact(), 1)
	assert_almost_eq(runtime.deeds.score_matching(&"player", &"paid"), 2.0, _ROUND)
	var quiet := _open()
	quiet.deeds.record(&"paid", &"player", &"ferry_master", &"gullhaven")
	quiet.deeds.record(&"paid", &"player", &"ferry_master", &"gullhaven")
	quiet.trace.enabled = true
	quiet.tick(0)
	assert_eq(quiet.deeds.size(), 2)
	assert_eq(_rows(quiet, "compact").size(), 0)
	var auto := _open()
	auto.config().compact_after = 2
	auto.deeds.record(&"paid", &"player", &"ferry_master", &"gullhaven")
	auto.deeds.record(&"paid", &"player", &"ferry_master", &"gullhaven")
	auto.trace.enabled = true
	auto.tick(0)
	assert_eq(auto.deeds.size(), 1)
	assert_eq(_rows(auto, "compact").size(), 1)
	auto.trace.prefix = "ferry_master"
	auto.trace.events.clear()
	auto.deeds.compact()
	assert_eq(_rows(auto, "compact").size(), 0)
	auto.trace.prefix = ""
	auto.trace.enabled = false
	auto.trace.events.clear()
	auto.deeds.compact()
	assert_eq(auto.trace.events.size(), 0)


func test_save_round_trip_and_seed_do_not_change_the_fold() -> void:
	var runtime := _boot()
	_arm(runtime)
	runtime.deeds.record(&"paid", &"player", &"ferry_master", &"gullhaven", PackedStringArray(["toll"]), 1.0, PackedStringArray([&"dock_apprentice"]))
	runtime.deeds.record(&"paid", &"player", &"ferry_master", &"gullhaven", PackedStringArray(["toll"]), 1.0, PackedStringArray([&"dock_apprentice"]))
	runtime.deeds.compact()
	var saved := runtime.save_state()
	assert_false(JSON.stringify(saved).contains("compact_after"))
	var fresh := _boot()
	_arm(fresh)
	fresh.trace.enabled = true
	assert_true(fresh.load_state(saved).ok)
	assert_eq(fresh.trace.events.size(), 0)
	assert_eq(fresh.deeds.size(), 1)
	assert_almost_eq(fresh.deeds.score_matching(&"player", &"paid"), 2.0, _ROUND)
	assert_true(_same(saved, fresh.save_state()))
	fresh.deeds.compact()
	assert_eq(fresh.deeds.size(), 1)
	var left := _folded(4)
	var right := _folded(11)
	assert_true(_same(left.deeds.export_state(), right.deeds.export_state()))
	assert_null(left.facts.get(&"player.coins"))


func _assert_same_scores(left: WyrdRuntime, right: WyrdRuntime) -> void:
	assert_almost_eq(left.deeds.score_matching(&"player", &"paid"), right.deeds.score_matching(&"player", &"paid"), _ROUND)
	assert_almost_eq(
		left.social.axis(&"ferry_master", &"player", &"affinity"),
		right.social.axis(&"ferry_master", &"player", &"affinity"),
		_ROUND
	)
	assert_eq(left.social.disposition(&"ferry_master", &"player"), right.social.disposition(&"ferry_master", &"player"))
	assert_almost_eq(left.social.reputation(&"player", &"harbor_guild"), right.social.reputation(&"player", &"harbor_guild"), _ROUND)
	assert_eq(left.deeds.mode_of(&"dock_apprentice", &"paid"), right.deeds.mode_of(&"dock_apprentice", &"paid"))


func _arm(runtime: WyrdRuntime) -> void:
	runtime.config().half_life_verbs = PackedStringArray(["paid"])
	runtime.config().half_life_minutes = PackedFloat64Array([60.0])
	runtime.config().set_axis_delta(&"paid", &"affinity", 20.0)
	_host(runtime).world.add_member(&"harbor_guild", &"ferry_master")


func _folded(seed_value: int) -> WyrdRuntime:
	var runtime := _open()
	runtime.start_new_game(seed_value)
	_arm(runtime)
	runtime.deeds.record(&"paid", &"player", &"ferry_master", &"gullhaven", PackedStringArray(["toll"]))
	runtime.deeds.record(&"paid", &"player", &"ferry_master", &"gullhaven", PackedStringArray(["toll"]))
	runtime.deeds.compact()
	return runtime


func _open() -> WyrdRuntime:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	runtime.set_meta(&"host", host)
	runtime.start_new_game(4)
	return runtime


func _boot() -> WyrdRuntime:
	var runtime := _open()
	var path := "user://wyrd_m5_compaction.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(_BODY)
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


func _rows(runtime: WyrdRuntime, kind: String) -> Array:
	var rows: Array = []
	for row in runtime.trace.events:
		if String(row.get("kind", "")) == kind:
			rows.append(row)
	return rows


func _same(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):
		return false
	if left is Dictionary:
		if left.size() != right.size():
			return false
		for key in left.keys():
			if not right.has(key) or not _same(left[key], right[key]):
				return false
		return true
	if left is Array:
		if left.size() != right.size():
			return false
		for i in left.size():
			if not _same(left[i], right[i]):
				return false
		return true
	return left == right
