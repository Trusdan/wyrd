extends GutTest

## The scale pack is generated, never committed. One seed has one hash.


const _EXPECTED := "res://bench/scale_pack.sha256"


func test_full_pack_hash_is_stable() -> void:
	var first := _write("full")
	var second := _write("full")
	assert_eq(first["hash"], second["hash"], "same seed produced different bytes")
	var expected := FileAccess.get_file_as_string(_EXPECTED).strip_edges()
	assert_eq(first["hash"], expected, "update bench/scale_pack.sha256 when the generator changes")
	assert_eq(int(first["info"]["quests"]), 700)
	assert_eq(int(first["info"]["facts"]), 10000)
	assert_eq(int(first["info"]["npcs"]), 500)
	assert_eq(int(first["info"]["deeds"]), 50000)
	assert_eq(int(first["info"]["storylets"]), 4000)
	assert_eq(int(first["info"]["topics"]), 80)
	assert_eq(int(first["info"]["speakers"]), 20)
	assert_eq(_deed_rows(first["dir"]), 50000)
	assert_eq(_storylet_count(first["dir"]), 4000)
	assert_false(DirAccess.dir_exists_absolute(WyrdScalePack.rumors_root(first["dir"])))
	WyrdScalePack.write_rumors(first["dir"], "full")
	assert_eq(WyrdScalePack.hash_release(first["dir"]), first["hash"])
	_assert_rumors(first["dir"], "full", 500, 1000, 100)


func test_m7_bench_metrics_are_registered() -> void:
	var names: PackedStringArray = []
	for item in WyrdPerfScale.metrics():
		var row: Dictionary = item
		names.append(str(row["name"]))
	assert_true(names.has("debug.snapshot"))
	assert_true(names.has("debug.snapshot_page"))
	assert_true(names.has("debug.snapshot_section"))
	assert_true(names.has("director.query_coverage"))
	assert_eq(WyrdPerfScale.MEMORY_PEAK_BUDGET, 402653184.0)
	var peak_budget := 0.0
	for item in WyrdPerfScale.metrics():
		var budget_row: Dictionary = item
		if str(budget_row["name"]) == "memory.peak":
			peak_budget = float(budget_row["budget"])
	assert_eq(peak_budget, WyrdPerfScale.MEMORY_PEAK_BUDGET)
	assert_eq(WyrdPerfScale.SNAPSHOT_PREFIX, "harbor.scale_000")
	assert_eq(WyrdPerfScale.SNAPSHOT_OFFSET, 0)
	assert_eq(WyrdPerfScale.SNAPSHOT_LIMIT, 50)
	var developer: PackedStringArray = ["compile.strict", "compile.tie_lint"]
	var added: PackedStringArray = [
		"memory.quests",
		"rumor.tick",
		"scheduler.tick",
		"publish.issue",
		"deeds_known_to",
		"memory.believers",
		"memory.per_belief",
		"save.believers",
		"save.flight",
		"save.flight_bytes",
		"load.flight",
		"deeds.index",
		"deeds.scan",
		"memory.resident",
	]
	for item in WyrdPerfScale.metrics():
		var row: Dictionary = item
		var name := str(row["name"])
		if developer.has(name):
			assert_false(bool(row["absolute"]))
		else:
			assert_false(row.has("absolute"))
		if added.has(name) or name == "debug.snapshot" or name == "debug.snapshot_page" or name == "debug.snapshot_section" or name == "director.query_coverage":
			assert_eq(str(row["stat"]), "median")
			assert_gt(float(row["budget"]), 0.0)
		if name == "memory.resident":
			assert_eq(float(row["budget"]), WyrdPerfScale.MEMORY_PEAK_BUDGET)
			assert_eq(str(row["unit"]), "B")


func test_smoke_is_one_tenth_and_compiles_strict() -> void:
	var written := _write("smoke")
	assert_ne(written["hash"], FileAccess.get_file_as_string(_EXPECTED).strip_edges())
	assert_eq(int(written["info"]["quests"]), 70)
	assert_eq(int(written["info"]["facts"]), 1000)
	assert_eq(int(written["info"]["npcs"]), 50)
	assert_eq(int(written["info"]["deeds"]), 5000)
	assert_eq(int(written["info"]["storylets"]), 400)
	assert_eq(int(written["info"]["topics"]), 8)
	assert_eq(int(written["info"]["speakers"]), 2)
	assert_eq(_storylet_count(written["dir"]), 400)
	var result := WyrdCli.execute(PackedStringArray(["check", "--strict", written["dir"]]))
	assert_eq(int(result["exit_code"]), 0, str(result["output"]))
	var story_dir := WyrdScalePack.storylets_root(written["dir"])
	var stories := WyrdCli.execute(PackedStringArray(["check", "--strict", story_dir]))
	assert_eq(int(stories["exit_code"]), 0, str(stories["output"]))
	_assert_query(story_dir, 8)
	WyrdScalePack.write_rumors(written["dir"], "smoke")
	assert_eq(WyrdScalePack.hash_release(written["dir"]), written["hash"])
	_assert_rumors(written["dir"], "smoke", 50, 100, 10)
	var rumors := WyrdCli.execute(PackedStringArray([
		"check", "--strict", WyrdScalePack.rumors_root(written["dir"]),
	]))
	assert_eq(int(rumors["exit_code"]), 0, str(rumors["output"]))


