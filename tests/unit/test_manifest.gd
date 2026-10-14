extends GutTest


func test_manifest_lists_only_its_files() -> void:
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray(["res://tests/golden/link/clean/quest.wyrd"])
	assert_eq(String(manifest.pack_id), "harbor")
	assert_eq(manifest.language_version, 1)
	var diagnostics := WyrdDiagnostics.new()
	var pack := WyrdPack.compile(manifest.files, String(manifest.pack_id), manifest.language_version, null, diagnostics)
	assert_eq(pack.units.size(), 1)
	assert_eq(pack.pack_id, "harbor")
	assert_true(diagnostics.format().contains("error[E_SCENE_UNKNOWN]"))


func test_command_file_registers_names() -> void:
	var path := "user://wyrd_commands_case.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{\"commands\":[\"assign_lodging\"]}\n")
	file.close()
	var diagnostics := WyrdDiagnostics.new()
	var read := WyrdPack.read_commands(path, diagnostics)
	var schema: WyrdCommandSchema = read["schema"]
	assert_true(schema.has_command(&"assign_lodging"))
	assert_true(bool(read["skip_note"]))
	var missing := WyrdPack.read_commands("user://wyrd_commands_absent.json", diagnostics)
	assert_null(missing["schema"])
	assert_false(bool(missing["skip_note"]))
