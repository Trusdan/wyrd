extends GutTest

const _HARBOR := "example/content/gullhaven/harbor.wyrdmanifest.tres"


func test_equal_storylets_warn_once_and_weight_does_not_clear_it() -> void:
	var compiled := _compile(_WEIGHT)
	var diagnostics: WyrdDiagnostics = compiled["diagnostics"]
	assert_false(diagnostics.has_errors(), diagnostics.format())
	var lines := _tie_lines(diagnostics)
	assert_eq(lines.size(), 1, diagnostics.format())
	var heavy := _find(compiled["pack"], "harbor.heavy")
	var path := str(compiled["path"])
	assert_true(lines[0].begins_with("%s:%d:%d: warning[W_STORYLET_TIE]:" % [path, heavy.line, heavy.col]), lines[0])
	assert_true(lines[0].contains(
		"storylet \"harbor.heavy\" ties \"harbor.light\" on topic rumor.ferry_toll speaker ferry: priority 0 specificity 1 weights 4 and 1"
	), lines[0])
	var many := _compile(_THREE)
	var many_text: WyrdDiagnostics = many["diagnostics"]
	assert_false(many_text.has_errors(), many_text.format())
	var pairs := _tie_lines(many_text)
	assert_eq(pairs.size(), 3, many_text.format())
	assert_true(many_text.format().contains("storylet \"harbor.two\" ties \"harbor.one\""))
	assert_true(many_text.format().contains("storylet \"harbor.three\" ties \"harbor.one\""))
	assert_true(many_text.format().contains("storylet \"harbor.three\" ties \"harbor.two\""))
	assert_eq(_tie_lines(_compile(_TRIO)["diagnostics"]).size(), 0)


func test_exclusion_speakers_and_scopes_skip_the_warning() -> void:
	_quiet(_SEASON)
	_quiet(_KNOWS)
	_quiet(_NOT_SEASON)
	_quiet(_FALSE)
	_quiet(_SPEAKERS)
	_quiet(_TOPICS)
	_quiet(_KIND)
	_quiet(_PRIORITY)
	_quiet(_SPECIFICITY)
	_quiet(_BEATS)
	_quiet(_EVENTS)
	_quiet(_SPELLED)
	var any_line := _one(_ANY)
	assert_true(any_line.contains("speaker any/tavern"), any_line)
	assert_true(any_line.contains("on topic rumor.ferry_toll"), any_line)
	var knows := _one(_KNOWS_SEASON)
	assert_true(knows.contains("storylet \"harbor.season\" ties \"harbor.knows\""), knows)
	var either := _one(_OR)
	assert_true(either.contains("warning[W_STORYLET_TIE]"), either)
	var grouped := _one(_NOT_AND)
	assert_true(grouped.contains("warning[W_STORYLET_TIE]"), grouped)
	var chance := _one(_CHANCE)
	assert_true(chance.contains("warning[W_STORYLET_TIE]"), chance)
	var bark := _one(_BARKS)
	assert_true(bark.contains("on bark speaker ferry"), bark)
	var beat := _one(_BEAT_PAIR)
	assert_true(beat.contains("on beat ferry_toll.offer speaker tavern"), beat)
	var poured := _one(_EVENT_PAIR)
	assert_true(poured.contains("on event bucket_poured speaker ferry"), poured)
	var duplicate := _compile(_DUPLICATE)
	var duplicate_text: WyrdDiagnostics = duplicate["diagnostics"]
	assert_true(duplicate_text.format().contains("error[E_STORYLET_DUPLICATE]"), duplicate_text.format())
	assert_eq(_tie_lines(duplicate_text).size(), 0, duplicate_text.format())


