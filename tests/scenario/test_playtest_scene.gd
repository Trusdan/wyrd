extends GutTest

const _UI := preload("res://example/playtest/gullhaven_playtest.gd")


func test_scene_loads_and_one_route_saves() -> void:
	var packed := load("res://example/playtest/gullhaven_playtest.tscn") as PackedScene
	assert_not_null(packed)
	var ui := packed.instantiate() as _UI
	add_child_autofree(ui)
	assert_eq(ui.boot_error(), "")
	ui.new_game(1)
	assert_eq(ui.line_text(), "A room's two coins a night, and the stew is free.")
	assert_false(ui.line_has_audio())
	var guard := 0
	while ui.line_text() != "" and guard < 12:
		var shown := ui.line_text()
		ui.press_continue()
		guard += 1
		assert_ne(ui.line_text(), shown)
	assert_true(ui.press_choice("Take the room"))
	assert_eq(ui.fact_value("player.coins"), "2")
	assert_eq(ui.fact_value("harbor.room_taken"), "true")
	guard = 0
	while ui.line_text() != "" and guard < 12:
		ui.press_continue()
		guard += 1
	assert_eq(ui.line_text(), "")
	assert_eq(ui.quest_stage(), "pay_toll")
	assert_gt(ui.journal_count(), 0)
	assert_true(ui.save_game())
	ui.advance_time()
	assert_eq(ui.quest_stage(), "cross")
	assert_true(ui.load_game())
	assert_eq(ui.fact_value("player.coins"), "2")
	assert_eq(ui.quest_stage(), "pay_toll")
	assert_gt(ui.journal_count(), 0)
	ui.set_flag("voice", true)
	ui.new_game(1)
	assert_false(ui.line_text().is_empty())
	assert_true(ui.line_has_audio())
	var held := ui.line_text()
	assert_eq(ui.line_text(), held)
	ui.set_flag("voice", false)
	ui.new_game(2)
	assert_false(ui.line_text().is_empty())
	assert_false(ui.line_has_audio())
