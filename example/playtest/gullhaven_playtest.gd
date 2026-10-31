# [EXAMPLE CONTENT] Gullhaven playtest. An invented fishing village, not a host game.
extends Control

## Playable Gullhaven slice. No art. Text stays on screen with or without voice.
##
## @experimental
## The host is the scripted fake host. F5 runs this scene.

const _MANIFEST := "res://example/content/gullhaven/harbor.wyrdmanifest.tres"
const _NEXT_MANIFEST := "res://example/versions/gullhaven_next/harbor_next.wyrdmanifest.tres"
const _Election := preload("res://example/playtest/harbor_election.gd")
const _LocalProvider := preload("res://example/ai/wyrd_local_provider.gd")
const _LocalTransport := preload("res://example/ai/wyrd_local_transport.gd")
const _SAVE_PATH := "user://playtest_save.json"
const _FERRY_NAME := "Bram"
const _SUCCESSOR_NAME := "Nia"
const _QUEST_ID := "ferry_toll"
const _CHANGED_BG := Color(0.62, 0.42, 0.1)
const _ROUTE_DEFAULTS := {
	"ai_local": false,
	"apprentice": false,
	"ferry_alive": true,
	"local": false,
	"lodging": true,
	"notice": true,
	"short": false,
	"storm": false,
	"voice": false,
	"watch_alive": false,
}
const _ROUTES: Array[Dictionary] = [
	{
		"id": "defaults",
		"label": "Defaults",
		"flags": {},
		"hint": "Innkeeper room line, Nia on \"The headland bell rang twice before the rain.\" and \"Bram, the ferry master, is on the dock.\", bell, then Take the room, then the dock lines spoken by Bram. Coins go from 4 to 2. Journal day 1, 00:00. Advance time moves the stage to cross and finishes the quest after the dock lines.",
	},
	{
		"id": "local",
		"label": "Local tag",
		"flags": {"local": true},
		"hint": "A second choice appears: \"I have a place in town\". Press it. Coins stay 4. The dock lines still play. The stage is still pay_toll and the journal still appears.",
	},
	{
		"id": "lodging",
		"label": "Lodging available",
		"flags": {"lodging": false},
		"hint": "After Take the room the innkeeper says \"No room left tonight.\" and \"The board lists the price as {two coins}}\". The second line really does show a single { and an extra }. Coins stay 4. The stage is pay_toll.",
	},
	{
		"id": "notice",
		"label": "Notice succeeds",
		"flags": {"notice": false},
		"hint": "The room conversation plays as in section 5, then the tavern conversation is offered again and the stage is gossip. The journal already has Bram's toll line.",
	},
	{
		"id": "ferry-gone",
		"label": "Ferry master gone",
		"flags": {"ferry_alive": false},
		"hint": "Nia says \"The dock is empty.\" You do not see a line with {?holder(ferry).name}. Take the room. The journal says \"The dock is empty, so the crossing waits.\" dated day 1, 00:00. The stage returns to gossip and the room is offered again. Continue is enabled. The summary says waiting scene:toll.offer_room. The ferry slot row is slot ferry — ferry master — none — empty.",
	},
	{
		"id": "successor",
		"label": "Successor",
		"flags": {"apprentice": true, "ferry_alive": false},
		"hint": "The successor is Nia, a different person from Bram. Nia also speaks the lookout line \"Nia, the ferry master, is on the dock.\" The journal says \"Nia, the ferry master, at the dock wants 2 coins before the crossing.\" The ferry slot row is slot ferry — ferry master — Nia — successor. Advance time reaches cross.",
	},
	{
		"id": "storm",
		"label": "Season storm",
		"flags": {"storm": true},
		"hint": "An extra line appears before the bell: narrator, \"The season smells like rain.\"",
	},
	{
		"id": "abort",
		"label": "Abort scene",
		"flags": {},
		"hint": "This step comes later. Abort scene while the first lines are up. The conversation stops. The status says you can save. The stage stays gossip and the tavern scene is offered again. The last line stays visible.",
	},
	{
		"id": "short",
		"label": "Short on coins",
		"flags": {"short": true},
		"hint": "\"Take the room (short on coins)\" is grey and cannot be pressed.",
	},
	{
		"id": "watch",
		"label": "Watch alive",
		"flags": {"watch_alive": true},
		"hint": "This step comes later. Press Emit alive while the innkeeper line is up. The conversation stays on that line. Continue then shows narrator: \"The ferry master is gone.\"",
	},
	{
		"id": "batch",
		"label": "Batch world",
		"flags": {},
		"hint": "This step comes later. Press Batch world after New game. The events line shows season_changed and mechanism_state, then flush 1. The journal gains \"The harbor bell was struck.\"",
	},
	{
		"id": "bell",
		"label": "Strike bell",
		"flags": {},
		"hint": "This step comes later. Press Strike bell after New game, then Strike bell again. The journal says \"The harbor bell was struck.\" harbor.bell_count is 1 and stays 1 the second time. The innkeeper line stays up.",
	},
	{
		"id": "secret",
		"label": "Tell secret",
		"flags": {},
		"hint": "Press Tell secret. Before it, the quest summary says secret role smugglers_contact — holder hidden. After it, the row names the holder and ends with (told). Save and Load keep the tell.",
	},
	{
		"id": "next",
		"label": "Next version",
		"flags": {},
		"hint": "Play until the journal appears and Continue is disabled. Press Save, then Load in next version. The status says Next version: ferry stage renamed pay_toll → toll_due. The load report lists the pay_toll to toll_due rows.",
	},
]

