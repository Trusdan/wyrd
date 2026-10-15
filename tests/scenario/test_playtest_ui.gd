extends GutTest

const _UI := preload("res://example/playtest/gullhaven_playtest.gd")

const _PANELS: PackedStringArray = [
	"StatusLine",
	"Controls",
	"Toggles",
	"Columns",
	"Dialogue",
	"Side",
	"JournalScroll",
	"FactScroll",
	"Continue",
]


func test_choice_and_continue_signals_do_not_error() -> void:
	var routes: Array[Dictionary] = [
		{"id": "room", "choice": "Take the room", "flags": {}},
		{"id": "local-room", "choice": "Take the room", "flags": {"local": true}},
		{"id": "local-place", "choice": "I have a place in town", "flags": {"local": true}},
		{"id": "lodging-off", "choice": "Take the room", "flags": {"lodging": false}},
		{"id": "notice-off", "choice": "Take the room", "flags": {"notice": false}},
		{"id": "ferry-dead", "choice": "Take the room", "flags": {"ferry_alive": false}},
		{"id": "apprentice", "choice": "Take the room", "flags": {"apprentice": true, "ferry_alive": false}},
		{"id": "storm", "choice": "Take the room", "flags": {"storm": true}},
		{"id": "short", "choice": "Take the room", "flags": {"short": true}},
	]
	for route in routes:
		var ui := _spawn()
		var flags: Dictionary = route["flags"]
		for key in flags.keys():
			_set_toggle(ui, String(key), bool(flags[key]))
		var new_game := _button_with_text(ui, "New game")
		assert_not_null(new_game, String(route["id"]))
		new_game.pressed.emit()
		_drive_until_choice(ui, String(route["choice"]), String(route["id"]))
		assert_engine_error_count(0, String(route["id"]))
		await wait_process_frames(1)


func test_toolbar_and_toggles_do_not_error() -> void:
	var ui := _spawn()
	_press(ui, "New game")
	for _i in 3:
		var cont := _button_with_text(ui, "Continue")
		if cont != null and not cont.disabled:
			cont.pressed.emit()
	_press(ui, "Abort scene")
	_press(ui, "Save")
	_press(ui, "Advance time")
	_press(ui, "Load")
	_press(ui, "Reset")
	_press(ui, "New game")
	for key in ["ferry_alive", "local", "lodging", "notice", "storm", "apprentice", "short", "voice"]:
		var box := ui.find_child("Toggle_%s" % key, true, false) as CheckButton
		assert_not_null(box, key)
		var was := box.button_pressed
		box.toggled.emit(not was)
		box.toggled.emit(was)
	assert_engine_error_count(0, "toolbar")
	await wait_process_frames(1)


func test_quest_panel_labels_title_and_stage() -> void:
	var ui := _spawn()
	_press(ui, "New game")
	_drive_until_choice(ui, "Take the room", "quest-panel")
	var facts := ui.find_child("FactList", true, false) as ItemList
	assert_not_null(facts)
	var lines := PackedStringArray()
	for i in facts.item_count:
		lines.append(facts.get_item_text(i))
	assert_true(lines.has("quest The Ferry Toll"), "\n".join(lines))
	assert_true(lines.has("stage pay_toll"), "\n".join(lines))
	assert_true(lines.has("status active"), "\n".join(lines))
	assert_false(lines.has("quest pay_toll"))
	assert_eq(ui.quest_stage(), "pay_toll")
	var journal := ui.find_child("JournalList", true, false) as ItemList
	assert_not_null(journal)
	assert_eq(journal.get_item_text(0), "day 1, 00:00  Bram, the ferry master, at the dock wants 2 coins before the crossing.")
	assert_true(lines.has("slot tavern — tavern owner — innkeeper — default"), "\n".join(lines))
	assert_true(lines.has("slot ferry — ferry master — Bram — default"), "\n".join(lines))
	assert_true(lines.has("slot lookout — storm watcher — watcher — default"), "\n".join(lines))
	await wait_process_frames(1)


func test_slot_row_shows_a_named_successor_or_an_empty_slot() -> void:
	var successor := _spawn()
	_set_toggle(successor, "apprentice", true)
	_set_toggle(successor, "ferry_alive", false)
	_press(successor, "New game")
	_drive_until_choice(successor, "Take the room", "successor-slot")
	var successor_facts := successor.find_child("FactList", true, false) as ItemList
	assert_not_null(successor_facts)
	var successor_lines := PackedStringArray()
	for i in successor_facts.item_count:
		successor_lines.append(successor_facts.get_item_text(i))
	assert_true(successor_lines.has("slot ferry — ferry master — Nia — successor"), "\n".join(successor_lines))
	var successor_journal := successor.find_child("JournalList", true, false) as ItemList
	assert_not_null(successor_journal)
	assert_eq(successor_journal.get_item_text(0), "day 1, 00:00  Nia, the ferry master, at the dock wants 2 coins before the crossing.")
	var empty := _spawn()
	_set_toggle(empty, "ferry_alive", false)
	_press(empty, "New game")
	_drive_until_choice(empty, "Take the room", "empty-slot")
	var empty_facts := empty.find_child("FactList", true, false) as ItemList
	assert_not_null(empty_facts)
	var empty_lines := PackedStringArray()
	for i in empty_facts.item_count:
		empty_lines.append(empty_facts.get_item_text(i))
	assert_true(empty_lines.has("slot ferry — ferry master — none — empty"), "\n".join(empty_lines))
	var empty_journal := empty.find_child("JournalList", true, false) as ItemList
	assert_not_null(empty_journal)
	assert_eq(empty_journal.get_item_text(0), "day 1, 00:00  The dock is empty, so the crossing waits.")
	await wait_process_frames(1)


