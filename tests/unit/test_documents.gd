extends GutTest

const _Harness := preload("res://tests/scenario/s2c_harness.gd")


func test_live_text_follows_state() -> void:
	var runtime := _boot(_LIVE)
	_player(runtime)
	runtime.facts.set(&"player.coins", 1)
	var first := runtime.documents.open(&"note", "", &"player")
	assert_eq(first.pages[0][0]["text"], "Coins: 1.")
	runtime.facts.set(&"player.coins", 4)
	var second := runtime.documents.open(&"note", "", &"player")
	assert_eq(second.pages[0][0]["text"], "Coins: 4.")
	assert_false(second.first_time)


func test_frozen_copy_keeps_text_across_state_save_and_locale() -> void:
	var runtime := _boot(_FROZEN)
	_player(runtime)
	runtime.facts.set(&"player.coins", 1)
	assert_true(runtime.documents.create_copy(&"letter", "kept"))
	runtime.facts.set(&"player.coins", 9)
	var opened := runtime.documents.open(&"letter", "kept", &"player")
	assert_eq(opened.pages[0][0]["text"], "Coins: 1.")
	assert_true(opened.frozen)
	var saved := runtime.save_state()
	var other := _boot(_FROZEN)
	_player(other)
	assert_true(other.load_state(saved).ok)
	var loaded := other.documents.open(&"letter", "kept", &"player")
	assert_eq(loaded.pages[0][0]["text"], "Coins: 1.")
	var prior := TranslationServer.get_locale()
	var translation := Translation.new()
	translation.locale = "fr"
	translation.add_message("Coins: 1.", "Pieces: 1.", "letter_body")
	translation.add_message("Letter", "Lettre", "letter_title")
	TranslationServer.add_translation(translation)
	TranslationServer.set_locale("fr")
	var translated := other.documents.open(&"letter", "kept", &"player")
	TranslationServer.set_locale(prior)
	TranslationServer.remove_translation(translation)
	assert_eq(translated.pages[0][0]["text"], "Pieces: 1.")
	assert_eq(translated.title, "Lettre")


func test_read_effects_run_once_then_every_time_and_the_signal_is_last() -> void:
	var runtime := _boot(_EFFECTS)
	_player(runtime)
	var seen: Array = []
	runtime.documents.document_read.connect(func(doc_id: StringName, _copy: String, _reader: StringName, first_time: bool) -> void:
		seen.append({"coins": runtime.facts.get(&"player.coins"), "first": first_time, "id": String(doc_id)})
	)
	runtime.documents.open(&"note", "", &"player")
	assert_eq(seen[0]["coins"], 2)
	assert_true(seen[0]["first"])
	runtime.documents.open(&"note", "", &"player")
	assert_eq(seen[1]["coins"], 3)
	assert_false(seen[1]["first"])
	assert_eq(seen.size(), 2)


func test_has_read_wakes_a_waiting_condition() -> void:
	var runtime := _boot(_WAKE)
	_player(runtime)
	runtime.quests.start("letter")
	runtime.tick(0)
	assert_eq(runtime.quests.stage("letter"), "wait")
	assert_false(runtime.documents.has_read(&"player", &"note"))
	runtime.documents.open(&"note", "", &"player")
	assert_true(runtime.documents.has_read(&"player", &"note"))
	runtime.tick(0)
	assert_eq(runtime.quests.stage("letter"), "read")


func test_open_refusals() -> void:
	var runtime := _boot(_REFUSE)
	_player(runtime)
	runtime.config().secrecy_tiers = PackedStringArray(["open", "sealed"])
	runtime.facts.set(&"player.clearance", &"open")
	runtime.trace.enabled = true
	assert_null(runtime.documents.open(&"missing", "", &"player"))
	assert_push_error("unknown document")
	assert_eq(_kinds(runtime, "document_open").size(), 0)
	assert_null(runtime.documents.open(&"note", "", &"nobody"))
	assert_push_error("unknown reader")
	assert_eq(_kinds(runtime, "document_open").size(), 0)
	assert_null(runtime.documents.open(&"gazette", "", &"player"))
	assert_push_warning("periodic")
	assert_eq(_kinds(runtime, "document_open")[0]["reason"], "periodic")
	runtime.trace.clear()
	assert_null(runtime.documents.open(&"sealed_note", "", &"player"))
	assert_push_warning("secrecy")
	assert_eq(_kinds(runtime, "document_open")[0]["reason"], "secrecy")
	assert_eq(_kinds(runtime, "secrecy").size(), 1)
	runtime.trace.clear()
	assert_null(runtime.documents.open(&"letter", "missing", &"player"))
	assert_push_warning("no_copy")
	assert_eq(_kinds(runtime, "document_open")[0]["reason"], "no_copy")


