extends GutTest

const _Harness := preload("res://tests/scenario/s2c_harness.gd")


func test_route_take_the_room() -> void:
	var runtime := _play(false)
	var harness := _Harness.new()
	runtime.dialogue.open_scene("toll.offer_room")
	var opening := harness.line_rows(runtime)
	assert_eq(harness.ids_of(opening), PackedStringArray(["a91f", "a_look", "a_alive", "a_bell"]))
	assert_eq(opening[0]["text"], "A room's two coins a night, and the stew is free.")
	assert_eq(opening[0]["speaker"], "tavern_owner")
	assert_eq(opening[0]["name"], "innkeeper")
	assert_null(opening[0]["audio"])
	assert_eq(runtime.dialogue.choices().size(), 1)
	assert_eq(runtime.dialogue.choices()[0].text, "Take the room")
	harness.choose_text(runtime, "Take the room")
	var rest := harness.line_rows(runtime)
	assert_eq(harness.ids_of(rest), PackedStringArray(["a920", "a_cross", "a_leave"]))
	assert_false(runtime.dialogue.is_open())
	assert_eq(runtime.facts.get(&"player.coins"), 2)
	assert_eq(runtime.facts.get(&"harbor.room_taken"), true)
	assert_eq(runtime.quests.stage("ferry_toll"), "pay_toll")
	assert_eq(runtime.quests.status("ferry_toll"), &"active")
	assert_true(runtime.quests.waiting_reason("ferry_toll").begins_with("waits_until:"))
	var entry: Dictionary = runtime.quests.journal("ferry_toll")[0]
	assert_eq(entry["id"], "j_ft_01")
	assert_eq(String(entry["text"]), "ferry master at the dock wants 2 coins before the crossing.")
	assert_eq(runtime.facts.get(&"ferry.toll_coins"), 2)
	runtime.facts.set(&"ferry.toll_coins", 9)
	assert_eq(String(runtime.quests.journal("ferry_toll")[0]["text"]), "ferry master at the dock wants 2 coins before the crossing.")


func test_journal_uses_the_holder_display_name() -> void:
	var opened := _boot(false)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.world.add_entity(&"ferry_master", &"person", "Bram", PackedStringArray(), true)
	_finish_room(runtime)
	assert_eq(runtime.roles.holder(&"ferry"), &"ferry_master")
	assert_eq(host.world.display_name(&"ferry_master"), "Bram")
	var entry: Dictionary = runtime.quests.journal("ferry_toll")[0]
	assert_eq(String(entry["text"]), "Bram at the dock wants 2 coins before the crossing.")


func test_route_local_place() -> void:
	var runtime := _play(true)
	var harness := _Harness.new()
	runtime.dialogue.open_scene("toll.offer_room")
	harness.line_rows(runtime)
	var labels := PackedStringArray()
	for view in runtime.dialogue.choices():
		labels.append(view.text)
	assert_eq(labels, PackedStringArray(["Take the room", "I have a place in town"]))
	harness.choose_text(runtime, "I have a place in town")
	var rest := harness.line_rows(runtime)
	assert_eq(harness.ids_of(rest), PackedStringArray(["a920", "a_cross", "a_leave"]))
	assert_eq(runtime.facts.get(&"player.coins"), 4)
	assert_null(runtime.facts.get(&"harbor.room_taken"))
	assert_eq(runtime.quests.stage("ferry_toll"), "pay_toll")


func test_route_lodging_fails() -> void:
	var opened := _boot(false)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.actions.set_result_for(&"assign_lodging", WyrdCommandResult.failed(&"full"))
	var harness := _Harness.new()
	runtime.dialogue.open_scene("toll.offer_room")
	harness.line_rows(runtime)
	harness.choose_text(runtime, "Take the room")
	var rest := harness.line_rows(runtime)
	assert_eq(harness.ids_of(rest), PackedStringArray(["a922", "a921"]))
	# `{{` is a literal brace. The second `}` is literal text, so the line keeps it.
	assert_eq(rest[1]["text"], "The board lists the price as {two coins}}.")
	assert_eq(runtime.facts.get(&"player.coins"), 4)
	assert_null(runtime.facts.get(&"harbor.room_taken"))
	assert_true(host.actions.executed.has(&"assign_lodging"))
	assert_false(runtime.dialogue.is_open())
	assert_true(runtime.can_save())
	assert_eq(runtime.quests.stage("ferry_toll"), "pay_toll")


