extends GutTest

const _Harness := preload("res://tests/scenario/s2c_harness.gd")

var _unlocked: Array = []
var _locked: Array = []
var _answered: Array = []


func before_each() -> void:
	_unlocked.clear()
	_locked.clear()
	_answered.clear()


func test_unlock_and_lock_reasons() -> void:
	var runtime := WyrdRuntime.new()
	runtime.topics.topic_unlocked.connect(_on_unlocked)
	runtime.topics.topic_locked.connect(_on_locked)
	assert_eq(runtime.topics.unlock(&"storm_rumour"), "unlocked")
	assert_eq(runtime.topics.unlock(&"storm_rumour"), "already")
	assert_eq(_unlocked, ["storm_rumour"])
	assert_true(runtime.topics.is_unlocked(&"storm_rumour"))
	assert_eq(runtime.topics.lock(&"missing_topic"), "not_unlocked")
	assert_eq(_locked, [])
	assert_eq(runtime.topics.lock(&"storm_rumour"), "locked")
	assert_eq(_locked, ["storm_rumour"])
	assert_false(runtime.topics.is_unlocked(&"storm_rumour"))
	runtime.topics.unlock(&"b_topic")
	runtime.topics.unlock(&"a_topic")
	assert_eq(runtime.topics.unlocked(), PackedStringArray(["a_topic", "b_topic"]))


func test_repeat_unlock_emits_once_from_effects_and_the_facade() -> void:
	var runtime := WyrdRuntime.new()
	var from_effects: Array = []
	runtime.effects.topic_unlocked.connect(func(topic: StringName) -> void:
		from_effects.append(String(topic))
	)
	var effect := WyrdEffectDef.new()
	effect.kind = &"unlock_topic"
	effect.topic = "storm_rumour"
	runtime.effects.run_one(effect)
	runtime.effects.run_one(effect)
	assert_eq(from_effects, ["storm_rumour"])
	assert_true(runtime.topics.is_unlocked(&"storm_rumour"))
	var facade: Node = load("res://addons/wyrd/runtime/wyrd.gd").new()
	add_child_autofree(facade)
	facade.topics.topic_unlocked.connect(_on_unlocked)
	facade.topics.topic_locked.connect(_on_locked)
	assert_eq(facade.topics.unlock(&"harbor_toll"), "unlocked")
	assert_eq(facade.topics.unlock(&"harbor_toll"), "already")
	assert_eq(_unlocked, ["harbor_toll"])
	assert_eq(facade.topics.lock(&"harbor_toll"), "locked")
	assert_eq(_locked, ["harbor_toll"])
	var locked := WyrdEffectDef.new()
	locked.kind = &"lock_topic"
	locked.topic = "storm_rumour"
	runtime.effects.run_one(locked)
	assert_false(runtime.topics.is_unlocked(&"storm_rumour"))


func test_open_lists_eligible_topics_without_a_selection() -> void:
	var opened := _boot(_PACK)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.world.add_entity(&"ada", &"person", "Ada", PackedStringArray(), true)
	host.world.add_entity(&"bea", &"person", "Bea", PackedStringArray(), true)
	runtime.roles.assign(&"keeper", &"ada")
	runtime.topics.unlock(&"b_topic")
	runtime.topics.unlock(&"a_topic")
	runtime.topics.unlock(&"closed_topic")
	runtime.topics.unlock(&"cooling_topic")
	runtime.topics.unlock(&"sealed_topic")
	runtime.topics.unlock(&"other_topic")
	var config := WyrdConfig.new()
	config.secrecy_tiers = PackedStringArray(["open", "sealed"])
	runtime.configure(config)
	runtime.facts.set(&"player.clearance", &"open")
	assert_true(runtime.can_save())
	var listed := runtime.dialogue.open("ada")
	assert_eq(listed, PackedStringArray(["a_topic", "b_topic", "cooling_topic"]))
	assert_eq(runtime.storylets.seen_of("topic.a"), 0)
	assert_eq(runtime.storylets.seen_of("topic.b"), 0)
	assert_true(runtime.can_save())
	assert_false(runtime.dialogue.is_open())
	runtime.director.query("topic", "cooling_topic", "ada")
	assert_eq(runtime.dialogue.open("ada"), PackedStringArray(["a_topic", "b_topic"]))
	assert_eq(runtime.dialogue.open("ghost"), PackedStringArray())
	assert_error("WyrdSceneRunner.open: unknown npc \"ghost\"")
	assert_eq(runtime.dialogue.open(""), PackedStringArray())
	assert_error("WyrdSceneRunner.open: unknown npc \"\"")


