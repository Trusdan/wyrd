extends GutTest

## Keep these rows, targets, and codes in step with docs/m3-exit-demo.md.
## The W_CLAIM row is the intentional Gullhaven baseline (M3P8Q6a).

const _SOURCE := "res://example/content/gullhaven/"
const _ROOT := "user://m3_exit/"
const _MANIFEST := "example/content/gullhaven/harbor.wyrdmanifest.tres"
const _EDIT_LINE := 13
const _EDIT_COLUMN := 17
const _BASELINE: PackedStringArray = [
	"res://example/content/gullhaven/harbor_storylets.wyrd:4:1: info[I_STORYLET_SCORE]: storylet \"harbor_gossip.generic\" specificity 0 priority 0 generic=true",
	"res://example/content/gullhaven/harbor_storylets.wyrd:9:1: info[I_STORYLET_SCORE]: storylet \"harbor_gossip.tavern\" specificity 2 priority 0 generic=false",
	"res://example/content/gullhaven/harbor_storylets.wyrd:19:1: info[I_STORYLET_SCORE]: storylet \"dock_bark_lantern\" specificity 1 priority 0 generic=false",
	"res://example/content/gullhaven/harbor_storylets.wyrd:26:1: info[I_STORYLET_SCORE]: storylet \"dock_bark_lantern_carried\" specificity 2 priority 0 generic=false",
	"res://example/content/gullhaven/harbor_storylets.wyrd:33:1: info[I_STORYLET_SCORE]: storylet \"dock_voice_crossing\" specificity 0 priority 0 generic=true",
	"res://example/content/gullhaven/harbor_storylets.wyrd:48:1: info[I_STORYLET_SCORE]: storylet \"harbor_ledger.open\" specificity 0 priority 0 generic=true",
	"res://example/content/gullhaven/harbor_storylets.wyrd:55:1: info[I_STORYLET_SCORE]: storylet \"harbor_ledger.sealed\" specificity 1 priority 1 generic=false",
	"res://example/content/gullhaven/harbor_storylets.wyrd:63:1: info[I_STORYLET_SCORE]: storylet \"harbor_gossip.storm\" specificity 0 priority 0 generic=true",
	"res://example/content/gullhaven/harbor_tale.wyrd:42:41: warning[W_CLAIM]: interpolation presents \"harbor.toll_fate\" as a claim",
	"res://example/content/gullhaven/harbor_templates.wyrd:30:1: info[I_TEMPLATE_SCORE]: template \"net_delivery\" specificity 1 priority 2",
	"res://example/content/gullhaven/harbor_templates.wyrd:50:1: info[I_TEMPLATE_SCORE]: template \"stolen_catch\" specificity 1 priority 4",
	"res://example/content/gullhaven/harbor_templates.wyrd:74:1: info[I_TEMPLATE_SCORE]: template \"cut_line\" specificity 1 priority 5",
	"res://example/content/gullhaven/harbor_templates.wyrd:101:1: info[I_TEMPLATE_SCORE]: template \"night_walk\" specificity 1 priority 3",
	"res://example/content/gullhaven/harbor_templates.wyrd:123:1: info[I_TEMPLATE_SCORE]: template \"tavern_stew_low\" specificity 1 priority 1",
	"res://example/content/gullhaven/harbor_templates.wyrd:145:1: info[I_TEMPLATE_SCORE]: template \"tavern_stew_mid\" specificity 1 priority 1",
	"res://example/content/gullhaven/harbor_templates.wyrd:167:1: info[I_TEMPLATE_SCORE]: template \"tavern_stew_high\" specificity 2 priority 1",
]
const _CODES: PackedStringArray = [
	"W_EMPTY_UNCOVERED",
	"W_LOCKED_GONE_UNCOVERED",
	"E_UNKNOWN_FACT",
	"W_ROLE_UNKNOWN",
	"E_UNKNOWN_FUNCTION",
	"W_STAGE_UNREACHABLE",
	"E_LINE_ID_DUPLICATE",
	"E_LINE_ID_MISSING",
	"E_RESOLVER_NO_INVALIDATE",
	"W_STORYLET_TIE",
	"W_SUBSTATE_DEPTH",
	"E_VOICED_VARIABLE",
	"E_FACT_LEAK",
	"W_FACT_NEVER_READ",
	"W_FACT_NEVER_SET",
	"W_SECRECY_LEAK",
]


func after_each() -> void:
	_wipe(_ROOT.trim_suffix("/"))