func _write(profile_name: String) -> Dictionary:
	var dir := OS.get_temp_dir().path_join("wyrd-scale-%s-%d" % [profile_name, randi()])
	var digest := WyrdScalePack.write(dir, profile_name)
	_dirs.append(dir)
	return {"dir": dir, "hash": digest, "info": WyrdScalePack.read_pack(dir)}


func _assert_query(story_dir: String, topics: int) -> void:
	var runtime := WyrdRuntime.new()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"gullhaven"
	manifest.language_version = 1
	manifest.files = PackedStringArray([story_dir.path_join("scale.wyrd")])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(WyrdPerfScale.SEED)
	var winner_id := WyrdScalePack.queried_winner(topics)
	var won := runtime.director.query("topic", WyrdPerfScale.QUERY_TOPIC, WyrdPerfScale.QUERY_SPEAKER)
	assert_eq(str(won["id"]), winner_id)
	assert_eq(int(won["candidates"]), 2)
	assert_eq(int(won["priority"]), 2)
	var why := runtime.director.why_not(winner_id, "topic", WyrdPerfScale.QUERY_TOPIC, WyrdPerfScale.QUERY_SPEAKER)
	assert_true(bool(why["eligible"]))
	assert_eq(str(why["reason"]), "ok")
	assert_eq(str(why["winner"]), winner_id)
	var blocked := runtime.director.why_not("harbor.line_00000", "topic", WyrdPerfScale.QUERY_TOPIC, WyrdPerfScale.QUERY_SPEAKER)
	assert_eq(str(blocked["reason"]), "outranked")


func _storylet_count(dir: String) -> int:
	var count := 0
	var text := FileAccess.get_file_as_string(WyrdScalePack.storylets_root(dir).path_join("scale.wyrd"))
	for line in text.split("\n"):
		if line.begins_with("storylet "):
			count += 1
	return count


func _deed_rows(dir: String) -> int:
	var count := 0
	for line in FileAccess.get_file_as_string(dir.path_join("deeds.tsv")).split("\n"):
		var row := line.strip_edges()
		if row.is_empty() or row.begins_with("#"):
			continue
		count += 1
	return count


var _dirs: Array[String] = []


func _assert_rumors(dir: String, profile_name: String, npcs: int, friends: int, coarse: int) -> void:
	var root := WyrdScalePack.rumors_root(dir)
	assert_eq(root, "%s_rumors" % dir)
	var text := FileAccess.get_file_as_string(root.path_join("harbor.wyrd"))
	assert_true(text.contains("document harbor_gazette"))
	assert_true(text.contains("publishes_by harbor_council"))
	assert_true(text.contains("harbor.gazette : symbol"))
	var spec := WyrdScalePack.read_rumors(dir)
	assert_eq(str(spec["profile"]), profile_name)
	assert_eq(int(spec["npcs"]), npcs)
	assert_eq(str(spec["coarse"]), "gullhaven")
	assert_eq(str(spec["precise"]), "dock")
	assert_eq((spec["friends"] as Array).size(), friends)
	var first: PackedStringArray = (spec["friends"] as Array)[0]
	assert_eq(String(first[0]), "dock_hand_000")
	assert_eq(String(first[1]), "dock_hand_001")
	var places: Dictionary = spec["places"]
	assert_eq(places.size(), npcs)
	assert_eq(str(places["dock_hand_000"]), "gullhaven")
	assert_eq(str(places["dock_hand_%03d" % coarse]), "dock")
	var ids: PackedStringArray = []
	for item in spec["policies"]:
		var row: Dictionary = item
		ids.append(str(row["id"]))
	assert_true(ids.has("harbor_whisper"))
	assert_true(ids.has("harbor_reach"))
	for item in spec["policies"]:
		var row: Dictionary = item
		if str(row["id"]) != "harbor_whisper":
			continue
		assert_eq(str(row["verb"]), "whispered")
		assert_eq(str(row["field"]), "harbor.toll_fate")
		assert_eq(str(row["to"]), "waived")
		assert_eq(int(row["hops"]), 2)
		assert_eq(float(row["keep"]), 0.0)
		assert_eq(str(row["kind"]), "friend")


func after_each() -> void:
	for dir in _dirs:
		WyrdScalePack.remove_dir(WyrdScalePack.rumors_root(dir))
		WyrdScalePack.remove_dir(WyrdScalePack.storylets_root(dir))
		WyrdScalePack.remove_dir(dir)
	_dirs.clear()
