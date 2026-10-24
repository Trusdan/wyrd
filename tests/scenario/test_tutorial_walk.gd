extends GutTest

## The tutorial's ferry walk is what the playtest shows.


const _UI := preload("res://example/playtest/gullhaven_playtest.gd")

const _TUTORIAL := "res://docs/tutorial.md"
const _PLAYTEST := "res://docs/playtest.md"

const _ROOM := "day 1, 00:00  Bram, the ferry master, at the dock wants 2 coins before the crossing."
const _EMPTY := "day 1, 00:00  The dock is empty, so the crossing waits."
const _NIA := "day 1, 00:00  Nia, the ferry master, at the dock wants 2 coins before the crossing."
const _HEADER := "The Ferry Toll — active"
const _TAVERN := "slot tavern — tavern owner — innkeeper — default"
const _FERRY := "slot ferry — ferry master — Bram — default"
const _LOOKOUT := "slot lookout — storm watcher — Nia — default"
const _GONE_SLOT := "slot ferry — ferry master — none — empty"
const _NEXT_SLOT := "slot ferry — ferry master — Nia — successor"
const _HIDDEN := "secret role smugglers_contact — holder hidden"
const _TOLD := "secret role smugglers_contact — watcher (told)"
const _STAGE_ALIAS := "alias stage:ferry_toll pay_toll → toll_due ×1"
const _TRAIL_ALIAS := "alias trail:ferry_toll:pay_toll pay_toll → toll_due ×1"
const _NEXT_STATUS := "Next version: ferry stage renamed pay_toll → toll_due."


func test_sections_three_through_seven_match_the_page() -> void:
	var page := FileAccess.get_file_as_string(_TUTORIAL)
	var ui := _spawn()
	_assert_page(page, "Content loaded.")
	assert_eq(_load_row(ui, 0), "Content loaded.")
	_press(ui, "New game")
	var lines := _read_lines(ui)
	_assert_spoken(page, lines, "innkeeper", "A room's two coins a night, and the stew is free.")
	_assert_spoken(page, lines, "Nia", "The headland bell rang twice before the rain.")
	_assert_spoken(page, lines, "Nia", "Bram, the ferry master, is on the dock.")
	_assert_spoken(page, lines, "bell", "The bell notes the tide.")
	_press_choice(ui, "Take the room")
	var rest := _read_lines(ui)
	_assert_spoken(page, rest, "innkeeper", "The ferry's charging double since the storm, mind.")
	_assert_spoken(page, rest, "Bram", "Two coins, and the boat will cross.")
	_assert_spoken(page, rest, "narrator", "The boat leaves the dock.")
	var journal := _journal(ui)
	assert_eq(journal.get_item_text(0), _HEADER)
	assert_false(journal.is_item_selectable(0))
	assert_eq(journal.get_item_text(1), _ROOM)
	var summary := _quest_summary(ui)
	for row in [_HEADER, _ROOM, _TAVERN, _FERRY, _LOOKOUT, "quest The Ferry Toll", "stage pay_toll", "status active", _HIDDEN]:
		assert_true(summary.contains(row) or journal.get_item_text(0) == row or journal.get_item_text(1) == row, row)
		_assert_page(page, row)
	assert_true(ui.save_game())
	assert_true(ui.load_game())
	assert_eq(ui.status_text(), "Loaded.")
	assert_eq(_load_row(ui, 0), "No changes.")
	_assert_page(page, "No changes.")
	_assert_page(page, "Loaded.")
	ui.advance_time()
	assert_eq(ui.quest_stage(), "cross")
	_assert_page(page, "stage cross")
	_read_lines(ui)
	assert_true(_quest_summary(ui).contains("status completed"))
	_assert_page(page, "status completed")
	_start_route(ui, "Ferry master gone")
	_drive_until_choice(ui, "Take the room")
	var gone := _journal(ui)
	assert_eq(gone.get_item_text(1), _EMPTY)
	assert_true(_quest_summary(ui).contains(_GONE_SLOT))
	_assert_page(page, _EMPTY)
	_assert_page(page, _GONE_SLOT)
	_start_route(ui, "Successor")
	_drive_until_choice(ui, "Take the room")
	var successor := _journal(ui)
	assert_eq(successor.get_item_text(1), _NIA)
	assert_true(_quest_summary(ui).contains(_NEXT_SLOT))
	_assert_page(page, _NIA)
	_assert_page(page, _NEXT_SLOT)
	_press(ui, "New game")
	assert_true(_quest_summary(ui).contains(_HIDDEN))
	_press(ui, "Tell secret")
	assert_true(_quest_summary(ui).contains(_TOLD))
	_assert_page(page, _TOLD)
	_press(ui, "Abort scene")
	assert_true(ui.save_game())
	assert_true(ui.load_game())
	assert_true(_quest_summary(ui).contains(_TOLD))
	await wait_process_frames(1)


