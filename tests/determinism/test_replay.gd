extends GutTest

const _Harness := preload("res://tests/scenario/s2c_harness.gd")


func test_replay_reproduces_decisions() -> void:
	var recorded := _play(false)
	var again := _play(false, recorded)
	assert_eq(WyrdTrace.diff(recorded, again), PackedStringArray())
	assert_gt(recorded.size(), 0)
	assert_true(_has(recorded, "line"))
	assert_true(_has(recorded, "choices"))
	assert_true(_has(recorded, "command"))
	assert_true(_has(recorded, "draw"))


func test_replay_reproduces_the_dock_errand() -> void:
	var recorded := _errand()
	var again := _errand(recorded)
	assert_eq(WyrdTrace.diff(recorded, again), PackedStringArray())
	assert_true(_has(recorded, "quest_start"))
	assert_true(_has(recorded, "quest_advance"))
	assert_true(_has(recorded, "quest_status"))


func test_a_changed_host_answer_is_detected() -> void:
	var recorded := _play(false)
	var changed := _play(true, recorded)
	assert_push_error("no line is waiting")
	var found := WyrdTrace.diff(recorded, changed)
	assert_gt(found.size(), 0)
	assert_true(" ".join(found).contains("command"))


func _play(fail_lodging: bool, recorded: Array = []) -> Array:
	var opened := _Harness.new().boot_gullhaven(false, 4)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	if fail_lodging:
		host.actions.set_result_for(&"assign_lodging", WyrdCommandResult.failed(&"full"))
	runtime.trace.enabled = true
	runtime.trace.clear()
	if recorded.is_empty():
		var harness := _Harness.new()
		runtime.dialogue.open_scene("toll.offer_room")
		harness.line_rows(runtime)
		harness.choose_text(runtime, "Take the room")
		harness.line_rows(runtime)
		runtime.tick(60)
		runtime.draw_u32(&"play")
	else:
		WyrdTrace.replay(runtime, recorded)
	return runtime.trace.snapshot()


func _errand(recorded: Array = []) -> Array:
	var opened := _Harness.new().boot_gullhaven()
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.trace.enabled = true
	runtime.trace.clear()
	if recorded.is_empty():
		var harness := _Harness.new()
		runtime.dialogue.open_scene("toll.offer_room")
		harness.line_rows(runtime)
		harness.choose_text(runtime, "Ask the dock errand")
		harness.line_rows(runtime)
		runtime.dialogue.open_scene("toll.offer_room")
		harness.line_rows(runtime)
		harness.choose_text(runtime, "Send the errand on")
		harness.line_rows(runtime)
	else:
		WyrdTrace.replay(runtime, recorded)
	return runtime.trace.snapshot()


func _has(events: Array, kind: String) -> bool:
	for item in events:
		if item is Dictionary and String((item as Dictionary).get("kind", "")) == kind:
			return true
	return false