func test_create_copy_refusals() -> void:
	var runtime := _boot(_REFUSE)
	_player(runtime)
	runtime.trace.enabled = true
	assert_false(runtime.documents.create_copy(&"letter", ""))
	assert_push_error("copy id is empty")
	assert_eq(_kinds(runtime, "document_copy").size(), 0)
	assert_false(runtime.documents.create_copy(&"missing", "one"))
	assert_push_error("unknown document")
	assert_eq(_kinds(runtime, "document_copy").size(), 0)
	assert_false(runtime.documents.create_copy(&"note", "one"))
	assert_push_warning("live")
	assert_eq(_kinds(runtime, "document_copy")[0]["reason"], "live")
	runtime.trace.clear()
	assert_false(runtime.documents.create_copy(&"gazette", "one"))
	assert_push_warning("periodic")
	assert_eq(_kinds(runtime, "document_copy")[0]["reason"], "periodic")
	runtime.trace.clear()
	assert_false(runtime.documents.create_copy(&"letter", "one", {"at": 1}))
	assert_push_warning("params")
	assert_false(runtime.documents.has_copy(&"letter", "one"))
	assert_eq(_kinds(runtime, "document_copy")[0]["reason"], "params")
	runtime.trace.clear()
	assert_true(runtime.documents.create_copy(&"letter", "one"))
	assert_eq(_kinds(runtime, "document_copy")[0]["reason"], "created")
	runtime.trace.clear()
	assert_true(runtime.documents.create_copy(&"letter", "one"))
	assert_eq(_kinds(runtime, "document_copy")[0]["reason"], "already")
	assert_eq(_kinds(runtime, "document_copy")[0]["ok"], "false")


func test_a_changed_paragraph_renders_live_and_logs_document_stale() -> void:
	var runtime := _boot(_FROZEN)
	_player(runtime)
	runtime.facts.set(&"player.coins", 1)
	runtime.trace.enabled = true
	assert_true(runtime.documents.create_copy(&"letter", "kept"))
	var document: WyrdDocumentDef = runtime.content().documents["letter"]
	var paragraph: Dictionary = document.pages[0]["paragraphs"][0]
	var prose := paragraph["prose"] as WyrdExprNode
	var extra := WyrdExprNode.new()
	extra.kind = &"value"
	extra.payload = _value_payload(prose)
	prose.kids.append(extra)
	runtime.trace.clear()
	var opened := runtime.documents.open(&"letter", "kept", &"player")
	assert_eq(_kinds(runtime, "document_stale").size(), 1)
	assert_eq(_kinds(runtime, "document_stale")[0]["line"], "letter_body")
	assert_eq(_kinds(runtime, "document_stale")[0]["key"], "letter")
	assert_eq(_kinds(runtime, "document_stale")[0]["path"], "kept")
	assert_ne(opened.pages[0][0]["text"], "Coins: 1.")


func test_save_bag_round_trip_keeps_unknown_ids_and_stays_schema_3() -> void:
	var runtime := _boot(_FROZEN)
	_player(runtime)
	var empty := runtime.save_state()
	assert_eq(int(empty["schema_version"]), 3)
	assert_false(empty.has("documents"))
	runtime.facts.set(&"player.coins", 2)
	runtime.documents.create_copy(&"letter", "kept")
	runtime.documents.open(&"letter", "kept", &"player")
	var saved := runtime.save_state()
	assert_true(saved.has("documents"))
	var other := _boot(_FROZEN)
	_player(other)
	assert_true(other.load_state(saved).ok)
	assert_eq(JSON.stringify(other.save_state()["documents"]), JSON.stringify(saved["documents"]))
	other.documents.import_state({
		"copies": [{"copy": "old", "doc": "gone", "record": {"missing": {"ifs": [], "page": true, "show": true, "values": []}}}],
		"read": [{"doc": "gone", "reader": "ghost"}],
	})
	var kept := other.documents.export_state()
	assert_eq(kept["read"][0]["reader"], "ghost")
	assert_eq(kept["copies"][0]["doc"], "gone")
	assert_true(other.documents.has_read(&"ghost", &"gone"))
	assert_null(other.documents.open(&"gone", "old", &"player"))
	assert_push_error("unknown document")