func test_route_pay_and_cross() -> void:
	var runtime := _reach_toll(false)
	var stages: Array[String] = []
	runtime.quests.stage_changed.connect(func(_quest_id: String, stage_id: String) -> void: stages.append(stage_id))
	assert_true(runtime.quests.waiting_reason("ferry_toll").begins_with("waits_until:"))
	assert_eq(runtime.quests.stage("ferry_toll"), "pay_toll")
	runtime.tick(60)
	assert_eq(runtime.now_minutes(), 60)
	assert_eq(runtime.quests.stage("ferry_toll"), "cross")
	assert_eq(stages, ["cross"])
	assert_eq(runtime.quests.outcome("ferry_toll", "crossing"), "done")
	assert_eq(runtime.facts.get(&"world.storm_heard"), true)
	assert_eq(runtime.quests.journal("ferry_toll")[0]["date"], "day 1, 00:00")
	assert_eq(runtime.quests.offered_scene("ferry_toll"), "toll.depart")
	assert_eq(runtime.quests.status("ferry_toll"), &"active")
	runtime.dialogue.open_scene("toll.depart")
	var harness := _Harness.new()
	var rows := harness.line_rows(runtime)
	assert_eq(harness.ids_of(rows), PackedStringArray(["a_cross", "a_leave"]))
	assert_false(rows[0]["text"].is_empty())
	assert_eq(runtime.quests.status("ferry_toll"), &"completed")
	assert_eq(runtime.quests.waiting_reason("ferry_toll"), "")
	assert_true(runtime.can_save())


func test_route_notice_fails() -> void:
	var opened := _boot(false)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.actions.set_result_for(&"post_notice", WyrdCommandResult.failed(&"lost"))
	var topics: Array[String] = []
	runtime.effects.topic_unlocked.connect(func(topic: StringName) -> void: topics.append(String(topic)))
	_finish_room(runtime)
	assert_eq(topics, ["storm_rumour"])
	assert_eq(runtime.deeds.count_matching(&"player", &"paid"), 1)
	assert_eq(runtime.quests.journal("ferry_toll")[0]["id"], "j_ft_01")
	assert_eq(runtime.quests.stage("ferry_toll"), "gossip")
	assert_eq(runtime.quests.offered_scene("ferry_toll"), "toll.offer_room")
	assert_eq(runtime.quests.status("ferry_toll"), &"active")
	assert_ne(runtime.quests.outcome("ferry_toll", "crossing"), "done")


func test_route_ferry_empty_waits() -> void:
	var opened := _boot(false)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	var stages: Array[String] = []
	runtime.quests.stage_changed.connect(func(_quest_id: String, stage_id: String) -> void: stages.append(stage_id))
	var harness := _Harness.new()
	runtime.dialogue.open_scene("toll.offer_room")
	var opening := harness.line_rows(runtime)
	assert_true(harness.ids_of(opening).has("a_alive"))
	host.world.add_entity(&"ferry_master", &"person", "ferry master", PackedStringArray(), false)
	runtime.roles.vacate(&"ferry_master", &"died")
	harness.choose_text(runtime, "Take the room")
	harness.line_rows(runtime)
	assert_false(runtime.dialogue.is_open())
	assert_true(stages.has("pay_toll"))
	assert_eq(runtime.quests.variant_of("ferry_toll"), "")
	assert_eq(runtime.quests.stage("ferry_toll"), "gossip")
	assert_eq(runtime.quests.waiting_reason("ferry_toll"), "on_empty")
	assert_eq(runtime.quests.status("ferry_toll"), &"active")
	assert_eq(runtime.quests.offered_scene("ferry_toll"), "")
	var found := false
	for entry in runtime.quests.journal("ferry_toll"):
		if String(entry["id"]) == "j_ft_empty":
			found = true
			assert_eq(String(entry["text"]), "The dock is empty, so the crossing waits.")
			assert_eq(String(entry["date"]), "day 1, 00:00")
	assert_true(found)
	assert_ne(runtime.quests.outcome("ferry_toll", "crossing"), "done")


func test_route_successor_resumes() -> void:
	var opened := _boot(false)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.roles.define(&"ferry_master", "relation(apprentice)")
	runtime.social.set_kind(&"ferry_master", &"dock_apprentice", &"apprentice")
	runtime.roles.vacate(&"ferry_master", &"died")
	assert_eq(runtime.roles.slot_state(&"ferry", "ferry_toll"), &"successor")
	assert_eq(runtime.roles.slot_holder("ferry_toll", &"ferry"), &"dock_apprentice")
	_finish_room(runtime)
	assert_eq(runtime.quests.stage("ferry_toll"), "pay_toll")
	assert_ne(runtime.quests.variant_of("ferry_toll"), "ferry.empty")
	assert_string_contains(String(runtime.quests.journal("ferry_toll")[0]["text"]), "apprentice")
	runtime.tick(0)
	assert_eq(runtime.quests.stage("ferry_toll"), "cross")
	runtime.dialogue.open_scene("toll.depart")
	var rows := _Harness.new().line_rows(runtime)
	assert_eq(rows[0]["speaker"], "dock_apprentice")
	assert_eq(rows[0]["name"], "apprentice")
	assert_eq(runtime.quests.status("ferry_toll"), &"completed")
	assert_eq(runtime.quests.outcome("ferry_toll", "crossing"), "done")