func test_an_edit_shows_as_a_wyrd_row_and_the_fix_clears_it() -> void:
	var live: Dictionary = WyrdCli.execute(PackedStringArray(["check", "--manifest", _MANIFEST]))
	assert_eq(int(live["exit_code"]), 0, str(live["output"]))
	assert_eq(str(live["output"]), "\n".join(_BASELINE) + "\n")
	var manifest_path := _copy_pack()
	var watch := WyrdCheckWatch.new(
		{"manifest": manifest_path, "note_path": ""},
		PackedStringArray(["check", "--manifest", manifest_path])
	)
	var copied := _baseline_rows()
	var first := _cycle(watch.tick(0))
	assert_eq(str(first["finished"]), "wyrd: check finished errors=0 warnings=1")
	assert_eq(first["rows"], copied)
	var crate := _ROOT + "dock_crate.wyrd"
	var original := FileAccess.get_file_as_string(crate)
	assert_eq(original.split("\n")[_EDIT_LINE - 1].strip_edges(), "waits_until false")
	_write(crate, original.replace("waits_until false", "waits_until harbor.crate_missing"))
	var edited := _cycle(watch.tick(500))
	assert_eq(str(edited["finished"]), "wyrd: check finished errors=1 warnings=1")
	var error_row := "%s:%d:%d: error[E_UNKNOWN_FACT]: unknown fact \"harbor.crate_missing\"" % [crate, _EDIT_LINE, _EDIT_COLUMN]
	var expected := PackedStringArray()
	expected.append(error_row)
	expected.append_array(copied)
	assert_eq(edited["rows"], expected)
	var matcher := _wyrd_matcher()
	var errors := 0
	for row in edited["rows"]:
		var found := matcher.search(str(row))
		assert_ne(found, null, str(row))
		if str(found.get_string(5)) == "E_UNKNOWN_FACT":
			errors += 1
			assert_eq(str(found.get_string(1)), crate)
			assert_eq(int(found.get_string(2)), _EDIT_LINE)
			assert_eq(int(found.get_string(3)), _EDIT_COLUMN)
			assert_eq(str(found.get_string(4)), "error")
	assert_eq(errors, 1)
	_write(crate, original)
	var restored := _cycle(watch.tick(1000))
	assert_eq(str(restored["finished"]), "wyrd: check finished errors=0 warnings=1")
	assert_eq(restored["rows"], copied)


func test_every_demo_f12_target_is_in_defs() -> void:
	var result: Dictionary = WyrdCli.execute(PackedStringArray(["defs", "--manifest", _MANIFEST]))
	assert_eq(int(result["exit_code"]), 0, str(result["output"]))
	var tags := str(result["output"])
	var pattern := _word_pattern()
	for target in _targets():
		var row: Dictionary = target
		var line := "%s\t%s\t%d;\"\t%s" % [str(row["id"]), str(row["file"]), int(row["line"]), str(row["kind"])]
		assert_true(tags.contains(line + "\n"), line)
		if not bool(row["plain"]):
			var partial := pattern.search(str(row["id"]))
			var whole: bool = partial != null and partial.get_start() == 0 and partial.get_string() == str(row["id"])
			assert_false(whole, str(row["id"]))
			continue
		var source := FileAccess.get_file_as_string("res://" + str(row["ref_file"])).split("\n")
		var text := source[int(row["ref_line"]) - 1]
		assert_true(text.contains(str(row["id"])), text)
		var matched := false
		for item in pattern.search_all(text):
			if item.get_string() == str(row["id"]):
				matched = true
		assert_true(matched, str(row["id"]))


func test_pot_has_a_scene_line_and_document_paragraphs() -> void:
	var result: Dictionary = WyrdCli.execute(PackedStringArray(["pot", "--manifest", _MANIFEST]))
	assert_eq(int(result["exit_code"]), 0, str(result["output"]))
	var body := str(result["output"])
	_context(body, "crate_line", "example/content/gullhaven/dock_crate.wyrd", 16)
	_context(body, "sched_title", "example/content/gullhaven/harbor_documents.wyrd", 4)
	_context(body, "sched_plain", "example/content/gullhaven/harbor_documents.wyrd", 7)


