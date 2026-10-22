extends GutTest

const _Bench := preload("res://tests/bench/wyrd_ai_bench.gd")

const _NAMES: Array[String] = ["ai.packet", "ai.validate", "ai.present_overhead", "ai.cache_lookup"]


func test_each_row_is_finite_and_stable() -> void:
	var bench := _Bench.new()
	for name in _NAMES:
		var first: Dictionary = bench.sample(name, 8)
		var second: Dictionary = bench.sample(name, 8)
		assert_false(first.has("error"), "%s %s" % [name, str(first.get("error", ""))])
		assert_false(second.has("error"), "%s %s" % [name, str(second.get("error", ""))])
		assert_gte(float(first["value"]), 0.0, name)
		assert_true(is_finite(float(first["value"])), name)
		assert_false(str(first["checksum"]).is_empty(), name)
		assert_eq(str(first["checksum"]), str(second["checksum"]), name)
		assert_eq(bench.pending_after, 0, name)


func test_packet_gossip_has_five_deeds() -> void:
	var row := _row("ai.packet")
	var extra: Dictionary = row["extra"]
	assert_true(extra.has("gossip"))
	var gossip: Dictionary = extra["gossip"]
	assert_true(gossip.has("deeds"))
	assert_eq((gossip["deeds"] as Array).size(), 5)


func test_validate_counts_each_step() -> void:
	var row := _row("ai.validate")
	var extra: Dictionary = row["extra"]
	assert_gte(int(extra["entities"]), 1)
	assert_gte(int(extra["banned"]), 1)
	assert_gte(int(extra["spoilers"]), 1)


func test_present_overhead_names_the_three_paths() -> void:
	var row := _row("ai.present_overhead")
	assert_true(str(row["checksum"]).begins_with("authored|authored|ai:"))
	var extra: Dictionary = row["extra"]
	assert_true(extra.has("authored"))
	assert_true(extra.has("fake_hit"))
	assert_true(extra.has("null_delta"))


func test_cache_lookup_counts_hits() -> void:
	var row := _row("ai.cache_lookup")
	var extra: Dictionary = row["extra"]
	assert_eq(int(extra["entries"]), 8)
	var parts := str(row["checksum"]).split(":")
	assert_eq(parts.size(), 3)
	assert_eq(int(parts[0]), 8)
	assert_eq(int(parts[1]), int(extra["entries"]) * _Bench.CACHE_PASSES)


func test_unknown_metric_and_measure() -> void:
	var bench := _Bench.new()
	var missing: Dictionary = bench.sample("ai.nope")
	assert_eq(str(missing.get("error", "")), "unknown metric ai.nope")
	var measured: Dictionary = bench.measure(8)
	assert_true(bool(measured["ok"]))
	var metrics: Dictionary = measured["metrics"]
	for name in _NAMES:
		assert_true(metrics.has(name), name)
		assert_false((metrics[name] as Dictionary).has("error"), name)
	assert_eq(bench.pending_after, 0)


func test_scale_rows_keep_the_previous_order() -> void:
	var rows: Array = WyrdPerfScale.metrics()
	var names: Array[String] = []
	for row in rows:
		names.append(str((row as Dictionary)["name"]))
	var expected: Array[String] = []
	expected.append_array(_PREVIOUS)
	expected.append_array(_NAMES)
	expected.append("memory.resident")
	assert_eq(names.size(), expected.size())
	for index in names.size():
		assert_eq(names[index], expected[index])
	assert_eq(names[names.size() - 1], "memory.resident")
	for name in _NAMES:
		var seen := 0
		for row in rows:
			var spec: Dictionary = row
			if str(spec["name"]) != name:
				continue
			seen += 1
			assert_false(bool(spec["absolute"]))
			assert_eq(str(spec["unit"]), "s")
			assert_eq(str(spec["stat"]), "median")
		assert_eq(seen, 1, name)


func test_fixture_is_outside_the_example_pack() -> void:
	var manifest := load("res://example/content/gullhaven/harbor.wyrdmanifest.tres") as WyrdContentManifest
	assert_not_null(manifest)
	assert_eq(String(manifest.pack_id), "harbor")
	assert_eq(manifest.files, _harbor_files())
	assert_false(_tree_has("res://example/content", "#line:bench_gate"))
	assert_false(_tree_has("res://example/content", "#line:bench_gossip"))
	assert_false(_tree_has("res://example/content", "#line:bench_plain"))
	assert_false(_tree_has("res://example/content", _Bench._BODY))


func _row(name: String) -> Dictionary:
	var bench := _Bench.new()
	var row: Dictionary = bench.sample(name, 8)
	assert_false(row.has("error"), str(row.get("error", "")))
	assert_eq(bench.pending_after, 0)
	return row


func _tree_has(root: String, needle: String) -> bool:
	var listing := DirAccess.open(root)
	if listing == null:
		return false
	listing.list_dir_begin()
	var file_name := listing.get_next()
	while file_name != "":
		if not file_name.begins_with("."):
			var path := root.path_join(file_name)
			if listing.current_is_dir():
				if _tree_has(path, needle):
					listing.list_dir_end()
					return true
			else:
				var text := FileAccess.get_file_as_string(path)
				if text.contains(needle):
					listing.list_dir_end()
					return true
		file_name = listing.get_next()
	listing.list_dir_end()
	return false


const _PREVIOUS: Array[String] = [
	"compile.strict",
	"tick.recheck",
	"believes.own",
	"believes.group",
	"perceive.credibility",
	"reputation.cached",
	"reputation.cold",
	"save.time",
	"save.bytes",
	"load.time",
	"compact.time",
	"memory.peak",
	"memory.steady",
	"director.query",
	"director.query_coverage",
	"director.why_not",
	"compile.tie_lint",
	"debug.snapshot",
	"debug.snapshot_page",
	"debug.snapshot_section",
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
	"generator.propose",
	"generator.cast_object",
	"generator.cast_person",
	"generator.validate",
	"generator.tick",
	"memory.generated",
	"save.generated_bytes",
	"load.generated",
]

func _harbor_files() -> PackedStringArray:
	var files := PackedStringArray()
	files.append("res://example/content/gullhaven/facts.wyrd")
	files.append("res://example/content/gullhaven/ferry_toll.wyrd")
	files.append("res://example/content/gullhaven/harbor_scenes.wyrd")
	files.append("res://example/content/gullhaven/dock_scenes.wyrd")
	files.append("res://example/content/gullhaven/harbor_bell.wyrd")
	files.append("res://example/content/gullhaven/harbor_roles.wyrd")
	files.append("res://example/content/gullhaven/harbor_guild.wyrd")
	files.append("res://example/content/gullhaven/harbor_tale.wyrd")
	files.append("res://example/content/gullhaven/harbor_storylets.wyrd")
	files.append("res://example/content/gullhaven/bell_repair.wyrd")
	files.append("res://example/content/gullhaven/harbor_gazette.wyrd")
	files.append("res://example/content/gullhaven/dock_errand.wyrd")
	files.append("res://example/content/gullhaven/dock_rumour.wyrd")
	files.append("res://example/content/gullhaven/dock_crate.wyrd")
	files.append("res://example/content/gullhaven/harbor_documents.wyrd")
	files.append("res://example/content/gullhaven/mooring_post.wyrd")
	files.append("res://example/content/gullhaven/harbor_templates.wyrd")
	return files
