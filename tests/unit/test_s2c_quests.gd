extends GutTest

const _Harness := preload("res://tests/scenario/s2c_harness.gd")


func test_statuses_journal_host_step_and_empty_wait() -> void:
	var opened := _Harness.new().open_pack(_Harness.SAMPLE)
	var runtime: WyrdRuntime = opened["runtime"]
	assert_true(opened["report"].ok, opened["report"].diagnostics.format())
	var unavailable: Array[String] = []
	var states: Array[String] = []
	var stages: Array[String] = []
	var host_steps: Array[String] = []
	runtime.quests.content_unavailable.connect(func(quest_id: String, pack_id: String) -> void:
		unavailable.append("%s:%s" % [quest_id, pack_id])
	)
	runtime.quests.quest_state_changed.connect(func(quest_id: String, status: StringName) -> void:
		states.append("%s:%s" % [quest_id, String(status)])
	)
	runtime.quests.stage_changed.connect(func(quest_id: String, stage_id: String) -> void:
		stages.append("%s:%s" % [quest_id, stage_id])
	)
	runtime.quests.host_step_requested.connect(func(quest_id: String, screen_id: StringName, fields: PackedStringArray) -> void:
		host_steps.append("%s:%s:%d" % [quest_id, String(screen_id), fields.size()])
	)
	assert_eq(runtime.quests.status("blocked"), &"unavailable")
	runtime.start_new_game(4)
	assert_eq(unavailable, ["blocked:missing"])
	assert_eq(runtime.quests.status("blocked"), &"unavailable")
	assert_eq(runtime.quests.status("sample"), &"dormant")
	assert_eq(runtime.quests.status("plain"), &"dormant")
	assert_eq(runtime.quests.format_date(0), "day 1, 00:00")
	assert_eq(runtime.quests.format_date(60), "day 1, 01:00")
	assert_eq(runtime.quests.format_date(1500), "day 2, 01:00")
	runtime.facts.set(&"meter.n", 0)
	runtime.facts.set(&"meter.arm", true)
	runtime.tick(0)
	assert_eq(runtime.quests.status("plain"), &"completed")
	assert_eq(runtime.quests.outcome("plain", "gate"), "done")
	assert_eq(runtime.quests.stage("plain"), "only")
	var entry: Dictionary = runtime.quests.journal("plain")[0]
	assert_eq(entry["id"], "j_arm")
	assert_eq(entry["text"], "Arm 0.")
	assert_eq(entry["date"], "day 1, 00:00")
	assert_eq(int(entry["minutes"]), 0)
	runtime.facts.set(&"meter.n", 7)
	assert_eq(runtime.quests.journal("plain")[0]["text"], "Arm 0.")
	runtime.quests.register_date_formatter(func(minutes: int) -> String: return "m%d" % minutes)
	assert_eq(runtime.quests.format_date(5), "m5")
	assert_eq(runtime.quests.journal("plain")[0]["date"], "day 1, 00:00")
	runtime.facts.set(&"meter.flag", true)
	runtime.tick(0)
	assert_eq(runtime.quests.status("endings"), &"failed")
	assert_eq(runtime.quests.outcome("endings", "gate"), "failed")
	assert_true(states.has("plain:available"))
	assert_true(states.has("plain:active"))
	assert_true(states.has("plain:completed"))
	assert_true(states.has("endings:failed"))
	assert_true(stages.has("plain:only"))
	assert_true(stages.has("endings:bad"))
	runtime.roles.assign(&"clerk_role", &"clerk")
	runtime.facts.set(&"meter.n", 1)
	runtime.tick(0)
	assert_eq(runtime.quests.status("sample"), &"active")
	assert_eq(runtime.quests.stage("sample"), "talk")
	assert_eq(runtime.quests.offered_scene("sample"), "talk")
	assert_eq(runtime.quests.waiting_reason("sample"), "scene:talk")
	var fields := PackedStringArray(["ok"])
	runtime.quests.request_host_step("sample", &"board", fields)
	assert_eq(host_steps, ["sample:board:1"])
	assert_eq(runtime.quests.waiting_reason("sample"), "host:board")
	runtime.tick(0)
	assert_eq(runtime.quests.stage("sample"), "talk")
	runtime.quests.complete_host_step("sample", {"ok": true})
	assert_eq(runtime.quests.host_returns("sample")["ok"], true)
	assert_eq(runtime.quests.waiting_reason("sample"), "scene:talk")
	assert_eq(runtime.quests.status("sample"), &"active")
	runtime.dialogue.open_scene("talk")
	assert_false(runtime.can_save())
	runtime.quests.abandon("sample")
	assert_eq(runtime.quests.status("sample"), &"abandoned")
	assert_true(runtime.can_save())
	assert_eq(runtime.dialogue.line(), null)


func test_empty_slot_waits_then_resumes() -> void:
	var opened := _Harness.new().open_pack(_Harness.SAMPLE)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.world.add_entity(&"clerk", &"person", "clerk", PackedStringArray(), true)
	runtime.start_new_game(5)
	runtime.facts.set(&"meter.n", 1)
	runtime.tick(0)
	assert_eq(runtime.quests.status("sample"), &"active")
	assert_eq(runtime.quests.waiting_reason("sample"), "on_empty")
	assert_eq(runtime.quests.offered_scene("sample"), "")
	runtime.roles.assign(&"clerk_role", &"clerk")
	runtime.tick(0)
	assert_eq(runtime.quests.waiting_reason("sample"), "scene:talk")
	assert_eq(runtime.quests.offered_scene("sample"), "talk")