func test_cross_file_tie_is_reported_on_the_later_file() -> void:
	var earlier := _write("user://wyrd_m6_tie_a.wyrd", """
language 1
storylet harbor.zeta
  scope: topic rumor.ferry_toll
  speaker: any
  - East of the ferry. #line:east1
""")
	var later := _write("user://wyrd_m6_tie_b.wyrd", """
language 1
storylet harbor.alpha
  scope: topic rumor.ferry_toll
  speaker: any
  - West of the ferry. #line:west1
""")
	var diagnostics := WyrdDiagnostics.new()
	var pack := WyrdPack.compile(PackedStringArray([later, earlier]), "harbor", 1, null, diagnostics, earlier, true)
	assert_false(diagnostics.has_errors(), diagnostics.format())
	var lines := _tie_lines(diagnostics)
	assert_eq(lines.size(), 1, diagnostics.format())
	var alpha := _find(pack, "harbor.alpha")
	assert_true(lines[0].begins_with("%s:%d:%d: warning[W_STORYLET_TIE]:" % [later, alpha.line, alpha.col]), lines[0])
	assert_true(lines[0].contains(
		"storylet \"harbor.alpha\" ties \"harbor.zeta\" on topic rumor.ferry_toll speaker any: priority 0 specificity 0 weights 1 and 1"
	), lines[0])
	var same_id := WyrdDiagnostics.new()
	WyrdPack.compile(PackedStringArray([
		_write("user://wyrd_m6_tie_c.wyrd", """
language 1
storylet harbor.rumor
  scope: bark
  speaker: any
  - Shared. #line:sg01
"""),
		_write("user://wyrd_m6_tie_d.wyrd", """
language 1
storylet harbor.rumor
  scope: bark
  speaker: ferry
  - Again. #line:sg02
"""),
	]), "harbor", 1, null, same_id, earlier, true)
	assert_true(same_id.format().contains("error[E_STORYLET_DUPLICATE]"), same_id.format())
	assert_eq(_tie_lines(same_id).size(), 0, same_id.format())


func test_why_not_names_the_failing_clause_and_does_not_select() -> void:
	var compiled := _compile(_TRIO)
	var tavern := _find(compiled["pack"], "harbor_gossip.tavern")
	assert_eq(tavern.clause_text, PackedStringArray([
		"knows(player, harbor.toll_fate)",
		"world.season == autumn",
	]))
	var bark := _find(compiled["pack"], "dock_bark_lantern")
	assert_eq(bark.clause_text, PackedStringArray(["nearby(player, 4m, tag: lantern) > 0"]))
	assert_eq(_find(compiled["pack"], "harbor_gossip.generic").clauses.size(), 0)
	var runtime := _runtime_from(compiled)
	assert_eq(runtime.condition_count(), 0)
	var cold := runtime.director.why_not("harbor_gossip.tavern", "topic", "rumor.ferry_toll", "tavern")
	assert_eq(str(cold["reason"]), "when")
	assert_false(bool(cold["eligible"]))
	assert_eq(str(cold["clause"]), "knows(player, harbor.toll_fate)")
	assert_eq(str(cold["score"]), "0/2/2/0")
	assert_eq(int(cold["cooldown"]), 60)
	assert_eq(int(cold["remaining"]), 0)
	assert_eq(str(cold["winner"]), "")
	assert_false(runtime.save_state().has("storylets"))
	runtime.facts.set(&"world.season", &"autumn")
	var still := runtime.director.why_not("harbor_gossip.tavern", "topic", "rumor.ferry_toll", "tavern")
	assert_eq(str(still["clause"]), "knows(player, harbor.toll_fate)")
	runtime.facts.set(&"world.season", &"winter")
	runtime.facts.set_in(&"harbor.toll_fate", &"stolen", &"known/player")
	var season := runtime.director.why_not("harbor_gossip.tavern", "topic", "rumor.ferry_toll", "tavern")
	assert_eq(str(season["reason"]), "when")
	assert_eq(str(season["clause"]), "world.season == autumn")
	var speaker := runtime.director.why_not("harbor_gossip.tavern", "topic", "rumor.ferry_toll", "ferry")
	assert_eq(str(speaker["reason"]), "speaker")
	assert_eq(str(speaker["clause"]), "")
	var scope := runtime.director.why_not("harbor_gossip.tavern", "bark", "", "tavern")
	assert_eq(str(scope["reason"]), "scope")
	assert_eq(str(runtime.director.why_not("harbor_gossip.tavern", "lane", "rumor.ferry_toll", "tavern")["reason"]), "scope")
	assert_push_error("unknown scope")
	assert_eq(str(runtime.director.why_not("missing.rumor", "topic", "rumor.ferry_toll", "tavern")["reason"]), "missing")
	assert_push_error("unknown storylet")
	var bare := WyrdRuntime.new()
	assert_eq(str(bare.director.why_not("harbor_gossip.tavern", "topic", "rumor.ferry_toll", "tavern")["reason"]), "missing")
	assert_push_error("load content")
	var pair := _boot(_PAIR, 5)
	var winner := _tied(5, 0)
	var other := "harbor.pair_west" if winner == "harbor.pair_east" else "harbor.pair_east"
	var before := JSON.stringify(pair.save_state())
	var won := pair.director.why_not(winner, "topic", "rumor.pair", "ferry")
	var lost := pair.director.why_not(other, "topic", "rumor.pair", "ferry")
	assert_eq(str(won["reason"]), "ok")
	assert_true(bool(won["eligible"]))
	assert_eq(str(won["winner"]), winner)
	assert_eq(str(lost["reason"]), "outranked")
	assert_false(bool(lost["eligible"]))
	assert_eq(str(lost["winner"]), winner)
	assert_eq(str(won["score"]), "0/0/1/0")
	assert_eq(JSON.stringify(pair.save_state()), before)
	assert_eq(pair.storylets.seen_of(winner), 0)
	assert_eq(pair.condition_count(), 0)