func test_entity_pool_keeps_raw_query() -> void:
	var opened := _boot(_PACK)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.world.add_entity(&"ada", &"person", "Ada", PackedStringArray(), true)
	runtime.roles.assign(&"keeper", &"ada")
	var pooled: Dictionary = runtime.director.query_for_entity("topic", "pool_topic", "ada")
	assert_eq(int(pooled["candidates"]), 3)
	assert_eq(str(pooled["id"]), "pool.role")
	var raw: Dictionary = runtime.director.query("topic", "pool_topic", "ada")
	assert_eq(int(raw["candidates"]), 2)
	assert_eq(str(raw["id"]), "pool.ada")
	assert_false(raw.has("reason"))


func test_ask_topic_refusals_then_a_line_and_a_scene() -> void:
	var opened := _boot(_PACK)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.world.add_entity(&"ada", &"person", "Ada", PackedStringArray(), true)
	runtime.roles.assign(&"keeper", &"ada")
	runtime.trace.enabled = true
	runtime.dialogue.topic_answered.connect(_on_answered)
	var unknown: Dictionary = runtime.dialogue.ask_topic("ghost", "line_topic")
	assert_error("WyrdSceneRunner.ask_topic: unknown npc \"ghost\"")
	assert_eq(str(unknown["reason"]), "")
	assert_eq(_kinds(runtime, "topic_ask").size(), 0)
	runtime.dialogue.open_scene("gate.hold")
	var busy: Dictionary = runtime.dialogue.ask_topic("ada", "line_topic")
	assert_warning("WyrdSceneRunner.ask_topic: a scene is open")
	assert_eq(str(busy["reason"]), "scene_open")
	assert_true(runtime.dialogue.is_open())
	runtime.dialogue.abort(&"host")
	var locked: Dictionary = runtime.dialogue.ask_topic("ada", "line_topic")
	assert_warning("WyrdSceneRunner.ask_topic: \"line_topic\" is locked")
	assert_eq(str(locked["reason"]), "locked")
	runtime.topics.unlock(&"empty_topic")
	var none: Dictionary = runtime.dialogue.ask_topic("ada", "empty_topic")
	assert_eq(str(none["reason"]), "no_storylet")
	assert_eq(str(none["id"]), "")
	var config := WyrdConfig.new()
	config.secrecy_tiers = PackedStringArray(["open", "sealed"])
	runtime.configure(config)
	runtime.facts.set(&"player.clearance", &"sealed")
	runtime.coverage.enabled = true
	runtime.topics.unlock(&"line_topic")
	var answered: Dictionary = runtime.dialogue.ask_topic("ada", "line_topic")
	assert_eq(str(answered["reason"]), "answered")
	assert_eq(str(answered["id"]), "topic.line")
	assert_eq(_answered.size(), 1)
	assert_eq(str(_answered[0]["npc"]), "ada")
	assert_eq(str(_answered[0]["topic"]), "line_topic")
	assert_eq(str(_answered[0]["id"]), "news_ada")
	assert_eq(str(_answered[0]["text"]), "Ada knows the tide.")
	assert_eq(str(_answered[0]["speaker"]), "ada")
	assert_eq(str(_answered[0]["name"]), "Ada")
	assert_true((_answered[0]["roles"] as PackedStringArray).has("keeper"))
	assert_gt(runtime.coverage.count("line", "news_ada"), 0)
	runtime.facts.set(&"player.clearance", &"open")
	var fallback: Dictionary = runtime.dialogue.ask_topic("ada", "line_topic")
	assert_eq(str(fallback["reason"]), "answered")
	assert_eq(str(_answered[1]["id"]), "news_base")
	runtime.topics.unlock(&"scene_topic")
	var scene: Dictionary = runtime.dialogue.ask_topic("ada", "scene_topic")
	assert_eq(str(scene["reason"]), "answered")
	assert_eq(str(scene["body"]), "scene")
	assert_true(runtime.dialogue.is_open())
	assert_eq(_answered.size(), 2)
	runtime.dialogue.abort(&"host")


