extends GutTest


class AbortActions extends WyrdActionAdapter:
	var runner: WyrdSceneRunner

	func execute(cmd: WyrdCommand) -> WyrdCommandResult:
		if runner != null and cmd != null and String(cmd.name) == "close_now":
			runner.abort(&"cut")
		return WyrdCommandResult.ok()


func test_storylet_effects_run_on_topic_bark_event_and_beat_wins() -> void:
	var runtime := _boot()
	runtime.effects.scene_id = "kept"
	runtime.effects.choice_id = "kept-choice"
	var topic: Dictionary = runtime.director.query("topic", "news", "")
	assert_eq(str(topic["id"]), "topic.win")
	assert_eq(runtime.facts.get(&"player.coins"), 4)
	assert_eq(runtime.quests.status("rumour"), &"active")
	var wrote := runtime.effects.provenance_of("player.coins")
	assert_eq(str(wrote["scene"]), "storylet:topic.win")
	assert_eq(str(wrote["choice"]), "")
	assert_eq(runtime.effects.scene_id, "kept")
	assert_eq(runtime.effects.choice_id, "kept-choice")
	assert_eq(str(runtime.director.query("bark", "", "ada")["id"]), "bark.win")
	assert_eq(runtime.facts.get(&"player.coins"), 1)
	assert_eq(str(runtime.director.query("event", "tide", "")["id"]), "event.win")
	assert_eq(runtime.facts.get(&"player.coins"), 2)
	assert_eq(str(runtime.director.query("beat", "gate.one", "")["id"]), "beat.win")
	assert_eq(runtime.facts.get(&"player.coins"), 3)


func test_storylet_effects_do_not_run_for_reads() -> void:
	var opened := _host()
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.world.add_entity(&"ada", &"person", "Ada", PackedStringArray(), true)
	runtime.facts.set(&"player.coins", 0)
	runtime.topics.unlock(&"read_news")
	assert_eq(str(runtime.director.why_not("topic.read", "topic", "read_news", "ada")["reason"]), "ok")
	runtime.director.candidate_rows("topic", "read_news", "ada")
	assert_eq(runtime.dialogue.open("ada"), PackedStringArray(["read_news"]))
	assert_eq(runtime.facts.get(&"player.coins"), 0)
	assert_eq(runtime.storylets.seen_of("topic.read"), 0)
	assert_eq(runtime.quests.status("rumour"), &"dormant")


func test_a_do_failure_pushes_an_error_and_continues() -> void:
	var opened := _host()
	var runtime: WyrdRuntime = opened["runtime"]
	opened["host"].actions.set_result(WyrdCommandResult.failed(&"nope"))
	runtime.topics.unlock(&"fail_news")
	var row: Dictionary = runtime.dialogue.ask_topic("ada", "fail_news")
	assert_push_error("WyrdEffects: \"miss\" failed with no on_fail")
	assert_eq(str(row["reason"]), "answered")
	assert_eq(runtime.facts.get(&"player.coins"), 5)


func test_scene_effects_run_in_order_and_on_fail_diverts() -> void:
	var opened := _host()
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.dialogue.open_scene("gate.order")
	assert_eq(runtime.facts.get(&"player.coins"), 1)
	assert_eq(runtime.dialogue.line().text, "Hello.")
	runtime.dialogue.advance()
	assert_eq(runtime.facts.get(&"player.coins"), 2)
	assert_false(runtime.dialogue.is_open())
	opened["host"].actions.set_result_for(&"ping", WyrdCommandResult.failed(&"nope"))
	runtime.dialogue.open_scene("gate.divert")
	assert_eq(runtime.dialogue.line().id, "divert_yes")
	runtime.dialogue.advance()
	assert_false(runtime.dialogue.is_open())


func test_an_effect_that_closes_the_scene_stops_the_pump() -> void:
	var opened := _host()
	var runtime: WyrdRuntime = opened["runtime"]
	var actions := AbortActions.new()
	actions.runner = runtime.dialogue
	runtime.register_adapter(WyrdActionAdapter, actions)
	runtime.dialogue.open_scene("gate.close")
	assert_false(runtime.dialogue.is_open())
	assert_null(runtime.dialogue.line())


func test_a_step_assign_does_not_abort_its_own_scene() -> void:
	var opened := _host()
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.world.add_entity(&"ada", &"person", "Ada", PackedStringArray(), true)
	host.world.add_entity(&"bea", &"person", "Bea", PackedStringArray(), true)
	runtime.roles.assign(&"keeper", &"ada")
	runtime.quests.start("gate")
	runtime.dialogue.open_scene("gate.step")
	assert_true(runtime.dialogue.is_open())
	assert_eq(runtime.dialogue.line().id, "step_line")
	assert_eq(runtime.roles.holder(&"keeper"), &"bea")
	runtime.dialogue.abort(&"host")
	runtime.roles.assign(&"keeper", &"ada")
	runtime.quests.start("outerq")
	runtime.dialogue.open_scene("gate.outer")
	assert_false(runtime.dialogue.is_open())
	assert_eq(runtime.roles.holder(&"keeper"), &"bea")


