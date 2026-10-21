extends GutTest

const _Harness := preload("res://tests/scenario/s2c_harness.gd")


func test_save_refuses_while_a_scene_is_open() -> void:
	var runtime := _boot()
	runtime.dialogue.open_scene("toll.offer_room")
	assert_eq(runtime.save_state(), {})
	assert_push_error("a scene is open")
	var report := runtime.load_state({})
	assert_push_error("a scene is open")
	assert_false(report.ok)
	assert_eq(report.error_count(), 1)


func test_json_round_trip_matches_and_continues() -> void:
	var runtime := _boot()
	runtime.social.set_baseline(&"ferry_master", &"player", &"affinity", 2.0)
	runtime.roles.define(&"ferry_master", "relation(apprentice)")
	runtime.social.set_kind(&"ferry_master", &"dock_apprentice", &"apprentice")
	var harness := _Harness.new()
	runtime.dialogue.open_scene("toll.offer_room")
	harness.line_rows(runtime)
	harness.choose_text(runtime, "Take the room")
	harness.line_rows(runtime)
	assert_false(runtime.dialogue.is_open())
	assert_eq(runtime.facts.get(&"player.coins"), 2)
	var first := runtime.draw_u32(&"play")
	var saved := runtime.save_state()
	assert_eq(int(saved["schema_version"]), 4)
	assert_eq(WyrdSave.migrations.size(), 3)
	assert_eq(String(saved["seed"]).length(), 16)
	var parsed: Variant = JSON.parse_string(JSON.stringify(saved))
	assert_true(parsed is Dictionary)
	var fresh := _blank()
	var report := fresh.load_state(parsed)
	assert_true(report.ok, report.diagnostics.format())
	assert_false(report.diagnostics.has_warnings())
	assert_true(_same(saved, fresh.save_state()))
	var later := runtime.draw_u32(&"play")
	assert_eq(fresh.draw_u32(&"play"), later)
	assert_ne(later, first)
	runtime.dialogue.open_scene("toll.depart")
	fresh.dialogue.open_scene("toll.depart")
	var left := harness.line_rows(runtime)
	var right := harness.line_rows(fresh)
	assert_eq(harness.ids_of(left), harness.ids_of(right))
	assert_eq(left[0]["text"], right[0]["text"])
	assert_eq(runtime.quests.status("ferry_toll"), fresh.quests.status("ferry_toll"))


func test_manifest_mismatch_warns_and_a_future_version_is_refused() -> void:
	var runtime := _boot()
	runtime.facts.set(&"player.coins", 4)
	var saved := runtime.save_state()
	var packs: Array = (saved["content"] as Dictionary)["packs"]
	(packs[0] as Dictionary)["hash"] = WyrdRng.format_u64(1)
	var fresh := _blank()
	var warned := fresh.load_state(saved)
	assert_true(warned.ok)
	assert_true(OS.is_debug_build())
	assert_true(warned.diagnostics.has_warnings())
	saved["schema_version"] = 5
	var blank := _blank()
	var refused := blank.load_state(saved)
	assert_false(refused.ok)
	assert_null(blank.facts.get(&"player.coins"))


func test_host_step_survives_json() -> void:
	var opened := _Harness.new().open_pack("res://tests/scenario/pack/host_step.wyrdmanifest.tres")
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.start_new_game(9)
	runtime.facts.set(&"gate.n", 0)
	runtime.tick(0)
	assert_eq(runtime.quests.waiting_reason("host_step"), "host:board")
	var parsed: Variant = JSON.parse_string(JSON.stringify(runtime.save_state()))
	var fresh: WyrdRuntime = _Harness.new().open_pack("res://tests/scenario/pack/host_step.wyrdmanifest.tres")["runtime"]
	assert_true(fresh.load_state(parsed).ok)
	assert_eq(fresh.quests.waiting_reason("host_step"), "host:board")
	assert_eq(fresh.facts.get(&"gate.n"), 0)
	fresh.quests.complete_host_step("host_step", {"ok": true})
	assert_eq(fresh.facts.get(&"gate.n"), 3)
	assert_eq(fresh.quests.status("host_step"), &"completed")


func _boot() -> WyrdRuntime:
	return _Harness.new().boot_gullhaven(false, 4)["runtime"]


func _blank() -> WyrdRuntime:
	var opened := _Harness.new().open_pack(_Harness.HARBOR)
	var host: WyrdFakeHost = opened["host"]
	host.world.add_entity(&"player", &"person", "traveler", PackedStringArray(), true)
	host.world.add_entity(&"tavern_owner", &"person", "innkeeper", PackedStringArray(), true)
	host.world.add_entity(&"ferry_master", &"person", "Bram", PackedStringArray(), true)
	host.world.add_entity(&"storm_watcher", &"person", "watcher", PackedStringArray(), true)
	host.world.add_entity(&"dock_apprentice", &"person", "Nia", PackedStringArray(), true)
	host.world.add_entity(&"dock.bell", &"object", "bell", PackedStringArray(), true)
	return opened["runtime"]


func _same(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):
		return false
	if left is Dictionary:
		if left.size() != right.size():
			return false
		for key in left.keys():
			if not right.has(key) or not _same(left[key], right[key]):
				return false
		return true
	if left is Array:
		if left.size() != right.size():
			return false
		for i in left.size():
			if not _same(left[i], right[i]):
				return false
		return true
	return left == right