var _runtime: WyrdRuntime


func _dlg() -> Variant:
	return _runtime.get("dialogue")
var _host: WyrdFakeHost
var _boot := ""
var _started := false
var _slot: Dictionary = {}
var _tone: AudioStreamWAV
var _player: AudioStreamPlayer
var _status: Label
var _speaker: Label
var _body: Label
var _continue: Button
var _choices: VBoxContainer
var _journal: ItemList
var _facts: ItemList
var _load_list: ItemList
var _summary: Label
var _route_list: OptionButton
var _route_hint: Label
var _pack_path := _MANIFEST
var _saw_load := false
var _load_rows: Array = []
var _boot_diag_count := 0
var _fact_filter: LineEdit
var _events: Label
var _fact_rows: Array[Dictionary] = []
var _fact_baseline: Dictionary = {}
var _highlight_from: Dictionary = {}
var _seed: LineEdit
var _buttons: Dictionary = {}
var _local_provider = null
var _local_transport: Node
var _flags := {
	"ai_local": false,
	"apprentice": false,
	"ferry_alive": true,
	"local": false,
	"lodging": true,
	"notice": true,
	"short": false,
	"storm": false,
	"voice": false,
	"watch_alive": false,
}


func _ready() -> void:
	_build()
	_boot_pack(_MANIFEST)
	_status.text = "Press New game." if _boot.is_empty() else _boot


func boot_error() -> String:
	return _boot


func _boot_pack(path: String) -> void:
	_pack_path = path
	_runtime = WyrdRuntime.new()
	_host = WyrdFakeHost.new()
	_host.register_into(_runtime)
	# harbor_reeve is an election. New game errors without an adapter.
	_runtime.register_adapter(WyrdElectionAdapter, _Election.new())
	# smugglers_contact uses host_decides. New game errors without a callback.
	_runtime.roles.set_host_decides(func(_role: StringName, _departed: StringName) -> void:
		pass
	)
	_dlg().register_line_audio(Callable(self, &"_line_audio"))
	_runtime.facts.subscribe(&"")
	_runtime.facts.fact_changed.connect(func(_key: StringName, _old_value: Variant, _new_value: Variant) -> void: _refresh())
	_dlg().line_ready.connect(_on_line)
	_dlg().choices_ready.connect(func(_rows: Array[WyrdChoiceView]) -> void: _refresh())
	_dlg().scene_ended.connect(func(_id: String, _status: StringName, _reason: StringName) -> void: _refresh())
	_runtime.quests.journal_entry_added.connect(func(_quest: String, _id: String, _text: String) -> void: _refresh())
	_runtime.load_report_ready.connect(_on_load_report)
	var report := _runtime.load_content(load(path) as WyrdContentManifest)
	_boot = "" if report.ok else report.diagnostics.format()
	_boot_diag_count = report.diagnostics.items.size()
	_saw_load = false
	_load_rows = []
	if _boot.is_empty():
		_register_harbor_whisper()
	_paint_load_report()


func _on_load_report(report: WyrdLoadReport) -> void:
	_saw_load = true
	_load_rows = report.rows.duplicate(true)
	_paint_load_report()


func new_game(seed_value: int) -> void:
	if _pack_path != _MANIFEST:
		_boot_pack(_MANIFEST)
	if not _boot.is_empty():
		return
	_begin_step()
	_place_entities()
	_runtime.start_new_game(seed_value)
	_runtime.roles.assign(&"tavern_owner", &"tavern_owner")
	_runtime.roles.assign(&"ferry_master", &"ferry_master")
	_runtime.roles.assign(&"storm_watcher", &"storm_watcher")
	if bool(_flags["apprentice"]):
		_arm_apprentice()
	_runtime.facts.set(&"player.coins", 0 if bool(_flags["short"]) else 4)
	# The lookout cast reads world.storm_heard. A false rumour leaves the slot
	# empty, and on_empty: wait holds gossip. Set it so the cast can pick.
	_runtime.facts.set(&"world.storm_heard", true)
	_runtime.deeds.record(&"arrived", &"player", &"", &"gullhaven")
	_apply_commands()
	_runtime.tick(0)
	if bool(_flags["watch_alive"]):
		_runtime.facts.set(&"harbor.watch_alive", true)
	_started = true
	_open_offered()
	if not bool(_flags["ferry_alive"]):
		_sync_ferry()
	_status.text = "New game, seed %d." % seed_value
	_refresh()
	_end_step()


func press_continue() -> void:
	_begin_step()
	if _dlg().line() != null:
		_dlg().advance()
	_open_offered()
	_refresh()
	_end_step()


func press_choice(label: String) -> bool:
	_begin_step()
	for view in _dlg().choices():
		if view.text == label and view.enabled:
			_dlg().choose(view.index)
			_open_offered()
			_refresh()
			_end_step()
			return true
	_end_step()
	return false


func line_text() -> String:
	var line: Variant = _dlg().line()
	if line == null:
		return ""
	return line.text


func speaker_text() -> String:
	if _speaker == null:
		return ""
	return _speaker.text


