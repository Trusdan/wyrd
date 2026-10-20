extends GutTest


func test_gullhaven_defs_matches_the_golden() -> void:
	var expected := FileAccess.get_file_as_string("res://tests/golden/defs/gullhaven.tags")
	assert_eq(WyrdDefsGolden.render(), expected)
