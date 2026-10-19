extends GutTest

const _Harness := preload("res://tests/scenario/s2c_harness.gd")


func test_dock_errand_plays_both_routes() -> void:
	var opened := _Harness.new().boot_gullhaven()
	var runtime: WyrdRuntime = opened["runtime"]
	assert_true(opened["report"].ok, opened["report"].diagnostics.format())
	assert_eq(runtime.quests.status("dock_errand"), &"dormant")
	var harness := _Harness.new()
	runtime.dialogue.open_scene("toll.offer_room")
	harness.line_rows(runtime)
	harness.choose_text(runtime, "Ask the dock errand")
	var asked := harness.line_rows(runtime)
	assert_eq(harness.ids_of(asked), PackedStringArray(["a_errand"]))
	assert_eq(asked[0]["text"], "The dock errand can wait.")
	assert_false(runtime.dialogue.is_open())
	assert_eq(runtime.quests.status("dock_errand"), &"active")
	assert_eq(runtime.quests.stage("dock_errand"), "asked")
	assert_eq(_baseline(runtime, "tavern_owner", "player", "affinity"), 5.0)
	assert_eq(String(runtime.roles.holder(&"dock_runner")), "dock_apprentice")
	assert_eq(String(runtime.roles.binding_status(&"dock_runner")), "successor")
	var first: Dictionary = runtime.quests.journal("dock_errand")[0]
	assert_eq(first["id"], "j_errand_asked")
	assert_eq(String(first["text"]), "A net on the dock needs a hand.")
	runtime.dialogue.open_scene("toll.offer_room")
	harness.line_rows(runtime)
	harness.choose_text(runtime, "Send the errand on")
	var sent := harness.line_rows(runtime)
	assert_eq(harness.ids_of(sent), PackedStringArray(["a_errand_on"]))
	assert_eq(sent[0]["text"], "The errand is on its way.")
	assert_false(runtime.dialogue.is_open())
	assert_eq(runtime.quests.status("dock_errand"), &"active")
	assert_eq(runtime.quests.stage("dock_errand"), "sent")
	assert_eq(runtime.quests.journal("dock_errand").size(), 2)
	var second: Dictionary = runtime.quests.journal("dock_errand")[1]
	assert_eq(second["id"], "j_errand_sent")
	assert_eq(String(second["text"]), "The net is sent up the dock.")
	assert_eq(String(runtime.roles.holder(&"dock_runner")), "")
	assert_eq(String(runtime.roles.binding_status(&"dock_runner")), "empty")
	assert_eq(_baseline(runtime, "tavern_owner", "player", "affinity"), 5.0)


func _baseline(runtime: WyrdRuntime, source: String, target: String, axis_name: String) -> float:
	for item in runtime.social.export_state()["baselines"]:
		var row: Dictionary = item
		if str(row["source"]) == source and str(row["target"]) == target and str(row["axis"]) == axis_name:
			return float(row["value"])
	return 0.0