func ai_provider_id() -> String:
	if _runtime == null or _runtime.ai == null:
		return ""
	return String(_runtime.ai.provider_id())


func status_text() -> String:
	if _status == null:
		return ""
	return _status.text


func line_has_audio() -> bool:
	var line: Variant = _dlg().line()
	return line != null and line.audio != null


func fact_value(key: String) -> String:
	var value: Variant = _runtime.facts.get(StringName(key))
	if value == null:
		return ""
	return str(value)


func quest_stage() -> String:
	return _runtime.quests.stage("ferry_toll")


func journal_count() -> int:
	return _runtime.quests.journal("ferry_toll").size()


func set_flag(name: String, on: bool) -> void:
	var previous := bool(_flags.get(name, false))
	if name == "ai_local" and previous == on:
		return
	_begin_step()
	_flags[name] = on
	var button: CheckButton = _buttons.get(name) as CheckButton
	if button != null:
		button.set_pressed_no_signal(on)
	if name == "ai_local":
		_apply_local_ai(on)
		_refresh()
		_end_step()
		return
	if name == "voice" or not _started:
		_refresh()
		_end_step()
		return
	_place_entities()
	_apply_commands()
	if name == "ferry_alive" or name == "apprentice":
		_sync_ferry()
	if name == "short":
		_runtime.facts.set(&"player.coins", 0 if on else 4)
	if name == "watch_alive" and on:
		_runtime.facts.set(&"harbor.watch_alive", true)
	_refresh()
	_end_step()


func emit_alive() -> void:
	_begin_step()
	_host.world.add_entity(&"ferry_master", &"person", _FERRY_NAME, PackedStringArray(), false)
	_runtime.events.emit(&"entity_alive_changed", {"alive": false, "entity": &"ferry_master"})
	_status.text = "Emitted entity_alive_changed."
	_refresh()
	_end_step()


func batch_world() -> void:
	_begin_step()
	_flags["storm"] = true
	var storm: CheckButton = _buttons.get("storm") as CheckButton
	if storm != null:
		storm.set_pressed_no_signal(true)
	_host.clock.season_name = &"storm"
	_runtime.events.begin_batch()
	_runtime.events.emit(&"season_changed", {})
	_runtime.events.emit(&"mechanism_state", {"actor": &"player", "object": &"dock_bell", "state": &"struck"})
	_runtime.events.end_batch()
	_status.text = "Batched season_changed and mechanism_state."
	_refresh()
	_end_step()


func strike_bell() -> void:
	_begin_step()
	_runtime.events.emit(&"mechanism_state", {"actor": &"player", "object": &"dock_bell", "state": &"struck"})
	_status.text = "Emitted mechanism_state."
	_refresh()
	_end_step()


func advance_time() -> void:
	_begin_step()
	_runtime.tick(60)
	_open_offered()
	_status.text = "Advanced 60 minutes. %s." % WyrdText.game_date(_runtime.now_minutes())
	_refresh()
	_end_step()


func save_game() -> bool:
	if not _runtime.can_save():
		_status.text = "Can't save during a conversation. Finish it, or press Abort scene."
		return false
	var data := _runtime.save_state()
	if data.is_empty():
		_status.text = "Save was refused."
		return false
	_slot = data.duplicate(true)
	var file := FileAccess.open(_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		_status.text = "Could not write user://playtest_save.json."
		return false
	file.store_string(JSON.stringify(data))
	_status.text = "Saved in memory and user://playtest_save.json."
	return true


func load_game() -> bool:
	_begin_step()
	if _dlg().is_open():
		_dlg().abort(&"load")
	var parsed: Variant = null
	if FileAccess.file_exists(_SAVE_PATH):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(_SAVE_PATH))
	var data: Dictionary = parsed if parsed is Dictionary else _slot
	if data.is_empty():
		_status.text = "Nothing to load."
		_end_step()
		return false
	var report := _runtime.load_state(data)
	if not report.ok:
		_status.text = report.diagnostics.format()
		_end_step()
		return false
	_started = true
	_open_offered()
	_status.text = "Loaded."
	_refresh()
	_end_step()
	return true


func load_next_version() -> bool:
	if _slot.is_empty():
		_status.text = "Save first."
		return false
	_begin_step()
	_boot_pack(_NEXT_MANIFEST)
	if not _boot.is_empty():
		_status.text = _boot
		_end_step()
		return false
	_place_entities()
	var report := _runtime.load_state(_slot)
	_started = report.ok
	_open_offered()
	if report.ok:
		_status.text = "Next version: ferry stage renamed pay_toll → toll_due."
	else:
		_status.text = report.diagnostics.format()
	_refresh()
	_end_step()
	return report.ok


func tell_secret() -> void:
	if _runtime == null or not _boot.is_empty():
		return
	_runtime.roles.tell(&"smugglers_contact", &"player")
	_status.text = "Told the player who holds smugglers_contact."
	_refresh()


func reset_play() -> void:
	_begin_step()
	if _pack_path != _MANIFEST:
		_boot_pack(_MANIFEST)
	_slot.clear()
	if FileAccess.file_exists(_SAVE_PATH):
		DirAccess.remove_absolute(_SAVE_PATH)
	_started = false
	_runtime.start_new_game(0)
	_speaker.text = ""
	_body.text = ""
	_status.text = "Reset."
	_refresh()
	_end_step()


