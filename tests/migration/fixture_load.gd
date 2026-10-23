extends RefCounted

## Shared readers for the migration fixtures. Not a test.


static func read(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed


static func codes(report: WyrdLoadReport) -> PackedStringArray:
	var found := PackedStringArray()
	for item in report.diagnostics.items:
		found.append(String(item.code))
	found.sort()
	return found


static func pack_hash(data: Dictionary) -> String:
	var content: Dictionary = data.get("content", {})
	var packs: Array = content.get("packs", [])
	if packs.is_empty():
		return ""
	var row: Dictionary = packs[0]
	return String(row.get("hash", ""))


## W_SAVE_MANIFEST when the fixture pack hash is not the loaded Gullhaven hash.
static func manifest_warning(fixture_hash: String, current_hash: String) -> PackedStringArray:
	var expected := PackedStringArray()
	if fixture_hash != current_hash:
		expected.append("W_SAVE_MANIFEST")
	return expected
