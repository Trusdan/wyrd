extends GutTest

const _Harness := preload("res://tests/scenario/s2c_harness.gd")


func test_lines_choices_subscene_fail_and_abort() -> void:
	var opened := _boot()
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	runtime.facts.set(&"meter.n", 1)
	var ended: Array[String] = []
	runtime.dialogue.scene_ended.connect(func(scene_id: String, status: StringName, reason: StringName) -> void:
		ended.append("%s:%s:%s" % [scene_id, String(status), String(reason)])
	)
	runtime.dialogue.open_scene("talk")
	var opening := _Harness.new().line_rows(runtime)
	assert_eq(_Harness.new().ids_of(opening), PackedStringArray(["h1", "h3"]))
	assert_eq(opening[0]["text"], "Hello.")
	assert_eq(opening[0]["name"], "narrator")
	assert_eq(opening[1]["text"], "You have 1.")
	assert_eq(opening[0]["audio"], null)
	var labels: PackedStringArray = PackedStringArray()
	for view in runtime.dialogue.choices():
		labels.append(view.text)
	assert_eq(labels, PackedStringArray(["Go", "Wait"]))
	var wait: WyrdChoiceView = runtime.dialogue.choices()[1]
	assert_false(wait.enabled)
	assert_eq(wait.reason, "too soon")
	assert_eq(wait.id, "c_wait")
	runtime.dialogue.choose(1)
	assert_push_error("disabled")
	assert_eq(runtime.dialogue.choices().size(), 2)
	_Harness.new().choose_text(runtime, "Go")
	var after := _Harness.new().line_rows(runtime)
	assert_eq(_Harness.new().ids_of(after), PackedStringArray(["h4", "i1"]))
	assert_eq(runtime.facts.get(&"meter.n"), 2)
	assert_eq(runtime.dialogue.choices()[0].text, "Fail the ping")
	host.actions.set_result_for(&"sample_ping", WyrdCommandResult.failed(&"nope"))
	_Harness.new().choose_text(runtime, "Fail the ping")
	var failed := _Harness.new().line_rows(runtime)
	assert_eq(_Harness.new().ids_of(failed), PackedStringArray(["i3"]))
	assert_eq(failed[0]["text"], "Ping failed.")
	assert_false(failed[0]["text"].is_empty())
	assert_eq(ended, ["talk:ended:"])
	assert_true(runtime.can_save())
	runtime.facts.set(&"meter.n", 6)
	runtime.dialogue.open_scene("talk")
	var big := _Harness.new().line_rows(runtime)
	assert_eq(_Harness.new().ids_of(big), PackedStringArray(["h1", "h2", "h3"]))
	assert_eq(big[1]["text"], "Big.")
	assert_eq(big[2]["text"], "You have 6.")
	runtime.dialogue.abort(&"left")
	assert_eq(runtime.facts.get(&"meter.n"), 7)
	assert_eq(ended[ended.size() - 1], "talk:aborted:left")
	assert_true(runtime.can_save())


func test_command_success_returns_from_subscene() -> void:
	var opened := _boot()
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.facts.set(&"meter.n", 0)
	runtime.dialogue.open_scene("talk")
	_Harness.new().line_rows(runtime)
	var wait: WyrdChoiceView = runtime.dialogue.choices()[1]
	assert_true(wait.enabled)
	assert_eq(wait.reason, "")
	_Harness.new().choose_text(runtime, "Go")
	_Harness.new().line_rows(runtime)
	_Harness.new().choose_text(runtime, "Fail the ping")
	var rows := _Harness.new().line_rows(runtime)
	assert_eq(_Harness.new().ids_of(rows), PackedStringArray(["i2"]))
	assert_eq(rows[0]["text"], "Pinged.")
	assert_eq(runtime.facts.get(&"meter.n"), 1)
	assert_false(runtime.dialogue.is_open())