func test_why_not_cooldown_survives_save_and_load() -> void:
	var runtime := _boot(_TRIO, 5)
	_arm(runtime)
	var picked := runtime.director.query("topic", "rumor.ferry_toll", "tavern")
	assert_eq(str(picked["id"]), "harbor_gossip.tavern")
	var saved := runtime.save_state()
	assert_eq(int(saved["schema_version"]), 2)
	var cooling := runtime.director.why_not("harbor_gossip.tavern", "topic", "rumor.ferry_toll", "tavern")
	assert_eq(str(cooling["reason"]), "cooldown")
	assert_false(bool(cooling["eligible"]))
	assert_eq(int(cooling["remaining"]), 60)
	assert_eq(str(cooling["score"]), "0/2/2/1")
	assert_eq(str(cooling["winner"]), "")
	assert_eq(int(runtime.save_state()["storylets"]["harbor_gossip.tavern"]["seen"]), 1)
	var generic := runtime.director.why_not("harbor_gossip.generic", "topic", "rumor.ferry_toll", "tavern")
	assert_eq(str(generic["reason"]), "ok")
	assert_eq(str(generic["winner"]), "harbor_gossip.generic")
	var parsed: Variant = JSON.parse_string(JSON.stringify(saved))
	assert_true(parsed is Dictionary)
	var loaded := _boot(_TRIO, 5)
	var report := loaded.load_state(parsed)
	assert_true(report.ok, report.diagnostics.format())
	var from_json := loaded.director.why_not("harbor_gossip.tavern", "topic", "rumor.ferry_toll", "tavern")
	assert_eq(str(from_json["reason"]), "cooldown")
	assert_eq(int(from_json["remaining"]), 60)
	assert_eq(str(from_json["clause"]), "")
	loaded.tick(60)
	var again := loaded.director.why_not("harbor_gossip.tavern", "topic", "rumor.ferry_toll", "tavern")
	assert_eq(str(again["reason"]), "ok")
	assert_true(bool(again["eligible"]))
	assert_eq(int(again["remaining"]), 0)
	assert_eq(str(again["winner"]), "harbor_gossip.tavern")
	assert_eq(str(again["score"]), "0/2/2/1")
	assert_eq(int(loaded.save_state()["storylets"]["harbor_gossip.tavern"]["seen"]), 1)
	var passed := loaded.director.why_not("harbor_gossip.generic", "topic", "rumor.ferry_toll", "tavern")
	assert_eq(str(passed["reason"]), "outranked")
	assert_eq(str(passed["winner"]), "harbor_gossip.tavern")
	assert_eq(loaded.storylets.seen_of("harbor_gossip.generic"), 0)