func test_holder_lines_name_bram_nia_or_the_empty_dock() -> void:
	var bram := _spawn()
	_press(bram, "New game")
	var opening := _read_lines(bram)
	assert_eq(_text_of(opening, "The headland bell rang twice before the rain."), "watcher")
	assert_eq(_line_named(opening, "Bram, the ferry master, is on the dock."), "watcher")
	assert_false(_has_text(opening, "The dock is empty."))
	_press_choice(bram, "Take the room")
	var rest := _read_lines(bram)
	assert_eq(_line_named(rest, "Two coins, and the boat will cross."), "Bram")
	var journal := bram.find_child("JournalList", true, false) as ItemList
	assert_eq(journal.get_item_text(0), "day 1, 00:00  Bram, the ferry master, at the dock wants 2 coins before the crossing.")
	_assert_no_missing_holder(opening)
	_assert_no_missing_holder(rest)
	var successor := _spawn()
	_set_toggle(successor, "apprentice", true)
	_set_toggle(successor, "ferry_alive", false)
	_press(successor, "New game")
	var successor_opening := _read_lines(successor)
	assert_eq(_line_named(successor_opening, "Nia, the ferry master, is on the dock."), "watcher")
	assert_false(_has_text(successor_opening, "Bram, the ferry master, is on the dock."))
	assert_false(_has_text(successor_opening, "The dock is empty."))
	_press_choice(successor, "Take the room")
	var successor_rest := _read_lines(successor)
	assert_eq(_line_named(successor_rest, "Two coins, and the boat will cross."), "Nia")
	var successor_journal := successor.find_child("JournalList", true, false) as ItemList
	assert_eq(successor_journal.get_item_text(0), "day 1, 00:00  Nia, the ferry master, at the dock wants 2 coins before the crossing.")
	_assert_no_missing_holder(successor_opening)
	_assert_no_missing_holder(successor_rest)
	var empty := _spawn()
	_set_toggle(empty, "ferry_alive", false)
	_press(empty, "New game")
	var empty_opening := _read_lines(empty)
	assert_eq(_line_named(empty_opening, "The dock is empty."), "watcher")
	assert_false(_has_text(empty_opening, "Bram, the ferry master, is on the dock."))
	_press_choice(empty, "Take the room")
	var empty_rest := _read_lines(empty)
	assert_false(_has_text(empty_rest, "Bram, the ferry master, is on the dock."))
	assert_false(_has_text(empty_rest, "Nia, the ferry master, is on the dock."))
	var empty_journal := empty.find_child("JournalList", true, false) as ItemList
	assert_eq(empty_journal.get_item_text(0), "day 1, 00:00  The dock is empty, so the crossing waits.")
	var empty_facts := empty.find_child("FactList", true, false) as ItemList
	var empty_fact_lines := PackedStringArray()
	for i in empty_facts.item_count:
		empty_fact_lines.append(empty_facts.get_item_text(i))
	assert_true(empty_fact_lines.has("alive ferry_master = false"), "\n".join(empty_fact_lines))
	_assert_no_missing_holder(empty_opening)
	_assert_no_missing_holder(empty_rest)
	var mid := _spawn()
	_press(mid, "New game")
	var first := _read_lines(mid, 1)
	assert_eq(String(first[0]["text"]), "A room's two coins a night, and the stew is free.")
	_set_toggle(mid, "ferry_alive", false)
	var mid_rest := _read_lines(mid)
	assert_eq(_line_named(mid_rest, "The dock is empty."), "watcher")
	assert_false(_has_text(mid_rest, "Bram, the ferry master, is on the dock."))
	_assert_no_missing_holder(mid_rest)
	await wait_process_frames(1)


func test_panels_fit_at_1280_and_1920() -> void:
	var window := get_tree().root
	var saved_size := window.size
	var saved_mode := window.content_scale_mode
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var sizes: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080)]
	for size in sizes:
		window.size = size
		var ui := _spawn_on(window)
		await wait_process_frames(2)
		_assert_layout(ui, size, "open")
		ui.new_game(1)
		await wait_process_frames(2)
		_assert_layout(ui, size, "playing")
		var guard := 0
		while guard < 8:
			var cont := _button_with_text(ui, "Continue")
			if cont == null or cont.disabled:
				break
			cont.pressed.emit()
			guard += 1
		await wait_process_frames(2)
		_assert_layout(ui, size, "choices")
		ui.queue_free()
		await wait_process_frames(1)
	window.size = saved_size
	window.content_scale_mode = saved_mode