func _unhandled_input(event: InputEvent) -> void:
	var accept := event.is_action_pressed(&"ui_accept")
	var space := false
	if event is InputEventKey:
		var pressed := event as InputEventKey
		space = pressed.pressed and not pressed.echo and pressed.keycode == KEY_SPACE
	if (accept or space) and not _continue.disabled:
		press_continue()
		get_viewport().set_input_as_handled()


func _on_line(line: WyrdLineView) -> void:
	if line.audio is AudioStream and DisplayServer.get_name() != "headless":
		_player.stream = line.audio
		_player.play()
	_refresh()


func _line_audio(_line_id: String, _locale: String) -> Variant:
	if not bool(_flags["voice"]):
		return null
	if _tone == null:
		_tone = AudioStreamWAV.new()
		_tone.format = AudioStreamWAV.FORMAT_8_BITS
		_tone.mix_rate = 22050
		_tone.stereo = false
		var data := PackedByteArray()
		data.resize(2205)
		for i in data.size():
			var sample := sin(TAU * 440.0 * float(i) / 22050.0)
			data[i] = clampi(int(round(128.0 + sample * 70.0)), 0, 255)
		_tone.data = data
	return _tone


func _place_entities() -> void:
	var tags := PackedStringArray()
	if bool(_flags["local"]):
		tags.append("local")
	_host.world.add_entity(&"player", &"person", "traveler", tags, true)
	_host.world.add_entity(&"tavern_owner", &"person", "innkeeper", PackedStringArray(), true)
	_host.world.add_entity(&"ferry_master", &"person", _FERRY_NAME, PackedStringArray(), true)
	_host.world.add_entity(&"storm_watcher", &"person", "watcher", PackedStringArray(), true)
	_host.world.add_entity(&"dock_apprentice", &"person", _SUCCESSOR_NAME, PackedStringArray(), true)
	_host.world.add_entity(&"dock.bell", &"object", "bell", PackedStringArray(), true)


func _apply_commands() -> void:
	if bool(_flags["lodging"]):
		_host.actions.results_by_name.erase(&"assign_lodging")
	else:
		_host.actions.set_result_for(&"assign_lodging", WyrdCommandResult.failed(&"full"))
	if bool(_flags["notice"]):
		_host.actions.results_by_name.erase(&"post_notice")
	else:
		_host.actions.set_result_for(&"post_notice", WyrdCommandResult.failed(&"lost"))
	_host.clock.season_name = &"storm" if bool(_flags["storm"]) else &""
	# New game reads facts while it is still starting, which caches world.season.
	# The event drops that cache so the clock above is what the lines see.
	_runtime.events.emit(&"season_changed", {})


func _register_harbor_whisper() -> void:
	var policy := WyrdRumorPolicy.new()
	policy.id = &"harbor_whisper"
	policy.kinds = PackedStringArray(["apprentice"])
	policy.max_hops = 2
	policy.verbs = PackedStringArray(["whispered"])
	policy.pass_chance = 1.0
	_runtime.register_rumor_policy(policy)


func _arm_apprentice() -> void:
	_runtime.roles.define(&"ferry_master", "relation(apprentice)")
	_runtime.social.set_kind(&"ferry_master", &"dock_apprentice", &"apprentice")


func _sync_ferry() -> void:
	if bool(_flags["apprentice"]):
		_arm_apprentice()
	var alive := bool(_flags["ferry_alive"])
	if bool(_flags["ferry_alive"]):
		_host.world.add_entity(&"ferry_master", &"person", _FERRY_NAME, PackedStringArray(), true)
		_runtime.roles.assign(&"ferry_master", &"ferry_master")
	else:
		_host.world.add_entity(&"ferry_master", &"person", _FERRY_NAME, PackedStringArray(), false)
		_runtime.roles.vacate(&"ferry_master", &"died")
	_runtime.events.emit(&"entity_alive_changed", {"alive": alive, "entity": &"ferry_master"})


func _open_offered() -> void:
	if _dlg().is_open():
		return
	var scene_id := _runtime.quests.offered_scene("ferry_toll")
	if not scene_id.is_empty():
		_dlg().open_scene(scene_id)


func _refresh() -> void:
	if _body == null or _runtime == null:
		return
	var line: Variant = _dlg().line()
	if line != null:
		_speaker.text = line.display_name
		if line.text_source == &"ai":
			_speaker.text = "%s (AI)" % line.display_name
		_body.text = line.text
		_continue.disabled = false
	else:
		_continue.disabled = true
	# pressed is still emitting when a choice calls choose(). choose() emits
	# line_ready / choices_ready before that handler returns, and those
	# listeners call _refresh. free() on the button that is emitting is
	# "Attempted to free a locked object". Remove it now and delete next frame.
	while _choices.get_child_count() > 0:
		var child := _choices.get_child(0)
		_choices.remove_child(child)
		if child.is_queued_for_deletion():
			continue
		child.queue_free()
	for view in _dlg().choices():
		var button := Button.new()
		button.text = view.text if view.enabled else "%s (%s)" % [view.text, view.reason]
		button.disabled = not view.enabled
		button.add_theme_color_override("font_disabled_color", Color(0.45, 0.45, 0.45))
		var index: int = int(view.index)
		# bind copies the index. A loop lambda would share the last value.
		button.pressed.connect(_choose_pressed.bind(button, index))
		_choices.add_child(button)
	_fill_journal_list()
	if _events != null:
		_events.text = _events_text()
	_paint_inspector()