func test_why_not_trace_and_cli() -> void:
	var compiled := _compile(_TRIO)
	var runtime := _runtime_from(compiled)
	runtime.trace.enabled = true
	var row := runtime.director.why_not("harbor_gossip.tavern", "topic", "rumor.ferry_toll", "tavern")
	assert_eq(WyrdDirector.format_why_not(row), "wyrd why_not storylet=harbor_gossip.tavern scope=topic rumor.ferry_toll speaker=tavern eligible=false reason=when clause=\"knows(player, harbor.toll_fate)\" score=0/2/2/0 cooldown=60 remaining=0 winner=- tier=- unlocked=-")
	var found := false
	for item in runtime.trace.snapshot():
		if str(item["kind"]) != "why_not":
			continue
		found = true
		assert_eq(str(item["reason"]), "when")
		assert_eq(str(item["key"]), "rumor.ferry_toll")
		assert_eq(str(item["speaker"]), "tavern")
		assert_eq(str(item["scope"]), "topic rumor.ferry_toll")
	assert_true(found)
	assert_eq(_rows(runtime, "director").size(), 0)
	runtime.trace.clear()
	runtime.trace.prefix = "tavern"
	runtime.director.why_not("harbor_gossip.tavern", "topic", "rumor.ferry_toll", "tavern")
	assert_eq(_rows(runtime, "why_not").size(), 1)
	runtime.trace.clear()
	runtime.trace.prefix = "no-such"
	runtime.director.why_not("harbor_gossip.tavern", "topic", "rumor.ferry_toll", "tavern")
	assert_eq(_rows(runtime, "why_not").size(), 0)
	var manifest := _save_manifest(str(compiled["path"]))
	var explained: Dictionary = WyrdCli.execute(PackedStringArray(["why-not", "--manifest", manifest, "harbor_gossip.tavern"]))
	assert_eq(int(explained["exit_code"]), 0, str(explained["output"]))
	assert_eq(str(explained["output"]), WyrdDirector.format_why_not(row) + "\n")
	var spoken: Dictionary = WyrdCli.execute(PackedStringArray([
		"why-not", "--manifest", manifest, "--speaker", "ferry", "harbor_gossip.tavern",
	]))
	assert_eq(int(spoken["exit_code"]), 0, str(spoken["output"]))
	assert_true(str(spoken["output"]).contains("reason=speaker"), str(spoken["output"]))
	var barked: Dictionary = WyrdCli.execute(PackedStringArray([
		"why-not", "--manifest", manifest, "--scope", "bark", "harbor_gossip.tavern",
	]))
	assert_eq(int(barked["exit_code"]), 0, str(barked["output"]))
	assert_true(str(barked["output"]).contains("reason=scope"), str(barked["output"]))
	var missing: Dictionary = WyrdCli.execute(PackedStringArray(["why-not", "--manifest", manifest, "missing.rumor"]))
	assert_eq(int(missing["exit_code"]), 1)
	assert_eq(str(missing["output"]), "wyrd: unknown storylet \"missing.rumor\"\n")
	assert_push_error("unknown storylet")
	assert_eq(int(WyrdCli.execute(PackedStringArray(["why-not"]))["exit_code"]), 1)
	assert_eq(str(WyrdCli.execute(PackedStringArray(["why-not"]))["output"]), "wyrd: why-not needs --manifest\n")
	assert_eq(str(WyrdCli.execute(PackedStringArray(["why-not", "--manifest", manifest]))["output"]), "wyrd: why-not needs one storylet id\n")
	_arm(runtime)
	var picked := runtime.director.query("topic", "rumor.ferry_toll", "tavern")
	assert_eq(str(picked["id"]), "harbor_gossip.tavern")
	var save_path := "user://wyrd_m6_tie_save.json"
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(runtime.save_state()))
	file.close()
	var cooled: Dictionary = WyrdCli.execute(PackedStringArray([
		"why-not", "--manifest", manifest, "--save", save_path, "harbor_gossip.tavern",
	]))
	assert_eq(int(cooled["exit_code"]), 0, str(cooled["output"]))
	assert_true(str(cooled["output"]).contains("reason=cooldown"), str(cooled["output"]))
	assert_true(str(cooled["output"]).contains("remaining=60"), str(cooled["output"]))
	var harbor: Dictionary = WyrdCli.execute(PackedStringArray(["why-not", "--manifest", _HARBOR, "harbor_gossip.tavern"]))
	assert_eq(int(harbor["exit_code"]), 0, str(harbor["output"]))
	assert_true(str(harbor["output"]).contains("reason=when"), str(harbor["output"]))
	assert_true(str(harbor["output"]).contains("clause=\"knows(player, harbor.toll_fate)\""), str(harbor["output"]))
	var strict_ok: Dictionary = WyrdCli.execute(PackedStringArray(["check", "--strict", "--manifest", _save_manifest(_write("user://wyrd_m6_tie_only.wyrd", _ONLY))]))
	assert_eq(int(strict_ok["exit_code"]), 0, str(strict_ok["output"]))
	var strict_tie: Dictionary = WyrdCli.execute(PackedStringArray(["check", "--strict", "--manifest", _save_manifest(_write("user://wyrd_m6_tie_weight.wyrd", _WEIGHT))]))
	assert_eq(int(strict_tie["exit_code"]), 1)
	assert_true(str(strict_tie["output"]).contains("warning[W_STORYLET_TIE]"), str(strict_tie["output"]))


