extends GutTest

const _ROOT := "res://addons/wyrd"
const _CALLS: Array[String] = [
	"runtime/wyrd_runtime.gd",
	"runtime/scenes/wyrd_scene_runner.gd",
	"runtime/quests/wyrd_quest_runner.gd",
	"runtime/save/wyrd_save.gd",
	"runtime/trace/wyrd_trace.gd",
]
const _QUIET: Array[String] = [
	"compiler",
	"runtime/conditions",
	"runtime/effects",
	"runtime/facts",
	"runtime/deeds",
	"runtime/roles",
	"runtime/generator",
]


func test_result_type_and_calls_stay_in_the_ai_boundary() -> void:
	var result_hits: PackedStringArray = PackedStringArray()
	var call_hits: PackedStringArray = PackedStringArray()
	for path in _files(_ROOT):
		var rel := path.substr(_ROOT.length() + 1)
		if rel.ends_with(".uid"):
			continue
		var text := FileAccess.get_file_as_string(path)
		if text.contains("WyrdAIResult"):
			result_hits.append(rel)
		if rel.ends_with(".gd") and _code_calls_ai(_code(text)):
			call_hits.append(rel)
	result_hits.sort()
	call_hits.sort()
	for rel in result_hits:
		var allowed := rel.begins_with("runtime/ai/") or rel == "runtime/trace/wyrd_trace.gd" or rel.ends_with(".md")
		assert_true(allowed, rel)
	for rel in call_hits:
		var allowed := rel.begins_with("runtime/ai/") or _CALLS.has(rel)
		assert_true(allowed, rel)
	for prefix in _QUIET:
		for rel in call_hits:
			assert_false(rel.begins_with(prefix + "/") or rel == prefix, rel)
	assert_eq(_sites("ai.present("), [
		"runtime/scenes/wyrd_scene_runner.gd|_show_line_body|runtime.ai.present(view, view.id)",
		"runtime/wyrd_runtime.gd|_story_line_view|ai.present(view, view.id)",
	])
	assert_eq(_sites("ai.summary_for("), [
		"runtime/quests/wyrd_quest_runner.gd|summary|return runtime.ai.summary_for(quest_id, entries)",
	])
	assert_eq(_sites("ai.cached_text("), [
		"runtime/quests/wyrd_quest_runner.gd|summary_source|if runtime.ai.cached_text(key).is_empty():",
	])


func test_a_fact_value_in_ai_text_does_not_write_gameplay() -> void:
	var opened := preload("res://tests/scenario/m10_gullhaven.gd").new().boot("echo")
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.facts.set_in(&"harbor.toll_fate", &"paid", &"known/player")
	var before := _slice(runtime)
	var packet := runtime.ai.packet_for_line("a_leave", &"bark_paraphrase", &"")
	var request_id := runtime.ai.request(&"bark_paraphrase", packet, {}, &"a_leave")
	assert_gt(request_id, 0)
	var result := WyrdAIResult.new()
	result.ok = true
	result.text = "The boat leaves, paid."
	assert_eq(runtime.ai.validate(result.text, &"bark_paraphrase", packet), &"")
	assert_true(runtime.ai.deliver(request_id, result))
	var view := WyrdLineView.new()
	view.id = "a_leave"
	view.speaker = &"narrator"
	view.text = str(packet["text"])
	runtime.ai.present(view, "a_leave")
	assert_eq(view.text, "The boat leaves, paid.")
	assert_eq(String(view.text_source), "ai")
	assert_eq(_slice(runtime), before)


func _slice(runtime: WyrdRuntime) -> String:
	var saved := runtime.save_state()
	return JSON.stringify({
		"deeds": saved.get("deeds", {}),
		"facts": saved.get("facts", {}),
		"quests": saved.get("quests", {}),
		"roles": saved.get("roles", {}),
		"topics": saved.get("topics", []),
	}, "", true)


func _sites(needle: String) -> Array:
	var found: Array = []
	for path in _files(_ROOT):
		var rel := path.substr(_ROOT.length() + 1)
		if not rel.ends_with(".gd") or rel.begins_with("runtime/ai/"):
			continue
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for index in lines.size():
			var statement := String(lines[index]).strip_edges()
			if statement.contains(needle):
				found.append("%s|%s|%s" % [rel, _enclosing_func(lines, index), statement])
	found.sort()
	return found


func _enclosing_func(lines: PackedStringArray, index: int) -> String:
	for cursor in range(index, -1, -1):
		var line := String(lines[cursor])
		var rest := ""
		if line.begins_with("static func "):
			rest = line.substr(12)
		elif line.begins_with("func "):
			rest = line.substr(5)
		else:
			continue
		var name := ""
		for ch_index in rest.length():
			var ch := rest.substr(ch_index, 1)
			if ch == "(" or ch == ":" or ch == " " or ch == "\t":
				break
			name += ch
		return name
	return ""


func _files(root: String) -> PackedStringArray:
	var out := PackedStringArray()
	_walk(root, out)
	return out


func _walk(path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(path)
	assert_not_null(dir, path)
	for name in dir.get_directories():
		_walk(path.path_join(name), out)
	for name in dir.get_files():
		out.append(path.path_join(name))


func _code(text: String) -> String:
	var kept := PackedStringArray()
	for raw in text.split("\n"):
		var line := String(raw)
		var trimmed := line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		var slash := line.find("//")
		if slash >= 0:
			line = line.substr(0, slash)
		kept.append(line)
	return "\n".join(kept)


func _code_calls_ai(code: String) -> bool:
	if code.contains(".ai."):
		return true
	var from := 0
	while true:
		var at := code.find("ai.", from)
		if at < 0:
			return false
		if at == 0 or not _ident(code.unicode_at(at - 1)):
			return true
		from = at + 3
	return false


func _ident(code: int) -> bool:
	var ch := String.chr(code)
	if ch == "_" or (ch >= "0" and ch <= "9"):
		return true
	return ch.to_lower() != ch.to_upper()
