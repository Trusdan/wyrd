extends GutTest

## The link-time storylet index returns the same winners as a full scan.


func test_indexed_winners_match_the_full_scan() -> void:
	var indexed := _boot(_PACK, 5)
	var scanned := _boot(_PACK, 5)
	assert_ne(indexed.content().storylet_index, null)
	scanned.content().storylet_index = null
	var left := _script(indexed)
	var right := _script(scanned)
	assert_eq(JSON.stringify(left), JSON.stringify(right))
	assert_eq(str(left[1]["id"]), "harbor.capital")
	assert_eq(int(left[1]["candidates"]), 3)
	assert_eq(str(left[2]["id"]), "harbor.capital")
	assert_eq(str(left[3]["id"]), "harbor.capital")
	assert_eq(str(left[4]["id"]), "harbor.named")
	assert_eq(int(left[4]["candidates"]), 2)
	assert_eq(str(left[4]["score"]), "2/0/1/0")
	assert_eq(str(left[5]["id"]), "harbor.wild")
	assert_eq(int(left[5]["candidates"]), 1)
	assert_eq(str(left[6]["reason"]), "cooldown")
	assert_eq(str(left[6]["winner"]), "")
	assert_true(str(left[7]["id"]) == "harbor.pair_east" or str(left[7]["id"]) == "harbor.pair_west")
	assert_eq(str(left[8]["id"]), "harbor.other")
	assert_eq(str(left[9]["id"]), "")
	assert_eq(int(left[9]["candidates"]), 0)
	assert_eq(str(left[10]["id"]), "harbor.bark_named")
	assert_eq(str(left[11]["id"]), "harbor.bark_named")
	assert_eq(str(left[12]["id"]), "harbor.bark_named")
	assert_eq(str(left[13]["id"]), "harbor.event_named")
	assert_eq(str(left[14]["id"]), "harbor.beat_offer")
	var rows: Array = left[15]["rows"]
	assert_eq(rows.size(), 2)
	assert_eq(str(rows[0]), "harbor.named")
	assert_eq(str(rows[1]), "harbor.wild")


func test_storylet_index_trace_is_filterable() -> void:
	var runtime := _boot(_PACK, 5)
	runtime.trace.enabled = true
	runtime.director.query("topic", "rumor.harbor", "ferry")
	var hits := _index_rows(runtime)
	assert_eq(hits.size(), 1)
	assert_eq(str(hits[0]["scope"]), "topic rumor.harbor")
	assert_eq(str(hits[0]["speaker"]), "ferry")
	assert_eq(str(hits[0]["key"]), "rumor.harbor")
	assert_eq(int(hits[0]["ids"]), 2)
	runtime.trace.clear()
	runtime.trace.prefix = "missing-prefix"
	runtime.director.query("topic", "rumor.harbor", "ferry")
	assert_eq(_index_rows(runtime).size(), 0)
	runtime.trace.prefix = "rumor.harbor"
	runtime.director.query("bark", "", "ferry")
	assert_eq(_index_rows(runtime).size(), 0)
	runtime.trace.prefix = ""
	runtime.config().trace_director = true
	runtime.trace.clear()
	runtime.director.query("topic", "rumor.harbor", "ferry")
	assert_eq(_index_rows(runtime).size(), 2)
	runtime.content().storylet_index = null
	runtime.trace.clear()
	runtime.director.query("topic", "rumor.harbor", "ferry")
	assert_eq(_index_rows(runtime).size(), 0)


func test_load_does_not_log_the_index_and_the_save_omits_it() -> void:
	var compiled := _compile(_PACK)
	var diagnostics: WyrdDiagnostics = compiled["diagnostics"]
	assert_false(diagnostics.has_errors(), diagnostics.format())
	var runtime := WyrdRuntime.new()
	runtime.trace.enabled = true
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([str(compiled["path"])])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	assert_ne(runtime.content().storylet_index, null)
	assert_eq(_index_rows(runtime).size(), 0)
	runtime.start_new_game(5)
	var saved := runtime.save_state()
	assert_eq(int(saved["schema_version"]), 4)
	assert_false(saved.has("storylet_index"))


func test_duplicate_id_keeps_the_last_speaker_once() -> void:
	var first := WyrdStoryletDef.new()
	first.id = "harbor.twice"
	first.scope_kind = &"topic"
	first.scope_id = "rumor.harbor"
	first.speaker = "ferry"
	var second := WyrdStoryletDef.new()
	second.id = "harbor.twice"
	second.scope_kind = &"topic"
	second.scope_id = "rumor.harbor"
	second.speaker = "any"
	var index := WyrdStoryletIndex.new()
	index.build([first, second])
	assert_eq(index.id_count(), 1)
	assert_eq(index.bucket_count(), 1)
	var named := index.ids_for(&"topic", "rumor.harbor", "ferry")
	assert_eq(named.size(), 1)
	assert_eq(String(named[0]), "harbor.twice")


func test_full_scale_index_stays_lean() -> void:
	# Mirrors bench/scale_pack.gd speaker assignment for the full profile.
	# text_bytes is stored id text plus bucket keys, not a timed sample.
	var total := 4000
	var topics := 80
	var speakers := 20
	var stories: Array = []
	for index in total:
		var topic := index % topics
		var slot := int(index / float(topics))
		var speaker := "any"
		if slot > 0:
			speaker = "dock_hand_%03d" % ((slot - 1) % speakers)
		var story := WyrdStoryletDef.new()
		story.id = "harbor.line_%05d" % index
		story.scope_kind = &"topic"
		story.scope_id = "rumor.scale_%02d" % topic
		story.speaker = speaker
		stories.append(story)
	var index := WyrdStoryletIndex.new()
	index.build(stories)
	assert_eq(index.id_count(), 4000)
	assert_eq(index.bucket_count(), 1680)
	assert_eq(index.text_bytes(), 124320)
	assert_lt(index.text_bytes(), 256 * 1024)


