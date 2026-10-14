extends GutTest


func test_statement_goldens_match_expected_json() -> void:
	var names := WyrdStmtGolden.case_names()
	assert_gt(names.size(), 0)
	for file_name in names:
		var base := file_name.trim_suffix(".wyrd")
		var case_path := "%s/%s" % [WyrdStmtGolden.CASES_DIR, file_name]
		var expected_path := "%s/%s.json" % [WyrdStmtGolden.EXPECTED_DIR, base]
		assert_true(FileAccess.file_exists(expected_path), "missing %s; run tools/update_goldens.sh" % expected_path)
		var source := WyrdSource.load_file(case_path)
		assert_not_null(source, case_path)
		var actual := WyrdGolden.to_json(WyrdStmtGolden.compile(source))
		var expected := FileAccess.get_file_as_string(expected_path)
		assert_eq(actual, expected, base)
