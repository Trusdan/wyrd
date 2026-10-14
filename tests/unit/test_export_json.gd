extends GutTest


func test_export_is_stable_and_uses_pack_line_ids() -> void:
	var diagnostics := WyrdDiagnostics.new()
	var pack := _pack(diagnostics)
	assert_eq(diagnostics.format(), "")
	var first := WyrdExport.to_json(WyrdExport.to_data(pack))
	var second := WyrdExport.to_json(WyrdExport.to_data(pack))
	assert_eq(first, second)
	assert_true(first.contains("\"wyrd_export\": 1"))
	assert_true(first.contains("\"id\": \"harbor/aa01\""))
	assert_true(first.contains("\"hash\":"))
	var result := WyrdCli.execute(PackedStringArray(["export-json", "res://tests/golden/link/clean"]))
	var again := WyrdCli.execute(PackedStringArray(["export-json", "res://tests/golden/link/clean"]))
	assert_eq(str(result["output"]), str(again["output"]))
	assert_eq(int(result["exit_code"]), 0)


func test_facts_json_is_the_xref_part() -> void:
	var result := WyrdCli.execute(PackedStringArray(["facts", "--json", "res://tests/golden/link/clean"]))
	assert_eq(int(result["exit_code"]), 0, str(result["output"]))
	assert_true(str(result["output"]).contains("\"facts\""))
	assert_true(str(result["output"]).contains("player.coins"))
	assert_false(str(result["output"]).contains("wyrd_export"))
	var table := WyrdCli.execute(PackedStringArray(["facts", "res://tests/golden/link/clean"]))
	assert_true(str(table["output"]).contains("player.coins"))
	assert_true(str(table["output"]).contains("writers"))
	assert_eq(int(table["exit_code"]), 0)


func _pack(diagnostics: WyrdDiagnostics) -> WyrdLinkedPack:
	return WyrdPack.compile(
		PackedStringArray([
			"res://tests/golden/link/clean/quest.wyrd",
			"res://tests/golden/link/clean/scene.wyrd",
		]),
		"harbor",
		1,
		null,
		diagnostics,
		"res://tests/golden/link/clean",
		true
	)
