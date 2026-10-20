extends GutTest


func test_tag_lines_golden_matches_tag_text() -> void:
	var rendered := WyrdTagLinesGolden.render()
	var notes := FileAccess.get_file_as_string("res://tests/golden/tag_lines/harbor_ids.notes")
	var tagged := FileAccess.get_file_as_string("res://tests/golden/tag_lines/harbor_ids.tagged")
	assert_eq(str(rendered["notes"]), notes)
	assert_eq(str(rendered["text"]), tagged)
	assert_false(tagged.contains("check strength(weight: 2) on_fail -> dropped #line:"))
	assert_true(tagged.contains("variant tavern: Still waiting on the dock. #line:"))
	assert_true(tagged.contains("variant ferry: The ferry master keeps the crossing open. #line:"))
	assert_true(notes.contains(": + #line:"))
