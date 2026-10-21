extends GutTest


func test_secrecy_filters_before_when_and_why_not_names_it() -> void:
	var runtime := _boot(_PACK)
	_tiers(runtime)
	var locked := runtime.director.query("topic", "rumor.ledger", "any")
	assert_eq(str(locked["id"]), "harbor_ledger.open")
	assert_eq(str(locked["line_id"]), "lg01")
	assert_eq(int(locked["candidates"]), 1)
	assert_eq(str(locked["score"]), "0/0/1/0")
	var before := JSON.stringify(runtime.save_state())
	var why := runtime.director.why_not("harbor_ledger.sealed", "topic", "rumor.ledger", "any")
	assert_eq(JSON.stringify(runtime.save_state()), before)
	assert_eq(str(why["reason"]), "secrecy")
	assert_false(bool(why["eligible"]))
	assert_eq(str(why["tier"]), "sealed")
	assert_eq(str(why["unlocked"]), "-")
	assert_eq(str(why["clause"]), "")
	assert_eq(str(why["winner"]), "")
	assert_eq(str(why["score"]), "1/1/1/0")
	assert_eq(
		WyrdDirector.format_why_not(why),
		"wyrd why_not storylet=harbor_ledger.sealed scope=topic rumor.ledger speaker=any eligible=false reason=secrecy clause=\"-\" score=1/1/1/0 cooldown=60 remaining=0 winner=- tier=sealed unlocked=-"
	)
	runtime.storylets.import_state({"harbor_ledger.sealed": {"seen": 1, "last_minute": 0}})
	var cooled := runtime.director.why_not("harbor_ledger.sealed", "topic", "rumor.ledger", "any")
	assert_eq(str(cooled["reason"]), "secrecy")
	assert_eq(int(cooled["remaining"]), 60)
	assert_eq(runtime.storylets.seen_of("harbor_ledger.sealed"), 1)


func test_each_unlock_is_inclusive() -> void:
	var lower := _boot(_PACK)
	_tiers(lower)
	lower.facts.set(&"player.clearance", &"open")
	assert_eq(str(lower.director.query("topic", "rumor.ledger", "any")["id"]), "harbor_ledger.open")
	var still := lower.director.why_not("harbor_ledger.sealed", "topic", "rumor.ledger", "any")
	assert_eq(str(still["reason"]), "secrecy")
	assert_eq(str(still["unlocked"]), "open")
	var upper := _boot(_PACK)
	_tiers(upper)
	upper.facts.set(&"player.clearance", &"sealed")
	var ready := upper.director.why_not("harbor_ledger.sealed", "topic", "rumor.ledger", "any")
	assert_eq(str(ready["reason"]), "ok")
	assert_true(bool(ready["eligible"]))
	assert_eq(str(ready["winner"]), "harbor_ledger.sealed")
	assert_eq(str(ready["tier"]), "sealed")
	assert_eq(str(ready["unlocked"]), "sealed")
	var won := upper.director.query("topic", "rumor.ledger", "any")
	assert_eq(str(won["id"]), "harbor_ledger.sealed")
	assert_eq(str(won["line_id"]), "lg03")
	assert_eq(int(won["candidates"]), 2)
	assert_eq(str(won["score"]), "1/1/1/0")


func test_unknown_tier_is_locked_once() -> void:
	var runtime := _boot(_PACK)
	var row := runtime.director.query("topic", "rumor.ledger", "any")
	assert_eq(str(row["id"]), "harbor_ledger.open")
	assert_push_error("unknown tier")
	runtime.director.query("topic", "rumor.ledger", "any")