func _quiet(body: String) -> void:
	var compiled := _compile(body)
	var diagnostics: WyrdDiagnostics = compiled["diagnostics"]
	assert_false(diagnostics.has_errors(), diagnostics.format())
	assert_eq(_tie_lines(diagnostics).size(), 0, diagnostics.format())


func _one(body: String) -> String:
	var compiled := _compile(body)
	var diagnostics: WyrdDiagnostics = compiled["diagnostics"]
	assert_false(diagnostics.has_errors(), diagnostics.format())
	var lines := _tie_lines(diagnostics)
	assert_eq(lines.size(), 1, diagnostics.format())
	return lines[0]


func _tie_lines(diagnostics: WyrdDiagnostics) -> PackedStringArray:
	var lines := PackedStringArray()
	for raw in diagnostics.format().split("\n"):
		if String(raw).contains("warning[W_STORYLET_TIE]"):
			lines.append(String(raw))
	return lines


func _rows(runtime: WyrdRuntime, kind: String) -> Array:
	var rows: Array = []
	for item in runtime.trace.snapshot():
		if str(item["kind"]) == kind:
			rows.append(item)
	return rows


func _tied(seed_value: int, minute: int) -> String:
	var names := ["harbor.pair_east", "harbor.pair_west"]
	names.sort()
	var rng := WyrdRng.for_decision(seed_value, &"storylet_director", StringName("topic rumor.pair\tferry"), minute)
	return str(names[rng.randi_bounded(names.size())])


func _arm(runtime: WyrdRuntime) -> void:
	runtime.facts.set(&"world.season", &"autumn")
	runtime.facts.set_in(&"harbor.toll_fate", &"stolen", &"known/player")


func _boot(body: String, seed_value: int) -> WyrdRuntime:
	return _runtime_from(_compile(body), seed_value)


func _runtime_from(compiled: Dictionary, seed_value: int = 5) -> WyrdRuntime:
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


func _save_manifest(path: String) -> String:
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var out := "user://wyrd_m6_tie_%d.tres" % path.hash()
	assert_eq(ResourceSaver.save(manifest, out), OK)
	return out


func _compile(body: String) -> Dictionary:
	var path := _write("user://wyrd_m6_tie_%d.wyrd" % body.hash(), body)
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


