extends GutTest


func test_directory_pack_id_is_the_directory_name() -> void:
	var result := WyrdCli.execute(PackedStringArray(["check", "res://tests/golden/link/pack_unknown"]))
	assert_eq(int(result["exit_code"]), 0, str(result["output"]))
	assert_true(str(result["output"]).contains("warning[W_PACK_UNKNOWN]"))
	assert_true(str(result["output"]).contains("pack \"other\""))


func test_cross_file_line_id_names_both_files() -> void:
	var result := WyrdCli.execute(PackedStringArray(["check", "res://tests/golden/link/line_duplicate"]))
	assert_eq(int(result["exit_code"]), 1)
	var output := str(result["output"])
	assert_true(output.contains("error[E_LINE_ID_DUPLICATE]"))
	assert_true(output.contains("a.wyrd"))
	assert_true(output.contains("b.wyrd"))


func test_strict_fails_on_warnings() -> void:
	var loose := WyrdCli.execute(PackedStringArray(["check", "res://tests/golden/link/unused"]))
	assert_eq(int(loose["exit_code"]), 0, str(loose["output"]))
	assert_true(str(loose["output"]).contains("warning[W_FACT_UNUSED]"))
	var strict := WyrdCli.execute(PackedStringArray(["check", "--strict", "res://tests/golden/link/unused"]))
	assert_eq(int(strict["exit_code"]), 1)
	assert_true(str(strict["output"]).contains("warning[W_FACT_UNUSED]"))


func test_speaker_unbound_and_unused_scene() -> void:
	var unbound := WyrdCli.execute(PackedStringArray(["check", "res://tests/golden/link/speaker_unbound"]))
	assert_eq(int(unbound["exit_code"]), 1)
	assert_true(str(unbound["output"]).contains("error[E_SPEAKER_UNBOUND]"))
	assert_false(str(unbound["output"]).contains("W_SCENE_UNUSED"))
	var unused := WyrdCli.execute(PackedStringArray(["check", "res://tests/golden/link/scene_unused"]))
	assert_eq(int(unused["exit_code"]), 0, str(unused["output"]))
	assert_true(str(unused["output"]).contains("warning[W_SCENE_UNUSED]"))
	assert_false(str(unused["output"]).contains("E_SPEAKER_UNBOUND"))


func test_clean_pack_has_no_diagnostics() -> void:
	var result := WyrdCli.execute(PackedStringArray(["check", "res://tests/golden/link/clean"]))
	assert_eq(int(result["exit_code"]), 0)
	assert_eq(str(result["output"]), "")