func test_topic_traces_and_prefix() -> void:
	var opened := _boot(_PACK)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.world.add_entity(&"ada", &"person", "Ada", PackedStringArray(), true)
	runtime.roles.assign(&"keeper", &"ada")
	runtime.trace.enabled = true
	runtime.trace.clear()
	var config := WyrdConfig.new()
	config.secrecy_tiers = PackedStringArray(["open", "sealed"])
	runtime.configure(config)
	runtime.facts.set(&"player.clearance", &"open")
	runtime.topics.unlock(&"storm_rumour")
	runtime.topics.unlock(&"storm_rumour")
	runtime.topics.lock(&"storm_rumour")
	runtime.topics.lock(&"missing_topic")
	var unlocks := _kinds(runtime, "topic_unlock")
	assert_eq(unlocks.size(), 2)
	assert_eq(str(unlocks[0]["ok"]), "true")
	assert_eq(str(unlocks[0]["reason"]), "unlocked")
	assert_eq(str(unlocks[0]["key"]), "storm_rumour")
	assert_eq(str(unlocks[1]["reason"]), "already")
	assert_eq(str(unlocks[1]["ok"]), "false")
	var locks := _kinds(runtime, "topic_lock")
	assert_eq(str(locks[0]["reason"]), "locked")
	assert_eq(str(locks[0]["ok"]), "true")
	assert_eq(str(locks[1]["reason"]), "not_unlocked")
	assert_eq(str(locks[1]["ok"]), "false")
	runtime.trace.prefix = "nope"
	runtime.trace.clear()
	runtime.topics.unlock(&"storm_rumour")
	assert_eq(_kinds(runtime, "topic_unlock").size(), 0)
	runtime.trace.prefix = "storm"
	runtime.topics.unlock(&"other_topic")
	runtime.topics.lock(&"storm_rumour")
	runtime.topics.unlock(&"storm_rumour")
	assert_eq(_kinds(runtime, "topic_unlock").size(), 1)
	assert_eq(_kinds(runtime, "topic_lock").size(), 1)
	runtime.trace.prefix = ""
	runtime.trace.clear()
	runtime.topics.unlock(&"line_topic")
	runtime.dialogue.open("ada")
	var opened_rows := _kinds(runtime, "topic_open")
	assert_eq(opened_rows.size(), 1)
	assert_eq(str(opened_rows[0]["speaker"]), "ada")
	runtime.dialogue.ask_topic("ada", "line_topic")
	var asked := _kinds(runtime, "topic_ask")
	assert_eq(asked.size(), 1)
	assert_eq(str(asked[0]["speaker"]), "ada")
	assert_eq(str(asked[0]["key"]), "line_topic")
	assert_eq(str(asked[0]["scope"]), "topic.line")
	assert_eq(str(asked[0]["ok"]), "true")
	assert_eq(str(asked[0]["reason"]), "answered")
	runtime.trace.prefix = "ada"
	runtime.trace.clear()
	runtime.dialogue.open("ada")
	runtime.dialogue.ask_topic("ada", "missing_topic")
	assert_eq(_kinds(runtime, "topic_open").size(), 1)
	assert_eq(_kinds(runtime, "topic_ask").size(), 1)
	runtime.trace.prefix = "line_topic"
	runtime.trace.clear()
	runtime.dialogue.ask_topic("ada", "line_topic")
	assert_eq(_kinds(runtime, "topic_ask").size(), 1)
	runtime.trace.prefix = "topic.line"
	runtime.trace.clear()
	runtime.dialogue.ask_topic("ada", "line_topic")
	assert_eq(_kinds(runtime, "topic_ask").size(), 1)


