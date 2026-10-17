extends GutTest

const _Facade := preload("res://addons/wyrd/runtime/wyrd.gd")
const _HARBOR := "res://example/content/gullhaven/harbor.wyrdmanifest.tres"
const _Election := preload("res://example/playtest/harbor_election.gd")


func test_adapters_answer_nearby_reach_and_carried_items() -> void:
	var opened := _open(_ADAPTERS, 5)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	assert_eq(runtime.condition_count(), 0)
	assert_eq(str(runtime.director.query("bark", "", "ferry")["id"]), "")
	host.spatial.set_nearby(&"player", 4.0, &"lantern", PackedStringArray([&"post"]))
	host.spatial.set_can_perceive(&"player", &"ferry", true)
	host.spatial.set_can_reach(&"player", &"dock", true)
	host.inventory.set_count(&"player", &"lantern", 2)
	var won := runtime.director.query("bark", "", "ferry")
	assert_eq(str(won["id"]), "harbor.full")
	assert_eq(str(won["line_id"]), "full1")
	host.spatial.set_can_perceive(&"player", &"ferry", false)
	assert_eq(str(runtime.director.query("bark", "", "ferry")["id"]), "")
	var bare := _bare(_ADAPTERS)
	assert_eq(str(bare.director.query("bark", "", "ferry")["id"]), "")


func test_carried_lantern_outranks_the_nearby_bark_and_cools_the_speaker() -> void:
	var runtime := _harbor()
	var host: WyrdFakeHost = runtime.get_meta("host")
	host.spatial.set_nearby(&"player", 4.0, &"lantern", PackedStringArray([&"post"]))
	var near := runtime.director.query("bark", "", "ferry")
	assert_eq(str(near["id"]), "dock_bark_lantern")
	assert_eq(str(near["line_id"]), "sg04")
	host.inventory.set_count(&"player", &"lantern", 1)
	var carried := runtime.director.query("bark", "", "ferry")
	assert_eq(str(carried["id"]), "dock_bark_lantern_carried")
	assert_eq(str(carried["line_id"]), "sg05")
	assert_eq(int(carried["specificity"]), 2)
	var blocked := runtime.director.why_not("dock_bark_lantern_carried", "bark", "", "ferry")
	assert_eq(str(blocked["reason"]), "cooldown")
	assert_eq(int(blocked["cooldown"]), 10)
	assert_eq(int(blocked["remaining"]), 10)
	assert_false(bool(blocked["eligible"]))
	assert_eq(str(runtime.director.query("bark", "", "ferry")["id"]), "")
	var gossip := runtime.director.query("topic", "rumor.ferry_toll", "ferry")
	assert_eq(str(gossip["id"]), "harbor_gossip.generic")
	runtime.tick(4)
	var later := runtime.director.why_not("dock_bark_lantern_carried", "bark", "", "ferry")
	assert_eq(str(later["reason"]), "cooldown")
	assert_eq(int(later["cooldown"]), 10)
	assert_eq(int(later["remaining"]), 6)
	var lantern_later := runtime.director.why_not("dock_bark_lantern", "bark", "", "ferry")
	assert_eq(str(lantern_later["reason"]), "cooldown")
	assert_eq(int(lantern_later["cooldown"]), 30)
	assert_eq(int(lantern_later["remaining"]), 26)
	runtime.tick(6)
	var again := runtime.director.query("bark", "", "ferry")
	assert_eq(str(again["id"]), "dock_bark_lantern_carried")