func test_text_stays_with_and_without_audio() -> void:
	var silent := _boot()
	var runtime: WyrdRuntime = silent["runtime"]
	runtime.facts.set(&"meter.n", 4)
	runtime.dialogue.locale = "en"
	runtime.dialogue.open_scene("talk.only")
	var first := runtime.dialogue.line()
	assert_eq(first.id, "t_if")
	assert_eq(first.text, "yes")
	assert_null(first.audio)
	var stuck := first.text
	assert_eq(runtime.dialogue.line().text, stuck)
	assert_eq(runtime.dialogue.line().id, "t_if")
	runtime.dialogue.advance()
	assert_false(runtime.dialogue.is_open())
	var voiced := _boot()
	var again: WyrdRuntime = voiced["runtime"]
	var heard: Array[String] = []
	again.facts.set(&"meter.n", 4)
	again.dialogue.locale = "en"
	again.dialogue.register_line_audio(func(line_id: String, locale: String) -> Variant:
		heard.append("%s:%s" % [line_id, locale])
		return _tone()
	)
	again.dialogue.open_scene("talk.only")
	var line := again.dialogue.line()
	assert_eq(line.text, first.text)
	assert_eq(line.id, first.id)
	assert_true(line.audio is AudioStreamWAV)
	assert_eq(heard, ["t_if:en"])
	assert_true(again.dialogue.is_open())
	assert_eq(again.dialogue.line().text, "yes")
	again.dialogue.advance()
	assert_false(again.dialogue.is_open())
	again.facts.set(&"meter.n", 0)
	again.dialogue.open_scene("talk.only")
	assert_eq(again.dialogue.line().text, "no")
	assert_true(again.dialogue.line().audio is AudioStreamWAV)


func test_missing_fact_hides_the_line_and_holder_death_aborts() -> void:
	var opened := _boot()
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	runtime.dialogue.open_scene("talk")
	var rows := _Harness.new().line_rows(runtime)
	var ids := _Harness.new().ids_of(rows)
	assert_false(ids.has("h2"))
	assert_true(ids.has("h3"))
	assert_eq(rows[1]["text"], "You have .")
	assert_eq(runtime.dialogue.choices().size(), 2)
	assert_eq(runtime.dialogue.choices()[0].id, "c_go")
	assert_true(runtime.dialogue.choices()[1].enabled)
	runtime.dialogue.abort(&"skip")
	host.world.add_entity(&"clerk", &"person", "clerk", PackedStringArray(), true)
	runtime.roles.assign(&"clerk_role", &"clerk")
	runtime.facts.set(&"meter.n", 1)
	runtime.tick(0)
	var reasons: Array[String] = []
	runtime.dialogue.scene_ended.connect(func(_id: String, status: StringName, reason: StringName) -> void:
		reasons.append("%s:%s" % [String(status), String(reason)])
	)
	runtime.dialogue.open_scene("talk")
	assert_false(runtime.can_save())
	assert_ne(runtime.dialogue.line(), null)
	host.world.add_entity(&"clerk", &"person", "clerk", PackedStringArray(), false)
	runtime.dialogue.on_tick()
	assert_eq(reasons, ["aborted:holder_died"])
	assert_true(runtime.can_save())
	assert_eq(runtime.quests.offered_scene("sample"), "talk")
	assert_eq(runtime.quests.waiting_reason("sample"), "scene:talk")
	runtime.dialogue.open_scene("talk")
	runtime.roles.assign(&"clerk_role", &"other")
	assert_false(runtime.dialogue.is_open())
	assert_eq(reasons, ["aborted:holder_died", "aborted:holder_left"])
	assert_eq(runtime.quests.status("sample"), &"active")
	assert_eq(runtime.quests.stage("sample"), "talk")


func _boot() -> Dictionary:
	var opened := _Harness.new().open_pack(_Harness.SAMPLE)
	var runtime: WyrdRuntime = opened["runtime"]
	assert_true(opened["report"].ok, opened["report"].diagnostics.format())
	runtime.start_new_game(8)
	return opened


func _tone() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	stream.data = PackedByteArray([128, 160, 128, 96])
	return stream
