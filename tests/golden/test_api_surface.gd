extends GutTest

## The stable-surface snapshot. CI compares it and does not write it.


func test_snapshot_matches_committed() -> void:
	assert_true(FileAccess.file_exists(WyrdApiGolden.EXPECTED_PATH), WyrdApiGolden.EXPECTED_PATH)
	var actual := WyrdApiGolden.build()
	var expected_text := FileAccess.get_file_as_string(WyrdApiGolden.EXPECTED_PATH)
	var parsed: Variant = JSON.parse_string(expected_text)
	assert_true(parsed is Dictionary, "stable_api.json is not an object")
	var diffs := WyrdApiGolden.compare(actual, parsed)
	if diffs.size() > 0:
		var shown := mini(diffs.size(), 40)
		for index in shown:
			print(diffs[index])
		if diffs.size() > 40:
			print("%d more" % (diffs.size() - shown))
	assert_eq(diffs.size(), 0)
	assert_eq(WyrdApiGolden.to_json(actual), expected_text)


func test_build_is_deterministic() -> void:
	var first := WyrdApiGolden.to_json(WyrdApiGolden.build())
	var second := WyrdApiGolden.to_json(WyrdApiGolden.build())
	assert_eq(first, second)


func test_every_stable_class_present() -> void:
	var built := WyrdApiGolden.build()
	var classes: Dictionary = built["classes"]
	for row in WyrdApiGolden.STABLE_CLASSES:
		var path := str(row["path"])
		var reported := str(row["name"])
		var loaded := load(path) as Script
		assert_not_null(loaded, path)
		assert_true(classes.has(reported), reported)
		assert_eq(str(classes[reported]["path"]), path)
	var facade := load("res://addons/wyrd/runtime/wyrd.gd") as Script
	assert_not_null(facade)
	var declared := {}
	for prop in facade.get_script_property_list():
		if int(prop.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		declared[str(prop.get("name", ""))] = str(prop.get("class_name", ""))
	for member_name in WyrdApiGolden.FACADE_MEMBERS:
		var declared_name := str(declared[member_name])
		var found := false
		for row in WyrdApiGolden.STABLE_CLASSES:
			if str(row["name"]) != declared_name:
				continue
			found = true
			var member_script := load(str(row["path"])) as Script
			assert_not_null(member_script, declared_name)
			assert_eq(String(member_script.get_global_name()), declared_name)
		assert_true(found, "%s declares %s" % [member_name, declared_name])
	for member_name in ["trace", "debug", "coverage"]:
		assert_false(classes.has(str(declared[member_name])), member_name)


func test_compare_catches_renamed_argument() -> void:
	var left := WyrdApiGolden.reflect_script(load("res://tests/golden/api/fixtures/sample_a.gd"))
	var right := WyrdApiGolden.reflect_script(load("res://tests/golden/api/fixtures/sample_b.gd"))
	var diffs := WyrdApiGolden.compare(left, right)
	assert_eq(diffs.size(), 1, "\n".join(diffs))
	assert_true(diffs[0].contains("label"), diffs[0])
	assert_true(diffs[0].contains("title"), diffs[0])


func test_compare_catches_type_and_default_changes() -> void:
	var left := WyrdApiGolden.reflect_script(load("res://tests/golden/api/fixtures/sample_a.gd"))
	var right := WyrdApiGolden.reflect_script(load("res://tests/golden/api/fixtures/sample_c.gd"))
	var diffs := WyrdApiGolden.compare(left, right)
	assert_eq(diffs.size(), 2, "\n".join(diffs))
	var saw_type := false
	var saw_default := false
	for line in diffs:
		if line.contains("type"):
			saw_type = true
		if line.contains("default"):
			saw_default = true
	assert_true(saw_type, "\n".join(diffs))
	assert_true(saw_default, "\n".join(diffs))
