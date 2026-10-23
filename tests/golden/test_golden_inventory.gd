extends GutTest

## Fails when a golden family, diagnostic code, or built-in drops out of the snapshots.
##
## A built-in counts when a source under tests/golden contains a call written
## as name(. A bare keyword such as role or stage does not.


const _DIAGNOSTIC_PATH := "res://addons/wyrd/compiler/wyrd_diagnostic.gd"
const _SIGNATURES_PATH := "res://addons/wyrd/compiler/wyrd_signatures.gd"
const _GOLDEN_ROOT := "res://tests/golden"

const _ALLOWLIST: PackedStringArray = [
	# Runtime and save only.
	"E_SAVE_OPEN",
	# Runtime and save only.
	"E_SAVE_POLICY",
	# Runtime and save only.
	"E_SAVE_VERSION",
	# Runtime and save only.
	"W_SAVE_MANIFEST",
	# Runtime and save only.
	"W_SAVE_TEMPLATE",
	# Runtime and save only.
	"W_SAVE_AI",
	# Runtime and save only.
	"W_SAVE_ALIAS",
	# Runtime and save only.
	"W_SAVE_STAGE",
	# Declared, never emitted.
	"E_RESOLVER_INVALIDATION",
]


func test_expected_files_have_sources() -> void:
	for json_path in _expected_json():
		assert_true(_has_source(json_path), "expected file %s has no source" % json_path)


func test_diagnostic_codes_appear_in_expected_json() -> void:
	var blob := _expected_blob()
	for code in _diagnostic_codes():
		if _ALLOWLIST.has(code):
			continue
		assert_true(
			blob.contains("\"code\": \"%s\"" % code),
			"diagnostic %s appears in no expected JSON" % code
		)


func test_builtins_appear_in_golden_sources() -> void:
	var sources := _source_blob()
	for builtin_name in _builtin_names():
		var call := RegEx.new()
		call.compile("\\b%s\\s*\\(" % builtin_name)
		assert_true(call.search(sources) != null, "built-in %s appears in no golden source" % builtin_name)


func _expected_json() -> PackedStringArray:
	var paths := PackedStringArray()
	_json_in("res://tests/golden/expected", paths)
	_json_in("res://tests/golden/conditions/expected", paths)
	_json_in("res://tests/golden/statements/expected", paths)
	_json_in("res://tests/golden/roles/expected", paths)
	var link := DirAccess.open("res://tests/golden/link")
	if link == null:
		return paths
	link.list_dir_begin()
	var name := link.get_next()
	while name != "":
		if link.current_is_dir() and not name.begins_with("."):
			var json_path := "res://tests/golden/link/%s/expected.json" % name
			if FileAccess.file_exists(json_path):
				paths.append(json_path)
		name = link.get_next()
	link.list_dir_end()
	paths.sort()
	return paths


func _json_in(dir: String, paths: PackedStringArray) -> void:
	var listing := DirAccess.open(dir)
	if listing == null:
		return
	listing.list_dir_begin()
	var name := listing.get_next()
	while name != "":
		if not listing.current_is_dir() and name.ends_with(".json"):
			paths.append(dir.trim_suffix("/") + "/" + name)
		name = listing.get_next()
	listing.list_dir_end()


func _has_source(json_path: String) -> bool:
	if json_path.begins_with("res://tests/golden/link/"):
		var dir := json_path.get_base_dir()
		var listing := DirAccess.open(dir)
		if listing == null:
			return false
		listing.list_dir_begin()
		var name := listing.get_next()
		while name != "":
			if not listing.current_is_dir() and name.ends_with(".wyrd"):
				listing.list_dir_end()
				return true
			name = listing.get_next()
		listing.list_dir_end()
		return false
	var base := json_path.get_file().trim_suffix(".json")
	var folder := json_path.get_base_dir()
	if folder.ends_with("/expected"):
		folder = folder.trim_suffix("/expected")
	if folder == "res://tests/golden":
		folder = "res://tests/golden/cases"
	return FileAccess.file_exists("%s/%s.wyrd" % [folder, base])


func _expected_blob() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for path in _expected_json():
		parts.append(FileAccess.get_file_as_string(path))
	return "\n".join(parts)


func _source_blob() -> String:
	var paths: PackedStringArray = PackedStringArray()
	_collect_wyrd(_GOLDEN_ROOT, paths)
	var parts: PackedStringArray = PackedStringArray()
	for path in paths:
		parts.append(FileAccess.get_file_as_string(path))
	return "\n".join(parts)


func _collect_wyrd(dir: String, paths: PackedStringArray) -> void:
	var listing := DirAccess.open(dir)
	if listing == null:
		return
	listing.list_dir_begin()
	var name := listing.get_next()
	while name != "":
		if not name.begins_with("."):
			var path := dir.trim_suffix("/") + "/" + name
			if listing.current_is_dir():
				_collect_wyrd(path, paths)
			elif name.ends_with(".wyrd"):
				paths.append(path)
		name = listing.get_next()
	listing.list_dir_end()


func _diagnostic_codes() -> PackedStringArray:
	var text := FileAccess.get_file_as_string(_DIAGNOSTIC_PATH)
	var codes := PackedStringArray()
	var regex := RegEx.new()
	regex.compile("const (E_[A-Z0-9_]+|W_[A-Z0-9_]+|I_[A-Z0-9_]+): StringName")
	for match in regex.search_all(text):
		codes.append(match.get_string(1))
	return codes


func _builtin_names() -> PackedStringArray:
	var text := FileAccess.get_file_as_string(_SIGNATURES_PATH)
	var start := text.find("const _BUILTINS")
	var end := text.find("]", start)
	var body := text.substr(start, end - start)
	var names := PackedStringArray()
	var regex := RegEx.new()
	regex.compile("\"([A-Za-z_][A-Za-z0-9_]*)\\(")
	for match in regex.search_all(body):
		names.append(match.get_string(1))
	return names
