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


func after_each() -> void:
	for dir in _dirs:
		WyrdScalePack.remove_dir(WyrdScalePack.storylets_root(dir))
		WyrdScalePack.remove_dir(dir)
	_dirs.clear()
