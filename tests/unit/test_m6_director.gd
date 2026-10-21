extends GutTest


func test_tavern_query_falls_back_until_the_when_is_true_and_the_cooldown_lifts() -> void:
	var left := _boot(_TRIO, 5)
	var right := _boot(_TRIO, 5)
	assert_eq(left.condition_count(), 0)
	var cold := left.director.query("topic", "rumor.ferry_toll", "tavern")
	assert_eq(str(cold["id"]), "harbor_gossip.generic")
	assert_eq(str(cold["line_id"]), "sg01")
	assert_eq(int(cold["candidates"]), 1)
	assert_eq(str(cold["score"]), "0/0/1/0")
	_arm(left)
	_arm(right)
	var first := left.director.query("topic", "rumor.ferry_toll", "tavern")
	var same := right.director.query("topic", "rumor.ferry_toll", "tavern")
	assert_eq(str(first["id"]), "harbor_gossip.tavern")
	assert_eq(str(first["line_id"]), str(same["line_id"]))
	assert_true(str(first["line_id"]) == "sg02" or str(first["line_id"]) == "sg03")
	assert_eq(int(first["candidates"]), 2)
	assert_eq(str(first["score"]), "0/2/2/0")
	var cooling := left.director.query("topic", "rumor.ferry_toll", "tavern")
	assert_eq(str(cooling["id"]), "harbor_gossip.generic")
	assert_eq(int(cooling["candidates"]), 1)
	left.tick(59)
	assert_eq(str(left.director.query("topic", "rumor.ferry_toll", "tavern")["id"]), "harbor_gossip.generic")
	left.tick(1)
	var again := left.director.query("topic", "rumor.ferry_toll", "tavern")
	assert_eq(str(again["id"]), "harbor_gossip.tavern")
	assert_ne(str(again["line_id"]), str(first["line_id"]))
	assert_true(str(again["line_id"]) == "sg02" or str(again["line_id"]) == "sg03")
	assert_eq(left.condition_count(), 0)


func test_speaker_any_is_a_wildcard_and_any_other_spelling_is_not() -> void:
	var ferry := _boot(_TRIO, 5)
	_arm(ferry)
	var from_ferry := ferry.director.query("topic", "rumor.ferry_toll", "ferry")
	assert_eq(str(from_ferry["id"]), "harbor_gossip.generic")
	assert_eq(int(from_ferry["candidates"]), 1)
	var spelled := _boot(_TRIO, 5)
	_arm(spelled)
	assert_eq(str(spelled.director.query("topic", "rumor.ferry_toll", "Any")["id"]), "harbor_gossip.generic")
	var open := _boot(_TRIO, 5)
	_arm(open)
	assert_eq(str(open.director.query("topic", "rumor.ferry_toll", "")["id"]), "harbor_gossip.tavern")
	var wild := _boot(_TRIO, 5)
	_arm(wild)
	assert_eq(str(wild.director.query("topic", "rumor.ferry_toll", "any")["id"]), "harbor_gossip.tavern")
	var other_seed := _boot(_TRIO, 9)
	assert_eq(str(other_seed.director.query("topic", "rumor.ferry_toll", "tavern")["id"]), "harbor_gossip.generic")


