extends GutTest

const _UI := preload("res://example/playtest/gullhaven_playtest.gd")

var _servers: Array[WyrdFakeLocalServer] = []


func before_each() -> void:
	for _i in 3:
		await get_tree().process_frame


func after_each() -> void:
	OS.set_environment("WYRD_LOCAL_AI_URL", "")
	OS.set_environment("WYRD_LOCAL_AI_MODEL", "")
	for server in _servers:
		if is_instance_valid(server):
			server.stop()
	_servers.clear()


func test_spawn_uses_the_null_provider_and_the_toggle_is_off() -> void:
	var ui := _ui()
	assert_eq(ui.boot_error(), "")
	assert_eq(ui.ai_provider_id(), "null")
	var toggle := ui.find_child("Toggle_ai_local", true, false) as CheckButton
	assert_not_null(toggle)
	assert_false(toggle.button_pressed)
	assert_eq(ui.status_text(), "Press New game.")


func test_on_with_the_fake_server_names_the_model() -> void:
	var server := _listen()
	OS.set_environment("WYRD_LOCAL_AI_URL", "http://127.0.0.1:%d" % server.port)
	var ui := _ui()
	ui.set_flag("ai_local", true)
	assert_true(await _until(func() -> bool: return ui.status_text().begins_with("Local AI flavor on:"), 2.0))
	assert_true(ui.ai_provider_id().begins_with("local:"))
	assert_true(ui.status_text().contains(str(ui._local_provider.model)))
	assert_true(ui.status_text().contains("127.0.0.1"))


func test_on_with_a_closed_port_reports_unreachable() -> void:
	OS.set_environment("WYRD_LOCAL_AI_URL", "http://127.0.0.1:59999")
	var ui := _ui()
	ui.set_flag("ai_local", true)
	assert_true(await _until(func() -> bool: return ui.status_text().contains("server not reachable"), 3.0))
	assert_true(ui.ai_provider_id().begins_with("local:"))


func test_off_registers_the_null_provider() -> void:
	var server := _listen()
	OS.set_environment("WYRD_LOCAL_AI_URL", "http://127.0.0.1:%d" % server.port)
	var ui := _ui()
	ui.set_flag("ai_local", true)
	assert_true(await _until(func() -> bool: return ui.status_text().begins_with("Local AI flavor on:"), 2.0))
	ui.set_flag("ai_local", false)
	assert_eq(ui.ai_provider_id(), "null")
	assert_eq(ui.status_text(), "Local AI flavor off.")


func test_setting_the_same_value_does_not_touch_the_provider() -> void:
	var ui := _ui()
	ui._runtime.trace.enabled = true
	ui._runtime.trace.clear()
	var status := ui.status_text()
	ui.set_flag("ai_local", false)
	assert_eq(ui.status_text(), status)
	assert_eq(_rows(ui._runtime, "ai_provider").size(), 0)

	var server := _listen()
	OS.set_environment("WYRD_LOCAL_AI_URL", "http://127.0.0.1:%d" % server.port)
	ui.set_flag("ai_local", true)
	assert_true(await _until(func() -> bool: return ui.status_text().begins_with("Local AI flavor on:"), 2.0))
	ui._runtime.trace.clear()
	status = ui.status_text()
	ui.set_flag("ai_local", true)
	assert_eq(ui.status_text(), status)
	assert_eq(_rows(ui._runtime, "ai_provider").size(), 0)
	assert_true(ui.ai_provider_id().begins_with("local:"))


func test_toggle_off_plays_the_opening_lines() -> void:
	var ui := _ui()
	assert_eq(ui.boot_error(), "")
	ui.new_game(1)
	var expected := [
		["innkeeper", "A room's two coins a night, and the stew is free."],
		["Nia", "The headland bell rang twice before the rain."],
		["Nia", "Bram, the ferry master, is on the dock."],
		["bell", "The bell notes the tide."],
	]
	for i in expected.size():
		assert_eq(ui.speaker_text(), String(expected[i][0]))
		assert_eq(ui.line_text(), String(expected[i][1]))
		assert_false(ui.speaker_text().contains("(AI)"))
		if i + 1 < expected.size():
			ui.press_continue()


func _ui() -> _UI:
	var packed := load("res://example/playtest/gullhaven_playtest.tscn") as PackedScene
	var ui := packed.instantiate() as _UI
	add_child_autofree(ui)
	return ui


func _listen() -> WyrdFakeLocalServer:
	var server := WyrdFakeLocalServer.new()
	add_child_autofree(server)
	var port := server.start()
	assert_gt(port, 0)
	_servers.append(server)
	return server


func _rows(runtime: WyrdRuntime, kind: String) -> Array:
	var rows: Array = []
	for event in runtime.trace.events:
		if str(event.get("kind", "")) == kind:
			rows.append(event)
	return rows


func _until(done: Callable, seconds: float) -> bool:
	var start := Time.get_ticks_msec()
	while not bool(done.call()):
		if Time.get_ticks_msec() - start > int(seconds * 1000.0):
			return false
		await get_tree().process_frame
	return true
