extends GutTest


func test_role_goldens_match_expected_json() -> void:
	var names := WyrdRoleGolden.case_names()
	assert_gt(names.size(), 0)
	for file_name in names:
		var base := file_name.trim_suffix(".wyrd")
		var case_path := "%s/%s" % [WyrdRoleGolden.CASES_DIR, file_name]
		var expected_path := "%s/%s.json" % [WyrdRoleGolden.EXPECTED_DIR, base]
		assert_true(FileAccess.file_exists(expected_path), "missing %s; run tools/update_goldens.sh" % expected_path)
		var source := WyrdSource.load_file(case_path)
		assert_not_null(source, case_path)
		var actual := WyrdGolden.to_json(WyrdRoleGolden.compile(source))
		var expected := FileAccess.get_file_as_string(expected_path)
		assert_eq(actual, expected, base)