func test_priority_beats_specificity_then_weight_then_recency() -> void:
	var runtime := _boot(_RANK, 5)
	var loud := runtime.director.query("topic", "rumor.ferry_toll", "tavern")
	assert_eq(str(loud["id"]), "harbor.loud")
	assert_eq(str(loud["score"]), "5/0/1/0")
	assert_eq(int(loud["candidates"]), 2)
	var still := runtime.director.query("topic", "rumor.ferry_toll", "tavern")
	assert_eq(str(still["id"]), "harbor.loud")
	assert_eq(str(still["score"]), "5/0/1/1")
	var weighted := _boot(_WEIGHT, 5)
	assert_eq(str(weighted.director.query("topic", "rumor.ferry_toll", "ferry")["id"]), "harbor.heavy")
	var quiet := _boot(_QUIET, 5)
	assert_eq(str(quiet.director.query("topic", "rumor.ferry_toll", "ferry")["id"]), "harbor.plain")
	var recent := _boot(_PAIR, 5)
	recent.storylets.import_state({
		"harbor.pair_east": {"seen": 2, "last_minute": 0},
	})
	assert_eq(str(recent.director.query("topic", "rumor.pair", "ferry")["id"]), "harbor.pair_west")
	var older := _boot(_PAIR, 5)
	older.storylets.import_state({
		"harbor.pair_east": {"seen": 1, "last_minute": 10},
		"harbor.pair_west": {"seen": 1, "last_minute": 4},
	})
	assert_eq(str(older.director.query("topic", "rumor.pair", "ferry")["id"]), "harbor.pair_west")
	var cooling := _boot(_COOL, 5)
	cooling.storylets.import_state({
		"harbor.cool_east": {"seen": 1, "last_minute": 0},
		"harbor.cool_west": {"seen": 1, "last_minute": 0},
	})
	var missed := cooling.director.query("topic", "rumor.pair", "ferry")
	assert_eq(str(missed["id"]), "")
	assert_eq(int(missed["candidates"]), 0)
	assert_eq(int(cooling.save_state()["storylets"]["harbor.cool_east"]["seen"]), 1)
	cooling.tick(10)
	assert_ne(str(cooling.director.query("topic", "rumor.pair", "ferry")["id"]), "")


func test_seeded_tie_save_load_and_new_game() -> void:
	var expected := _tied(5, 0)
	var left := _boot(_PAIR, 5)
	var right := _boot(_PAIR, 5)
	var first := left.director.query("topic", "rumor.pair", "ferry")
	assert_eq(str(first["id"]), expected)
	assert_eq(str(right.director.query("topic", "rumor.pair", "ferry")["id"]), expected)
	assert_eq(str(_boot(_PAIR, 5).director.query("topic", "rumor.pair", "ferry")["id"]), expected)
	var later := _boot(_PAIR, 5)
	later.tick(100)
	assert_eq(str(later.director.query("topic", "rumor.pair", "ferry")["id"]), _tied(5, 100))
	var saved := left.save_state()
	assert_eq(int(saved["schema_version"]), 4)
	assert_true(saved.has("storylets"))
	var parsed: Variant = JSON.parse_string(JSON.stringify(saved))
	assert_true(parsed is Dictionary)
	var loaded := _boot(_PAIR, 5)
	var report := loaded.load_state(parsed)
	assert_true(report.ok, report.diagnostics.format())
	var from_json := loaded.director.query("topic", "rumor.pair", "ferry")
	var continued := left.director.query("topic", "rumor.pair", "ferry")
	assert_eq(str(from_json["id"]), str(continued["id"]))
	assert_ne(str(from_json["id"]), str(first["id"]))
	var direct := _boot(_PAIR, 5)
	assert_true(direct.load_state(saved).ok)
	assert_eq(str(direct.director.query("topic", "rumor.pair", "ferry")["id"]), str(from_json["id"]))
	left.start_new_game(5)
	assert_false(left.save_state().has("storylets"))
	assert_eq(str(left.director.query("topic", "rumor.pair", "ferry")["id"]), expected)
	var fresh := _boot(_PAIR, 5)
	left.director.query("topic", "rumor.pair", "ferry")
	assert_true(left.load_state(fresh.save_state()).ok)
	assert_false(left.save_state().has("storylets"))


