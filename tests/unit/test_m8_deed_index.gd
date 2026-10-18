extends GutTest

## Witness and time-bucket indexes match a full deed walk.


func test_indexed_snapshot_matches_the_full_scan() -> void:
	var runtime := _runtime()
	runtime.deeds.import_state({
		"next": 2,
		"rows": [{
			"actor": "",
			"id": 1,
			"perception": ["saw"],
			"t": 3,
			"target": "ferry",
			"verb": "paid",
			"witnesses": ["dock_hand"],
		}],
	})
	runtime.deeds.record(&"paid", &"player", &"ferry", &"gullhaven", PackedStringArray(), 2.0, PackedStringArray([&"dock_hand", &"lane_watch"]), &"public", false)
	runtime.tick(50)
	runtime.deeds.record(&"arrived", &"dock_hand", &"player", &"slip", PackedStringArray([&"toll"]), 1.0, PackedStringArray([&"ferry"]), &"witnessed", false)
	runtime.tick(80)
	runtime.deeds.record(&"whispered", &"ferry", &"player", &"slip", PackedStringArray(), 4.0, PackedStringArray([&"dock_hand"]), &"secret", true)
	runtime.social.set_baseline(&"ferry", &"player", &"affinity", 4.0)
	runtime.social.set_kind(&"player", &"ferry", &"crew")
	runtime.config().axis_verbs = PackedStringArray(["paid"])
	runtime.config().axis_names = PackedStringArray(["affinity"])
	runtime.config().axis_deltas = PackedFloat64Array([-2.0])
	var indexed := _sections(runtime)
	var counted := runtime.deeds.count_matching(&"player", &"paid", &"ferry")
	var scored := runtime.deeds.score_matching(&"", null, null, null, 60, PackedStringArray())
	var mode := String(runtime.deeds.mode_of(&"dock_hand", &"whispered"))
	runtime.deeds.set_lookup(false)
	var scanned := _sections(runtime)
	assert_eq(JSON.stringify(indexed), JSON.stringify(scanned))
	assert_eq(runtime.deeds.count_matching(&"player", &"paid", &"ferry"), counted)
	assert_eq(runtime.deeds.score_matching(&"", null, null, null, 60, PackedStringArray()), scored)
	assert_eq(String(runtime.deeds.mode_of(&"dock_hand", &"whispered")), mode)
	assert_eq(counted, 1)
	assert_eq(mode, "saw")
	assert_gt((indexed["deeds"]["rows"] as Array).size(), 2)
	assert_false(_find(indexed["deeds"], "/paid/ferry").is_empty())
	assert_false(_find(indexed["social"], "ferry/player").is_empty())
	assert_false(_find(indexed["precedence"], "dock_hand").is_empty())
	assert_false(_find(indexed["precedence"], "ferry").is_empty())
	var saved := runtime.save_state()
	assert_eq(int(saved["schema_version"]), 3)
	assert_false(JSON.stringify(saved).contains("by_witness"))
	assert_false(JSON.stringify(saved).contains("deed_index"))


func test_deed_index_trace_is_filterable_and_load_is_quiet() -> void:
	var runtime := _runtime()
	runtime.deeds.record(&"paid", &"player", &"ferry", &"", PackedStringArray(), 1.0, PackedStringArray([&"dock_hand"]), &"public", false)
	runtime.trace.enabled = true
	runtime.debug.snapshot(PackedStringArray(["deeds"]), "player")
	var hits := _index_rows(runtime)
	assert_eq(hits.size(), 1)
	assert_eq(str(hits[0]["scope"]), "deeds")
	assert_eq(str(hits[0]["key"]), "player")
	assert_gt(int(hits[0]["ids"]), 0)
	runtime.trace.clear()
	runtime.trace.prefix = "missing-prefix"
	runtime.debug.snapshot(PackedStringArray(["social", "precedence"]), "dock")
	assert_eq(_index_rows(runtime).size(), 0)
	runtime.trace.prefix = "precedence"
	runtime.debug.snapshot(PackedStringArray(["precedence"]), "")
	var named := _index_rows(runtime)
	assert_eq(named.size(), 1)
	assert_eq(str(named[0]["scope"]), "precedence")
	runtime.deeds.set_lookup(false)
	runtime.trace.prefix = ""
	runtime.trace.clear()
	runtime.debug.snapshot(PackedStringArray(["deeds", "social", "precedence"]))
	assert_eq(_index_rows(runtime).size(), 0)
	runtime.trace.clear()
	runtime.deeds.import_state(runtime.deeds.export_state())
	assert_eq(_index_rows(runtime).size(), 0)


