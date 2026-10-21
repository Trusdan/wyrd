extends GutTest

const _HARBOR := "res://example/content/gullhaven/harbor.wyrdmanifest.tres"
const _Election := preload("res://example/playtest/harbor_election.gd")

const _ROLE := """
role ferry_master
  default_holder: ferry_master
  succession: none
  vacancy: hold
"""

const _SCENE := """
language 1
""" + _ROLE + """
scene dock.voice
  narrator: The crossing stays open. {holder(ferry_master)|variants} #tag:voiced #line:dock_voice
    variant ferry_master: The ferry master keeps the crossing open. #tag:voiced #line:dock_voice_master
    variant net_mender: The net mender keeps the crossing open. #tag:voiced #line:dock_voice_mender
  -> end
"""

const _JOURNAL := """
language 1
""" + _ROLE + """
quest voice "Voice"
  start when true
  stage greet
    journal: The crossing stays open. {holder(ferry_master)|variants} #tag:voiced #line:dock_voice
      variant ferry_master: The ferry master keeps the crossing open. #tag:voiced #line:dock_voice_master
      variant net_mender: The net mender keeps the crossing open. #tag:voiced #line:dock_voice_mender
"""

const _VOICED_IF := """
language 1
scene dock.voice
  narrator: Hello {if true}there{end}. #tag:voiced #line:bad
  narrator: Hello {if true}there{end}. #line:ok
"""

const _PLAIN_IF := """
language 1
scene dock.voice
  narrator: Hello {if true}there{end}. #line:ok
"""

const _DUPLICATE := """
language 1
scene dock.voice
  narrator: The crossing stays open. {holder(ferry_master)|variants} #line:dock_voice
    variant ferry_master: One wording. #line:dock_voice_a
    variant ferry_master: Another wording. #line:dock_voice_b
"""

const _TWO_SPANS := """
language 1
scene dock.voice
  narrator: {holder(ferry_master)|variants}{holder(ferry_master)|variants} #line:dock_voice
"""

const _BAD_HOLDER := """
language 1
scene dock.voice
  narrator: Ask {nope|variants}. #line:dock_voice
"""

const _ORPHAN := """
language 1
scene dock.voice
  narrator: The crossing stays open. #line:dock_voice
    variant ferry_master: The ferry master keeps the crossing open. #line:dock_voice_master
"""


func test_voiced_tag_rejects_variable_text_only() -> void:
	var voiced := _compile(_VOICED_IF)
	assert_eq(_count(voiced["diagnostics"], "E_VOICED_VARIABLE"), 1)
	assert_true(voiced["diagnostics"].format().contains("a voiced line cannot interpolate variable text"))
	assert_eq(_count(voiced["diagnostics"], "E_VARIANT_SYNTAX"), 0)
	var plain := _compile(_PLAIN_IF)
	assert_false(plain["diagnostics"].has_errors(), plain["diagnostics"].format())
	assert_eq(_count(plain["diagnostics"], "E_VOICED_VARIABLE"), 0)


func test_variant_shape_errors() -> void:
	var duplicate := _compile(_DUPLICATE)
	assert_true(duplicate["diagnostics"].format().contains("duplicate variant for \"ferry_master\""))
	var spans := _compile(_TWO_SPANS)
	assert_true(spans["diagnostics"].format().contains("a line holds one {holder|variants} span"))
	var holder := _compile(_BAD_HOLDER)
	assert_true(holder["diagnostics"].format().contains("variants need holder(<name>)"))
	var orphan := _compile(_ORPHAN)
	assert_true(orphan["diagnostics"].format().contains("variant lines need {holder(<name>)|variants} on the line"))


