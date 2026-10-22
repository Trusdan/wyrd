extends GutTest

const _Exit := preload("res://tests/scenario/m10_gullhaven.gd")


func test_silent_and_unpumped_echo_do_not_wait() -> void:
	for provider in ["silent", "echo"]:
		_play_without_pump(provider)


func test_cap_logs_capped_and_still_accepts_a_host_request() -> void:
	var exit := _Exit.new()
	var opened := exit.boot("silent")
	var runtime: WyrdRuntime = opened["runtime"]
	var shown: Array = []
	for step in exit.ROUTES["take_room"]["steps"]:
		exit.run_step(runtime, step, shown)
	assert_false(runtime.dialogue.is_open())
	assert_true(runtime.can_save())
	var cap := runtime.config().ai_max_inflight
	var packet := runtime.ai.packet_for_line("sg04", &"bark_paraphrase", &"ferry_master")
	while runtime.ai.pending_count() < cap:
		assert_gt(runtime.ai.request(&"bark_paraphrase", packet, {}, &"sg04"), 0)
	runtime.trace.clear()
	var joined := exit.joined_journal(runtime, "ferry_toll")
	assert_eq(runtime.quests.summary("ferry_toll"), joined)
	var prefetch := _row(runtime, "ai_prefetch")
	assert_eq(int(prefetch.get("capped", 0)), 1)
	assert_eq(runtime.ai.pending_count(), cap)
	var accepted := runtime.ai.request(&"journal_summary", runtime.ai.summary_packet("ferry_toll", runtime.quests.journal("ferry_toll")), {}, &"ferry_toll")
	assert_gt(accepted, 0)
	assert_eq(runtime.ai.pending_count(), cap + 1)


func _play_without_pump(provider: String) -> void:
	var exit := _Exit.new()
	var opened := exit.boot(provider)
	var runtime: WyrdRuntime = opened["runtime"]
	var harness: RefCounted = runtime.get_meta("m10_harness")
	runtime.dialogue.open_scene("toll.offer_room")
	var started := Time.get_ticks_usec()
	harness.line_rows(runtime)
	harness.choose_text(runtime, "Take the room")
	var line := runtime.dialogue.line()
	assert_lt(Time.get_ticks_usec() - started, 2000000)
	assert_false(line.text.is_empty())
	assert_eq(line.text, exit.authored(runtime, line.id))
	while runtime.dialogue.line() != null and runtime.dialogue.line().id != "a_leave":
		runtime.dialogue.advance()
	var leave := runtime.dialogue.line()
	assert_eq(leave.id, "a_leave")
	assert_eq(leave.text, "The boat leaves the dock.")
	assert_eq(str(leave.text_source), "authored")
	runtime.dialogue.advance()
	assert_false(runtime.dialogue.is_open())
	# Scene end cancels the depart prefetch. A host request stays open, and save still can.
	var held := runtime.ai.request(&"bark_paraphrase", runtime.ai.packet_for_line("sg04", &"bark_paraphrase", &""), {}, &"sg04")
	assert_gt(held, 0)
	assert_gt(runtime.ai.pending_count(), 0)
	assert_true(runtime.can_save())
	_storm_and_bark(exit, runtime)
	var joined := exit.joined_journal(runtime, "ferry_toll")
	assert_false(joined.is_empty())
	assert_eq(runtime.quests.summary("ferry_toll"), joined)
	var saved := runtime.save_state()
	var fresh := exit.boot(provider)
	var loaded: WyrdRuntime = fresh["runtime"]
	var report := loaded.load_state(JSON.parse_string(JSON.stringify(saved)))
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(loaded.ai.pending_count(), 0)
	loaded.dialogue.open_scene("toll.offer_room")
	assert_eq(loaded.dialogue.line().id, "a91f")
	assert_eq(loaded.dialogue.line().text, exit.authored(loaded, "a91f"))


func _storm_and_bark(exit: RefCounted, runtime: WyrdRuntime) -> void:
	runtime.facts.set_in(&"world.storm_heard", true, &"known/player")
	runtime.dialogue.open("tavern_owner")
	var asked: Dictionary = runtime.dialogue.ask_topic("tavern_owner", "storm_rumour")
	assert_eq(str(asked.get("reason", "")), "answered")
	var catcher: RefCounted = runtime.get_meta("m10_catch")
	var storm: WyrdLineView = catcher.get("topic_line")
	assert_eq(storm.id, "sg_storm")
	assert_eq(storm.text, "The storm took a skiff off the bar.")
	var host: WyrdFakeHost = runtime.get_meta("m10_host")
	host.spatial.set_nearby(&"player", 4.0, &"lantern", PackedStringArray([&"post"]))
	var won := runtime.director.query("bark", "", "ferry")
	assert_eq(str(won.get("line_id", "")), "sg04")
	var story := runtime.content().storylets.get(str(won.get("id", ""))) as WyrdStoryletDef
	runtime.present_bark(story, {"line_id": "sg04"})
	var bark: WyrdLineView = catcher.get("bark_line")
	assert_eq(bark.id, "sg04")
	assert_eq(bark.text, "Mind that flame near the ropes.")
	assert_eq(str(bark.text_source), "authored")


func _row(runtime: WyrdRuntime, kind: String) -> Dictionary:
	for item in runtime.trace.events:
		if str((item as Dictionary).get("kind", "")) == kind:
			return item
	return {}