func test_trace_filter_replay_and_load_is_silent() -> void:
	var runtime := _boot(_FROZEN)
	_player(runtime)
	runtime.facts.set(&"player.coins", 1)
	runtime.trace.enabled = true
	runtime.documents.create_copy(&"letter", "kept")
	runtime.documents.open(&"letter", "kept", &"player")
	var opened: Dictionary = _kinds(runtime, "document_open")[0]
	assert_eq(opened["key"], "letter")
	assert_eq(opened["path"], "kept")
	assert_eq(opened["who"], "player")
	assert_eq(opened["ok"], "true")
	assert_eq(opened["reason"], "opened")
	var copied: Dictionary = _kinds(runtime, "document_copy")[0]
	assert_eq(copied["source"], "host")
	assert_eq(copied["key"], "letter")
	assert_eq(copied["path"], "kept")
	var recorded := runtime.trace.snapshot()
	runtime.trace.prefix = "letter"
	runtime.trace.clear()
	runtime.documents.open(&"letter", "kept", &"player")
	assert_gt(_kinds(runtime, "document_open").size(), 0)
	runtime.trace.prefix = "zzz"
	runtime.trace.clear()
	runtime.documents.open(&"letter", "kept", &"player")
	assert_eq(_kinds(runtime, "document_open").size(), 0)
	var replayed := _boot(_FROZEN)
	_player(replayed)
	replayed.facts.set(&"player.coins", 1)
	replayed.trace.enabled = true
	WyrdTrace.replay(replayed, recorded)
	assert_eq(WyrdTrace.diff(recorded, replayed.trace.snapshot()), PackedStringArray())
	var saved := replayed.save_state()
	replayed.trace.clear()
	assert_true(replayed.load_state(saved).ok)
	assert_eq(_kinds(replayed, "document_open").size(), 0)
	assert_eq(_kinds(replayed, "document_copy").size(), 0)
	assert_eq(_kinds(replayed, "document_stale").size(), 0)


func test_opening_during_a_scene_leaves_can_save() -> void:
	var runtime := _boot(_SCENE)
	_player(runtime)
	assert_true(runtime.dialogue.can_save())
	runtime.dialogue.open_scene("talk")
	assert_false(runtime.dialogue.can_save())
	var view := runtime.documents.open(&"note", "", &"player")
	assert_false(view == null)
	assert_false(runtime.dialogue.can_save())
	runtime.dialogue.advance()
	assert_true(runtime.dialogue.can_save())


func test_gullhaven_schedule_letter_save_and_replay() -> void:
	var opened := _Harness.new().boot_gullhaven()
	var runtime: WyrdRuntime = opened["runtime"]
	var schedule := runtime.documents.open(&"ferry_schedule", "", &"player")
	var first := _page_text(schedule)
	assert_true(first.contains("The toll is still due."), first)
	assert_false(first.contains("chair is empty"))
	runtime.quests.start("ferry_toll")
	runtime.quests.note_outcome("ferry_toll", &"crossing", &"done")
	var paid := _page_text(runtime.documents.open(&"ferry_schedule", "", &"player"))
	assert_true(paid.contains("The toll is paid and the ferry runs."), paid)
	runtime.roles.vacate(&"ferry_master", &"left")
	var empty := _page_text(runtime.documents.open(&"ferry_schedule", "", &"player"))
	assert_true(empty.contains("The ferry master's chair is empty."), empty)
	runtime.quests.start("dock_letter")
	runtime.dialogue.open_scene("dock.letter_talk")
	var hidden := _Harness.new().ids_of(_Harness.new().line_rows(runtime))
	assert_false(hidden.has("letter_heard"))
	assert_true(runtime.documents.has_copy(&"reeve_letter", "dock_letter"))
	var unlocks: Array = []
	runtime.topics.topic_unlocked.connect(func(topic: StringName) -> void: unlocks.append(String(topic)))
	var letter := runtime.documents.open(&"reeve_letter", "dock_letter", &"player")
	var letter_text := _page_text(letter)
	assert_eq(unlocks, ["storm_rumour"])
	assert_true(letter.first_time)
	var again := runtime.documents.open(&"reeve_letter", "dock_letter", &"player")
	assert_false(again.first_time)
	assert_eq(unlocks.size(), 1)
	assert_eq(_page_text(again), letter_text)
	assert_true(runtime.documents.has_read(&"player", &"reeve_letter"))
	var saved := runtime.save_state()
	var restored: WyrdRuntime = _Harness.new().boot_gullhaven().runtime
	assert_true(restored.load_state(saved).ok)
	var loaded := restored.documents.open(&"reeve_letter", "dock_letter", &"player")
	assert_eq(_page_text(loaded), letter_text)
	var positive: WyrdRuntime = _Harness.new().boot_gullhaven().runtime
	assert_true(positive.documents.create_copy(&"reeve_letter", "dock_letter"))
	positive.documents.open(&"reeve_letter", "dock_letter", &"player")
	positive.quests.start("dock_letter")
	positive.dialogue.open_scene("dock.letter_talk")
	var shown := _Harness.new().ids_of(_Harness.new().line_rows(positive))
	assert_true(shown.has("letter_heard"), str(shown))


