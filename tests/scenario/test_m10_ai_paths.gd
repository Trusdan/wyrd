extends GutTest

const _Exit := preload("res://tests/scenario/m10_gullhaven.gd")


func test_bark_scene_gossip_and_summary() -> void:
	var exit := _Exit.new()
	var opened := exit.boot("echo")
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = runtime.get_meta("m10_host")
	host.spatial.set_nearby(&"player", 4.0, &"lantern", PackedStringArray([&"post"]))
	runtime.tick(0)
	var won := runtime.director.query("bark", "", "ferry")
	assert_eq(str(won.get("line_id", "")), "sg04")
	var story := runtime.content().storylets["dock_bark_lantern"] as WyrdStoryletDef
	var drawn := {"line_id": "sg04"}
	runtime.present_bark(story, drawn)
	var first: WyrdLineView = (runtime.get_meta("m10_catch") as RefCounted).get("bark_line")
	assert_eq(first.text, "Mind that flame near the ropes.")
	assert_eq(str(first.text_source), "authored")
	exit.pump(runtime)
	runtime.present_bark(story, drawn)
	var second: WyrdLineView = (runtime.get_meta("m10_catch") as RefCounted).get("bark_line")
	assert_eq(str(second.text_source), "ai")
	assert_eq(str(_use(runtime, "sg04").get("slot_kind", "")), "bark_paraphrase")
	assert_eq(str(_use(runtime, "sg04").get("source", "")), "ai")
	_scene(exit, runtime)
	_gossip(exit, runtime)
	_journal(exit, runtime)
	runtime.ai.set_enabled(false)
	runtime.present_bark(story, drawn)
	var back: WyrdLineView = (runtime.get_meta("m10_catch") as RefCounted).get("bark_line")
	assert_eq(back.text, "Mind that flame near the ropes.")
	assert_eq(str(back.text_source), "authored")


func _scene(exit: RefCounted, runtime: WyrdRuntime) -> void:
	var harness: RefCounted = runtime.get_meta("m10_harness")
	runtime.dialogue.open_scene("toll.offer_room")
	harness.line_rows(runtime)
	harness.choose_text(runtime, "Take the room")
	# a920 waits in offer_room. The depart prefetch is sent when that divert is pushed.
	while runtime.dialogue.line() != null and runtime.dialogue.line().id != "a_cross":
		runtime.dialogue.advance()
	assert_eq(runtime.dialogue.line().id, "a_cross")
	assert_gt(runtime.ai.pending_count(), 0)
	exit.pump(runtime)
	runtime.dialogue.advance()
	var leave := runtime.dialogue.line()
	assert_eq(leave.id, "a_leave")
	assert_eq(str(leave.text_source), "ai")
	assert_eq(leave.text, "The boat leaves the dock.")
	runtime.dialogue.advance()


func _gossip(exit: RefCounted, runtime: WyrdRuntime) -> void:
	runtime.facts.set_in(&"world.storm_heard", true, &"known/player")
	var host: WyrdFakeHost = runtime.get_meta("m10_host")
	host.clock.season_name = &"autumn"
	runtime.events.emit(&"season_changed", {})
	runtime.facts.set_in(&"harbor.toll_fate", &"paid", &"known/player")
	runtime.roles.assign(&"tavern", &"tavern_owner")
	runtime.topics.unlock(&"rumor.ferry_toll")
	runtime.dialogue.open("tavern_owner")
	exit.pump(runtime)
	runtime.dialogue.ask_topic("tavern_owner", "rumor.ferry_toll")
	var gossip: WyrdLineView = (runtime.get_meta("m10_catch") as RefCounted).get("topic_line")
	assert_true(gossip.id == "sg02" or gossip.id == "sg03", gossip.id)
	assert_eq(str(gossip.text_source), "ai")
	assert_eq(str(_use(runtime, gossip.id).get("slot_kind", "")), "gossip")
	runtime.dialogue.open("tavern_owner")
	exit.pump(runtime)
	runtime.dialogue.ask_topic("tavern_owner", "storm_rumour")
	var storm: WyrdLineView = (runtime.get_meta("m10_catch") as RefCounted).get("topic_line")
	assert_eq(storm.id, "sg_storm")
	assert_eq(str(storm.text_source), "ai")
	assert_eq(str(_use(runtime, "sg_storm").get("slot_kind", "")), "gossip")
	var packet := runtime.ai.packet_for_line("sg_storm", &"gossip", &"tavern_owner")
	assert_true(packet["facts"].has("world.storm_heard"))


func _journal(exit: RefCounted, runtime: WyrdRuntime) -> void:
	var harness: RefCounted = runtime.get_meta("m10_harness")
	if runtime.quests.status("dock_rumour") != &"active":
		runtime.dialogue.ask_topic("tavern_owner", "storm_rumour")
	runtime.dialogue.open_scene("dock.rumour_talk")
	harness.line_rows(runtime)
	var joined: String = exit.joined_journal(runtime, "dock_rumour")
	assert_false(joined.is_empty())
	assert_eq(runtime.quests.summary("dock_rumour"), joined)
	assert_eq(String(runtime.quests.summary_source("dock_rumour")), "authored")
	exit.pump(runtime)
	assert_eq(runtime.quests.summary("dock_rumour"), joined)
	assert_eq(String(runtime.quests.summary_source("dock_rumour")), "ai")


func _use(runtime: WyrdRuntime, path: String) -> Dictionary:
	var found := {}
	for item in runtime.trace.events:
		var row: Dictionary = item
		if str(row.get("kind", "")) == "ai_use" and str(row.get("path", "")) == path:
			found = row
	return found