## Full playtest state. The visual harness writes this to state.jsonl.
## It is not the rows currently drawn in the fact list: a filter can hide those.
func inspector_state() -> Dictionary:
	return {
		"facts": _world_facts(),
		"alive": _alive_facts(),
		"cache": _cache_facts(),
		"events": _event_rows(),
		"rechecks": _runtime.last_rechecks(),
		"flush": _runtime.events.last_wave,
		"invalidated": _string_list(_runtime.events.last_keys),
		"quest": _quest_fields(),
		"outcomes": {"crossing": _shown(_runtime.quests.outcome(_QUEST_ID, "crossing"))},
		"slots": _slot_records(),
		"journal": _journal_records(),
		"load_report": _load_rows.duplicate(true),
	}


func _paint_inspector() -> void:
	if _summary == null or _facts == null:
		return
	var state := inspector_state()
	_summary.text = _summary_text(state)
	_paint_load_report()
	_fact_rows.clear()
	var facts: Dictionary = state["facts"]
	for key in facts.keys():
		var fact_key := String(key)
		var fact_value := String(facts[key])
		_fact_rows.append(_fact_row(fact_key, fact_value, "world %s = %s" % [fact_key, fact_value]))
	var alive: Dictionary = state["alive"]
	for key in alive.keys():
		var entity_id := String(key)
		var alive_value := String(alive[key])
		_fact_rows.append(_fact_row("alive %s" % entity_id, alive_value, "alive %s = %s" % [entity_id, alive_value]))
	var cache: Dictionary = state["cache"]
	for key in cache.keys():
		var cache_key := String(key)
		var cache_value := String(cache[key])
		_fact_rows.append(_fact_row("cache %s" % cache_key, cache_value, "cache %s = %s" % [cache_key, cache_value]))
	_fill_fact_list()


func _summary_text(state: Dictionary) -> String:
	var lines := PackedStringArray()
	var quest: Dictionary = state["quest"]
	lines.append("quest %s" % String(quest["title"]))
	lines.append("stage %s" % String(quest["stage"]))
	lines.append("status %s" % String(quest["status"]))
	var outcomes: Dictionary = state["outcomes"]
	for key in outcomes.keys():
		lines.append("outcome %s = %s" % [String(key), String(outcomes[key])])
	lines.append("waiting %s" % String(quest["waiting"]))
	var slots: Array = state["slots"]
	for item in slots:
		var slot := item as Dictionary
		lines.append("slot %s — %s — %s — %s" % [String(slot["name"]), String(slot["role"]), String(slot["holder"]), String(slot["state"])])
	lines.append(_secret_row())
	return "\n".join(lines)


func _world_facts() -> Dictionary:
	var facts := {}
	var content := _runtime.content()
	if content == null or content.schema == null:
		return facts
	for fact in content.schema.entries:
		if fact.is_pattern():
			continue
		var key := String(fact.key)
		facts[key] = _shown(_runtime.facts.get(StringName(key)))
	return facts


func _alive_facts() -> Dictionary:
	# Live world state. Cache rows show the resolved npc.{id}.alive values.
	var alive := {}
	for entity_id in ["player", "ferry_master", "tavern_owner", "dock_apprentice"]:
		var id := StringName(entity_id)
		var value := "absent"
		if _host.world.exists(id):
			value = "true" if _host.world.is_alive(id) else "false"
		alive[entity_id] = value
	return alive


func _quest_fields() -> Dictionary:
	# pay_toll is the stage. The quest id is ferry_toll; the panel shows the title.
	var title := _QUEST_ID
	var content := _runtime.content()
	if content != null:
		var quest := content.quests.get(_QUEST_ID) as WyrdQuestDef
		if quest != null and not quest.title.is_empty():
			title = quest.title
	return {
		"id": _QUEST_ID,
		"title": title,
		"stage": _shown(_runtime.quests.stage(_QUEST_ID)),
		"status": _shown(String(_runtime.quests.status(_QUEST_ID))),
		"waiting": _shown(_runtime.quests.waiting_reason(_QUEST_ID)),
	}


func _slot_records() -> Array:
	# A role id is a symbol. The grammar has no title, so the readable title
	# is that id with spaces. The state is the runtime slot state
	# (default, successor, empty, hostile), not the slot mode (live, locked_at, cast).
	var rows: Array = []
	var content := _runtime.content()
	if content == null:
		return rows
	var quest := content.quests.get(_QUEST_ID) as WyrdQuestDef
	if quest == null:
		return rows
	for slot in quest.slots:
		var holder_id := _runtime.roles.slot_holder(_QUEST_ID, StringName(slot.name))
		var holder_name := "none"
		if holder_id != &"":
			holder_name = _host.world.display_name(holder_id)
			if holder_name.is_empty():
				holder_name = String(holder_id)
		var title := slot.role.replace("_", " ")
		var state := _shown(String(_runtime.roles.slot_state(StringName(slot.name), _QUEST_ID)))
		rows.append({
			"name": String(slot.name),
			"role": title,
			"holder": holder_name,
			"state": state,
		})
	return rows