func _script(runtime: WyrdRuntime) -> Array:
	var rows: Array = []
	rows.append(_why(runtime, "harbor.named", "topic", "rumor.harbor", "ferry"))
	rows.append(_query(runtime, "topic", "rumor.harbor", "any"))
	rows.append(_query(runtime, "topic", "rumor.harbor", ""))
	rows.append(_query(runtime, "topic", "rumor.harbor", "Any"))
	rows.append(_query(runtime, "topic", "rumor.harbor", "ferry"))
	rows.append(_query(runtime, "topic", "rumor.harbor", "ferry"))
	rows.append(_why(runtime, "harbor.named", "topic", "rumor.harbor", "ferry"))
	rows.append(_query(runtime, "topic", "rumor.pair", "ferry"))
	rows.append(_query(runtime, "topic", "rumor.other", "ferry"))
	rows.append(_query(runtime, "topic", "rumor.missing", "ferry"))
	rows.append(_query(runtime, "bark", "", "ferry"))
	rows.append(_query(runtime, "bark", "ignored", "ferry"))
	rows.append(_query(runtime, "bark", "ignored", "any"))
	rows.append(_query(runtime, "event", "tide_turned", "ferry"))
	rows.append(_query(runtime, "beat", "harbor_shift.offer", "tavern"))
	rows.append({"rows": _candidate_ids(runtime, "topic", "rumor.harbor", "ferry")})
	return rows


func _query(runtime: WyrdRuntime, kind: String, scope_id: String, speaker: String) -> Dictionary:
	var won := runtime.director.query(kind, scope_id, speaker)
	return {
		"candidates": int(won["candidates"]),
		"id": str(won["id"]),
		"score": str(won["score"]),
	}


func _why(runtime: WyrdRuntime, storylet_id: String, kind: String, scope_id: String, speaker: String) -> Dictionary:
	var row := runtime.director.why_not(storylet_id, kind, scope_id, speaker)
	return {
		"reason": str(row["reason"]),
		"winner": str(row["winner"]),
	}


func _candidate_ids(runtime: WyrdRuntime, kind: String, scope_id: String, speaker: String) -> Array:
	var ids: Array = []
	for item in runtime.director.candidate_rows(kind, scope_id, speaker):
		var row: Dictionary = item
		ids.append(str(row["storylet"]))
	return ids


func _index_rows(runtime: WyrdRuntime) -> Array:
	var rows: Array = []
	for item in runtime.trace.snapshot():
		var row: Dictionary = item
		if str(row["kind"]) == "storylet_index":
			rows.append(row)
	return rows


func _boot(body: String, seed_value: int) -> WyrdRuntime:
	var compiled := _compile(body)
	var diagnostics: WyrdDiagnostics = compiled["diagnostics"]
	assert_false(diagnostics.has_errors(), diagnostics.format())
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([str(compiled["path"])])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(seed_value)
	return runtime


func _compile(body: String) -> Dictionary:
	var path := "user://wyrd_m8_storylet_index_%d.wyrd" % body.hash()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(body.strip_edges() + "\n")
	file.close()
	var diagnostics := WyrdDiagnostics.new()
	var pack := WyrdPack.compile(PackedStringArray([path]), "harbor", 1, null, diagnostics, path, true)
	return {"diagnostics": diagnostics, "pack": pack, "path": path}


const _PACK := """
language 1
events
  tide_turned()
storylet harbor.named
  scope: topic rumor.harbor
  speaker: ferry
  priority: 2
  cooldown: 5m
  - The ferry keeps its own hour. #line:hn
storylet harbor.wild
  scope: topic rumor.harbor
  speaker: any
  priority: 1
  - The harbor repeats this one. #line:hw
storylet harbor.capital
  scope: topic rumor.harbor
  speaker: Any
  priority: 3
  - This spelling is its own speaker. #line:hc
storylet harbor.other
  scope: topic rumor.other
  speaker: ferry
  priority: 1
  - A different topic. #line:ho
storylet harbor.pair_east
  scope: topic rumor.pair
  speaker: ferry
  priority: 1
  weight: 1
  - East of the channel. #line:pe
storylet harbor.pair_west
  scope: topic rumor.pair
  speaker: ferry
  priority: 1
  weight: 1
  - West of the channel. #line:pw
storylet harbor.bark_named
  scope: bark
  speaker: ferry
  priority: 2
  - The ferry calls across the slip. #line:bn
storylet harbor.bark_wild
  scope: bark
  speaker: any
  priority: 1
  - Someone calls across the slip. #line:bw
storylet harbor.event_named
  scope: event tide_turned
  speaker: ferry
  priority: 2
  - The ferry marks the turn. #line:en
storylet harbor.event_wild
  scope: event tide_turned
  speaker: any
  priority: 1
  - The harbor marks the turn. #line:ew
storylet harbor.beat_offer
  scope: beat harbor_shift.offer
  speaker: tavern
  priority: 1
  - The shift is open. #line:bo
"""