func test_time_window_follows_the_hour_bucket() -> void:
	var runtime := _runtime()
	runtime.deeds.record(&"paid", &"player", &"ferry", &"", PackedStringArray(), 1.0, PackedStringArray([&"dock_hand"]), &"public", false)
	runtime.tick(100)
	runtime.deeds.record(&"paid", &"player", &"ferry", &"", PackedStringArray(), 3.0, PackedStringArray([&"lane_watch"]), &"public", false)
	assert_eq(runtime.deeds.time_buckets(), 2)
	assert_eq(runtime.deeds.witness_buckets(), 2)
	var early := runtime.deeds.score_matching(&"player", &"paid", null, null, 40, PackedStringArray())
	runtime.deeds.set_lookup(false)
	assert_eq(runtime.deeds.score_matching(&"player", &"paid", null, null, 40, PackedStringArray()), early)
	runtime.deeds.set_lookup(true)
	runtime.config().hour_bucket_minutes = 1000
	assert_eq(runtime.deeds.time_buckets(), 1)
	assert_eq(runtime.deeds.time_refs(), 2)
	var widened := runtime.deeds.score_matching(&"player", &"paid", null, null, 40, PackedStringArray())
	runtime.deeds.set_lookup(false)
	assert_eq(runtime.deeds.score_matching(&"player", &"paid", null, null, 40, PackedStringArray()), widened)


func test_hour_bucket_keeps_append_order() -> void:
	var runtime := _runtime()
	runtime.deeds.import_state({
		"next": 5,
		"rows": [
			{"actor": "ada", "id": 1, "perception": ["saw"], "t": 20, "verb": "paid", "witnesses": ["bea"]},
			{"actor": "ada", "id": 2, "perception": ["saw"], "t": 5, "verb": "paid", "witnesses": ["bea"]},
			{"actor": "ada", "id": 3, "perception": ["saw"], "t": 40, "verb": "paid", "witnesses": ["bea"]},
			{"actor": "ada", "id": 4, "perception": ["saw"], "t": 80, "verb": "paid", "witnesses": ["bea"]},
		],
	})
	assert_eq(runtime.deeds.rows_for_deed_prefix(""), PackedInt32Array([0, 1, 2, 3]))
	var hour: Variant = runtime.deeds._by_time[0]
	assert_true(hour is PackedInt32Array)
	assert_eq(hour, PackedInt32Array([0, 1, 2]))
	var witness: Variant = runtime.deeds._by_witness["bea"]
	assert_true(witness is PackedInt32Array)
	assert_eq(witness, PackedInt32Array([0, 1, 2, 3]))
	runtime.deeds.record(&"paid", &"ada")
	assert_eq(runtime.deeds.rows_for_deed_prefix(""), PackedInt32Array([0, 1, 2, 4, 3]))
	assert_true(runtime.deeds._by_time[0] is PackedInt32Array)
	assert_eq(runtime.deeds._by_time[0], PackedInt32Array([0, 1, 2, 4]))
	assert_true(runtime.deeds._by_witness["bea"] is PackedInt32Array)
	assert_eq(runtime.deeds.time_buckets(), 2)
	assert_eq(runtime.deeds.time_refs(), 5)


func test_full_scale_index_stays_lean() -> void:
	# Mirrors bench/scale_pack.gd witness and minute assignment for the full profile.
	# text_bytes is witness names, bucket labels, and 4 bytes per row ref.
	var total := 50000
	var npcs := 500
	var mergeable := (total * 4) / 5
	var rows: Array = []
	for index in total:
		var minute := 0
		var witness := ""
		if index < mergeable:
			var bucket := index % 32
			minute = bucket
			witness = "dock_hand_%03d" % ((bucket + 1) % npcs)
		else:
			minute = 1000 + index
			witness = "dock_hand_%03d" % ((index + 1) % npcs)
		var mode := "saw" if index < mergeable else "heard"
		rows.append({
			"actor": "dock_hand_%03d" % (index % npcs),
			"id": index + 1,
			"perception": [mode],
			"t": minute,
			"target": "player",
			"verb": "paid",
			"witnesses": [witness],
		})
	var log := WyrdDeedLog.new()
	log.import_state({"next": total + 1, "rows": rows})
	assert_eq(log.size(), total)
	assert_eq(log.witness_buckets(), 500)
	assert_eq(log.witness_refs(), total)
	assert_eq(log.time_buckets(), 168)
	assert_eq(log.time_refs(), total)
	assert_eq(log.rows_for_deed_prefix("").size(), total)
	assert_eq(log.index_text_bytes(), 407336)
	assert_lt(log.index_text_bytes(), 512 * 1024)


func _sections(runtime: WyrdRuntime) -> Dictionary:
	var shot := runtime.debug.snapshot(PackedStringArray(["deeds", "social", "precedence"]))
	var narrowed := runtime.debug.snapshot(PackedStringArray(["deeds", "social", "precedence"]), "dock")
	var rooted := runtime.debug.snapshot(PackedStringArray(["deeds"]), "/")
	return {"deeds": shot["deeds"], "narrowed": narrowed, "precedence": shot["precedence"], "rooted": rooted["deeds"], "social": shot["social"]}


func _find(section: Dictionary, key: String) -> Dictionary:
	var rows: Array = section["rows"]
	for item in rows:
		var row: Dictionary = item
		if str(row.get("key", "")) == key:
			return row
	return {}


func _index_rows(runtime: WyrdRuntime) -> Array:
	var rows: Array = []
	for item in runtime.trace.snapshot():
		var row: Dictionary = item
		if str(row["kind"]) == "deed_index":
			rows.append(row)
	return rows


func _runtime() -> WyrdRuntime:
	var runtime := WyrdRuntime.new()
	runtime.start_new_game(5)
	return runtime