func test_line_skip_trace_prefix_and_silence() -> void:
	var runtime := _boot(_PACK)
	_tiers(runtime)
	runtime.storylets.import_state({
		"harbor_ledger.open": {"cursor": 0, "cycle": 0, "order": ["lg02", "lg01"], "seen": 0},
	})
	runtime.trace.enabled = true
	var drawn := runtime.director.query("topic", "rumor.ledger", "any")
	assert_eq(str(drawn["line_id"]), "lg01")
	var rows := _rows(runtime, "secrecy")
	assert_eq(rows.size(), 2)
	assert_eq(str(rows[0]["storylet"]), "harbor_ledger.sealed")
	assert_eq(str(rows[0]["line"]), "-")
	assert_eq(str(rows[0]["tier"]), "sealed")
	assert_eq(str(rows[0]["unlocked"]), "-")
	assert_eq(str(rows[1]["line"]), "lg02")
	assert_eq(str(rows[1]["key"]), "harbor_ledger.open")
	assert_eq(str(rows[1]["path"]), "lg02")
	var story_only := _boot(_PACK)
	_tiers(story_only)
	story_only.storylets.import_state({
		"harbor_ledger.open": {"cursor": 0, "cycle": 0, "order": ["lg02", "lg01"], "seen": 0},
	})
	story_only.trace.enabled = true
	story_only.trace.prefix = "harbor_ledger.sealed"
	story_only.director.query("topic", "rumor.ledger", "any")
	var kept := _rows(story_only, "secrecy")
	assert_eq(kept.size(), 1)
	assert_eq(str(kept[0]["storylet"]), "harbor_ledger.sealed")
	var line_only := _boot(_PACK)
	_tiers(line_only)
	line_only.storylets.import_state({
		"harbor_ledger.open": {"cursor": 0, "cycle": 0, "order": ["lg02", "lg01"], "seen": 0},
	})
	line_only.trace.enabled = true
	line_only.trace.prefix = "lg02"
	line_only.director.query("topic", "rumor.ledger", "any")
	var lines := _rows(line_only, "secrecy")
	assert_eq(lines.size(), 1)
	assert_eq(str(lines[0]["line"]), "lg02")
	var quiet := _boot(_PACK)
	_tiers(quiet)
	quiet.director.query("topic", "rumor.ledger", "any")
	assert_eq(quiet.trace.events.size(), 0)


func test_save_load_keeps_the_fact_and_does_not_log() -> void:
	var runtime := _boot(_PACK)
	_tiers(runtime)
	runtime.facts.set(&"player.clearance", &"sealed")
	var saved := runtime.save_state()
	assert_eq(int(saved["schema_version"]), 4)
	assert_false(saved.has("secrecy"))
	assert_eq(str(saved["facts"]["world"]["player.clearance"]), "sealed")
	var loaded := _boot(_PACK)
	_tiers(loaded)
	loaded.trace.enabled = true
	var report := loaded.load_state(saved)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(_rows(loaded, "secrecy").size(), 0)
	assert_eq(str(loaded.facts.get(&"player.clearance")), "sealed")
	assert_eq(str(loaded.director.query("topic", "rumor.ledger", "any")["id"]), "harbor_ledger.sealed")
	loaded.facts.set(&"player.clearance", &"open")
	assert_eq(str(loaded.director.query("topic", "rumor.ledger", "any")["id"]), "harbor_ledger.open")
	assert_gt(_rows(loaded, "secrecy").size(), 0)


func test_scene_journal_and_choice_lines_are_filtered() -> void:
	var runtime := _boot(_PACK)
	_tiers(runtime)
	runtime.trace.enabled = true
	runtime.dialogue.open_scene("dock.ledger")
	assert_eq(runtime.dialogue.line().id, "s_open")
	runtime.dialogue.advance()
	assert_eq(runtime.dialogue.line().id, "s_dry")
	var skipped := _rows(runtime, "secrecy")
	assert_eq(skipped.size(), 1)
	assert_eq(str(skipped[0]["line"]), "s_shut")
	assert_eq(str(skipped[0]["key"]), "s_shut")
	var shown := _boot(_PACK)
	_tiers(shown)
	shown.facts.set(&"player.clearance", &"sealed")
	shown.dialogue.open_scene("dock.ledger")
	assert_eq(shown.dialogue.line().id, "s_open")
	shown.dialogue.advance()
	assert_eq(shown.dialogue.line().id, "s_shut")
	var picked := _boot(_PACK)
	_tiers(picked)
	picked.facts.set(&"player.clearance", &"sealed")
	picked.dialogue.open_scene("dock.choice")
	assert_eq(picked.dialogue.choices().size(), 2)
	var hidden := _boot(_PACK)
	_tiers(hidden)
	hidden.dialogue.open_scene("dock.choice")
	assert_eq(hidden.dialogue.choices().size(), 1)
	assert_eq(hidden.dialogue.choices()[0].id, "c_open")
	var journal := _boot(_PACK)
	_tiers(journal)
	journal.trace.enabled = true
	journal.tick(0)
	var pages: Array = journal.quests.journal("ledger")
	assert_eq(pages.size(), 1)
	assert_eq(str(pages[0]["id"]), "j_open")
	assert_eq(_rows(journal, "secrecy").size(), 1)
	assert_eq(str(_rows(journal, "secrecy")[0]["line"]), "j_shut")
	var both := _boot(_PACK)
	_tiers(both)
	both.facts.set(&"player.clearance", &"sealed")
	both.tick(0)
	var full: Array = both.quests.journal("ledger")
	assert_eq(full.size(), 2)
	assert_eq(str(full[1]["id"]), "j_shut")
	var frozen := both.save_state()
	var again := _boot(_PACK)
	_tiers(again)
	again.trace.enabled = true
	assert_true(again.load_state(frozen).ok)
	assert_eq(_rows(again, "secrecy").size(), 0)
	var loaded: Array = again.quests.journal("ledger")
	assert_eq(loaded.size(), 2)
	assert_eq(str(loaded[0]["text"]), str(full[0]["text"]))
	assert_eq(str(loaded[1]["text"]), str(full[1]["text"]))


