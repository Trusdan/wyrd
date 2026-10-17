extends GutTest

const _Facade := preload("res://addons/wyrd/runtime/wyrd.gd")


func test_choice_summary_filters_provenance() -> void:
	var runtime := _prime()
	var all: Array = runtime.facts.choice_summary()
	assert_eq(all.size(), 3)
	assert_eq(str(all[0]["key"]), "dock.ropes")
	assert_eq(int(all[0]["time"]), 60)
	assert_false(bool(all[0]["recap"]))
	assert_eq(str(all[1]["key"]), "harbor.coins")
	assert_true(bool(all[1]["recap"]))
	assert_eq(str(all[1]["scene"]), "toll_booth")
	assert_eq(str(all[1]["choice"]), "pay")
	var booth: Array = runtime.facts.choice_summary({"scene": "toll_booth"})
	assert_eq(booth.size(), 1)
	assert_eq(str(booth[0]["key"]), "harbor.coins")
	var noted: Array = runtime.facts.choice_summary({"choice": "note"})
	assert_eq(noted.size(), 1)
	assert_eq(str(noted[0]["key"]), "harbor.tide")
	var harbor: Array = runtime.facts.choice_summary({"prefix": "harbor"})
	assert_eq(harbor.size(), 2)
	var minute: Array = runtime.facts.choice_summary({"from": 30, "to": 30})
	assert_eq(minute.size(), 1)
	assert_eq(str(minute[0]["key"]), "harbor.tide")
	var later: Array = runtime.facts.choice_summary({"from": 30})
	assert_eq(later.size(), 2)
	runtime.facts.choice_summary({"graph": "toll"})
	assert_push_error("unknown filter")
	assert_eq(runtime.trace.events.size(), 0)


func test_trace_filters_and_load_keeps_rows() -> void:
	var runtime := _prime()
	runtime.trace.enabled = true
	var full: Array = runtime.facts.choice_summary()
	var logged := _rows(runtime, "choice_summary")
	assert_eq(logged.size(), 1)
	assert_eq(str(logged[0]["scene"]), "-")
	assert_eq(str(logged[0]["prefix"]), "-")
	assert_eq(str(logged[0]["key"]), "")
	assert_eq(int(logged[0]["rows"]), 3)
	runtime.trace.clear()
	runtime.trace.prefix = "harbor"
	runtime.facts.choice_summary()
	assert_eq(_rows(runtime, "choice_summary").size(), 0)
	runtime.facts.choice_summary({"prefix": "harbor"})
	assert_eq(_rows(runtime, "choice_summary").size(), 1)
	assert_eq(str(_rows(runtime, "choice_summary")[0]["key"]), "harbor")
	runtime.trace.prefix = "toll_booth"
	runtime.trace.clear()
	runtime.facts.choice_summary({"scene": "toll_booth"})
	assert_eq(_rows(runtime, "choice_summary").size(), 1)
	assert_eq(str(_rows(runtime, "choice_summary")[0]["path"]), "toll_booth")
	var saved := runtime.save_state()
	assert_eq(int(saved["schema_version"]), 3)
	assert_eq(str(saved["provenance"]["harbor.coins"]["choice"]), "pay")
	assert_false(saved.has("recap"))
	var loaded := _boot()
	loaded.trace.enabled = true
	assert_true(loaded.load_state(saved).ok)
	assert_eq(loaded.trace.events.size(), 0)
	assert_eq(JSON.stringify(loaded.facts.choice_summary()), JSON.stringify(full))


func test_recap_survives_compaction() -> void:
	var runtime := _prime()
	runtime.trace.enabled = true
	runtime.deeds.compact()
	var kept: Array = runtime.facts.choice_summary()
	assert_eq(kept.size(), 1)
	assert_eq(str(kept[0]["key"]), "harbor.coins")
	assert_eq(runtime.effects.provenance_of("harbor.tide"), {})
	var line: Dictionary = _rows(runtime, "choice_compact")[0]
	assert_eq(int(line["dropped"]), 2)
	assert_eq(int(line["kept"]), 1)
	assert_eq(str(line["path"]), "dock.ropes,harbor.tide")
	var saved := runtime.save_state()
	assert_false((saved["provenance"] as Dictionary).has("dock.ropes"))
	assert_true((saved["provenance"] as Dictionary).has("harbor.coins"))
	var loaded := _boot()
	assert_true(loaded.load_state(saved).ok)
	loaded.deeds.compact()
	assert_eq(loaded.facts.choice_summary().size(), 1)
	assert_eq(str(loaded.facts.choice_summary()[0]["key"]), "harbor.coins")