func _find(pack: WyrdLinkedPack, id: String) -> WyrdStoryletDef:
	for unit in pack.units:
		var file: WyrdFileDef = unit["file"]
		for story in file.storylets:
			if story.id == id:
				return story
	return null


const _HEAD := """
language 1
facts
  harbor.toll_fate : symbol stored
  world.season : symbol stored
"""


const _TRIO := _HEAD + """
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
storylet dock_bark_lantern
  scope: bark
  speaker: ferry
  when: nearby(player, 4m, tag: lantern) > 0
  cooldown: 30m
  - Mind that flame near the ropes. #line:sg04
"""


const _WEIGHT := """
language 1
storylet harbor.light
  scope: topic rumor.ferry_toll
  speaker: ferry
  when: true
  weight: 1
  - The light line. #line:light1
storylet harbor.heavy
  scope: topic rumor.ferry_toll
  speaker: ferry
  when: true
  weight: 4
  - The heavy line. #line:heavy1
"""


const _THREE := """
language 1
storylet harbor.one
  scope: topic rumor.ferry_toll
  speaker: any
  - One. #line:one1
storylet harbor.two
  scope: topic rumor.ferry_toll
  speaker: any
  - Two. #line:two1
storylet harbor.three
  scope: topic rumor.ferry_toll
  speaker: any
  - Three. #line:three1
"""


const _SEASON := _HEAD + """
storylet harbor.autumn
  scope: topic rumor.ferry_toll
  speaker: ferry
  when: world.season == autumn
  - Autumn. #line:autumn1
storylet harbor.winter
  scope: topic rumor.ferry_toll
  speaker: ferry
  when: world.season == winter
  - Winter. #line:winter1
"""


const _KNOWS := _HEAD + """
storylet harbor.knows
  scope: topic rumor.ferry_toll
  speaker: ferry
  when: knows(player, harbor.toll_fate)
  - Heard. #line:knows1
storylet harbor.blind
  scope: topic rumor.ferry_toll
  speaker: ferry
  when: not knows(player, harbor.toll_fate)
  - Unheard. #line:blind1
"""


const _NOT_SEASON := _HEAD + """
storylet harbor.autumn
  scope: topic rumor.ferry_toll
  speaker: ferry
  when: world.season == autumn
  - Autumn. #line:autumn1
storylet harbor.other
  scope: topic rumor.ferry_toll
  speaker: ferry
  when: not (world.season == autumn)
  - Later. #line:other1
"""


const _FALSE := """
language 1
storylet harbor.never
  scope: topic rumor.ferry_toll
  speaker: ferry
  when: false
  - Never. #line:never1
storylet harbor.always
  scope: topic rumor.ferry_toll
  speaker: ferry
  when: true
  - Always. #line:always1
"""


const _SPEAKERS := """
language 1
storylet harbor.tavern_line
  scope: topic rumor.ferry_toll
  speaker: tavern
  - The tavern. #line:tavern1
storylet harbor.ferry_line
  scope: topic rumor.ferry_toll
  speaker: ferry
  - The ferry. #line:ferry1
"""


const _TOPICS := """
language 1
storylet harbor.toll
  scope: topic rumor.ferry_toll
  speaker: ferry
  - The toll. #line:toll1
storylet harbor.nets
  scope: topic rumor.nets
  speaker: ferry
  - The nets. #line:nets1
"""


const _KIND := """
language 1
storylet harbor.topic_line
  scope: topic rumor.ferry_toll
  speaker: ferry
  - The topic. #line:topic1
storylet harbor.bark_line
  scope: bark
  speaker: ferry
  - The bark. #line:bark1
"""


const _PRIORITY := """
language 1
storylet harbor.loud
  scope: topic rumor.ferry_toll
  speaker: ferry
  priority: 5
  - Loud. #line:loud1
storylet harbor.plain
  scope: topic rumor.ferry_toll
  speaker: ferry
  - Plain. #line:plain1
"""


const _SPECIFICITY := _HEAD + """
storylet harbor.generic
  scope: topic rumor.ferry_toll
  speaker: ferry
  - Generic. #line:generic1
storylet harbor.specific
  scope: topic rumor.ferry_toll
  speaker: ferry
  when: true
  - Specific. #line:specific1
"""


