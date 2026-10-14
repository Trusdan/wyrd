extends GutTest


func test_link_goldens_match_expected_json() -> void:
	var names := WyrdLinkGolden.case_names()
	assert_gt(names.size(), 0)
	for name in names:
		var dir := "%s/%s" % [WyrdLinkGolden.ROOT, name]
		var expected_path := "%s/expected.json" % dir
		assert_true(FileAccess.file_exists(expected_path), "missing %s; run tools/update_goldens.sh" % expected_path)
		var actual := WyrdExport.to_json(WyrdLinkGolden.compile_dir(dir))
		var expected := FileAccess.get_file_as_string(expected_path)
		assert_eq(actual, expected, name)
