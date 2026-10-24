extends GutTest

## The 1.0 exit suite. Each test names the criterion it proves. No timings.


const _Load := preload("res://tests/migration/fixture_load.gd")
const _Harness := preload("res://tests/scenario/s2c_harness.gd")
const _M11 := preload("res://tests/migration/test_m11_exit.gd")
const _Docs := preload("res://tests/unit/test_docs_site.gd")
const _Api := preload("res://tests/unit/test_api_reference.gd")
const _Coverage := preload("res://tests/scenario/test_gullhaven_coverage.gd")
const _Facade := preload("res://addons/wyrd/runtime/wyrd.gd")

const CRITERIA := {
	"F1": "API freeze of the stable surface",
	"F2": "docs site",
	"F3": "polished example",
	"X1": "1.0 tag (`v1.0.0`, §5.4)",
	"X2": "every milestone suite green",
	"X3": "benchmarks, including load time, are informational and don't gate 1.0",
	"X4": "the measured load time listed in the 1.0 notes",
	"P1": "every 1.x release loads any 1.x save and every schema 1–4 save",
}

# S3 runs in the host repository.
const _MILESTONE_SUITES := {
	"S0": [
		"res://tests/unit/test_rng.gd",
		"res://tests/unit/test_hash.gd",
		"res://tests/unit/test_version.gd",
	],
	"S1": [
		"res://tests/unit/test_linker.gd",
		"res://tests/golden/test_goldens.gd",
	],
	"S2": [
		"res://tests/unit/test_s2a_load.gd",
		"res://tests/unit/test_s2b_roles.gd",
		"res://tests/unit/test_s2c_quests.gd",
		"res://tests/unit/test_s2d_save.gd",
	],
	"M1": [
		"res://tests/unit/test_statements.gd",
		"res://tests/golden/test_statement_goldens.gd",
		"res://tests/golden/test_link_goldens.gd",
	],
	"M2": [
		"res://tests/unit/test_quest_flow.gd",
		"res://tests/unit/test_facts.gd",
	],
	"M3": ["res://tests/scenario/test_m3_exit.gd"],
	"M4": ["res://tests/scenario/test_m4_matrix.gd"],
	"M5": ["res://tests/scenario/test_m5_matrix.gd"],
	"M6": ["res://tests/unit/test_m6_matrix.gd"],
	"M7": ["res://tests/scenario/test_m7_exit.gd"],
	"M8": [
		"res://tests/unit/test_m8_schema3.gd",
		"res://tests/unit/test_m8_scheduler.gd",
	],
	"M9": ["res://tests/scenario/test_m9_exit.gd"],
	"M10": [
		"res://tests/determinism/test_m10_ai_exit_replay.gd",
		"res://tests/scenario/test_m10_ai_off_equivalence.gd",
	],
	"M11": ["res://tests/migration/test_m11_exit.gd"],
	"M12": [
		"res://tests/scenario/test_1_0_exit.gd",
		"res://tests/golden/test_api_surface.gd",
		"res://tests/unit/test_m12_surface.gd",
	],
}

const _HOOKS := {
	"res://tests/golden/test_api_surface.gd": [
		"test_snapshot_matches_committed",
		"test_every_stable_class_present",
	],
	"res://tests/unit/test_m12_surface.gd": [
		"test_experimental_flags_match_the_stable_list_and_the_doc",
	],
	"res://tests/unit/test_deprecations.gd": [
		"test_stability_doc_matches_the_table",
		"test_runtime_warns_once_for_two_uses_and_once_each_for_two_ids",
	],
	"res://tests/unit/test_language_doc.gd": [
		"test_language_reference_covers_keywords_builtins_and_pointers",
	],
	"res://tests/unit/test_api_reference.gd": [
		"test_stable_pages_match_stability_doc",
		"test_index_links_every_page_and_generated_line",
	],
	"res://tests/unit/test_docs_site.gd": [
		"test_pages_quote_sources_link_files_and_name_real_api",
	],
	"res://tests/scenario/test_gullhaven_coverage.gd": [
		"test_features_are_in_the_manifest_and_the_file",
		"test_check_strict_baseline_on_both_manifests",
	],
	"res://tests/scenario/test_tutorial_walk.gd": [
		"test_sections_three_through_seven_match_the_page",
	],
}

const _DESIGN_MILESTONES: PackedStringArray = [
	"S0", "S1", "S2", "M1", "M2", "M3", "M4", "M5", "M6", "M7", "M8", "M9", "M10", "M11", "M12",
]