func test_scene_picks_a_holder_variant_and_traces_it() -> void:
	var runtime := _boot(_SCENE)
	runtime.trace.enabled = true
	runtime.dialogue.open_scene("dock.voice")
	var view := runtime.dialogue.line()
	assert_eq(view.id, "dock_voice_master")
	assert_eq(view.text, "The ferry master keeps the crossing open.")
	assert_true(view.tags.has("voiced"))
	var opened := _trace_rows(runtime, "voice")
	assert_eq(opened.size(), 1)
	assert_eq(str(opened[0]["key"]), "dock_voice")
	assert_eq(str(opened[0]["who"]), "ferry_master")
	assert_eq(str(opened[0]["holder"]), "ferry_master")
	assert_eq(str(opened[0]["chosen"]), "dock_voice_master")
	runtime.dialogue.advance()
	runtime.roles.assign(&"ferry_master", &"net_mender")
	runtime.trace.clear()
	runtime.dialogue.open_scene("dock.voice")
	var swapped := runtime.dialogue.line()
	assert_eq(swapped.id, "dock_voice_mender")
	assert_eq(swapped.text, "The net mender keeps the crossing open.")
	runtime.dialogue.advance()
	runtime.roles.vacate(&"ferry_master", &"left")
	runtime.trace.prefix = "net_mender"
	runtime.trace.clear()
	runtime.dialogue.open_scene("dock.voice")
	var fallback := runtime.dialogue.line()
	assert_eq(fallback.id, "dock_voice")
	assert_eq(fallback.text, "The crossing stays open.")
	assert_eq(_trace_rows(runtime, "voice").size(), 0)
	runtime.trace.prefix = "dock_voice"
	runtime.trace.clear()
	runtime.dialogue.advance()
	runtime.dialogue.open_scene("dock.voice")
	var kept := _trace_rows(runtime, "voice")
	assert_eq(kept.size(), 1)
	assert_eq(str(kept[0]["chosen"]), "dock_voice")
	assert_eq(str(kept[0]["holder"]), "")
	runtime.dialogue.advance()
	var saved := runtime.save_state()
	assert_eq(int(saved["schema_version"]), 4)
	assert_false(saved.has("voice"))
	var loaded := _boot(_SCENE)
	loaded.trace.enabled = true
	assert_true(loaded.load_state(saved).ok)
	assert_eq(_trace_rows(loaded, "voice").size(), 0)
	loaded.dialogue.open_scene("dock.voice")
	assert_eq(loaded.dialogue.line().text, "The crossing stays open.")


func test_journal_freezes_the_chosen_line_and_load_does_not_repick() -> void:
	var runtime := _boot(_JOURNAL)
	runtime.trace.enabled = true
	runtime.tick(0)
	var rows: Array = runtime.quests.journal("voice")
	assert_eq(rows.size(), 1)
	assert_eq(str(rows[0]["id"]), "dock_voice_master")
	assert_eq(str(rows[0]["text"]), "The ferry master keeps the crossing open.")
	assert_eq(_trace_rows(runtime, "voice").size(), 1)
	var saved := runtime.save_state()
	assert_eq(int(saved["schema_version"]), 4)
	assert_false(saved.has("voice"))
	var loaded := _boot(_JOURNAL)
	loaded.trace.enabled = true
	assert_true(loaded.load_state(saved).ok)
	loaded.tick(0)
	assert_eq(_trace_rows(loaded, "voice").size(), 0)
	var again: Array = loaded.quests.journal("voice")
	assert_eq(again.size(), 1)
	assert_eq(str(again[0]["id"]), "dock_voice_master")
	assert_eq(str(again[0]["text"]), "The ferry master keeps the crossing open.")
	var quiet := _boot(_JOURNAL)
	quiet.tick(0)
	assert_eq(quiet.trace.events.size(), 0)


func test_gullhaven_storylet_uses_the_role_holder() -> void:
	var runtime := _harbor()
	var story: WyrdStoryletDef = runtime.content().storylets["dock_voice_crossing"]
	var heard: Array[WyrdLineView] = []
	runtime.bark_ready.connect(func(line: WyrdLineView) -> void: heard.append(line))
	runtime.trace.enabled = true
	runtime.present_bark(story, {"line_id": "dock_voice"})
	assert_eq(heard.size(), 1)
	assert_eq(heard[0].id, "dock_voice_master")
	assert_eq(heard[0].text, "The ferry master keeps the crossing open.")
	assert_eq(heard[0].speaker, &"narrator")
	runtime.roles.assign(&"ferry_master", &"net_mender")
	runtime.present_bark(story, {"line_id": "dock_voice"})
	assert_eq(heard[1].id, "dock_voice_mender")
	assert_eq(heard[1].text, "The net mender keeps the crossing open.")
	var saved := runtime.save_state()
	assert_false(saved.has("voice"))
	assert_eq(int(saved["schema_version"]), 4)