func test_own_quest_advance_from_a_step_refuses_scene_open() -> void:
	var runtime := _boot()
	runtime.quests.start("mover")
	runtime.dialogue.open_scene("gate.advance")
	assert_push_warning("WyrdQuestRunner.advance: \"mover\" has an open scene")
	assert_true(runtime.dialogue.is_open())
	assert_eq(runtime.quests.stage("mover"), "one")
	assert_eq(runtime.dialogue.line().id, "advance_line")


func test_effect_run_traces_storylet_and_scene() -> void:
	var runtime := _boot()
	runtime.trace.enabled = true
	runtime.trace.clear()
	runtime.director.query("topic", "news", "")
	var story := _kinds(runtime, "effect_run")
	assert_eq(story.size(), 2)
	assert_eq(str(story[0]["source"]), "storylet")
	assert_eq(str(story[0]["id"]), "topic.win")
	assert_eq(str(story[0]["effect"]), "set")
	assert_eq(str(story[0]["scope"]), "topic.win")
	assert_eq(str(story[1]["effect"]), "start_quest")
	runtime.trace.prefix = "topic.win"
	runtime.trace.clear()
	runtime.director.query("bark", "", "ada")
	assert_eq(_kinds(runtime, "effect_run").size(), 0)
	runtime.trace.prefix = "gate.order"
	runtime.dialogue.open_scene("gate.order")
	var scene := _kinds(runtime, "effect_run")
	assert_eq(scene.size(), 1)
	assert_eq(str(scene[0]["source"]), "scene")
	assert_eq(str(scene[0]["id"]), "gate.order")
	assert_eq(str(scene[0]["effect"]), "set")
	runtime.dialogue.abort(&"host")


func _kinds(runtime: WyrdRuntime, kind: String) -> Array:
	var found: Array = []
	for item in runtime.trace.events:
		if item is Dictionary and str((item as Dictionary).get("kind", "")) == kind:
			found.append(item)
	return found


func _boot() -> WyrdRuntime:
	return _host()["runtime"]


func _host() -> Dictionary:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var path := "user://wyrd_effect_sites.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(_PACK.strip_edges() + "\n")
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(5)
	host.world.add_entity(&"ada", &"person", "Ada", PackedStringArray(), true)
	return {"host": host, "runtime": runtime}


const _PACK := """
language 1

events
  tide()

facts
  player.coins : int stored

role keeper
  succession: none
  vacancy: hold

quest gate "Gate"
  start when false
  on_empty: wait
  slot desk = keeper mode: live
  stage one
    scene gate.step with desk
    waits_until false

quest outerq "Outer"
  start when false
  on_empty: wait
  slot desk = keeper mode: live
  stage one
    scene gate.outer with desk
    waits_until false

quest mover "Mover"
  start when false
  stage one
    scene gate.advance
    waits_until false
  stage two
    waits_until false

quest rumour "Rumour"
  start when false
  stage told
    waits_until false

storylet topic.win
  scope: topic news
  speaker: any
  ~ set player.coins = 4
  ~ start quest rumour
  - News. #line:news_line

storylet bark.win
  scope: bark
  speaker: ada
  ~ set player.coins = 1
  - Bark. #line:bark_line

storylet event.win
  scope: event tide
  speaker: any
  ~ set player.coins = 2
  - Event. #line:event_line

storylet beat.win
  scope: beat gate.one
  speaker: any
  ~ set player.coins = 3
  - Beat. #line:beat_line

storylet topic.fail
  scope: topic fail_news
  speaker: any
  ~ do miss()
  ~ set player.coins = 5
  - Fail. #line:fail_line

storylet topic.read
  scope: topic read_news
  speaker: any
  ~ set player.coins = 8
  - Read. #line:read_line

scene gate.order
  ~ set player.coins = 1
  narrator: Hello. #line:order_hi
  ~ set player.coins = 2
  -> end

scene gate.divert
  ~ do ping() on_fail -> skip
  narrator: No. #line:divert_no
  - (skip)
  narrator: Yes. #line:divert_yes
  -> end

scene gate.close
  ~ do close_now()
  narrator: After. #line:close_after
  -> end

scene gate.step
  ~ assign role keeper to bea
  desk: Still here. #line:step_line
  -> end

scene gate.outer
  -> scene gate.inner

scene gate.inner
  ~ assign role keeper to bea
  desk: Inner. #line:inner_line
  -> end

scene gate.advance
  ~ advance mover to two
  narrator: Stayed. #line:advance_line
  -> end
"""