func test_exit_F1_snapshot_matches_and_stable_is_unmarked() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(WyrdApiGolden.EXPECTED_PATH))
	assert_true(parsed is Dictionary)
	var diffs := WyrdApiGolden.compare(WyrdApiGolden.build(), parsed)
	assert_eq(diffs.size(), 0, "\n".join(diffs))
	var classes: Dictionary = (parsed as Dictionary)["classes"]
	var marked := 0
	for stable_name in _stable_class_names(_read("res://docs/stability.md")):
		if not classes.has(stable_name):
			continue
		var entry: Dictionary = classes[stable_name]
		assert_false(bool(entry["experimental"]), stable_name)
		marked += 1
	assert_gt(marked, 0)


func test_exit_F1_deprecation_and_removed_keyword() -> void:
	var text := _read("res://docs/stability.md")
	assert_true(text.contains("## Deprecation policy"))
	var deprecated := _section(text, "## Deprecated")
	assert_true(deprecated.contains("disabled_when"))
	var removed := _section(text, "## Removed before 1.0")
	assert_true(removed.contains("known"))
	assert_true(removed.contains("1.0.0"))
	assert_true(FileAccess.file_exists("res://tests/golden/conditions/c_known_removed.wyrd"))
	var golden := _read("res://tests/golden/conditions/expected/c_known_removed.json")
	assert_true(golden.contains("E_KNOWN_REMOVED"))


func test_exit_F2_every_site_page_exists() -> void:
	for link in _Docs._INDEX_LINKS:
		var path := "res://docs/%s" % String(link)
		assert_true(FileAccess.file_exists(path), path)
	for recipe in _Docs._RECIPES:
		var path := "res://docs/cookbook/%s" % String(recipe)
		assert_true(FileAccess.file_exists(path), path)
	var index := _read("res://docs/api/index.md")
	assert_eq(index.split("\n")[0], _Api._GENERATED)


func test_exit_F2_pages_workflow_triggers() -> void:
	var text := _read("res://.github/workflows/pages.yml")
	assert_true(text.contains("pull_request:"))
	assert_true(text.contains("push:"))
	assert_true(text.contains("branches: [main]"))
	assert_true(text.contains("tags: ['v*']"))


func test_exit_F3_gullhaven_is_strict_clean_and_on_the_live_hash() -> void:
	for path in [_Coverage._GULLHAVEN, _Coverage._NEXT]:
		var result: Dictionary = WyrdCli.execute(PackedStringArray(["check", "--strict", "--manifest", path]))
		for line in String(result["output"]).split("\n"):
			var text := String(line)
			assert_false(text.contains("error["), "%s %s" % [path, text])
			if text.contains("warning["):
				assert_true(text.contains("warning[W_CLAIM]"), "%s %s" % [path, text])
	var runtime := _open(true)
	assert_eq(WyrdRng.format_u64(runtime.content().manifest_hash), "918b2aad2be7d4fa")
	assert_eq(_M11._LIVE_HASH, "918b2aad2be7d4fa")


func test_exit_X1_version_is_semver_1x() -> void:
	var version := _read("res://addons/wyrd/VERSION").strip_edges()
	var pattern := RegEx.create_from_string("^1\\.[0-9]+\\.[0-9]+$")
	assert_not_null(pattern.search(version), version)
	assert_true(_read("res://addons/wyrd/plugin.cfg").contains("version=\"%s\"" % version))
	assert_eq(WyrdRuntime.read_version(), version)
	var runtime := WyrdRuntime.new()
	assert_eq(runtime.get_version(), version)
	var facade := _Facade.new()
	assert_eq(facade.get_version(), version)
	facade.free()
	assert_eq(WyrdCli.render().split("\n")[0], "wyrd %s" % version)


func test_exit_X1_changelogs_have_the_1_0_0_section() -> void:
	var root := _read("res://CHANGELOG.md")
	var addon := _read("res://addons/wyrd/CHANGELOG.md")
	_assert_one_release_heading(root)
	_assert_one_release_heading(addon)
	assert_eq(_through_m11(root), _through_m11(addon))


func test_exit_X1_support_note_replaces_the_pre_1_0_lines() -> void:
	assert_true(_read("res://docs/stability.md").contains("## Support"))
	for path in ["res://README.md", "res://addons/wyrd/README.md"]:
		assert_false(_read(path).to_lower().contains("no support guarantee"), path)
	assert_true(_read("res://README.md").contains("docs/stability.md#support"))
	for path in ["res://README.md", "res://docs/host-checklist.md", "res://docs/CONTRIBUTING.md"]:
		var text := _read(path)
		assert_false(text.contains("Tags before 1.0"), path)
		assert_false(text.contains("`0.x` lasts until 1.0"), path)


