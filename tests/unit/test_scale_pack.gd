extends GutTest

## The scale pack is generated, never committed. One seed has one hash.


const _EXPECTED := "res://bench/scale_pack.sha256"


func test_full_pack_hash_is_stable() -> void:
	var first := _write("full")
	var second := _write("full")
	assert_eq(first["hash"], second["hash"], "same seed produced different bytes")
	var expected := FileAccess.get_file_as_string(_EXPECTED).strip_edges()
	assert_eq(first["hash"], expected, "update bench/scale_pack.sha256 when the generator changes")
	assert_eq(int(first["info"]["quests"]), 700)
	assert_eq(int(first["info"]["facts"]), 10000)
	assert_eq(int(first["info"]["npcs"]), 500)
	assert_eq(int(first["info"]["deeds"]), 50000)
	assert_eq(_deed_rows(first["dir"]), 50000)


func test_smoke_is_one_tenth_and_compiles_strict() -> void:
	var written := _write("smoke")
	assert_ne(written["hash"], FileAccess.get_file_as_string(_EXPECTED).strip_edges())
	assert_eq(int(written["info"]["quests"]), 70)
	assert_eq(int(written["info"]["facts"]), 1000)
	assert_eq(int(written["info"]["npcs"]), 50)
	assert_eq(int(written["info"]["deeds"]), 5000)
	var result := WyrdCli.execute(PackedStringArray(["check", "--strict", written["dir"]]))
	assert_eq(int(result["exit_code"]), 0, str(result["output"]))


func _write(profile_name: String) -> Dictionary:
	var dir := OS.get_temp_dir().path_join("wyrd-scale-%s-%d" % [profile_name, randi()])
	var digest := WyrdScalePack.write(dir, profile_name)
	_dirs.append(dir)
	return {"dir": dir, "hash": digest, "info": WyrdScalePack.read_pack(dir)}


func _deed_rows(dir: String) -> int:
	var count := 0
	for line in FileAccess.get_file_as_string(dir.path_join("deeds.tsv")).split("\n"):
		var row := line.strip_edges()
		if row.is_empty() or row.begins_with("#"):
			continue
		count += 1
	return count


var _dirs: Array[String] = []


func after_each() -> void:
	for dir in _dirs:
		WyrdScalePack.remove_dir(dir)
	_dirs.clear()