func test_choices_cli_filters_a_save() -> void:
	var runtime := _prime()
	var path := "user://wyrd_m7_choices_save.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(runtime.save_state()))
	file.close()
	var pack := "user://wyrd_m7_choices_pack.wyrd"
	var listed: Dictionary = WyrdCli.execute(PackedStringArray([
		"choices", pack, "--save", path,
	]))
	assert_eq(int(listed["exit_code"]), 0, str(listed["output"]))
	var listed_keys := _table_keys(str(listed["output"]))
	assert_eq(listed_keys.size(), 3, str(listed["output"]))
	assert_true(listed_keys.has("harbor.coins"))
	assert_true(str(listed["output"]).contains("recap"))
	assert_true(str(listed["output"]).contains("true"))
	var booth: Dictionary = WyrdCli.execute(PackedStringArray([
		"choices", pack, "--save", path, "--scene", "toll_booth", "--from", "0", "--to", "0",
	]))
	assert_eq(int(booth["exit_code"]), 0, str(booth["output"]))
	var booth_keys := _table_keys(str(booth["output"]))
	assert_eq(booth_keys.size(), 1, str(booth["output"]))
	assert_eq(booth_keys[0], "harbor.coins")
	var bad: Dictionary = WyrdCli.execute(PackedStringArray([
		"choices", pack, "--from", "soon",
	]))
	assert_eq(int(bad["exit_code"]), 1)
	assert_true(str(bad["output"]).contains("--from"))


func test_facade_choice_summary() -> void:
	var node = _Facade.new()
	var rows: Array = node.facts.choice_summary()
	assert_eq(rows.size(), 0)
	node.free()


func _prime() -> WyrdRuntime:
	var runtime := _boot()
	_write(runtime, "toll_booth", "pay", "harbor.coins", "1")
	runtime.tick(30)
	_write(runtime, "dock", "note", "harbor.tide", "2")
	runtime.tick(30)
	_write(runtime, "dock", "stow", "dock.ropes", "4")
	return runtime


func _write(runtime: WyrdRuntime, scene_id: String, choice_id: String, key: String, value: String) -> void:
	runtime.effects.scene_id = scene_id
	runtime.effects.choice_id = choice_id
	var effect := WyrdEffectDef.new()
	effect.kind = &"set"
	effect.fact_key = key
	effect.value = WyrdCondition.new().compile(value, runtime.content().schema, WyrdDiagnostics.new(), "", 1, 1, WyrdCondition.CONTEXT_STORYLET, 1440, null, false)
	assert_eq(runtime.effects.run_one(effect), "")


func _boot() -> WyrdRuntime:
	var path := "user://wyrd_m7_choices_pack.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(_PACK.strip_edges() + "\n")
	file.close()
	var diagnostics := WyrdDiagnostics.new()
	var pack := WyrdPack.compile(PackedStringArray([path]), "harbor", 1, null, diagnostics, path, true)
	assert_false(diagnostics.has_errors(), diagnostics.format())
	var exported: Dictionary = WyrdExport.to_data(pack)
	var marked := false
	for item in exported["facts"]:
		if item is Dictionary and str((item as Dictionary).get("key", "")) == "harbor.coins":
			marked = bool((item as Dictionary).get("recap", false))
			assert_true(marked)
		if item is Dictionary and str((item as Dictionary).get("key", "")) == "harbor.tide":
			assert_false((item as Dictionary).has("recap"))
	var runtime := WyrdRuntime.new()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(4)
	return runtime


func _table_keys(output: String) -> PackedStringArray:
	var keys := PackedStringArray()
	for raw in output.split("\n"):
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("key ") or line.contains("]:"):
			continue
		var cells := line.split("  ", false)
		if cells.is_empty():
			continue
		keys.append(cells[0].strip_edges())
	return keys


func _rows(runtime: WyrdRuntime, kind: String) -> Array:
	var found: Array = []
	for item in runtime.trace.events:
		if item is Dictionary and String((item as Dictionary).get("kind", "")) == kind:
			found.append(item)
	return found


const _PACK := """
language 1
facts
  harbor.coins : int stored recap: true
  harbor.tide : int stored
  dock.ropes : int stored
"""