func _journal_records() -> Array:
	var rows: Array = []
	_append_journal(rows, _QUEST_ID)
	var content := _runtime.content()
	if content == null:
		return rows
	var ids: Array = content.quests.keys()
	ids.sort()
	for quest_id in ids:
		if String(quest_id) == _QUEST_ID:
			continue
		_append_journal(rows, String(quest_id))
	return rows


func _fill_journal_list() -> void:
	if _journal == null or _runtime == null:
		return
	_journal.clear()
	var content := _runtime.content()
	if content == null:
		return
	var ids: Array = []
	ids.append(_QUEST_ID)
	var rest: Array = content.quests.keys()
	rest.sort()
	for quest_id in rest:
		if String(quest_id) == _QUEST_ID:
			continue
		ids.append(String(quest_id))
	for quest_id in ids:
		var entries: Array = _runtime.quests.journal(String(quest_id))
		if entries.is_empty():
			continue
		var header := "%s — %s" % [_quest_title(String(quest_id)), _shown(String(_runtime.quests.status(String(quest_id))))]
		_journal.add_item(header)
		_journal.set_item_selectable(_journal.item_count - 1, false)
		for entry in entries:
			_journal.add_item("%s  %s" % [String(entry["date"]), String(entry["text"])])


func _quest_title(quest_id: String) -> String:
	var content := _runtime.content()
	if content == null:
		return quest_id
	var quest := content.quests.get(quest_id) as WyrdQuestDef
	if quest != null and not quest.title.is_empty():
		return quest.title
	return quest_id


func _secret_row() -> String:
	if _runtime == null or not _boot.is_empty():
		return "secret role smugglers_contact — holder hidden"
	var told := _runtime.roles.revealed(&"player", &"role.smugglers_contact.holder")
	if not told:
		return "secret role smugglers_contact — holder hidden"
	var holder := _runtime.roles.holder(&"smugglers_contact")
	var holder_name := "none"
	if holder != &"":
		holder_name = _host.world.display_name(holder)
		if holder_name.is_empty():
			holder_name = String(holder)
	return "secret role smugglers_contact — %s (told)" % holder_name


func _paint_load_report() -> void:
	if _load_list == null:
		return
	_load_list.clear()
	if not _saw_load:
		if _boot.is_empty():
			_load_list.add_item("Content loaded.")
		else:
			_load_list.add_item("%d diagnostics" % _boot_diag_count)
		return
	if _load_rows.is_empty():
		_load_list.add_item("No changes.")
		return
	for row in _load_rows:
		_load_list.add_item(_format_load_row(row))


func _format_load_row(row: Dictionary) -> String:
	var parts := PackedStringArray()
	var kind := String(row.get("kind", ""))
	if not kind.is_empty():
		parts.append(kind)
	var id := String(row.get("id", ""))
	if not id.is_empty():
		parts.append(id)
	var from_id := String(row.get("from", ""))
	var to_id := String(row.get("to", ""))
	if not from_id.is_empty() or not to_id.is_empty():
		parts.append("%s → %s" % [from_id, to_id])
	var count := int(row.get("count", 0))
	if count != 0:
		parts.append("×%d" % count)
	var code := String(row.get("code", ""))
	if not code.is_empty():
		parts.append(code)
	return " ".join(parts)


func _append_journal(rows: Array, quest_id: String) -> void:
	for entry in _runtime.quests.journal(quest_id):
		rows.append({
			"date": String(entry["date"]),
			"text": String(entry["text"]),
		})


func _cache_facts() -> Dictionary:
	var rows := {}
	var content := _runtime.content()
	if content == null or content.schema == null:
		return rows
	for fact in content.schema.entries:
		if fact.origin != &"resolved":
			continue
		if fact.is_pattern():
			if fact.key == "npc.{id}.alive":
				for entity_id in ["dock_apprentice", "ferry_master", "player", "storm_watcher", "tavern_owner"]:
					var concrete := "npc.%s.alive" % String(entity_id)
					rows[concrete] = _cache_label(_runtime.facts.cache_view(concrete))
			continue
		rows[fact.key] = _cache_label(_runtime.facts.cache_view(fact.key))
	return rows


func _cache_label(view: Dictionary) -> String:
	var mode := String(view.get("mode", "absent"))
	var event := String(view.get("event", "")).strip_edges()
	if event.is_empty():
		return mode if not mode.is_empty() else "absent"
	return "%s %s" % [mode, event]


func _event_rows() -> Array:
	var rows: Array = []
	for item in _runtime.events.recent:
		var payload: Variant = item.get("payload", {})
		rows.append({
			"id": int(item.get("id", 0)),
			"name": String(item.get("name", "")),
			"payload": payload if payload is Dictionary else {},
			"time": int(item.get("time", 0)),
		})
	return rows


func _events_text() -> String:
	var parts := PackedStringArray()
	for item in _event_rows():
		var row := item as Dictionary
		var bits := PackedStringArray()
		var payload: Dictionary = row.get("payload", {})
		var keys: Array = payload.keys()
		keys.sort()
		for key in keys:
			bits.append("%s=%s" % [String(key), str(payload[key])])
		var name := String(row.get("name", ""))
		if bits.is_empty():
			parts.append(name)
		else:
			parts.append("%s %s" % [name, ", ".join(bits)])
	var flush := int(_runtime.events.last_wave)
	if parts.is_empty():
		return "flush %d" % flush
	return "%s  flush %d" % [" | ".join(parts), flush]


