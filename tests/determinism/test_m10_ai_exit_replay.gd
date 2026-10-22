extends GutTest

const _Exit := preload("res://tests/scenario/m10_gullhaven.gd")


func test_echo_and_fuzz_replay_line_text() -> void:
	for provider in ["echo", "fuzz"]:
		var exit := _Exit.new()
		var opened := exit.boot(provider)
		var runtime: WyrdRuntime = opened["runtime"]
		exit.play(runtime, exit.ROUTES["exit_replay"]["steps"])
		var recorded: Array = runtime.trace.snapshot()
		var live_lines := exit.line_texts(recorded)
		var live_hash := exit.gameplay_hash(runtime)
		assert_true(_has(recorded, "quest_summary"))
		assert_true(_has(recorded, "ai_host_request"))
		assert_true(_has(recorded, "ai_deliver"))
		var again := exit.boot(provider)
		var replayed: WyrdRuntime = again["runtime"]
		WyrdTrace.replay(replayed, recorded)
		assert_eq(exit.line_texts(replayed.trace.events), live_lines)
		assert_true(_has(replayed.trace.events, "quest_summary"))
		assert_true(_has(replayed.trace.events, "ai_host_request"))
		var stripped: Array = []
		for item in recorded:
			if str((item as Dictionary).get("kind", "")) == "ai_deliver":
				continue
			stripped.append(item)
		var bare := exit.boot(provider)
		var authored_run: WyrdRuntime = bare["runtime"]
		WyrdTrace.replay(authored_run, stripped)
		for item in authored_run.trace.events:
			if str((item as Dictionary).get("kind", "")) != "line":
				continue
			var row: Dictionary = item
			assert_eq(str(row.get("text", "")), exit.authored(authored_run, str(row.get("id", ""))))
		assert_eq(exit.gameplay_hash(authored_run), live_hash)


func _has(events: Array, kind: String) -> bool:
	for item in events:
		if str((item as Dictionary).get("kind", "")) == kind:
			return true
	return false