func test_secrecy_syntax_and_export_omit_an_empty_name() -> void:
	var compiled := _compile(_PACK)
	assert_false(compiled["diagnostics"].has_errors(), compiled["diagnostics"].format())
	var sealed: WyrdStoryletDef = _find(compiled["pack"], "harbor_ledger.sealed")
	assert_eq(sealed.secrecy, "sealed")
	var open: WyrdStoryletDef = _find(compiled["pack"], "harbor_ledger.open")
	assert_eq(open.secrecy, "")
	assert_eq(open.lines[1].secrecy, "sealed")
	var body := WyrdExport.to_json(WyrdExport.to_data(compiled["pack"]))
	assert_true(body.contains("\"secrecy\": \"sealed\""), body)
	var bare := _compile(_BARE)
	assert_true(bare["diagnostics"].format().contains("secrecy needs a name"), bare["diagnostics"].format())


func _tiers(runtime: WyrdRuntime) -> void:
	runtime.config().secrecy_tiers = PackedStringArray(["open", "sealed"])


func _boot(body: String) -> WyrdRuntime:
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


func _compile(body: String) -> Dictionary:
	var path := _write("user://wyrd_m6_secrecy_%d.wyrd" % body.hash(), body)
	var diagnostics := WyrdDiagnostics.new()
	var pack := WyrdPack.compile(PackedStringArray([path]), "harbor", 1, null, diagnostics, path, true)
	return {"diagnostics": diagnostics, "pack": pack, "path": path}


func _find(pack: WyrdLinkedPack, id: String) -> WyrdStoryletDef:
	for unit in pack.units:
		var file: WyrdFileDef = unit["file"]
		for story in file.storylets:
			if story.id == id:
				return story
	return null


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


func _rows(runtime: WyrdRuntime, kind: String) -> Array:
	var found: Array = []
	for item in runtime.trace.events:
		if item is Dictionary and String((item as Dictionary).get("kind", "")) == kind:
			found.append(item)
	return found


const _PACK := """
		language 1

		facts
		  player.clearance: symbol stored

		storylet harbor_ledger.open
		  scope: topic rumor.ledger
		  speaker: any
		  lines:
		    - The dock ledger is open on the bench. #line:lg01
		    - A later page stays shut. #secrecy:sealed #line:lg02

		storylet harbor_ledger.sealed
		  scope: topic rumor.ledger
		  speaker: any
		  secrecy: sealed
		  priority: 1
		  cooldown: 60m
		  when: player.clearance == sealed
		  - The sealed page names the late cargo. #line:lg03

		scene dock.ledger
		  narrator: The dock ledger is open. #line:s_open
		  narrator: The sealed page stays shut. #secrecy:sealed #line:s_shut
		  narrator: The bench is dry. #line:s_dry

		scene dock.choice
		  * [The open page] -> end #line:c_open
		  * [The sealed page] -> end #secrecy:sealed #line:c_shut

		quest ledger "Ledger"
		  start when true
		  stage note
		    journal: The dock ledger is open. #line:j_open
		    journal: The sealed page stays shut. #secrecy:sealed #line:j_shut
		    ~ set player.clearance = open
		"""


const _BARE := """
		language 1

		facts
		  player.clearance: symbol stored

		storylet harbor_ledger.bare
		  scope: topic rumor.ledger
		  speaker: any
		  secrecy:
		  - No name. #line:bare1
		"""
