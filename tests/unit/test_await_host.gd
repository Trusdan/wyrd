extends GutTest


func test_statement_stores_screen_and_fields() -> void:
	var file := _file("""
language 1
quest gate "Gate"
  stage ask
    await_host board returns { ok, note }
""")
	assert_eq(file.codes, [])
	var host: Dictionary = file.unit.quests[0].stages[0].hosts[0]
	assert_eq(host["screen"], "board")
	assert_eq(host["fields"], PackedStringArray(["ok", "note"]))


func test_parser_keeps_await_host_as_the_line_keyword() -> void:
	var source := WyrdSource.new("sample.wyrd", """
language 1
quest gate "Gate"
  stage ask
    await_host board returns { ok }
""")
	var tree := WyrdParser.new().parse(source, WyrdDiagnostics.new())
	var quest: WyrdNode = tree.children[0]
	var stage: WyrdNode = quest.children[0]
	assert_eq(stage.children[0].keyword, "await_host")


func test_bad_shape_is_rejected() -> void:
	var file := _file("""
language 1
quest gate "Gate"
  stage ask
    await_host board
""")
	assert_true(file.messages.has("await_host needs <screen_id> returns { <field>, ... }"))


func test_fact_named_await_host_stays_reserved() -> void:
	var file := _file("""
language 1
facts
  await_host : int stored
""")
	assert_true(file.codes.has("E_RESERVED_WORD"))


func test_scene_does_not_accept_await_host() -> void:
	var file := _file("""
language 1
scene door
  await_host board returns { ok }
""")
	assert_true(file.messages.has("unknown statement \"await_host\""))


func test_linker_rejects_a_duplicate_field() -> void:
	var source := WyrdSource.new("mem.wyrd", """
language 1
quest gate "Gate"
  stage ask
    await_host board returns { ok, ok }
""")
	var diagnostics := WyrdDiagnostics.new()
	var tree := WyrdParser.new().parse(source, diagnostics)
	var file := WyrdStatements.new().compile(source, tree, diagnostics)
	assert_false(diagnostics.has_errors())
	var units: Array = [{"file": file, "hash": "0", "path": "mem.wyrd", "text": source.text}]
	WyrdLinker.new().link(units, tree.schema, "mem", 1, null, "", true, diagnostics)
	var messages: Array = []
	for item in diagnostics.items:
		messages.append(item.message)
	assert_true(messages.has("duplicate await_host field \"ok\""))


func test_runtime_pauses_on_the_compiled_step() -> void:
	var opened := _Harness.new().open_pack("res://tests/scenario/pack/host_step.wyrdmanifest.tres")
	var runtime: WyrdRuntime = opened["runtime"]
	assert_true(opened["report"].ok, opened["report"].diagnostics.format())
	var screens: Array[String] = []
	runtime.quests.host_step_requested.connect(func(quest_id: String, screen_id: StringName, fields: PackedStringArray) -> void:
		screens.append("%s:%s:%s" % [quest_id, String(screen_id), ",".join(fields)])
	)
	runtime.start_new_game(3)
	runtime.facts.set(&"gate.n", 0)
	runtime.tick(0)
	assert_eq(screens, ["host_step:board:ok,note"])
	assert_eq(runtime.quests.waiting_reason("host_step"), "host:board")
	assert_eq(runtime.facts.get(&"gate.n"), 0)
	runtime.quests.complete_host_step("host_step", {"note": "kept", "ok": true})
	assert_eq(runtime.facts.get(&"gate.n"), 3)
	assert_eq(runtime.quests.status("host_step"), &"completed")
	assert_eq(runtime.quests.outcome("host_step", "crossing"), "done")
	assert_eq(runtime.quests.host_returns("host_step")["note"], "kept")


const _Harness := preload("res://tests/scenario/s2c_harness.gd")


func _file(text: String) -> Dictionary:
	var source := WyrdSource.new("sample.wyrd", text)
	var diagnostics := WyrdDiagnostics.new()
	var tree := WyrdParser.new().parse(source, diagnostics)
	var unit := WyrdStatements.new().compile(source, tree, diagnostics)
	var codes: Array = []
	var messages: Array = []
	for item in diagnostics.items:
		codes.append(String(item.code))
		messages.append(item.message)
	return {"codes": codes, "messages": messages, "unit": unit}