func test_save_keeps_topics_and_drops_an_empty_bag() -> void:
	var runtime: WyrdRuntime = _boot(_PACK)["runtime"]
	assert_false(runtime.save_state().has("topics"))
	runtime.topics.unlock(&"b_topic")
	runtime.topics.unlock(&"a_topic")
	var saved: Dictionary = runtime.save_state()
	assert_eq(saved["topics"], ["a_topic", "b_topic"])
	var reopened := _boot(_PACK)
	var fresh: WyrdRuntime = reopened["runtime"]
	var host: WyrdFakeHost = reopened["host"]
	host.world.add_entity(&"ada", &"person", "Ada", PackedStringArray(), true)
	fresh.topics.unlock(&"keep_me")
	assert_true(fresh.load_state(saved).ok)
	assert_eq(fresh.topics.unlocked(), PackedStringArray(["a_topic", "b_topic"]))
	assert_false(fresh.topics.is_unlocked(&"keep_me"))
	var again := fresh.save_state()
	assert_eq(again["topics"], saved["topics"])
	saved.erase("topics")
	fresh.topics.unlock(&"keep_me")
	assert_true(fresh.load_state(saved).ok)
	assert_eq(fresh.topics.unlocked(), PackedStringArray())
	var unknown := fresh.save_state()
	unknown["topics"] = ["ghost.topic"]
	assert_true(fresh.load_state(unknown).ok)
	assert_true(fresh.topics.is_unlocked(&"ghost.topic"))
	assert_eq(fresh.dialogue.open("ada"), PackedStringArray())


func test_schema_2_fixture_still_loads() -> void:
	var text := FileAccess.get_file_as_string("res://tests/fixtures/schema2_harbor.json")
	var parsed: Variant = JSON.parse_string(text)
	var opened := _Harness.new().open_pack(_Harness.HARBOR)
	var runtime: WyrdRuntime = opened["runtime"]
	var report := runtime.load_state(parsed)
	assert_true(report.ok, report.diagnostics.format())
	assert_false(report.diagnostics.has_warnings(), report.diagnostics.format())
	assert_eq(runtime.topics.unlocked(), PackedStringArray())


func _on_unlocked(topic: StringName) -> void:
	_unlocked.append(String(topic))


func _on_locked(topic: StringName) -> void:
	_locked.append(String(topic))


func _on_answered(npc: StringName, topic: StringName, line: WyrdLineView) -> void:
	_answered.append({
		"id": line.id,
		"name": line.display_name,
		"npc": String(npc),
		"roles": line.roles.duplicate(),
		"speaker": String(line.speaker),
		"text": line.text,
		"topic": String(topic),
	})


func _kinds(runtime: WyrdRuntime, kind: String) -> Array:
	var found: Array = []
	for item in runtime.trace.events:
		if item is Dictionary and str((item as Dictionary).get("kind", "")) == kind:
			found.append(item)
	return found


func _boot(body: String) -> Dictionary:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var path := "user://wyrd_topics_%d.wyrd" % body.hash()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(body.strip_edges() + "\n")
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(5)
	return {"host": host, "runtime": runtime}


func assert_error(message: String) -> void:
	assert_push_error(message)


func assert_warning(message: String) -> void:
	assert_push_warning(message)


const _PACK := """
language 1

facts
  player.clearance : symbol stored

role keeper
  succession: none
  vacancy: hold

storylet topic.a
  scope: topic a_topic
  speaker: any
  - Alpha. #line:a_line

storylet topic.b
  scope: topic b_topic
  speaker: ada
  - Beta. #line:b_line

storylet topic.closed
  scope: topic closed_topic
  speaker: any
  when: false
  - Closed. #line:closed_line

storylet topic.cooling
  scope: topic cooling_topic
  speaker: any
  cooldown: 60m
  - Cooling. #line:cool_line

storylet topic.sealed
  scope: topic sealed_topic
  speaker: any
  secrecy: sealed
  - Sealed. #line:sealed_line

storylet topic.other
  scope: topic other_topic
  speaker: bea
  - Other. #line:other_line

storylet pool.ada
  scope: topic pool_topic
  speaker: ada
  priority: 1
  - From Ada. #line:pool_ada

storylet pool.role
  scope: topic pool_topic
  speaker: keeper
  priority: 5
  - From the keeper. #line:pool_role

storylet pool.any
  scope: topic pool_topic
  speaker: any
  - From anyone. #line:pool_any

storylet topic.line
  scope: topic line_topic
  speaker: any
  - The {holder(keeper)|variants} knows the tide. #line:news_base
    variant ada: Ada knows the tide. #secrecy:sealed #line:news_ada

storylet topic.scene
  scope: topic scene_topic
  speaker: any
  -> scene gate.entered

scene gate.hold
  narrator: Wait. #line:hold_line

scene gate.entered
  narrator: The gate is open. #line:entered_line
  -> end
"""