func _string_list(keys: PackedStringArray) -> Array:
	var rows: Array = []
	for key in keys:
		rows.append(String(key))
	return rows


func _fact_row(key: String, value: String, text: String) -> Dictionary:
	var had := _highlight_from.has(key)
	var previous := String(_highlight_from.get(key, ""))
	var changed := had and previous != value
	return {"key": key, "value": value, "text": text, "changed": changed}


func _fill_fact_list() -> void:
	_facts.clear()
	var query := ""
	if _fact_filter != null:
		query = _fact_filter.text.strip_edges().to_lower()
	for row in _fact_rows:
		var key := String(row["key"]).to_lower()
		var value := String(row["value"]).to_lower()
		var text := String(row["text"]).to_lower()
		if not query.is_empty() and not key.contains(query) and not value.contains(query) and not text.contains(query):
			continue
		_facts.add_item(String(row["text"]))
		if bool(row["changed"]):
			var index := _facts.item_count - 1
			_facts.set_item_custom_bg_color(index, _CHANGED_BG)
			_facts.set_item_custom_fg_color(index, Color(1, 0.96, 0.88))


func _on_fact_filter(_text: String) -> void:
	if _facts == null:
		return
	_fill_fact_list()


func _begin_step() -> void:
	_highlight_from = _fact_baseline.duplicate()


func _end_step() -> void:
	_fact_baseline.clear()
	for row in _fact_rows:
		_fact_baseline[String(row["key"])] = String(row["value"])


func _shown(value: Variant) -> String:
	# null is a fact that was never set. An empty name is the same on screen:
	# time.season is "" until a season is chosen, and str("") would leave the
	# row blank. Both read as absent.
	if value == null:
		return "absent"
	var text := str(value).strip_edges()
	if text.is_empty():
		return "absent"
	return text


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.12, 0.13, 0.16)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)
	_status = Label.new()
	_status.name = "StatusLine"
	_status.text = "Loading Gullhaven."
	root.add_child(_status)
	root.add_child(_controls())
	root.add_child(_world_buttons())
	root.add_child(_routes())
	root.add_child(_toggles())
	_events = Label.new()
	_events.name = "Events"
	_events.text = "flush 0"
	_events.clip_text = true
	_events.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_events.custom_minimum_size = Vector2(200, 22)
	root.add_child(_events)
	var columns := HSplitContainer.new()
	columns.name = "Columns"
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12)
	root.add_child(columns)
	columns.add_child(_dialogue())
	columns.add_child(_side())
	_player = AudioStreamPlayer.new()
	add_child(_player)


func _controls() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Controls"
	row.add_theme_constant_override("separation", 8)
	_seed = LineEdit.new()
	_seed.placeholder_text = "seed"
	_seed.text = "1"
	_seed.custom_minimum_size = Vector2(80, 0)
	row.add_child(_seed)
	row.add_child(_button("New game", func() -> void:
		var seed_value := 1
		if _seed.text.is_valid_int():
			seed_value = int(_seed.text)
		new_game(seed_value)
	))
	row.add_child(_button("Advance time", advance_time))
	row.add_child(_button("Save", func() -> void: save_game()))
	row.add_child(_button("Load", func() -> void: load_game()))
	row.add_child(_button("Load in next version", load_next_version))
	row.add_child(_button("Reset", reset_play))
	row.add_child(_button("Abort scene", func() -> void:
		if _dlg().is_open():
			_begin_step()
			_dlg().abort(&"left")
			_status.text = "Aborted. You can save."
			_refresh()
			_end_step()
	))
	return row


func _world_buttons() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "WorldEvents"
	row.add_theme_constant_override("separation", 8)
	row.add_child(_button("Emit alive", emit_alive))
	row.add_child(_button("Batch world", batch_world))
	row.add_child(_button("Strike bell", strike_bell))
	row.add_child(_button("Tell secret", tell_secret))
	return row


func _routes() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Routes"
	row.add_theme_constant_override("separation", 8)
	var list := OptionButton.new()
	list.name = "RouteList"
	list.clip_text = true
	list.custom_minimum_size = Vector2(160, 0)
	for route in _ROUTES:
		list.add_item(String(route["label"]))
	row.add_child(list)
	_route_list = list
	row.add_child(_button("Start route", _start_selected_route))
	_route_hint = Label.new()
	_route_hint.name = "RouteHint"
	_route_hint.clip_text = true
	_route_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_route_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_route_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_route_hint)
	return row


func _start_selected_route() -> void:
	if _route_list == null:
		return
	var index := _route_list.selected
	if index < 0 or index >= _ROUTES.size():
		return
	var route: Dictionary = _ROUTES[index]
	var flags: Dictionary = route["flags"]
	for key in _flags.keys():
		var value := bool(_ROUTE_DEFAULTS[key])
		if flags.has(key):
			value = bool(flags[key])
		set_flag(String(key), value)
	_route_hint.text = String(route["hint"])
	var seed_value := 1
	if _seed.text.is_valid_int():
		seed_value = int(_seed.text)
	new_game(seed_value)


