extends GutTest

const _Harness := preload("res://tests/scenario/s2c_harness.gd")

var _answered: Array = []


func test_dock_rumour_route() -> void:
	var opened := _Harness.new().boot_gullhaven(false, 4)
	var runtime: WyrdRuntime = opened["runtime"]
	var harness := _Harness.new()
	runtime.dialogue.topic_answered.connect(_on_answered)
	runtime.dialogue.open_scene("toll.offer_room")
	harness.line_rows(runtime)
	harness.choose_text(runtime, "Take the room")
	harness.line_rows(runtime)
	assert_false(runtime.dialogue.is_open())
	assert_true(runtime.topics.is_unlocked(&"storm_rumour"))
	assert_eq(runtime.storylets.seen_of("harbor_gossip.storm"), 0)
	assert_true(runtime.can_save())
	assert_eq(runtime.dialogue.open("tavern_owner"), PackedStringArray(["storm_rumour"]))
	assert_eq(runtime.storylets.seen_of("harbor_gossip.storm"), 0)
	assert_true(runtime.can_save())
	var row: Dictionary = runtime.dialogue.ask_topic("tavern_owner", "storm_rumour")
	assert_eq(str(row["reason"]), "answered")
	assert_eq(str(row["id"]), "harbor_gossip.storm")
	assert_eq(_answered.size(), 1)
	assert_eq(str(_answered[0]["speaker"]), "tavern_owner")
	assert_eq(str(_answered[0]["name"]), "innkeeper")
	assert_eq(runtime.quests.status("dock_rumour"), &"active")
	assert_eq(runtime.quests.offered_scene("dock_rumour"), "dock.rumour_talk")
	runtime.dialogue.open_scene("dock.rumour_talk")
	var lines := harness.line_rows(runtime)
	assert_eq(lines.size(), 1)
	assert_eq(str(lines[0]["id"]), "rumour_line")
	assert_false(runtime.dialogue.is_open())
	assert_false(runtime.topics.is_unlocked(&"storm_rumour"))
	assert_eq(runtime.dialogue.open("tavern_owner"), PackedStringArray())
	var saved := runtime.save_state()
	var fresh: WyrdRuntime = _Harness.new().boot_gullhaven(false, 4)["runtime"]
	var report := fresh.load_state(JSON.parse_string(JSON.stringify(saved)))
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(JSON.stringify(fresh.save_state()), JSON.stringify(saved))


func _on_answered(npc: StringName, topic: StringName, line: WyrdLineView) -> void:
	_answered.append({
		"name": line.display_name,
		"npc": String(npc),
		"speaker": String(line.speaker),
		"topic": String(topic),
	})