func test_exit_X2_every_milestone_suite_is_present() -> void:
	var parsed: Variant = JSON.parse_string(_read("res://.gutconfig.json"))
	assert_true(parsed is Dictionary)
	var dirs: Array = (parsed as Dictionary).get("dirs", [])
	var keys: Array = _MILESTONE_SUITES.keys()
	keys.sort()
	var expected: Array = []
	for milestone in _DESIGN_MILESTONES:
		expected.append(milestone)
	expected.sort()
	assert_eq(keys, expected)
	assert_false(_MILESTONE_SUITES.has("S3"))
	for milestone in _MILESTONE_SUITES.keys():
		for path in _MILESTONE_SUITES[milestone]:
			var file := String(path)
			assert_true(FileAccess.file_exists(file), file)
			assert_true(_read(file).contains("func test_"), file)
			assert_true(_under_gut_dir(file, dirs), file)


func test_exit_X2_the_1_0_hooks_are_present() -> void:
	for path in _HOOKS.keys():
		var script := load(String(path)) as Script
		assert_not_null(script, String(path))
		var found := {}
		for item in script.get_script_method_list():
			found[String((item as Dictionary).get("name", ""))] = true
		for method_name in _HOOKS[path]:
			assert_true(found.has(String(method_name)), "%s %s" % [String(path), String(method_name)])


func test_exit_X3_the_benchmark_step_is_informational() -> void:
	var text := _read("res://.github/workflows/ci.yml")
	var at := text.find("- name: Benchmark (informational)")
	assert_ne(at, -1)
	assert_true(text.substr(at, 240).contains("continue-on-error: true"))


func test_exit_X4_the_1_0_0_notes_list_load_time() -> void:
	var notes := _section(_read("res://CHANGELOG.md"), "## 1.0.0")
	assert_true(notes.contains("load.time"))
	var pattern := RegEx.create_from_string("\\d+(\\.\\d+)?\\s*(ms|s)\\b")
	assert_not_null(pattern.search(notes))


func test_exit_P1_fixtures_load_and_save_as_schema_4() -> void:
	var fixtures: Dictionary = _M11._FIXTURES
	assert_gt(fixtures.size(), 0)
	for name in fixtures.keys():
		var path := String(fixtures[name])
		var data := _Load.read(path)
		var gullhaven := path.contains("gullhaven")
		var runtime := _open(gullhaven)
		var report := runtime.load_state(data)
		assert_true(report.ok, "%s %s" % [name, report.diagnostics.format()])
		assert_eq(int(runtime.save_state()["schema_version"]), 4, path)
	var fresh := _open(true).save_state()
	assert_eq(int(fresh["schema_version"]), 4)


func test_exit_every_criterion_has_a_test() -> void:
	var names: Array = []
	for item in get_script().get_script_method_list():
		names.append(String((item as Dictionary).get("name", "")))
	for id in CRITERIA.keys():
		var prefix := "test_exit_%s_" % String(id)
		var found := false
		for test_name in names:
			if String(test_name).begins_with(prefix):
				found = true
				break
		assert_true(found, "%s %s" % [id, String(CRITERIA[id])])


func _open(gullhaven: bool) -> WyrdRuntime:
	var harness := _Harness.new()
	var opened: Dictionary = harness.boot_gullhaven() if gullhaven else harness.open_pack(_Harness.HARBOR)
	var loaded: WyrdLoadReport = opened["report"]
	assert_true(loaded.ok, loaded.diagnostics.format())
	return opened["runtime"]


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _section(text: String, heading: String) -> String:
	var at := text.find(heading)
	assert_ne(at, -1, heading)
	var next := text.find("\n## ", at + heading.length())
	if next < 0:
		return text.substr(at)
	return text.substr(at, next - at)


func _through_m11(text: String) -> String:
	var marker := "## 0.9.0-" + "m11"
	var at := text.find(marker)
	assert_ne(at, -1)
	var line_end := text.find("\n", at)
	return text.substr(0, line_end + 1)


func _assert_one_release_heading(text: String) -> void:
	var pattern := RegEx.create_from_string("^## 1\\.0\\.0 - [0-9]{4}-[0-9]{2}-[0-9]{2}$")
	var count := 0
	for line in text.split("\n"):
		if pattern.search(String(line)) != null:
			count += 1
	assert_eq(count, 1)
	assert_lt(text.find("## Unreleased"), text.find("## 1.0.0 - "))


func _stable_class_names(text: String) -> PackedStringArray:
	var names := PackedStringArray()
	var in_stable := false
	for line in text.split("\n"):
		var row := String(line)
		if row.begins_with("## "):
			in_stable = row == "## Stable surface"
			continue
		if in_stable and row.begins_with("### "):
			names.append(row.substr(4).strip_edges())
	return names


func _under_gut_dir(path: String, dirs: Array) -> bool:
	for entry in dirs:
		var root := String(entry)
		if not root.ends_with("/"):
			root += "/"
		if path.begins_with(root):
			return true
	return false