func test_m3_lint_codes_exist() -> void:
	var inventory := FileAccess.get_file_as_string("res://tests/golden/test_golden_inventory.gd")
	assert_true(inventory.contains("res://addons/wyrd/compiler/wyrd_diagnostic.gd"))
	var diagnostic := FileAccess.get_file_as_string("res://addons/wyrd/compiler/wyrd_diagnostic.gd")
	var listed := RegEx.new()
	assert_eq(listed.compile("const (E_[A-Z0-9_]+|W_[A-Z0-9_]+|I_[A-Z0-9_]+): StringName"), OK)
	var names := PackedStringArray()
	for item in listed.search_all(diagnostic):
		names.append(item.get_string(1))
	for code in _CODES:
		assert_true(names.has(code), code)
		assert_true(diagnostic.contains("const %s: StringName = &\"%s\"" % [code, code]), code)
		assert_false(inventory.contains("\"%s\"" % code), code)


func _targets() -> Array:
	return [
		_target("dock.crate_talk", "g", "example/content/gullhaven/dock_crate.wyrd", 15, "example/content/gullhaven/dock_crate.wyrd", 11, true),
		_target("harbor.rope_done", "f", "example/content/gullhaven/facts.wyrd", 20, "example/content/gullhaven/bell_repair.wyrd", 23, true),
		_target("cross", "s", "example/content/gullhaven/ferry_toll.wyrd", 34, "example/content/gullhaven/ferry_toll.wyrd", 32, true),
		_target("ferry_toll", "q", "example/content/gullhaven/ferry_toll.wyrd", 4, "example/content/gullhaven/harbor_documents.wyrd", 8, true),
		_target("ferry_master", "r", "example/content/gullhaven/harbor_roles.wyrd", 9, "example/content/gullhaven/harbor_documents.wyrd", 9, true),
		_target("npc.{id}.alive", "f", "example/content/gullhaven/facts.wyrd", 31, "", 0, false),
	]


func _target(id: String, kind: String, file: String, line: int, ref_file: String, ref_line: int, plain: bool) -> Dictionary:
	return {
		"file": file,
		"id": id,
		"kind": kind,
		"line": line,
		"plain": plain,
		"ref_file": ref_file,
		"ref_line": ref_line,
	}


func _copy_pack() -> String:
	_wipe(_ROOT.trim_suffix("/"))
	DirAccess.make_dir_recursive_absolute(_ROOT)
	var spec := load("res://" + _MANIFEST) as WyrdContentManifest
	var copies := PackedStringArray()
	for listed in spec.files:
		var dest := _ROOT + str(listed).get_file()
		_write(dest, FileAccess.get_file_as_string(str(listed)))
		copies.append(dest)
	_write(_ROOT + "wyrd_commands.json", FileAccess.get_file_as_string(_SOURCE + "wyrd_commands.json"))
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = spec.pack_id
	manifest.language_version = spec.language_version
	manifest.files = copies
	var path := _ROOT + "harbor.wyrdmanifest.tres"
	assert_eq(ResourceSaver.save(manifest, path), OK)
	return path


func _baseline_rows() -> PackedStringArray:
	var rows := PackedStringArray()
	for line in _BASELINE:
		rows.append(line.replace(_SOURCE, _ROOT))
	return rows


func _cycle(text: String) -> Dictionary:
	assert_false(text.is_empty(), text)
	assert_true(text.begins_with("wyrd: check started\n"), text)
	assert_true(text.ends_with("\n"), text)
	var lines := text.split("\n")
	assert_eq(lines[lines.size() - 1], "")
	lines.remove_at(lines.size() - 1)
	assert_eq(lines[0], "wyrd: check started")
	var rows := PackedStringArray()
	for index in range(1, lines.size() - 1):
		rows.append(lines[index])
	return {"finished": lines[lines.size() - 1], "rows": rows}


func _wyrd_matcher() -> RegEx:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/vscode-wyrd/package.json"))
	var root: Dictionary = parsed
	var contributes: Dictionary = root["contributes"]
	var matchers: Array = contributes["problemMatchers"]
	var pattern := ""
	for item in matchers:
		var row: Dictionary = item
		if str(row["name"]) == "wyrd":
			var body: Dictionary = row["pattern"]
			pattern = str(body["regexp"])
	var expression := RegEx.new()
	assert_eq(expression.compile(pattern), OK)
	return expression


func _word_pattern() -> RegEx:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/vscode-wyrd/language-configuration.json"))
	var root: Dictionary = parsed
	var expression := RegEx.new()
	assert_eq(expression.compile(str(root["wordPattern"])), OK)
	return expression


func _context(body: String, id: String, file: String, line: int) -> void:
	var needle := "#: %s:%d\nmsgctxt \"%s\"" % [file, line, id]
	assert_true(body.contains(needle), needle)


func _write(path: String, body: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, path)
	file.store_string(body)


func _wipe(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		return
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name != "." and file_name != "..":
			_wipe(path.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