const _BEATS := """
language 1
storylet harbor.offer
  scope: beat ferry_toll.offer
  speaker: tavern
  - The offer. #line:offer1
storylet harbor.leave
  scope: beat ferry_toll.leave
  speaker: tavern
  - The leave. #line:leave1
"""


const _EVENTS := """
language 1
events
  bucket_poured()
  net_hauled()
storylet harbor.pour
  scope: event bucket_poured
  speaker: ferry
  - The bucket. #line:pour1
storylet harbor.haul
  scope: event net_hauled
  speaker: ferry
  - The haul. #line:haul1
"""


const _SPELLED := """
language 1
storylet harbor.spelled
  scope: topic rumor.ferry_toll
  speaker: Any
  - Spelled. #line:spelled1
storylet harbor.ferry_line
  scope: topic rumor.ferry_toll
  speaker: ferry
  - The ferry. #line:ferry1
"""


const _ANY := """
language 1
storylet harbor.tavern_line
  scope: topic rumor.ferry_toll
  speaker: tavern
  when: true
  - The tavern. #line:tavern1
storylet harbor.any_line
  scope: topic rumor.ferry_toll
  speaker: any
  when: true
  - Anyone. #line:any1
"""


const _KNOWS_SEASON := _HEAD + """
storylet harbor.knows
  scope: topic rumor.ferry_toll
  speaker: ferry
  when: knows(player, harbor.toll_fate)
  - Heard. #line:knows1
storylet harbor.season
  scope: topic rumor.ferry_toll
  speaker: ferry
  when: world.season == autumn
  - Autumn. #line:season1
"""


const _OR := _HEAD + """
storylet harbor.either
  scope: topic rumor.ferry_toll
  speaker: ferry
  when: world.season == autumn or world.season == winter
  - Either. #line:either1
storylet harbor.spring
  scope: topic rumor.ferry_toll
  speaker: ferry
  when: world.season == spring
  - Spring. #line:spring1
"""


const _NOT_AND := _HEAD + """
storylet harbor.grouped
  scope: topic rumor.ferry_toll
  speaker: ferry
  when: not (world.season == autumn and knows(player, harbor.toll_fate))
  - Grouped. #line:grouped1
storylet harbor.autumn
  scope: topic rumor.ferry_toll
  speaker: ferry
  when: world.season == autumn
  - Autumn. #line:autumn1
"""


const _CHANCE := """
language 1
storylet harbor.coin
  scope: topic rumor.ferry_toll
  speaker: ferry
  when: chance(0.25)
  - Maybe. #line:coin1
storylet harbor.other
  scope: topic rumor.ferry_toll
  speaker: ferry
  when: chance(0.75)
  - Else. #line:other1
"""


const _BARKS := """
language 1
storylet harbor.bark_east
  scope: bark
  speaker: ferry
  - East. #line:east1
storylet harbor.bark_west
  scope: bark
  speaker: ferry
  - West. #line:west1
"""


const _BEAT_PAIR := """
language 1
storylet harbor.offer_east
  scope: beat ferry_toll.offer
  speaker: tavern
  - East. #line:east1
storylet harbor.offer_west
  scope: beat ferry_toll.offer
  speaker: tavern
  - West. #line:west1
"""


const _EVENT_PAIR := """
language 1
events
  bucket_poured()
storylet harbor.pour_east
  scope: event bucket_poured
  speaker: ferry
  - East. #line:east1
storylet harbor.pour_west
  scope: event bucket_poured
  speaker: ferry
  - West. #line:west1
"""


const _DUPLICATE := """
language 1
storylet harbor.rumor
  scope: bark
  speaker: any
  - First. #line:a
storylet harbor.rumor
  scope: bark
  speaker: any
  - Second. #line:b
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


const _ONLY := """
language 1
storylet harbor.only
  scope: topic rumor.ferry_toll
  speaker: ferry
  - One line. #line:only1
"""