func test_route_season_changes_lines() -> void:
	var calm := _play(false)
	calm.dialogue.open_scene("toll.offer_room")
	var calm_ids := _Harness.new().ids_of(_Harness.new().line_rows(calm))
	assert_false(calm_ids.has("a_season"))
	calm.dialogue.abort(&"stop")
	var opened := _boot(false)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.clock.season_name = &"storm"
	runtime.events.emit(&"season_changed", {})
	runtime.dialogue.open_scene("toll.offer_room")
	var rows := _Harness.new().line_rows(runtime)
	var storm_ids := _Harness.new().ids_of(rows)
	assert_eq(storm_ids, PackedStringArray(["a91f", "a_look", "a_alive", "a_season", "a_bell"]))
	var season_text := ""
	for row in rows:
		if String(row["id"]) == "a_season":
			season_text = String(row["text"])
	assert_eq(season_text, "The season smells like rain.")


func test_route_abort_pending_and_save() -> void:
	var runtime := _play(false)
	var ended: Array[String] = []
	runtime.dialogue.scene_ended.connect(func(scene_id: String, status: StringName, reason: StringName) -> void:
		ended.append("%s:%s:%s" % [scene_id, String(status), String(reason)])
	)
	runtime.dialogue.open_scene("toll.offer_room")
	var line := runtime.dialogue.line()
	assert_eq(line.id, "a91f")
	assert_false(line.text.is_empty())
	assert_false(runtime.can_save())
	assert_false(runtime.dialogue.can_save())
	runtime.dialogue.abort(&"left")
	assert_eq(ended, ["toll.offer_room:aborted:left"])
	assert_eq(runtime.deeds.count_matching(&"player", &"left"), 1)
	assert_true(runtime.can_save())
	assert_eq(runtime.quests.status("ferry_toll"), &"active")
	assert_eq(runtime.quests.stage("ferry_toll"), "gossip")
	assert_eq(runtime.quests.offered_scene("ferry_toll"), "toll.offer_room")
	assert_eq(runtime.quests.waiting_reason("ferry_toll"), "scene:toll.offer_room")
	runtime.dialogue.open_scene("toll.offer_room")
	assert_eq(runtime.dialogue.line().id, "a91f")
	assert_false(runtime.can_save())
	runtime.dialogue.abort(&"left")
	assert_true(runtime.can_save())


func test_text_stays_with_and_without_audio() -> void:
	var silent := _play(false)
	silent.dialogue.open_scene("toll.offer_room")
	var first := silent.dialogue.line()
	assert_eq(first.id, "a91f")
	assert_false(first.text.is_empty())
	assert_null(first.audio)
	var held := first.text
	assert_eq(silent.dialogue.line().id, "a91f")
	assert_eq(silent.dialogue.line().text, held)
	silent.dialogue.advance()
	assert_ne(silent.dialogue.line().id, "a91f")
	assert_false(silent.dialogue.line().text.is_empty())
	var voiced := _play(false)
	var heard: Array[String] = []
	voiced.dialogue.locale = "en"
	voiced.dialogue.register_line_audio(func(line_id: String, locale: String) -> Variant:
		heard.append("%s:%s" % [line_id, locale])
		return _tone()
	)
	voiced.dialogue.open_scene("toll.offer_room")
	var line := voiced.dialogue.line()
	assert_eq(line.id, first.id)
	assert_eq(line.text, held)
	assert_true(line.audio is AudioStreamWAV)
	assert_eq(heard, ["a91f:en"])
	assert_eq(voiced.dialogue.line().text, held)
	assert_eq(voiced.dialogue.line().id, "a91f")
	voiced.dialogue.advance()
	assert_eq(voiced.dialogue.line().id, "a_look")
	assert_false(voiced.dialogue.line().text.is_empty())
	assert_true(voiced.dialogue.line().audio is AudioStreamWAV)
	var silent_rest := _Harness.new().ids_of(_Harness.new().line_rows(silent))
	var voiced_rest := _Harness.new().ids_of(_Harness.new().line_rows(voiced))
	assert_eq(voiced_rest, silent_rest)


func _play(local_tag: bool) -> WyrdRuntime:
	return _boot(local_tag)["runtime"]


func _boot(local_tag: bool) -> Dictionary:
	var opened := _Harness.new().boot_gullhaven(local_tag)
	var runtime: WyrdRuntime = opened["runtime"]
	assert_true(opened["report"].ok, opened["report"].diagnostics.format())
	assert_eq(runtime.quests.status("ferry_toll"), &"active")
	assert_eq(runtime.quests.stage("ferry_toll"), "gossip")
	assert_eq(runtime.quests.offered_scene("ferry_toll"), "toll.offer_room")
	return opened


func _reach_toll(local_tag: bool) -> WyrdRuntime:
	var runtime := _play(local_tag)
	_finish_room(runtime)
	return runtime


func _finish_room(runtime: WyrdRuntime) -> void:
	var harness := _Harness.new()
	runtime.dialogue.open_scene("toll.offer_room")
	harness.line_rows(runtime)
	harness.choose_text(runtime, "Take the room")
	harness.line_rows(runtime)


func _tone() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	stream.data = PackedByteArray([128, 160, 128, 96])
	return stream
