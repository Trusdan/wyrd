extends GutTest

## Deprecation table, the once-per-id warning, and docs/stability.md.


func test_every_row_has_every_field() -> void:
	assert_gt(WyrdDeprecations.TABLE.size(), 0)
	for id in WyrdDeprecations.TABLE.keys():
		var row: Dictionary = WyrdDeprecations.TABLE[id]
		for key in ["kind", "replacement", "since", "diagnostic"]:
			assert_true(row.has(key), "%s %s" % [id, key])
		assert_false(str(row["kind"]).is_empty(), str(id))
		assert_false(str(row["replacement"]).is_empty(), str(id))
		assert_false(str(row["since"]).is_empty(), str(id))
		assert_true(str(row["kind"]) == "call" or str(row["kind"]) == "keyword", str(id))


func test_every_deprecated_code_has_one_row() -> void:
	var text := FileAccess.get_file_as_string("res://addons/wyrd/compiler/wyrd_diagnostic.gd")
	var pattern := RegEx.new()
	pattern.compile("const (W_[A-Z0-9_]*DEPRECATED)")
	var codes := {}
	for match in pattern.search_all(text):
		codes[match.get_string(1)] = true
	var by_code := {}
	for id in WyrdDeprecations.TABLE.keys():
		var code := str(WyrdDeprecations.TABLE[id]["diagnostic"])
		if code.is_empty():
			continue
		assert_false(by_code.has(code), code)
		by_code[code] = str(id)
		assert_true(codes.has(code), code)
	assert_eq(by_code.size(), codes.size(), str(codes.keys()))


func test_stability_doc_matches_the_table() -> void:
	var text := FileAccess.get_file_as_string("res://docs/stability.md")
	var start := text.find("## Deprecated")
	var finish := text.find("## Removed before 1.0")
	assert_true(start >= 0 and finish > start)
	var found := {}
	for line in text.substr(start, finish - start).split("\n"):
		if not line.begins_with("|"):
			continue
		var cells := line.split("|")
		var id := cells[1].strip_edges()
		if id == "id" or id.begins_with("-"):
			continue
		found[id] = {
			"kind": cells[2].strip_edges(),
			"replacement": cells[3].strip_edges(),
			"since": cells[4].strip_edges(),
		}
	for id in WyrdDeprecations.TABLE.keys():
		assert_true(found.has(str(id)), str(id))
		var row: Dictionary = WyrdDeprecations.TABLE[id]
		assert_eq(found[str(id)]["kind"], str(row["kind"]))
		assert_eq(found[str(id)]["replacement"], str(row["replacement"]))
		assert_eq(found[str(id)]["since"], str(row["since"]))
	assert_eq(found.size(), WyrdDeprecations.TABLE.size())
	assert_true(text.contains("E_KNOWN_REMOVED"))
	assert_true(text.contains("known was removed in 1.0; use knows(agent, key)"))


func test_runtime_warns_once_for_two_uses_and_once_each_for_two_ids() -> void:
	var runtime := WyrdRuntime.new()
	var table := {
		"sample_call": {
			"kind": "call",
			"replacement": "other_call",
			"since": "1.1.0",
			"diagnostic": "",
		},
		"sample_other": {
			"kind": "call",
			"replacement": "other_two",
			"since": "1.2.0",
			"diagnostic": "",
		},
	}
	runtime._warn_deprecated("sample_call", table)
	runtime._warn_deprecated("sample_call", table)
	runtime._warn_deprecated("sample_other", table)
	assert_push_warning("Wyrd: sample_call is deprecated since 1.1.0; use other_call")
	assert_push_warning("Wyrd: sample_other is deprecated since 1.2.0; use other_two")
	assert_push_warning_count(2)


func test_loading_disabled_when_twice_warns_once() -> void:
	var runtime := WyrdRuntime.new()
	var path := "user://wyrd_m12_disabled_when.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("""language 1
facts
  player.coins : int stored
scene room
  narrator: Hello. #line:hi
  * [Stay] disabled_when {player.coins < 1} "wait" -> end #line:c1
  * [Wait] disabled_when {player.coins < 2} "wait" -> end #line:c2
""")
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"sample"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	var uses := 0
	for item in report.diagnostics.items:
		if str(item.code) == "W_DISABLED_WHEN_DEPRECATED":
			uses += 1
	assert_eq(uses, 2, report.diagnostics.format())
	assert_push_warning("Wyrd: disabled_when is deprecated since 0.6.3-m8; use show_disabled_when")
	assert_push_warning_count(1)