func test_voice_tools_report_script_and_audio() -> void:
	var path := str(_compile(_SCENE)["path"])
	var clean: Dictionary = WyrdCli.execute(PackedStringArray(["voice-check", path]))
	assert_eq(int(clean["exit_code"]), 0, str(clean["output"]))
	assert_eq(str(clean["output"]), "speaker=narrator lines=3 voiced=3 variable=0\n")
	var noisy: Dictionary = WyrdCli.execute(PackedStringArray(["voice-check", str(_compile(_PLAIN_IF)["path"])]))
	assert_eq(int(noisy["exit_code"]), 1)
	assert_true(str(noisy["output"]).contains("speaker=narrator lines=1 voiced=0 variable=1"))
	assert_true(str(noisy["output"]).contains("  ok scene:dock.voice"))
	var missing: Dictionary = WyrdCli.execute(PackedStringArray(["script-export", path]))
	assert_eq(int(missing["exit_code"]), 1)
	assert_eq(str(missing["output"]), "wyrd: script-export needs --speaker\n")
	var script: Dictionary = WyrdCli.execute(PackedStringArray(["script-export", "--speaker", "narrator", path]))
	assert_eq(int(script["exit_code"]), 0, str(script["output"]))
	var body := str(script["output"])
	assert_true(body.contains("id=dock_voice "))
	assert_true(body.contains("{holder(ferry_master)|variants}"))
	assert_true(body.contains("id=dock_voice_master text=The ferry master keeps the crossing open. tags=voiced scene=dock.voice context=variant:ferry_master scene:dock.voice"))
	assert_true(body.contains("id=dock_voice_mender text=The net mender keeps the crossing open. tags=voiced scene=dock.voice context=variant:net_mender scene:dock.voice"))
	var audio_path := "user://wyrd_m6_voice_audio.json"
	var audio := FileAccess.open(audio_path, FileAccess.WRITE)
	audio.store_string("{\"en\": [\"dock_voice\", \"dock_voice_master\"], \"cy\": [\"dock_voice\"]}\n")
	audio.close()
	var report: Dictionary = WyrdCli.execute(PackedStringArray([
		"unvoiced-report",
		"--locale",
		"cy",
		"--locale",
		"en",
		"--audio",
		audio_path,
		path,
	]))
	assert_eq(int(report["exit_code"]), 0, str(report["output"]))
	assert_eq(
		str(report["output"]),
		"locale=cy\ndock_voice_master\ndock_voice_mender\nlocale=en\ndock_voice_mender\n"
	)
	var harbor_voice: Dictionary = WyrdCli.execute(PackedStringArray([
		"voice-check",
		"--manifest",
		"example/content/gullhaven/harbor.wyrdmanifest.tres",
	]))
	assert_eq(int(harbor_voice["exit_code"]), 1, str(harbor_voice["output"]))
	var narrator := ""
	for line in str(harbor_voice["output"]).split("\n"):
		if line.begins_with("speaker=narrator "):
			narrator = line
	assert_true(narrator.contains("voiced=3"), narrator)
	assert_false(str(harbor_voice["output"]).contains("dock_voice"))
	var harbor_script: Dictionary = WyrdCli.execute(PackedStringArray([
		"script-export",
		"--speaker",
		"narrator",
		"--manifest",
		"example/content/gullhaven/harbor.wyrdmanifest.tres",
	]))
	assert_eq(int(harbor_script["exit_code"]), 0, str(harbor_script["output"]))
	assert_true(str(harbor_script["output"]).contains("id=dock_voice "))
	assert_true(str(harbor_script["output"]).contains("id=dock_voice_master "))
	assert_true(str(harbor_script["output"]).contains("id=dock_voice_mender "))


func test_tracing_off_records_nothing() -> void:
	var runtime := _boot(_SCENE)
	runtime.dialogue.open_scene("dock.voice")
	assert_eq(runtime.dialogue.line().id, "dock_voice_master")
	assert_eq(runtime.trace.events.size(), 0)


func _harbor() -> WyrdRuntime:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var manifest := load(_HARBOR) as WyrdContentManifest
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.register_adapter(WyrdElectionAdapter, _Election.new())
	runtime.start_new_game(5)
	return runtime


func _boot(body: String) -> WyrdRuntime:
	var compiled := _compile(body)
	assert_false(compiled["diagnostics"].has_errors(), compiled["diagnostics"].format())
	var runtime := WyrdRuntime.new()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([str(compiled["path"])])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(5)
	return runtime


func _compile(body: String) -> Dictionary:
	var path := _write("user://wyrd_m6_voice_%d.wyrd" % body.hash(), body)
	var diagnostics := WyrdDiagnostics.new()
	var pack := WyrdPack.compile(PackedStringArray([path]), "harbor", 1, null, diagnostics, path, true)
	return {"diagnostics": diagnostics, "pack": pack, "path": path}


func _write(path: String, body: String) -> String:
	var lines := PackedStringArray()
	for line in body.strip_edges().split("\n"):
		if line.begins_with("\t\t"):
			lines.append(line.substr(2))
		else:
			lines.append(line)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	file.close()
	return path


func _count(diagnostics: WyrdDiagnostics, code: String) -> int:
	var found := 0
	for item in diagnostics.items:
		if String(item.code) == code:
			found += 1
	return found


func _trace_rows(runtime: WyrdRuntime, kind: String) -> Array:
	var rows: Array = []
	for item in runtime.trace.events:
		if item is Dictionary and String((item as Dictionary).get("kind", "")) == kind:
			rows.append(item)
	return rows