func test_speaker_clock_save_load_and_a_wildcard_does_not_start_one() -> void:
	var opened := _open(_CLOCK, 5)
	var runtime: WyrdRuntime = opened["runtime"]
	var first := runtime.director.query("bark", "", "ferry")
	assert_eq(str(first["id"]), "harbor.ferry")
	assert_eq(str(runtime.director.query("bark", "", "ferry")["id"]), "")
	var topic := runtime.director.query("topic", "rumor.ferry_toll", "ferry")
	assert_eq(str(topic["id"]), "harbor.topic")
	var saved := runtime.save_state()
	assert_eq(int(saved["schema_version"]), 3)
	assert_eq(int(saved["bark_speakers"]["ferry"]["cooldown"]), 10)
	assert_eq(int(saved["bark_speakers"]["ferry"]["last_minute"]), 0)
	assert_eq(int(saved["storylets"]["harbor.ferry"]["seen"]), 1)
	saved["bark_speakers"]["no_such"] = {"cooldown": 5, "last_minute": 1}
	saved["bark_speakers"]["bad"] = 1
	var parsed: Variant = JSON.parse_string(JSON.stringify(saved))
	assert_true(parsed is Dictionary)
	var loaded := _open(_CLOCK, 5)
	var loaded_runtime: WyrdRuntime = loaded["runtime"]
	var report := loaded_runtime.load_state(parsed)
	assert_true(report.ok, report.diagnostics.format())
	var from_json: Dictionary = loaded_runtime.save_state()
	assert_true(from_json["bark_speakers"].has("ferry"))
	assert_true(from_json["bark_speakers"].has("no_such"))
	assert_false(from_json["bark_speakers"].has("bad"))
	assert_eq(str(loaded_runtime.director.query("bark", "", "ferry")["id"]), "")
	var stripped: Dictionary = (parsed as Dictionary).duplicate(true)
	stripped.erase("bark_speakers")
	var cleared := _open(_CLOCK, 5)
	var cleared_runtime: WyrdRuntime = cleared["runtime"]
	assert_true(cleared_runtime.load_state(stripped).ok)
	assert_false(cleared_runtime.save_state().has("bark_speakers"))
	assert_eq(int(cleared_runtime.save_state()["storylets"]["harbor.ferry"]["seen"]), 1)
	assert_eq(str(cleared_runtime.director.query("bark", "", "ferry")["id"]), "harbor.ferry")
	runtime.start_new_game(5)
	assert_false(runtime.save_state().has("bark_speakers"))
	assert_false(runtime.save_state().has("storylets"))
	var wild := _open(_WILD, 5)
	var wild_runtime: WyrdRuntime = wild["runtime"]
	assert_eq(str(wild_runtime.director.query("bark", "", "any")["id"]), "harbor.open")
	assert_eq(str(wild_runtime.director.query("bark", "", "any")["id"]), "harbor.open")
	assert_false(wild_runtime.save_state().has("bark_speakers"))
	var named := _open(_CLOCK, 3)
	var named_runtime: WyrdRuntime = named["runtime"]
	assert_eq(str(named_runtime.director.query("bark", "", "any")["id"]), "harbor.ferry")
	assert_true(named_runtime.save_state()["bark_speakers"].has("ferry"))
	assert_eq(str(named_runtime.director.query("bark", "", "ferry")["id"]), "")


func test_bark_ready_carries_the_holder_roles_and_audio() -> void:
	var opened := _open(_ROLE, 5)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.world.add_entity(&"dock_hand", &"person", "Dock Hand", PackedStringArray(), true)
	runtime.roles.define(&"ferry_master")
	runtime.roles.define(&"harbor_watch")
	runtime.roles.assign(&"ferry_master", &"dock_hand")
	runtime.roles.assign(&"harbor_watch", &"dock_hand")
	runtime.dialogue.register_line_audio(func(line_id: String, _locale: String) -> Variant:
		if line_id == "role1":
			return "clip"
		return null
	)
	var heard: Array = []
	runtime.bark_ready.connect(func(line: WyrdLineView) -> void:
		heard.append(line)
	)
	var won := runtime.director.query("bark", "", "ferry_master")
	assert_eq(str(won["line_id"]), "role1")
	assert_eq(heard.size(), 1)
	var view: WyrdLineView = heard[0]
	assert_eq(String(view.speaker), "dock_hand")
	assert_eq(view.display_name, "Dock Hand")
	assert_eq(view.roles, PackedStringArray(["ferry_master", "harbor_watch"]))
	assert_eq(view.text, "Mind the lantern.")
	assert_eq(view.audio, "clip")
	var scene_heard: Array = []
	var scene_opened := _open(_SCENE, 5)
	var scene_runtime: WyrdRuntime = scene_opened["runtime"]
	scene_runtime.bark_ready.connect(func(line: WyrdLineView) -> void:
		scene_heard.append(line)
	)
	var scene_won := scene_runtime.director.query("bark", "", "ferry")
	assert_eq(str(scene_won["body"]), "scene")
	assert_eq(str(scene_won["line_id"]), "")
	assert_eq(scene_heard.size(), 1)
	var empty: WyrdLineView = scene_heard[0]
	assert_eq(empty.id, "")
	assert_eq(empty.text, "")
	assert_eq(String(empty.speaker), "ferry")
	var node = _Facade.new()
	var relayed: Array = []
	node.bark_ready.connect(func(line: WyrdLineView) -> void:
		relayed.append(line)
	)
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([_write("user://wyrd_m6_barks_facade.wyrd", _SCENE)])
	assert_true(node.load_content(manifest).ok)
	node.start_new_game(5)
	assert_eq(str(node.director.query("bark", "", "ferry")["id"]), "harbor.scene_bark")
	assert_eq(relayed.size(), 1)
	node.free()


