extends GutTest

const _Facade := preload("res://addons/wyrd/runtime/wyrd.gd")


func test_recording_is_off_until_enabled() -> void:
	var runtime := _boot()
	assert_false(runtime.coverage.enabled)
	runtime.trace.enabled = true
	runtime.storylets.draw("harbor.rumor")
	assert_eq(runtime.coverage.count("storylet", "harbor.rumor"), 0)
	assert_eq(_rows(runtime, "coverage").size(), 0)
	runtime.coverage.hit("graph", "harbor.rumor")
	assert_eq(_rows(runtime, "coverage").size(), 0)
	runtime.coverage.enabled = true
	runtime.coverage.hit("graph", "harbor.rumor")
	assert_push_error("unknown kind")
	assert_eq(runtime.coverage.count("storylet", "harbor.rumor"), 0)


func test_hits_trace_save_and_merge() -> void:
	var runtime := _boot()
	runtime.coverage.enabled = true
	runtime.trace.enabled = true
	var drawn: Dictionary = runtime.storylets.draw("harbor.rumor")
	assert_eq(str(drawn["line_id"]), "rumor")
	assert_eq(runtime.coverage.count("storylet", "harbor.rumor"), 1)
	assert_eq(runtime.coverage.count("line", "rumor"), 1)
	runtime.trace.prefix = "harbor.late"
	runtime.trace.clear()
	runtime.storylets.draw("harbor.rumor")
	assert_eq(_rows(runtime, "coverage").size(), 0)
	runtime.trace.prefix = "harbor.rumor"
	runtime.trace.clear()
	runtime.storylets.draw("harbor.rumor")
	var kept := _rows(runtime, "coverage")
	assert_eq(kept.size(), 1)
	assert_eq(str(kept[0]["hit"]), "storylet")
	assert_eq(str(kept[0]["key"]), "harbor.rumor")
	assert_eq(int(kept[0]["count"]), 3)
	runtime.trace.prefix = ""
	runtime.trace.clear()
	var barked: Dictionary = runtime.director.query("bark", "", "ferry")
	assert_eq(str(barked["line_id"]), "bark1")
	assert_eq(runtime.coverage.count("line", "bark1"), 1)
	assert_eq(runtime.coverage.count("storylet", "harbor.bark"), 1)
	runtime.tick(0)
	assert_eq(runtime.quests.variant_of("harbor_toll"), "ferry.empty")
	assert_eq(runtime.coverage.count("variant", "harbor_toll.arrive.ferry.empty"), 1)
	assert_eq(runtime.coverage.count("line", "j_empty"), 1)
	assert_eq(runtime.coverage.count("line", "j_due"), 0)
	runtime.dialogue.open_scene("toll_booth")
	assert_eq(runtime.coverage.count("line", "booth"), 1)
	runtime.dialogue.advance()
	assert_eq(runtime.coverage.count("line", "pay"), 1)
	runtime.dialogue.choose(0)
	assert_true(runtime.can_save())
	var saved := runtime.save_state()
	assert_false(saved.has("coverage"))
	assert_eq(int(saved["schema_version"]), 2)
	var before := runtime.coverage.count("storylet", "harbor.rumor")
	runtime.start_new_game(4)
	assert_eq(runtime.coverage.count("storylet", "harbor.rumor"), before)
	var loaded := _boot()
	loaded.trace.enabled = true
	loaded.coverage.enabled = true
	assert_true(loaded.load_state(saved).ok)
	assert_eq(_rows(loaded, "coverage").size(), 0)
	assert_eq(_rows(loaded, "coverage_report").size(), 0)
	assert_eq(loaded.coverage.count("storylet", "harbor.rumor"), 0)
	var late := loaded.content().storylets["harbor.late"] as WyrdStoryletDef
	var missed: Array = loaded.coverage.missed_rows(loaded.coverage.counts())
	var row := _missed(missed, "storylet", "harbor.late")
	assert_eq(str(row["path"]), str(late.source_path))
	assert_eq(int(row["line"]), late.line)
	loaded.trace.clear()
	var table := loaded.coverage.render(loaded.coverage.counts())
	assert_true(table.contains("harbor.late"))
	assert_eq(_rows(loaded, "coverage_report").size(), 1)
	loaded.trace.prefix = "harbor.rumor"
	loaded.trace.clear()
	loaded.coverage.render(loaded.coverage.counts())
	assert_eq(_rows(loaded, "coverage_report").size(), 0)
	var path := WyrdCoverage.DEFAULT_PATH
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_true(runtime.coverage.merge(path))
	assert_eq(runtime.coverage.count("storylet", "harbor.rumor"), 0)
	loaded.coverage.enabled = true
	loaded.storylets.draw("harbor.late")
	assert_true(loaded.coverage.merge(path))
	var read: Dictionary = WyrdCoverage.read_file(path)
	assert_true(bool(read["ok"]))
	var counts: Dictionary = read["counts"]
	var stories: Dictionary = counts["storylet"]
	assert_eq(int(stories["harbor.rumor"]), before)
	assert_eq(int(stories["harbor.late"]), 1)
	assert_true(runtime.coverage.merge(path))
	var again: Dictionary = WyrdCoverage.read_file(path)
	var again_counts: Dictionary = again["counts"]
	var again_stories: Dictionary = again_counts["storylet"]
	assert_eq(int(again_stories["harbor.rumor"]), before)
	var pack := "user://wyrd_m7_coverage_pack.wyrd"
	var listed: Dictionary = WyrdCli.execute(PackedStringArray(["coverage", pack, "--file", path]))
	assert_eq(int(listed["exit_code"]), 0, str(listed["output"]))
	var ids := _ids(str(listed["output"]))
	assert_false(ids.has("harbor.rumor"), str(listed["output"]))
	assert_false(ids.has("harbor.late"), str(listed["output"]))
	assert_true(ids.has("j_due"), str(listed["output"]))
	assert_true(ids.has("harbor.set"), str(listed["output"]))
	var bad_path := "user://wyrd_m7_coverage_bad.json"
	var bad_file := FileAccess.open(bad_path, FileAccess.WRITE)
	bad_file.store_string("[]")
	bad_file.close()
	var bad: Dictionary = WyrdCli.execute(PackedStringArray(["coverage", pack, "--file", bad_path]))
	assert_eq(int(bad["exit_code"]), 1)
	assert_true(str(bad["output"]).contains("coverage file"))
	assert_push_error("file is not a JSON object")