func _load_panel() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "LoadReport"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 0)
	var label := Label.new()
	label.text = "Load report"
	box.add_child(label)
	var scroll := ScrollContainer.new()
	scroll.name = "LoadReportScroll"
	scroll.custom_minimum_size = Vector2(0, 28)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var list := ItemList.new()
	list.name = "LoadReportList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.fixed_icon_size = Vector2i(0, 0)
	list.custom_minimum_size = Vector2(0, 28)
	scroll.add_child(list)
	box.add_child(scroll)
	_load_list = list
	return box


func _toggles() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "Toggles"
	box.add_theme_constant_override("separation", 2)
	var specs: Array[Array] = [
		["ferry_alive", "Ferry master alive"],
		["local", "Local tag"],
		["lodging", "Lodging available"],
		["notice", "Notice succeeds"],
		["storm", "Season storm"],
		["apprentice", "Apprentice ready"],
		["short", "Short on coins"],
		["voice", "Voice"],
		["watch_alive", "Watch alive"],
		["ai_local", "Local AI flavor"],
	]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for i in specs.size():
		if i == 4 or i == 9:
			box.add_child(row)
			row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
		var spec: Array = specs[i]
		var toggle := CheckButton.new()
		var key := String(spec[0])
		toggle.name = "Toggle_%s" % key
		toggle.text = String(spec[1])
		toggle.button_pressed = bool(_flags[key])
		toggle.toggled.connect(_flag_toggled.bind(key))
		_buttons[key] = toggle
		row.add_child(toggle)
	box.add_child(row)
	return box


func _dialogue() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = "Dialogue"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	_speaker = Label.new()
	_speaker.add_theme_font_size_override("font_size", 18)
	column.add_child(_speaker)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(360, 80)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("font_size", 22)
	column.add_child(_body)
	_continue = _button("Continue", press_continue)
	_continue.name = "Continue"
	_continue.disabled = true
	column.add_child(_continue)
	_choices = VBoxContainer.new()
	_choices.name = "Choices"
	column.add_child(_choices)
	return column


func _side() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = "Side"
	column.custom_minimum_size = Vector2(320, 0)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	var journal_label := Label.new()
	journal_label.text = "Journal"
	column.add_child(journal_label)
	column.add_child(_scroll_list("Journal", 28))
	# Quest, stage, status, outcome, waiting, and slots stay on screen.
	# The fact list below them scrolls, and a filter can hide rows.
	_summary = Label.new()
	_summary.name = "QuestSummary"
	_summary.add_theme_font_size_override("font_size", 14)
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	column.add_child(_summary)
	column.add_child(_load_panel())
	_fact_filter = LineEdit.new()
	_fact_filter.name = "FactFilter"
	_fact_filter.placeholder_text = "Filter facts"
	_fact_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fact_filter.text_changed.connect(_on_fact_filter)
	column.add_child(_fact_filter)
	column.add_child(_scroll_list("Fact", 32))
	return column


func _scroll_list(title: String, min_height: int) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "%sScroll" % title
	scroll.custom_minimum_size = Vector2(0, min_height)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := ItemList.new()
	list.name = "%sList" % title
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	if title == "Journal":
		_journal = list
	else:
		_facts = list
	return scroll


func _choose_pressed(button: Button, index: int) -> void:
	# pressed.emit() still fires when the button is disabled. choose() errors then.
	if button.disabled:
		return
	_begin_step()
	_dlg().choose(index)
	_open_offered()
	_refresh()
	_end_step()


func _apply_local_ai(on: bool) -> void:
	if _runtime == null:
		return
	if not on:
		_runtime.register_adapter(WyrdAIProvider, WyrdNullAIProvider.new())
		_status.text = "Local AI flavor off."
		return
	if _local_provider == null:
		_local_transport = _LocalTransport.new()
		_local_transport.name = "LocalAITransport"
		add_child(_local_transport)
		_local_provider = _LocalProvider.new()
		_local_provider.attach(_local_transport)
	_local_provider.bind_trace(_runtime)
	var url := OS.get_environment("WYRD_LOCAL_AI_URL")
	if not url.is_empty() and not bool(_local_provider.set_base_url(url)):
		_status.text = "Local AI flavor: %s is not a loopback address. Use 127.0.0.1 or localhost." % url
		return
	var model := OS.get_environment("WYRD_LOCAL_AI_MODEL")
	if not model.is_empty():
		if not str(_LocalProvider.check_model(model)).is_empty():
			_status.text = "Local AI flavor: model %s is refused because it names a cloud model." % model
			return
		_local_provider.model = model
	_runtime.register_adapter(WyrdAIProvider, _local_provider as WyrdAIProvider)
	var base := String(_local_provider.base_url)
	var shown := String(_local_provider.model)
	_status.text = "Local AI flavor: checking %s." % base
	_local_provider.probe(func(ok: bool, _reason: String) -> void:
		if not bool(_flags.get("ai_local", false)):
			return
		if ok:
			_status.text = "Local AI flavor on: %s at %s." % [shown, base]
		else:
			_status.text = "Local AI flavor: server not reachable at %s." % base
	)


func _flag_toggled(on: bool, key: String) -> void:
	set_flag(key, on)


func _button(title: String, call: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.pressed.connect(call)
	return button
