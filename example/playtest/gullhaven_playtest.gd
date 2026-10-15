extends Control

## Playable Gullhaven slice. No art. Text stays on screen with or without voice.
##
## @experimental
## The host is the scripted fake host. F5 runs this scene.

const _MANIFEST := "res://example/content/gullhaven/harbor.wyrdmanifest.tres"
const _SAVE_PATH := "user://playtest_save.json"
const _FERRY_NAME := "Bram"
const _SUCCESSOR_NAME := "Nia"
const _QUEST_ID := "ferry_toll"
const _CHANGED_BG := Color(0.62, 0.42, 0.1)

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
var _summary: Label
var _fact_filter: LineEdit
var _fact_rows: Array[Dictionary] = []
var _fact_baseline: Dictionary = {}
var _highlight_from: Dictionary = {}
var _seed: LineEdit
var _buttons: Dictionary = {}
var _flags := {
	"apprentice": false,
	"ferry_alive": true,
	"local": false,
	"lodging": true,
	"notice": true,
	"short": false,
	"storm": false,
	"voice": false,
}


func _ready() -> void:
	_build()
	_runtime = WyrdRuntime.new()
	_host = WyrdFakeHost.new()
	_host.register_into(_runtime)
	_dlg().register_line_audio(Callable(self, &"_line_audio"))
	_runtime.facts.subscribe(&"")
	_runtime.facts.fact_changed.connect(func(_key: StringName, _old_value: Variant, _new_value: Variant) -> void: _refresh())
	_dlg().line_ready.connect(_on_line)
	_dlg().choices_ready.connect(func(_rows: Array[WyrdChoiceView]) -> void: _refresh())
	_dlg().scene_ended.connect(func(_id: String, _status: StringName, _reason: StringName) -> void: _refresh())
	_runtime.quests.journal_entry_added.connect(func(_quest: String, _id: String, _text: String) -> void: _refresh())
	var report := _runtime.load_content(load(_MANIFEST) as WyrdContentManifest)
	_boot = "" if report.ok else report.diagnostics.format()
	_status.text = "Press New game." if _boot.is_empty() else _boot


func boot_error() -> String:
	return _boot


func new_game(seed_value: int) -> void:
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
	_runtime.deeds.record(&"arrived", &"player", &"", &"gullhaven")
	_apply_commands()
	_runtime.tick(0)
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
	_begin_step()
	_flags[name] = on
	var button: CheckButton = _buttons.get(name) as CheckButton
	if button != null:
		button.set_pressed_no_signal(on)
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


func reset_play() -> void:
	_begin_step()
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


func _arm_apprentice() -> void:
	_runtime.roles.define(&"ferry_master", "relation(apprentice)")
	_runtime.social.set_kind(&"ferry_master", &"dock_apprentice", &"apprentice")


func _sync_ferry() -> void:
	if bool(_flags["apprentice"]):
		_arm_apprentice()
	if bool(_flags["ferry_alive"]):
		_host.world.add_entity(&"ferry_master", &"person", _FERRY_NAME, PackedStringArray(), true)
		_runtime.roles.assign(&"ferry_master", &"ferry_master")
		return
	_host.world.add_entity(&"ferry_master", &"person", _FERRY_NAME, PackedStringArray(), false)
	_runtime.roles.vacate(&"ferry_master", &"died")


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
	_journal.clear()
	for entry in _runtime.quests.journal("ferry_toll"):
		_journal.add_item("%s  %s" % [String(entry["date"]), String(entry["text"])])
	_paint_inspector()


## Full playtest state. The visual harness writes this to state.jsonl.
## It is not the rows currently drawn in the fact list: a filter can hide those.
func inspector_state() -> Dictionary:
	return {
		"facts": _world_facts(),
		"alive": _alive_facts(),
		"quest": _quest_fields(),
		"outcomes": {"crossing": _shown(_runtime.quests.outcome(_QUEST_ID, "crossing"))},
		"slots": _slot_records(),
		"journal": _journal_records(),
	}


func _paint_inspector() -> void:
	if _summary == null or _facts == null:
		return
	var state := inspector_state()
	_summary.text = _summary_text(state)
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
	# Live world state. A resolved npc.{id}.alive fact with no invalidate stays cached.
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
	for entry in _runtime.quests.journal(_QUEST_ID):
		rows.append({
			"date": String(entry["date"]),
			"text": String(entry["text"]),
		})
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
	root.add_child(_toggles())
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
	]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for i in specs.size():
		if i == 4:
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
	column.add_theme_constant_override("separation", 8)
	var journal_label := Label.new()
	journal_label.text = "Journal"
	column.add_child(journal_label)
	column.add_child(_scroll_list("Journal", 72))
	# Quest, stage, status, outcome, waiting, and slots stay on screen.
	# The fact list below them scrolls, and a filter can hide rows.
	_summary = Label.new()
	_summary.name = "QuestSummary"
	_summary.add_theme_font_size_override("font_size", 14)
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	column.add_child(_summary)
	_fact_filter = LineEdit.new()
	_fact_filter.name = "FactFilter"
	_fact_filter.placeholder_text = "Filter facts"
	_fact_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fact_filter.text_changed.connect(_on_fact_filter)
	column.add_child(_fact_filter)
	column.add_child(_scroll_list("Fact", 80))
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


func _flag_toggled(on: bool, key: String) -> void:
	set_flag(key, on)


func _button(title: String, call: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.pressed.connect(call)
	return button