func test_next_version_load_report_matches_the_page() -> void:
	var page := FileAccess.get_file_as_string(_TUTORIAL)
	var ui := _spawn()
	_press(ui, "New game")
	_drive_until_choice(ui, "Take the room")
	assert_true(ui.save_game())
	_press(ui, "Load in next version")
	assert_eq(ui.status_text(), _NEXT_STATUS)
	var rows := _load_rows(ui)
	assert_true(rows.has(_STAGE_ALIAS), "\n".join(rows))
	assert_true(rows.has(_TRAIL_ALIAS), "\n".join(rows))
	var manifest := false
	for row in rows:
		if row.begins_with("manifest ") and row.contains("W_SAVE_MANIFEST"):
			manifest = true
	assert_true(manifest, "\n".join(rows))
	for needle in [_NEXT_STATUS, _STAGE_ALIAS, _TRAIL_ALIAS, "W_SAVE_MANIFEST"]:
		_assert_page(page, needle)
	_press(ui, "New game")
	assert_eq(ui.quest_stage(), "gossip")
	await wait_process_frames(1)


func test_route_labels_are_on_the_playtest_page() -> void:
	var doc := FileAccess.get_file_as_string(_PLAYTEST)
	var section_5 := _between(doc, "## 5. Walk one route", "## 6. Every other route")
	var section_6 := _between(doc, "## 6. Every other route", "## 7. Save and load")
	var ui := _spawn()
	var list := ui.find_child("RouteList", true, false) as OptionButton
	assert_not_null(list)
	assert_gt(list.item_count, 1)
	for index in list.item_count:
		var label := list.get_item_text(index)
		if label == "Defaults":
			assert_true(section_5.contains(label), label)
		else:
			assert_true(section_6.contains(label), label)
	await wait_process_frames(1)


func _spawn() -> _UI:
	var packed := load("res://example/playtest/gullhaven_playtest.tscn") as PackedScene
	var ui := packed.instantiate() as _UI
	add_child_autofree(ui)
	assert_eq(ui.boot_error(), "")
	return ui


func _press(ui: Node, title: String) -> bool:
	var button := _button_with_text(ui, title)
	assert_not_null(button, title)
	button.pressed.emit()
	return true


func _press_load(ui: Node) -> bool:
	for node in ui.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text == "Load":
			button.pressed.emit()
			return true
	assert_true(false, "Load")
	return false


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
	for child in choices.get_children():
		var button := child as Button
		if button != null and button.text == label:
			return button
	return null


func _shown_line(ui: Node) -> Dictionary:
	var dialogue := ui.find_child("Dialogue", true, false) as VBoxContainer
	var labels: Array[Label] = []
	for child in dialogue.get_children():
		var label := child as Label
		if label != null:
			labels.append(label)
	return {"speaker": labels[0].text, "text": labels[1].text}


func _read_lines(ui: Node, limit: int = 12) -> Array:
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


func _drive_until_choice(ui: Node, label: String) -> void:
	var steps := 0
	while steps < 20:
		var cont := _button_with_text(ui, "Continue")
		if cont != null and not cont.disabled:
			cont.pressed.emit()
			steps += 1
			continue
		break
	_press_choice(ui, label)
	_read_lines(ui)


func _journal(ui: Node) -> ItemList:
	var journal := ui.find_child("JournalList", true, false) as ItemList
	assert_not_null(journal)
	return journal


func _quest_summary(ui: Node) -> String:
	var summary := ui.find_child("QuestSummary", true, false) as Label
	assert_not_null(summary)
	return summary.text


func _load_row(ui: Node, index: int) -> String:
	return _load_rows(ui)[index]


func _load_rows(ui: Node) -> PackedStringArray:
	var list := ui.find_child("LoadReportList", true, false) as ItemList
	assert_not_null(list)
	var rows := PackedStringArray()
	for index in list.item_count:
		rows.append(list.get_item_text(index))
	return rows


func _start_route(ui: Node, label: String) -> void:
	var list := ui.find_child("RouteList", true, false) as OptionButton
	assert_not_null(list, label)
	var found := -1
	for index in list.item_count:
		if list.get_item_text(index) == label:
			found = index
	assert_ne(found, -1, label)
	list.select(found)
	_press(ui, "Start route")


func _assert_spoken(page: String, rows: Array, speaker: String, text: String) -> void:
	var saw := false
	for row in rows:
		if String(row["speaker"]) == speaker and String(row["text"]) == text:
			saw = true
	assert_true(saw, "%s: %s" % [speaker, text])
	_assert_page(page, text)


func _assert_page(page: String, needle: String) -> void:
	assert_true(page.contains(needle), needle)


func _between(text: String, start: String, stop: String) -> String:
	var from := text.find(start)
	var to := text.find(stop)
	assert_true(from >= 0, start)
	assert_gt(to, from, stop)
	return text.substr(from, to - from)