func test_scope_filters_scene_body_and_the_director_trace() -> void:
	var runtime := _boot(_SCOPES, 5)
	assert_eq(runtime.condition_count(), 0)
	var bark := runtime.director.query("bark", "", "ferry")
	assert_eq(str(bark["id"]), "harbor.bark_plain")
	assert_eq(str(bark["line_id"]), "bark1")
	var topic := runtime.director.query("topic", "rumor.ferry_toll", "ferry")
	assert_eq(str(topic["id"]), "harbor.topic_plain")
	var poured := runtime.director.query("event", "bucket_poured", "ferry")
	assert_eq(str(poured["line_id"]), "pour1")
	var beat := runtime.director.query("beat", "ferry_toll.offer", "tavern")
	assert_eq(str(beat["line_id"]), "beat1")
	var scene := runtime.director.query("bark", "", "tavern")
	assert_eq(str(scene["id"]), "harbor.room")
	assert_eq(str(scene["body"]), "scene")
	assert_eq(str(scene["scene"]), "toll.offer_room")
	assert_eq(str(scene["line_id"]), "")
	var row: Dictionary = runtime.save_state()["storylets"]["harbor.room"]
	assert_eq(int(row["seen"]), 1)
	assert_eq(int(row["last_minute"]), 0)
	assert_false(row.has("order"))
	runtime.trace.enabled = true
	var picked := runtime.director.query("topic", "rumor.ferry_toll", "ferry")
	var found := false
	for item in runtime.trace.snapshot():
		if str(item["kind"]) != "director":
			continue
		found = true
		assert_eq(str(item["scope"]), "topic rumor.ferry_toll")
		assert_eq(str(item["speaker"]), "ferry")
		assert_eq(str(item["winner"]), str(picked["id"]))
		assert_eq(int(item["candidates"]), int(picked["candidates"]))
		assert_eq(str(item["score"]), str(picked["score"]))
		assert_eq(str(item["key"]), "rumor.ferry_toll")
	assert_true(found)
	runtime.trace.clear()
	runtime.trace.prefix = "tavern"
	runtime.director.query("beat", "ferry_toll.offer", "tavern")
	assert_eq(_director_rows(runtime).size(), 1)
	runtime.trace.clear()
	runtime.trace.prefix = "no-such"
	var hidden := runtime.director.query("topic", "rumor.ferry_toll", "ferry")
	assert_eq(str(hidden["id"]), "harbor.topic_plain")
	assert_eq(_director_rows(runtime).size(), 0)
	var bare := WyrdRuntime.new()
	assert_eq(str(bare.director.query("topic", "rumor.ferry_toll", "tavern")["id"]), "")
	assert_push_error("load content")
	assert_eq(str(runtime.director.query("lane", "rumor.ferry_toll", "ferry")["id"]), "")
	assert_push_error("unknown scope")


func test_draw_does_not_record_a_selection_and_chance_uses_the_storylet() -> void:
	var runtime := _boot(_LINE, 5)
	runtime.storylets.draw("harbor_gossip.generic")
	assert_false(runtime.save_state().has("storylets"))
	var picked := runtime.director.query("topic", "rumor.ferry_toll", "tavern")
	assert_eq(str(picked["line_id"]), "sg01")
	var row: Dictionary = runtime.save_state()["storylets"]["harbor_gossip.generic"]
	assert_eq(int(row["seen"]), 1)
	assert_eq(int(row["last_minute"]), 0)
	assert_false(row.has("order"))
	runtime.director.query("topic", "rumor.ferry_toll", "tavern")
	assert_eq(int(runtime.save_state()["storylets"]["harbor_gossip.generic"]["seen"]), 2)
	var chance := _boot(_CHANCE, 5)
	assert_eq(chance.condition_count(), 0)
	chance.trace.enabled = true
	var won := chance.director.query("topic", "rumor.ferry_toll", "ferry")
	assert_eq(str(won["id"]), "harbor.always")
	assert_eq(str(won["score"]), "1/1/1/0")
	var rolled := false
	for item in chance.trace.snapshot():
		if str(item.get("kind", "")) == "roll" and str(item.get("key", "")) == "harbor.coin:when":
			rolled = true
	assert_true(rolled)


func _tied(seed_value: int, minute: int) -> String:
	var names := ["harbor.pair_east", "harbor.pair_west"]
	names.sort()
	var rng := WyrdRng.for_decision(seed_value, &"storylet_director", StringName("topic rumor.pair\tferry"), minute)
	return str(names[rng.randi_bounded(names.size())])


func _arm(runtime: WyrdRuntime) -> void:
	runtime.facts.set(&"world.season", &"autumn")
	runtime.facts.set_in(&"harbor.toll_fate", &"stolen", &"known/player")


func _director_rows(runtime: WyrdRuntime) -> Array:
	var rows: Array = []
	for item in runtime.trace.snapshot():
		if str(item["kind"]) == "director":
			rows.append(item)
	return rows


