extends GutTest


func test_extension_license_matches_the_repo_license() -> void:
	var repo := FileAccess.get_file_as_string("res://LICENSE")
	var extension := FileAccess.get_file_as_string("res://tools/vscode-wyrd/LICENSE")
	assert_false(repo.is_empty())
	assert_eq(extension, repo)


func test_snapshot_sources_match_gullhaven() -> void:
	var names: PackedStringArray = PackedStringArray([
		"facts.wyrd",
		"harbor_scenes.wyrd",
		"harbor_storylets.wyrd",
		"harbor_documents.wyrd",
	])
	for name in names:
		var original := FileAccess.get_file_as_string("res://example/content/gullhaven/" + name)
		var copy := FileAccess.get_file_as_string("res://tools/vscode-wyrd/tests/snap/" + name)
		assert_false(original.is_empty(), name)
		assert_eq(copy, original, name)