func test_same_seed_draws_the_same_line() -> void:
	var left := _boot()
	var right := _boot()
	left.coverage.enabled = true
	right.coverage.enabled = true
	left.start_new_game(9)
	right.start_new_game(9)
	var first: Dictionary = left.storylets.draw("harbor.set")
	var second: Dictionary = right.storylets.draw("harbor.set")
	assert_eq(str(first["line_id"]), str(second["line_id"]))
	assert_eq(left.coverage.count("line", str(first["line_id"])), 1)
	assert_eq(right.coverage.count("line", str(second["line_id"])), 1)
	assert_eq(left.coverage.count("storylet", "harbor.set"), right.coverage.count("storylet", "harbor.set"))


func test_facade_coverage_starts_off() -> void:
	var node = _Facade.new()
	assert_false(node.coverage.enabled)
	assert_eq(node.coverage.count("line", "rumor"), 0)
	node.free()


func _boot() -> WyrdRuntime:
	var path := "user://wyrd_m7_coverage_pack.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(_PACK.strip_edges() + "\n")
	file.close()
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(4)
	return runtime


func _rows(runtime: WyrdRuntime, kind: String) -> Array:
	var found: Array = []
	for item in runtime.trace.events:
		if item is Dictionary and String((item as Dictionary).get("kind", "")) == kind:
			found.append(item)
	return found


func _missed(rows: Array, kind: String, id: String) -> Dictionary:
	for item in rows:
		if not (item is Dictionary):
			continue
		var row: Dictionary = item
		if String(row.get("kind", "")) == kind and String(row.get("id", "")) == id:
			return row
	return {}


func _ids(output: String) -> PackedStringArray:
	var ids := PackedStringArray()
	for raw in output.split("\n"):
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("kind ") or line.contains("]:"):
			continue
		var kind := ""
		if line.begins_with("storylet "):
			kind = "storylet"
		elif line.begins_with("variant "):
			kind = "variant"
		elif line.begins_with("line "):
			kind = "line"
		else:
			continue
		var rest := line.substr(kind.length()).strip_edges()
		var parts := rest.split(" ", false)
		if parts.is_empty():
			continue
		ids.append(parts[0])
	return ids


const _PACK := """
language 1
quest harbor_toll "Toll"
  slot ferry = ferry_master mode: live
  stage arrive
    variant ferry.empty:
      journal: The dock is empty. #line:j_empty
    journal: The toll is due. #line:j_due
scene toll_booth
  lookout: The booth is shut. #line:booth
  * [Pay the toll] -> end #line:pay
  -> end
storylet harbor.rumor
  scope: topic harbor
  speaker: any
  priority: 0
  - The ferry is late. #line:rumor
storylet harbor.late
  scope: topic harbor
  speaker: any
  priority: 1
  - Nobody came. #line:late
storylet harbor.set
  scope: topic harbor
  speaker: any
  priority: 2
  lines:
    - The tide turned. #line:set_a
    - The ropes held. #line:set_b
storylet harbor.bark
  scope: bark
  speaker: ferry
  - Mind the ropes. #line:bark1
"""