func _boot(body: String, seed_value: int) -> WyrdRuntime:
	var compiled := _compile(body)
	var diagnostics: WyrdDiagnostics = compiled["diagnostics"]
	assert_false(diagnostics.has_errors(), diagnostics.format())
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
	return runtime


func _compile(body: String) -> Dictionary:
	var path := _write("user://wyrd_m6_director_%d.wyrd" % body.hash(), body)
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


const _TRIO := """
language 1
facts
  harbor.toll_fate : symbol stored
  world.season : symbol stored
storylet harbor_gossip.generic
  scope: topic rumor.ferry_toll
  speaker: any
  - They say the ferry's dear since the storm. #line:sg01
storylet harbor_gossip.tavern
  scope: topic rumor.ferry_toll
  speaker: tavern
  when: knows(player, harbor.toll_fate) and world.season == autumn
  weight: 2
  cooldown: 60m
  lines:
    - The toll money never reached the council, if you ask me. #line:sg02
    - Lost at sea, they say. Lost in someone's pocket. #line:sg03
"""


const _RANK := """
language 1
storylet harbor.specific
  scope: topic rumor.ferry_toll
  speaker: tavern
  when: true
  weight: 9
  - The specific line. #line:sp1
storylet harbor.loud
  scope: topic rumor.ferry_toll
  speaker: any
  priority: 5
  - The loud line. #line:loud1
"""


const _WEIGHT := """
language 1
storylet harbor.heavy
  scope: topic rumor.ferry_toll
  speaker: ferry
  when: true
  weight: 4
  - The heavy line. #line:heavy1
storylet harbor.light
  scope: topic rumor.ferry_toll
  speaker: ferry
  when: true
  weight: 1
  - The light line. #line:light1
"""


const _QUIET := """
language 1
storylet harbor.quiet
  scope: topic rumor.ferry_toll
  speaker: ferry
  when: true
  priority: -2
  - The quiet line. #line:quiet1
storylet harbor.plain
  scope: topic rumor.ferry_toll
  speaker: any
  - The plain line. #line:plain1
"""


const _PAIR := """
language 1
storylet harbor.pair_east
  scope: topic rumor.pair
  speaker: any
  - East of the ferry. #line:east
storylet harbor.pair_west
  scope: topic rumor.pair
  speaker: any
  - West of the ferry. #line:west
"""


const _COOL := """
language 1
storylet harbor.cool_east
  scope: topic rumor.pair
  speaker: any
  cooldown: 10m
  - East again. #line:ceast
storylet harbor.cool_west
  scope: topic rumor.pair
  speaker: any
  cooldown: 10m
  - West again. #line:cwest
"""


const _SCOPES := """
language 1
events
  bucket_poured()
scene toll.offer_room
  narrator: The room. #line:room1
  -> end
storylet harbor.bark_plain
  scope: bark
  speaker: ferry
  - Mind the ropes. #line:bark1
storylet harbor.topic_plain
  scope: topic rumor.ferry_toll
  speaker: ferry
  - The toll again. #line:topic1
storylet harbor.pour
  scope: event bucket_poured
  speaker: ferry
  - The bucket. #line:pour1
storylet harbor.beat_line
  scope: beat ferry_toll.offer
  speaker: tavern
  - The offer. #line:beat1
storylet harbor.room
  scope: bark
  speaker: tavern
  -> scene toll.offer_room
"""


const _LINE := """
language 1
storylet harbor_gossip.generic
  scope: topic rumor.ferry_toll
  speaker: any
  - They say the ferry's dear since the storm. #line:sg01
"""


const _CHANCE := """
language 1
storylet harbor.always
  scope: topic rumor.ferry_toll
  speaker: any
  when: chance(1)
  priority: 1
  - Always. #line:always1
storylet harbor.coin
  scope: topic rumor.ferry_toll
  speaker: any
  when: chance(0.5)
  - Maybe. #line:coin1
storylet harbor.never
  scope: topic rumor.ferry_toll
  speaker: any
  when: chance(0)
  - Never. #line:never1
storylet harbor_gossip.generic
  scope: topic rumor.ferry_toll
  speaker: any
  - They say the ferry's dear since the storm. #line:sg01
"""
