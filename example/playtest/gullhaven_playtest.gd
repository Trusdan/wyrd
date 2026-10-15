extends Control

## Playable Gullhaven slice. No art. Text stays on screen with or without voice.
##
## @experimental
## The host is the scripted fake host. F5 runs this scene.

const _MANIFEST := "res://example/content/gullhaven/harbor.wyrdmanifest.tres"
const _SAVE_PATH := "user://playtest_save.json"

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


func press_continue() -> void:
	if _dlg().line() != null:
		_dlg().advance()
	_open_offered()
	_refresh()


func press_choice(label: String) -> bool:
	for view in _dlg().choices():
		if view.text == label and view.enabled:
			_dlg().choose(view.index)
			_open_offered()
			_refresh()
			return true
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
	_flags[name] = on
	var button: CheckButton = _buttons.get(name) as CheckButton
	if button != null:
		button.set_pressed_no_signal(on)
	if name == "voice" or not _started:
		_refresh()
		return
	_place_entities()
	_apply_commands()
	if name == "ferry_alive" or name == "apprentice":
		_sync_ferry()
	if name == "short":
		_runtime.facts.set(&"player.coins", 0 if on else 4)
	_refresh()


func advance_time() -> void:
	_runtime.tick(60)
	_open_offered()
	_status.text = "Advanced 60 minutes. %s." % WyrdText.game_date(_runtime.now_minutes())
	_refresh()


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
	if _dlg().is_open():
		_dlg().abort(&"load")
	var parsed: Variant = null
	if FileAccess.file_exists(_SAVE_PATH):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(_SAVE_PATH))
	var data: Dictionary = parsed if parsed is Dictionary else _slot
	if data.is_empty():
		_status.text = "Nothing to load."
		return false
	var report := _runtime.load_state(data)
	if not report.ok:
		_status.text = report.diagnostics.format()
		return false
	_started = true
	_open_offered()
	_status.text = "Loaded."
	_refresh()
	return true


func reset_play() -> void:
	_slot.clear()
	if FileAccess.file_exists(_SAVE_PATH):
		DirAccess.remove_absolute(_SAVE_PATH)
	_started = false
	_runtime.start_new_game(0)
	_speaker.text = ""
	_body.text = ""
	_status.text = "Reset."
	_refresh()


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
	_host.world.add_entity(&"ferry_master", &"person", "ferry master", PackedStringArray(), true)
	_host.world.add_entity(&"storm_watcher", &"person", "watcher", PackedStringArray(), true)
	_host.world.add_entity(&"dock_apprentice", &"person", "apprentice", PackedStringArray(), true)
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
	if _started:
		_runtime.events.emit(&"season_changed", {})


func _arm_apprentice() -> void:
	_runtime.roles.define(&"ferry_master", "relation(apprentice)")
	_runtime.social.set_kind(&"ferry_master", &"dock_apprentice", &"apprentice")


func _sync_ferry() -> void:
	if bool(_flags["apprentice"]):
		_arm_apprentice()
	if bool(_flags["ferry_alive"]):
		_host.world.add_entity(&"ferry_master", &"person", "ferry master", PackedStringArray(), true)
		_runtime.roles.assign(&"ferry_master", &"ferry_master")
		return
	_host.world.add_entity(&"ferry_master", &"person", "ferry master", PackedStringArray(), false)
	_runtime.roles.vacate(&"ferry_master", &"died")


func _open_offered() -> void:
	if _dlg().is_open():
		return
	var scene_id := _runtime.quests.offered_scene("ferry_toll")
	if not scene_id.is_empty():
		_dlg().open_scene(scene_id)


func _refresh() -> void:
	if _body == null:
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
	_facts.clear()
	var content := _runtime.content()
	if content != null and content.schema != null:
		for fact in content.schema.entries:
			if fact.is_pattern():
				continue
			_facts.add_item("world %s = %s" % [fact.key, _shown(_runtime.facts.get(StringName(fact.key)))])
	for entity_id in ["player", "ferry_master", "tavern_owner", "dock_apprentice"]:
		var key := "npc.%s.alive" % entity_id
		_facts.add_item("world %s = %s" % [key, _shown(_runtime.facts.get(StringName(key)))])
	_append_quest(_facts)
	_facts.add_item("outcome crossing = %s" % _runtime.quests.outcome("ferry_toll", "crossing"))
	for slot_name in ["tavern", "ferry", "lookout"]:
		_facts.add_item("slot %s = %s (%s)" % [
			slot_name,
			String(_runtime.roles.slot_holder("ferry_toll", StringName(slot_name))),
			String(_runtime.roles.slot_state(StringName(slot_name), "ferry_toll")),
		])


func _append_quest(list: ItemList) -> void:
	# pay_toll is the stage. The quest id is ferry_toll; the panel shows the title.
	var quest_id := "ferry_toll"
	var title := quest_id
	var content := _runtime.content()
	if content != null:
		var quest := content.quests.get(quest_id) as WyrdQuestDef
		if quest != null and not quest.title.is_empty():
			title = quest.title
	list.add_item("quest %s" % title)
	list.add_item("stage %s" % _runtime.quests.stage(quest_id))
	list.add_item("status %s" % String(_runtime.quests.status(quest_id)))
	var waiting := _runtime.quests.waiting_reason(quest_id)
	if not waiting.is_empty():
		list.add_item("waiting %s" % waiting)


func _shown(value: Variant) -> String:
	if value == null:
		return "absent"
	return str(value)


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
			_dlg().abort(&"left")
			_status.text = "Aborted. You can save."
			_refresh()
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
	column.add_child(_scroll_list("Journal", 120))
	var fact_label := Label.new()
	fact_label.text = "Facts, quest, slots"
	column.add_child(fact_label)
	column.add_child(_scroll_list("Fact", 180))
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
	_dlg().choose(index)
	_open_offered()
	_refresh()


func _flag_toggled(on: bool, key: String) -> void:
	set_flag(key, on)


func _button(title: String, call: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.pressed.connect(call)
	return button
