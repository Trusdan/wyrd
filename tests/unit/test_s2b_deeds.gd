extends GutTest


func test_decay_bucket_edges_and_memorable() -> void:
	var clock := {"now": 0}
	var log := WyrdDeedLog.new()
	var cfg := WyrdConfig.new()
	cfg.hour_bucket_minutes = 60
	cfg.half_life_verbs = PackedStringArray(["gift", "insult"])
	cfg.half_life_minutes = PackedFloat64Array([60.0, 60.0])
	log.clock = func() -> int: return int(clock["now"])
	log.config_of = func() -> WyrdConfig: return cfg
	var seen: Array = []
	log.deed_recorded.connect(func(deed: Dictionary) -> void: seen.append(deed))
	assert_eq(log.record(&"gift", &"player", &"keeper", &"dock", PackedStringArray(["toll", "gift"]), 8.0), 1)
	clock["now"] = 30
	assert_eq(log.record(&"insult", &"player", &"keeper", &"dock", PackedStringArray(), 8.0, null, &"secret", true), 2)
	assert_eq(seen.size(), 2)
	assert_eq(int(seen[0]["t"]), 0)
	assert_eq(seen[1]["memorable"], true)
	assert_eq(seen[0]["tags"], PackedStringArray(["gift", "toll"]))
	clock["now"] = 59
	assert_almost_eq(log.score_matching(&"player", &"gift"), 8.0, 0.000001)
	clock["now"] = 60
	assert_almost_eq(log.score_matching(&"player", &"gift"), 4.0, 0.000001)
	clock["now"] = 119
	assert_almost_eq(log.score_matching(&"player", &"gift"), 4.0, 0.000001)
	clock["now"] = 120
	assert_almost_eq(log.score_matching(&"player", &"gift"), 2.0, 0.000001)
	assert_almost_eq(log.score_matching(&"player", &"insult"), 8.0, 0.000001)
	clock["now"] = 0
	log.record(&"gift", &"player", &"", &"", PackedStringArray(), 0.1)
	log.record(&"gift", &"player", &"", &"", PackedStringArray(), 0.2)
	cfg.half_life_minutes[0] = 0.0
	assert_almost_eq(log.score_matching(&"player", &"gift"), 8.3, 0.000001)
	assert_eq(log.record(&"", &"player"), -1)
	assert_push_error("verb and actor")


func test_indexes_filters_witnesses_and_within() -> void:
	var opened := _open()
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.spatial.set_witnesses(&"dock", PackedStringArray([&"keeper", &"clerk"]))
	runtime.deeds.record(&"gift", &"player", &"keeper", &"dock", PackedStringArray(["toll"]), 1.0, &"auto")
	runtime.deeds.record(&"gift", &"clerk", &"keeper", &"dock")
	runtime.deeds.record(&"arrived", &"player", &"", &"dock", PackedStringArray(["toll", "gate"]))
	var listed := runtime.deeds.record(
		&"insult", &"player", &"stranger", &"road", PackedStringArray(), 1.0, PackedStringArray([&"keeper", &"ada"])
	)
	assert_eq(runtime.deeds.index_size(&"actor", &"player"), 3)
	assert_eq(runtime.deeds.index_size(&"verb", &"gift"), 2)
	assert_eq(runtime.deeds.index_size(&"target", &"keeper"), 2)
	assert_eq(runtime.deeds.index_size(&"actor", &"missing"), 0)
	assert_eq(runtime.deeds.count_matching(&"player", &"gift", &"keeper", &"dock"), 1)
	assert_eq(runtime.deeds.count_matching(&"player", null, null, null, null, PackedStringArray(["toll"])), 2)
	assert_eq(runtime.deeds.count_matching(&"player", null, null, null, null, PackedStringArray(["toll", "missing"])), 0)
	assert_eq(runtime.deeds.count_matching(&"player", null, null, null, 0), 3)
	runtime.tick(61)
	assert_eq(runtime.deeds.count_matching(&"player", null, null, null, 60), 0)
	var row := runtime.deeds.row_at(0)
	assert_eq(row["witnesses"], PackedStringArray(["clerk", "keeper"]))
	var insult := runtime.deeds.row_at(listed - 1)
	assert_eq(insult["witnesses"], PackedStringArray(["ada", "keeper"]))
	assert_eq(insult["visibility"], &"public")
	runtime.deeds.record(&"gift", &"player", &"", &"", PackedStringArray(), 1.0, &"nope")
	assert_push_error("witnesses")
	runtime.start_new_game(3)
	assert_eq(runtime.deeds.size(), 0)
	assert_eq(runtime.deeds.record(&"gift", &"player"), 1)
	var facade = load("res://addons/wyrd/runtime/wyrd.gd").new()
	assert_eq(facade.deeds, facade._runtime.deeds)
	facade.free()


func test_axes_disposition_and_formula() -> void:
	var opened := _open()
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.config().set_axis_delta(&"gift", &"affinity", 40.0)
	runtime.config().set_axis_delta(&"insult", &"affinity", -10.0)
	runtime.config().half_life_verbs = PackedStringArray(["gift"])
	runtime.config().half_life_minutes = PackedFloat64Array([60.0])
	runtime.social.set_baseline(&"keeper", &"player", &"affinity", 10.0)
	runtime.deeds.record(&"gift", &"player", &"keeper")
	runtime.deeds.record(&"insult", &"player", &"other", &"", PackedStringArray(), 1.0, PackedStringArray([&"keeper"]))
	assert_eq(runtime.social.axis(&"keeper", &"player", &"affinity"), 40.0)
	assert_eq(runtime.social.disposition(&"keeper", &"player"), 70)
	runtime.tick(60)
	assert_eq(runtime.social.axis(&"keeper", &"player", &"affinity"), 20.0)
	assert_eq(runtime.social.disposition(&"keeper", &"player"), 60)
	runtime.social.register_formula(func(_a: StringName, _b: StringName, axes: Dictionary) -> int:
		return int(axes[&"affinity"]) + 5
	)
	assert_eq(runtime.social.disposition(&"keeper", &"player"), 25)
	runtime.social.register_formula(func(_a: StringName, _b: StringName, _axes: Dictionary) -> int: return 500)
	assert_eq(runtime.social.disposition(&"keeper", &"player"), 100)
	runtime.social.register_formula(func(_a: StringName, _b: StringName, _axes: Dictionary) -> int: return -4)
	assert_eq(runtime.social.disposition(&"keeper", &"player"), 0)
	runtime.social.register_formula(Callable())
	assert_push_error("missing callable")
	runtime.config().disposition_default = 10
	runtime.social.formula = Callable()
	runtime.social.set_baseline(&"keeper", &"player", &"affinity", 0.0)
	runtime.deeds.clear()
	assert_eq(runtime.social.disposition(&"keeper", &"player"), 10)


func _open() -> Dictionary:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	runtime.start_new_game(4)
	return {"host": host, "runtime": runtime}
