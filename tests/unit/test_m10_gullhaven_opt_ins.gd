extends GutTest

const _HARBOR := "res://example/content/gullhaven/harbor.wyrdmanifest.tres"
const _POT := "res://tests/golden/pot/gullhaven.pot"
const _IDS: Array[String] = ["a_leave", "sg02", "sg03", "sg04", "sg05", "sg_storm"]


func test_opted_in_set_kinds_and_context() -> void:
	var runtime := _runtime()
	var ids: Array = runtime.content().ai_lines.keys()
	ids.sort()
	assert_eq(ids, _IDS)
	for line_id in ["a_leave", "sg04", "sg05"]:
		assert_eq(String(runtime.ai.kind_for_line(line_id)), "bark_paraphrase", line_id)
		assert_false(_line(runtime, line_id).tags.has("gossip"), line_id)
	for line_id in ["sg02", "sg03", "sg_storm"]:
		assert_eq(String(runtime.ai.kind_for_line(line_id)), "gossip", line_id)
		assert_true(_line(runtime, line_id).tags.has("gossip"), line_id)
		assert_true(_line(runtime, line_id).tags.has("ai"), line_id)
	var storm := runtime.content().storylets.get("harbor_gossip.storm") as WyrdStoryletDef
	assert_eq(storm.ai_context, PackedStringArray(["world.storm_heard"]))
	var entry: Dictionary = runtime.content().ai_lines["sg_storm"]
	assert_eq(entry["keys"], PackedStringArray(["world.storm_heard"]))
	assert_eq(str(entry["id"]), "harbor_gossip.storm")


func test_check_stays_on_the_existing_codes() -> void:
	var result: Dictionary = WyrdCli.execute(PackedStringArray([
		"check",
		"--manifest",
		"example/content/gullhaven/harbor.wyrdmanifest.tres",
	]))
	assert_eq(int(result["exit_code"]), 0, str(result["output"]))
	var output := str(result["output"])
	assert_true(output.contains("warning[W_CLAIM]"), output)
	assert_true(output.contains("info[I_STORYLET_SCORE]"), output)
	assert_true(output.contains("info[I_TEMPLATE_SCORE]"), output)
	assert_false(output.contains("error["), output)
	for line in output.split("\n"):
		if line.is_empty():
			continue
		var claim := line.contains("warning[W_CLAIM]")
		var score := line.contains("info[I_STORYLET_SCORE]") or line.contains("info[I_TEMPLATE_SCORE]")
		assert_true(claim or score, line)


func test_authored_text_matches_the_pot() -> void:
	var runtime := _runtime()
	var pot := _pot_messages()
	for line_id in _IDS:
		var authored := str(runtime.resolve_line(_line(runtime, line_id)).get("text", ""))
		assert_false(authored.is_empty(), line_id)
		assert_eq(authored, str(pot[line_id]), line_id)


func _runtime() -> WyrdRuntime:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var report := runtime.load_content(load(_HARBOR) as WyrdContentManifest)
	assert_true(report.ok, report.diagnostics.format())
	return runtime


func _line(runtime: WyrdRuntime, line_id: String) -> WyrdLineDef:
	return runtime.content().lines.get(line_id) as WyrdLineDef


func _pot_messages() -> Dictionary:
	var messages := {}
	var context := ""
	for raw in FileAccess.get_file_as_string(_POT).split("\n"):
		var line := String(raw)
		if line.begins_with("msgctxt "):
			context = _quoted(line.substr(8).strip_edges())
		elif line.begins_with("msgid "):
			messages[context] = _quoted(line.substr(6).strip_edges())
	return messages


func _quoted(text: String) -> String:
	if text.length() >= 2 and text.begins_with("\"") and text.ends_with("\""):
		return text.substr(1, text.length() - 2)
	return text