func test_spatial_waits_wake_on_the_declared_event() -> void:
	var opened := _open(_WATCH, 5)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	assert_eq(host.spatial.nearby_calls, 0)
	runtime.tick(0)
	var after_first := host.spatial.nearby_calls
	assert_gt(after_first, 0)
	runtime.tick(1)
	runtime.tick(5)
	assert_eq(host.spatial.nearby_calls, after_first)
	runtime.events.emit(&"season_changed", {})
	assert_eq(host.spatial.nearby_calls, after_first)
	runtime.events.emit(&"entered_area", {})
	assert_gt(host.spatial.nearby_calls, after_first)
	var after_emit := host.spatial.nearby_calls
	runtime.tick(1)
	assert_eq(host.spatial.nearby_calls, after_emit)


func test_spatial_context_and_speaker_cooldown_diagnostics() -> void:
	var bare := _compile(_WAIT_BARE)
	assert_true(bare["diagnostics"].format().contains("error[E_SPATIAL_CONTEXT]"))
	assert_true(bare["diagnostics"].format().contains("needs an on <event> handler"))
	var started := _compile(_START)
	assert_true(started["diagnostics"].format().contains("nearby is not allowed in a wait, trigger, or eligibility condition"))
	var cast := _compile(_CAST)
	assert_true(cast["diagnostics"].format().contains("error[E_SPATIAL_CONTEXT]"))
	var ordinary := _compile(_TRANSITION)
	assert_true(ordinary["diagnostics"].format().contains("error[E_SPATIAL_CONTEXT]"))
	var variant := _compile(_VARIANT)
	assert_true(variant["diagnostics"].format().contains("error[E_SPATIAL_CONTEXT]"))
	var allowed := _compile(_WAIT_ON)
	assert_false(allowed["diagnostics"].has_errors(), allowed["diagnostics"].format())
	var story := _compile(_ADAPTERS)
	assert_false(story["diagnostics"].has_errors(), story["diagnostics"].format())
	var negative := _compile(_NEGATIVE)
	assert_true(negative["diagnostics"].format().contains("speaker_cooldown cannot be negative"))
	var missing := _compile(_MISSING)
	assert_true(missing["diagnostics"].format().contains("speaker_cooldown needs a duration"))
	var unit := _compile(_UNIT)
	assert_true(unit["diagnostics"].format().contains("speaker_cooldown unit must be m, h, or d"))
	var packed := _compile(_CLOCK)
	assert_false(packed["diagnostics"].has_errors(), packed["diagnostics"].format())
	var found: WyrdStoryletDef = packed["pack"].units[0]["file"].storylets[0]
	var saw := false
	for item in packed["pack"].units[0]["file"].storylets:
		if item.id == "harbor.ferry":
			found = item
			saw = true
	assert_true(saw)
	assert_eq(found.speaker_cooldown_minutes, 10)
	assert_true(WyrdExport.to_json(WyrdExport.to_data(packed["pack"])).contains("\"speaker_cooldown\": 10"))


func _harbor() -> WyrdRuntime:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var manifest := load(_HARBOR) as WyrdContentManifest
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.register_adapter(WyrdElectionAdapter, _Election.new())
	runtime.start_new_game(5)
	runtime.set_meta("host", host)
	return runtime


func _bare(body: String) -> WyrdRuntime:
	var compiled := _compile(body)
	assert_false(compiled["diagnostics"].has_errors(), compiled["diagnostics"].format())
	var runtime := WyrdRuntime.new()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([str(compiled["path"])])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(5)
	return runtime