func _spawn() -> _UI:
	var packed := load("res://example/playtest/gullhaven_playtest.tscn") as PackedScene
	var ui := packed.instantiate() as _UI
	add_child_autofree(ui)
	assert_eq(ui.boot_error(), "")
	return ui


func _spawn_on(parent: Node) -> _UI:
	var packed := load("res://example/playtest/gullhaven_playtest.tscn") as PackedScene
	var ui := packed.instantiate() as _UI
	parent.add_child(ui)
	assert_eq(ui.boot_error(), "")
	return ui


func _set_toggle(ui: Node, key: String, on: bool) -> void:
	var box := ui.find_child("Toggle_%s" % key, true, false) as CheckButton
	assert_not_null(box, key)
	if box.button_pressed == on:
		return
	box.toggled.emit(on)


func _press(ui: Node, title: String) -> void:
	var button := _button_with_text(ui, title)
	assert_not_null(button, title)
	button.pressed.emit()


func _button_with_text(ui: Node, title: String) -> Button:
	for node in ui.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text == title:
			return button
	return null


func _choice_button(ui: Node, label: String) -> Button:
	var choices := ui.find_child("Choices", true, false) as VBoxContainer
	if choices == null:
		return null
	var prefix := "%s (" % label
	for child in choices.get_children():
		var button := child as Button
		if button == null:
			continue
		if button.text == label or button.text.begins_with(prefix):
			return button
	return null


func _shown_line(ui: Node) -> Dictionary:
	var dialogue := ui.find_child("Dialogue", true, false) as VBoxContainer
	assert_not_null(dialogue)
	var labels: Array[Label] = []
	for child in dialogue.get_children():
		var label := child as Label
		if label != null:
			labels.append(label)
	assert_gte(labels.size(), 2)
	return {"speaker": labels[0].text, "text": labels[1].text}


func _read_lines(ui: Node, limit: int = 20) -> Array:
	var rows: Array = []
	var guard := 0
	while guard < limit:
		var cont := _button_with_text(ui, "Continue")
		if cont == null or cont.disabled:
			break
		rows.append(_shown_line(ui))
		cont.pressed.emit()
		guard += 1
	return rows


func _press_choice(ui: Node, label: String) -> void:
	var choice := _choice_button(ui, label)
	assert_not_null(choice, label)
	assert_false(choice.disabled, label)
	choice.pressed.emit()


func _line_named(rows: Array, text: String) -> String:
	for row in rows:
		if String(row["text"]) == text:
			return String(row["speaker"])
	assert_true(false, "missing line \"%s\"" % text)
	return ""


func _text_of(rows: Array, text: String) -> String:
	return _line_named(rows, text)


func _has_text(rows: Array, text: String) -> bool:
	for row in rows:
		if String(row["text"]) == text:
			return true
	return false


func _assert_no_missing_holder(rows: Array) -> void:
	for row in rows:
		assert_false(String(row["text"]).contains("{?"), String(row["text"]))


func _drive_until_choice(ui: Node, label: String, route_id: String) -> void:
	var steps := 0
	var pressed := 0
	var saw := false
	while steps < 40:
		var cont := _button_with_text(ui, "Continue")
		if cont != null and not cont.disabled:
			cont.pressed.emit()
			steps += 1
			continue
		var choice := _choice_button(ui, label)
		if choice == null:
			break
		saw = true
		var was_disabled := choice.disabled
		choice.pressed.emit()
		pressed += 1
		steps += 1
		if was_disabled or pressed >= 3:
			break
	assert_true(saw, "no choice button for %s" % route_id)
	var drain := 0
	while drain < 20:
		var cont := _button_with_text(ui, "Continue")
		if cont == null or cont.disabled:
			break
		cont.pressed.emit()
		drain += 1


func _assert_layout(ui: Control, size: Vector2i, phase: String) -> void:
	var viewport := ui.get_viewport().get_visible_rect()
	var where := "%s %s" % [size, phase]
	assert_eq(Vector2i(viewport.size), size, "%s viewport" % where)
	assert_eq(ui.size, Vector2(size), "%s root" % where)
	assert_true(viewport.grow(1.0).encloses(ui.get_global_rect()), "%s root rect" % where)
	for node_name in _PANELS:
		var panel := ui.find_child(node_name, true, false) as Control
		assert_not_null(panel, "%s %s" % [where, node_name])
		var rect := panel.get_global_rect()
		assert_gt(rect.size.x, 1.0, "%s %s width" % [where, node_name])
		assert_gt(rect.size.y, 1.0, "%s %s height" % [where, node_name])
		assert_true(viewport.grow(1.0).encloses(rect), "%s %s %s outside %s" % [where, node_name, rect, viewport])
	for node in ui.find_children("*", "Button", true, false):
		var button := node as Button
		if button == null or not button.is_visible_in_tree():
			continue
		var rect := button.get_global_rect()
		if rect.size.x <= 1.0 or rect.size.y <= 1.0:
			continue
		assert_true(viewport.grow(1.0).encloses(rect), "%s button '%s' %s outside %s" % [where, button.text, rect, viewport])