func test_gullhaven_replay_matches() -> void:
	var runtime: WyrdRuntime = _Harness.new().boot_gullhaven().runtime
	runtime.quests.start("dock_letter")
	runtime.trace.enabled = true
	runtime.documents.open(&"ferry_schedule", "", &"player")
	runtime.dialogue.open_scene("dock.letter_talk")
	runtime.documents.open(&"reeve_letter", "dock_letter", &"player")
	var recorded := runtime.trace.snapshot()
	var replayed: WyrdRuntime = _Harness.new().boot_gullhaven().runtime
	replayed.quests.start("dock_letter")
	replayed.trace.enabled = true
	WyrdTrace.replay(replayed, recorded)
	assert_eq(WyrdTrace.diff(recorded, replayed.trace.snapshot()), PackedStringArray())


func _page_text(view: WyrdDocumentView) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for page in view.pages:
		for paragraph in page:
			parts.append(str(paragraph["text"]))
	return "\n".join(parts)


func _value_payload(node: WyrdExprNode) -> Variant:
	if node == null:
		return null
	if node.kind == &"value":
		return node.payload
	for kid in node.kids:
		var found: Variant = _value_payload(kid)
		if found != null:
			return found
	return _value_payload(node.b)


func _kinds(runtime: WyrdRuntime, kind: String) -> Array:
	var found: Array = []
	for item in runtime.trace.events:
		if item is Dictionary and str((item as Dictionary).get("kind", "")) == kind:
			found.append(item)
	return found


func _player(runtime: WyrdRuntime) -> void:
	var world := runtime.adapter(WyrdWorldAdapter) as WyrdFakeWorld
	world.add_entity(&"player", &"person", "traveler", PackedStringArray(), true)


func _boot(body: String) -> WyrdRuntime:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var path := "user://wyrd_documents_%d.wyrd" % body.hash()
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
	return runtime


const _LIVE := """
language 1

facts
  player.coins : int stored

document note "Note" #line:note_title
  text: live
  page
    Coins: {player.coins}. #line:note_body
"""

const _FROZEN := """
language 1

facts
  player.coins : int stored

document letter "Letter" #line:letter_title
  text: frozen
  page
    Coins: {player.coins}. #line:letter_body
"""

const _EFFECTS := """
language 1

facts
  player.coins : int stored

document note "Note" #line:note_title
  text: live
  page
    Ready. #line:note_body
  on_first_read:
    ~ set player.coins = 1
  on_read:
    ~ inc player.coins by 1
"""

const _WAKE := """
language 1

document note "Note" #line:note_title
  text: live
  page
    Ready. #line:note_body

quest letter "Letter"
  start when false
  stage wait
    waits_until has_read(player, note)
    -> read
  stage read
    waits_until false
"""

const _REFUSE := """
language 1

facts
  player.clearance : symbol stored

document note "Note" #line:note_title
  text: live
  page
    Ready. #line:note_body

document letter "Letter" #line:letter_title
  text: frozen
  page
    Ready. #line:letter_body

document sealed_note "Sealed" #secrecy:sealed #line:sealed_title
  text: live
  page
    Hidden. #line:sealed_body

document gazette "Gazette" publishes_by guild every 1 hour delay 1 hour
"""

const _SCENE := """
language 1

document note "Note" #line:note_title
  text: live
  page
    Ready. #line:note_body

scene talk
  narrator: Hello. #line:hi
  -> end
"""
