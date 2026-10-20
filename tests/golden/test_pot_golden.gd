extends GutTest


func test_gullhaven_pot_matches_the_golden() -> void:
	var expected := FileAccess.get_file_as_string("res://tests/golden/pot/gullhaven.pot")
	assert_eq(WyrdPotGolden.render(), expected)