func _open(body: String, seed_value: int) -> Dictionary:
	var compiled := _compile(body)
	assert_false(compiled["diagnostics"].has_errors(), compiled["diagnostics"].format())
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([str(compiled["path"])])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(seed_value)
	return {"host": host, "runtime": runtime}


func _compile(body: String) -> Dictionary:
	var path := _write("user://wyrd_m6_barks_%d.wyrd" % body.hash(), body)
	var diagnostics := WyrdDiagnostics.new()
	var pack := WyrdPack.compile(PackedStringArray([path]), "harbor", 1, null, diagnostics, path, true)
	return {"diagnostics": diagnostics, "pack": pack, "path": path}


func _write(path: String, body: String) -> String:
	var lines := PackedStringArray()
	for line in body.strip_edges().split("\n"):
		if line.begins_with("\t\t"):
			lines.append(line.substr(2))
		else:
			lines.append(line)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	file.close()
	return path


const _ADAPTERS := """
language 1
storylet harbor.full
  scope: bark
  speaker: ferry
  when: nearby(player, 4m, tag: lantern) > 0 and can_perceive(player, ferry) and can_reach(player, dock) and has(player, lantern) and count(player, lantern) == 2
  - The lantern is in hand. #line:full1
"""


const _CLOCK := """
language 1
storylet harbor.topic
  scope: topic rumor.ferry_toll
  speaker: ferry
  - The toll again. #line:topic1
storylet harbor.ferry
  scope: bark
  speaker: ferry
  speaker_cooldown: 10m
  - Mind the ropes. #line:ferry1
"""


const _WILD := """
language 1
storylet harbor.open
  scope: bark
  speaker: any
  speaker_cooldown: 10m
  - A general shout. #line:open1
"""


const _ROLE := """
language 1
storylet harbor.role
  scope: bark
  speaker: ferry_master
  - Mind the lantern. #line:role1
"""


const _SCENE := """
language 1
scene toll.quiet
  narrator: Quiet on the dock. #line:quiet1
  -> end
storylet harbor.scene_bark
  scope: bark
  speaker: ferry
  -> scene toll.quiet
"""


const _WATCH := """
language 1
events
  entered_area()
  season_changed()
quest harbor_watch "Harbor Watch"
  start when true
  stage watch
    waits_until nearby(player, 4m, tag: lantern) > 0
    on entered_area where can_perceive(player, ferry):
"""


const _WAIT_BARE := """
language 1
quest harbor_watch "Harbor Watch"
  start when true
  stage watch
    waits_until nearby(player, 4m, tag: lantern) > 0
"""


const _START := """
language 1
quest harbor_watch "Harbor Watch"
  start when nearby(player, 4m, tag: lantern) > 0
  stage watch
    waits_until true
"""


const _CAST := """
language 1
quest harbor_watch "Harbor Watch"
  slot lookout = storm_watcher mode: cast(nearby(player, 4m, tag: lantern) > 0)
  start when true
  stage watch
    waits_until true
"""


const _TRANSITION := """
language 1
quest harbor_watch "Harbor Watch"
  start when true
  stage watch
    waits_until true
    -> next when nearby(player, 4m, tag: lantern) > 0
  stage next
    waits_until false
"""


const _VARIANT := """
language 1
quest harbor_watch "Harbor Watch"
  slot ferry = ferry_master mode: live
  start when true
  stage watch
    waits_until true
    variant ferry.unwilling(can_reach(player, dock)):
      waits_until false
"""


const _WAIT_ON := """
language 1
events
  entered_area()
quest harbor_watch "Harbor Watch"
  start when true
  stage watch
    waits_until nearby(player, 4m, tag: lantern) > 0
    on entered_area where can_perceive(player, ferry):
      -> next when can_reach(player, dock)
  stage next
    waits_until false
"""


const _NEGATIVE := """
language 1
storylet harbor.ferry
  scope: bark
  speaker: ferry
  speaker_cooldown: -1m
  - Mind the ropes. #line:ferry1
"""


const _MISSING := """
language 1
storylet harbor.ferry
  scope: bark
  speaker: ferry
  speaker_cooldown: 10
  - Mind the ropes. #line:ferry1
"""


const _UNIT := """
language 1
storylet harbor.ferry
  scope: bark
  speaker: ferry
  speaker_cooldown: 10s
  - Mind the ropes. #line:ferry1
"""
