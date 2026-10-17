extends GutTest

const _Harness := preload("res://tests/scenario/s2c_harness.gd")
const _MANIFEST := "res://example/content/gullhaven/harbor.wyrdmanifest.tres"

## One console kill plus time 0, observed after --out is loaded.
## An offered scene keeps the stage. A cast lookout stays. The ferry lock
## adopts ferry.locked_gone. The console runtime has no host, so a player tag
## reads false and a petition tick can adopt factor.barred.
const _EXPECT := {
	"tavern_owner|gossip": "stage=gossip variant= waiting=scene:toll.offer_room holder= status=empty abolished=false slot=empty reason=no_holder slot_holder= journal= crossing= petition= levy=",
	"ferry_master|gossip": "stage=gossip variant= waiting=scene:toll.offer_room holder= status=empty abolished=false slot=empty reason=no_holder slot_holder= journal= crossing= petition= levy=",
	"storm_watcher|gossip": "stage=gossip variant= waiting=scene:toll.offer_room holder= status=empty abolished=false slot=default reason=holder slot_holder=dock_apprentice journal= crossing= petition= levy=",
	"tavern_owner|pay_toll": "stage=pay_toll variant= waiting=on_empty holder= status=empty abolished=false slot=empty reason=no_holder slot_holder= journal=j_ft_01 crossing= petition= levy=",
	"ferry_master|pay_toll": "stage=pay_toll variant=ferry.locked_gone waiting=waits_until: false holder= status=empty abolished=false slot=locked_gone reason=frozen_vacated slot_holder=ferry_master journal=j_ft_01 j_ft_gone crossing= petition= levy=",
	"storm_watcher|pay_toll": "stage=pay_toll variant= waiting=waits_until: player.coins >= 2 and ferry.toll_coins >= 0 holder= status=empty abolished=false slot=default reason=holder slot_holder=dock_apprentice journal=j_ft_01 crossing= petition= levy=",
	"tavern_owner|cross": "stage=cross variant= waiting=scene:toll.depart holder= status=empty abolished=false slot=empty reason=no_holder slot_holder= journal=j_ft_01 crossing=done petition= levy=",
	"ferry_master|cross": "stage=cross variant= waiting=scene:toll.depart holder= status=empty abolished=false slot=locked_gone reason=frozen_vacated slot_holder=ferry_master journal=j_ft_01 crossing=done petition= levy=",
	"storm_watcher|cross": "stage=cross variant= waiting=scene:toll.depart holder= status=empty abolished=false slot=default reason=holder slot_holder=dock_apprentice journal=j_ft_01 crossing=done petition= levy=",
	"harbor_factor|petition": "stage=petition variant=factor.empty waiting=waits_until: false holder= status=empty abolished=true slot=empty reason=no_holder slot_holder= journal=j_guild_levy j_guild_empty crossing= petition=done levy=",
	"harbor_reeve|petition": "stage=petition variant=factor.barred waiting=waits_until: false holder= status=contested abolished=false slot=contested reason=contested slot_holder= journal=j_guild_levy j_guild_barred crossing= petition=route_closed levy=",
	"harbor_factor|signed": "stage=signed variant= waiting=on_empty holder= status=empty abolished=true slot=empty reason=no_holder slot_holder= journal=j_guild_levy j_guild_signed crossing= petition=done levy=done",
	"harbor_reeve|signed": "stage=signed variant=reeve.contested waiting=waits_until: false holder= status=contested abolished=false slot=contested reason=contested slot_holder= journal=j_guild_levy j_guild_signed j_guild_vote crossing= petition=done levy=done",
}


func test_exit_kill_reroutes_the_ferry() -> void:
	var opened := _reach_ferry("pay_toll")
	var runtime: WyrdRuntime = opened["runtime"]
	var before := "user://m7_exit_ferry_before.json"
	var after := "user://m7_exit_ferry_after.json"
	_write_json(before, runtime.save_state())
	var result := _console(PackedStringArray([
		"--save", before,
		"--out", after,
		"--cmd", "kill ferry_master",
		"--cmd", "time 0",
		"--cmd", "set harbor.bell_count 3",
	]))
	assert_push_error("time.season")
	assert_eq(int(result["exit_code"]), 0, str(result["output"]))
	assert_true(str(result["output"]).begins_with("killed ferry_master\ntime 0\nset harbor.bell_count = 3\n"))
	var fresh := _load_out(after, false)
	assert_eq(fresh.quests.stage("ferry_toll"), "pay_toll")
	assert_eq(fresh.quests.variant_of("ferry_toll"), "ferry.locked_gone")
	assert_true(_journal(fresh, "ferry_toll").has("j_ft_gone"))
	assert_ne(fresh.quests.outcome("ferry_toll", "crossing"), "done")
	assert_eq(String(fresh.roles.holder(&"ferry_master")), "")
	var saved := fresh.save_state()
	assert_eq(int(saved["schema_version"]), 2)
	assert_false(saved.has("coverage"))
	var prov: Dictionary = fresh.effects.export_state()["harbor.bell_count"]
	assert_eq(str(prov["scene"]), "console")
	assert_eq(str(prov["choice"]), "set")
	var again: WyrdRuntime = _Harness.new().boot_gullhaven(false, 4, true)["runtime"]
	assert_true(again.load_state(JSON.parse_string(JSON.stringify(saved))).ok)
	var kept: Dictionary = again.effects.export_state()["harbor.bell_count"]
	assert_eq(str(kept["scene"]), "console")
	assert_eq(again.quests.variant_of("ferry_toll"), "ferry.locked_gone")


func test_console_kill_covers_each_holder_and_stage() -> void:
	var cases := _cases()
	assert_eq(cases.size(), 13)
	var problems := PackedStringArray()
	for item in cases:
		var case: Dictionary = item
		var role := str(case["role"])
		var stage := str(case["stage"])
		var quest := str(case["quest"])
		var slot := str(case["slot"])
		var guild := quest == "harbor_guild"
		var opened: Dictionary = _reach(quest, stage)
		var runtime: WyrdRuntime = opened["runtime"]
		assert_eq(runtime.quests.stage(quest), stage, "%s %s reach" % [role, stage])
		var before := "user://m7_exit_%s_%s_before.json" % [role, stage]
		var after := "user://m7_exit_%s_%s_after.json" % [role, stage]
		_write_json(before, runtime.save_state())
		var result := _console(PackedStringArray([
			"--save", before,
			"--out", after,
			"--cmd", "kill %s" % role,
			"--cmd", "time 0",
		]))
		assert_push_error("time.season")
		if int(result["exit_code"]) != 0:
			problems.append("%s %s exit %s" % [role, stage, str(result["output"])])
			continue
		var fresh := _load_out(after, guild)
		var got := _observe(fresh, quest, role, slot)
		var expect := str(_EXPECT["%s|%s" % [role, stage]])
		if got != expect:
			problems.append("%s %s\n  got %s\n  exp %s" % [role, stage, got, expect])
	assert_eq(problems.size(), 0, "\n".join(problems))


func test_console_out_refuses_an_open_scene() -> void:
	var path := "user://m7_exit_open_scene.json"
	_remove(path)
	var result := _console(PackedStringArray([
		"--out", path,
		"--cmd", "scene toll.offer_room",
	]))
	assert_eq(int(result["exit_code"]), 1)
	assert_true(str(result["output"]).contains("wyrd: console could not write the save: a scene is open"))
	assert_false(FileAccess.file_exists(path))


func test_console_out_skips_a_failed_command() -> void:
	var path := "user://m7_exit_failed.json"
	_remove(path)
	var result := _console(PackedStringArray([
		"--out", path,
		"--cmd", "kill no_such_role",
	]))
	assert_push_error("unknown role")
	assert_eq(int(result["exit_code"]), 1)
	assert_false(FileAccess.file_exists(path))
	var missing := WyrdCli.execute(PackedStringArray(["console", "--manifest", _MANIFEST, "--out"]))
	assert_eq(int(missing["exit_code"]), 1)
	assert_true(str(missing["output"]).contains("--out needs a path"))


func test_console_dash_o_writes_the_save() -> void:
	var path := "user://m7_exit_dash_o.json"
	var result := _console(PackedStringArray([
		"-o", path,
		"--cmd", "set harbor.bell_count 4",
	]))
	assert_eq(int(result["exit_code"]), 0, str(result["output"]))
	assert_true(FileAccess.file_exists(path))
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(data is Dictionary)
	var saved: Dictionary = data
	assert_eq(int(saved["schema_version"]), 2)
	assert_false(saved.has("coverage"))
	var prov: Dictionary = (saved["provenance"] as Dictionary)["harbor.bell_count"]
	assert_eq(str(prov["scene"]), "console")
	assert_eq(str(prov["choice"]), "set")


func test_snapshot_sections_match_after_load() -> void:
	var opened := _reach_ferry("pay_toll")
	var runtime: WyrdRuntime = opened["runtime"]
	var before := runtime.debug.snapshot(_saved_sections())
	var saved := runtime.save_state()
	assert_false(saved.has("coverage"))
	assert_false(saved.has("dirty"))
	var fresh: WyrdRuntime = _Harness.new().boot_gullhaven(false, 4, true)["runtime"]
	assert_true(fresh.load_state(JSON.parse_string(JSON.stringify(saved))).ok)
	var after := fresh.debug.snapshot(_saved_sections())
	for name in _saved_sections():
		assert_eq(JSON.stringify(after[String(name)]), JSON.stringify(before[String(name)]), String(name))


func test_coverage_replays_from_one_seed() -> void:
	var left := _play_coverage()
	var right := _play_coverage()
	assert_eq(str(left["id"]), "harbor_gossip.generic")
	assert_eq(str(right["id"]), str(left["id"]))
	assert_eq(str(right["line_id"]), str(left["line_id"]))
	assert_gt(int(left["storylet"]), 0)
	assert_eq(JSON.stringify(right["counts"]), JSON.stringify(left["counts"]))
	var saved: Dictionary = left["saved"]
	assert_false(saved.has("coverage"))
	assert_eq(int(saved["schema_version"]), 2)


func test_choice_summary_keeps_the_recap_fact() -> void:
	var runtime: WyrdRuntime = _reach_ferry("pay_toll")["runtime"]
	var toll := _summary_row(runtime.facts.choice_summary(), "ferry.toll_coins")
	assert_false(toll.is_empty())
	assert_true(bool(toll["recap"]))
	assert_eq(str(toll["scene"]), "")
	var prefixed: Array = runtime.facts.choice_summary({"prefix": "ferry.toll"})
	assert_eq(prefixed.size(), 1)
	assert_eq(str((prefixed[0] as Dictionary)["key"]), "ferry.toll_coins")
	var scene_rows: Array = runtime.facts.choice_summary({"scene": "toll.offer_room"})
	assert_true(_summary_row(scene_rows, "ferry.toll_coins").is_empty())
	var coins := _summary_row(scene_rows, "player.coins")
	assert_eq(str(coins["scene"]), "toll.offer_room")
	assert_eq(str(coins["choice"]), "c_room")
	assert_false(bool(coins["recap"]))
	runtime.deeds.compact()
	var kept: Array = runtime.facts.choice_summary()
	assert_eq(kept.size(), 2)
	assert_eq(str((kept[0] as Dictionary)["key"]), "ferry.toll_coins")
	assert_true(bool((kept[0] as Dictionary)["recap"]))
	assert_eq(str((kept[1] as Dictionary)["key"]), "harbor.room_taken")
	assert_true(bool((kept[1] as Dictionary)["recap"]))
	var saved := runtime.save_state()
	var fresh: WyrdRuntime = _Harness.new().boot_gullhaven(false, 4, true)["runtime"]
	assert_true(fresh.load_state(saved).ok)
	fresh.deeds.compact()
	var loaded: Array = fresh.facts.choice_summary()
	assert_eq(loaded.size(), 2)
	assert_eq(str((loaded[0] as Dictionary)["key"]), "ferry.toll_coins")
	assert_true(bool((loaded[0] as Dictionary)["recap"]))
	assert_eq(str((loaded[1] as Dictionary)["key"]), "harbor.room_taken")
	assert_true(bool((loaded[1] as Dictionary)["recap"]))


func _cases() -> Array:
	var rows: Array = []
	var ferry: Array = [
		{"quest": "ferry_toll", "role": "tavern_owner", "slot": "tavern"},
		{"quest": "ferry_toll", "role": "ferry_master", "slot": "ferry"},
		{"quest": "ferry_toll", "role": "storm_watcher", "slot": "lookout"},
	]
	for stage in ["gossip", "pay_toll", "cross"]:
		for item in ferry:
			var case: Dictionary = (item as Dictionary).duplicate()
			case["stage"] = String(stage)
			rows.append(case)
	var guild: Array = [
		{"quest": "harbor_guild", "role": "harbor_factor", "slot": "factor"},
		{"quest": "harbor_guild", "role": "harbor_reeve", "slot": "reeve"},
	]
	for stage in ["petition", "signed"]:
		for item in guild:
			var case: Dictionary = (item as Dictionary).duplicate()
			case["stage"] = String(stage)
			rows.append(case)
	return rows


func _reach(quest: String, stage: String) -> Dictionary:
	if quest == "harbor_guild":
		return _reach_guild(stage)
	return _reach_ferry(stage)


func _reach_ferry(stage: String) -> Dictionary:
	var opened := _Harness.new().boot_gullhaven(false, 4, true)
	var runtime: WyrdRuntime = opened["runtime"]
	if stage == "pay_toll" or stage == "cross":
		var harness := _Harness.new()
		runtime.dialogue.open_scene("toll.offer_room")
		harness.line_rows(runtime)
		harness.choose_text(runtime, "Take the room")
		harness.line_rows(runtime)
	if stage == "cross":
		runtime.tick(0)
	elif stage == "pay_toll":
		runtime.facts.set(&"player.coins", 0)
	return opened


func _reach_guild(stage: String) -> Dictionary:
	var opened := _Harness.new().boot_gullhaven(true, 4, true)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.deeds.record(&"asked_guild", &"player", &"", &"gullhaven")
	runtime.tick(0)
	if stage == "signed":
		runtime.facts.set(&"harbor.guild_signed", true)
		runtime.tick(0)
	return opened


func _console(args: PackedStringArray) -> Dictionary:
	var full := PackedStringArray(["console", "--manifest", _MANIFEST])
	full.append_array(args)
	return WyrdCli.execute(full)


func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func _load_out(path: String, guild: bool) -> WyrdRuntime:
	var fresh: WyrdRuntime = _Harness.new().boot_gullhaven(guild, 4, true)["runtime"]
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(data is Dictionary, path)
	assert_true(fresh.load_state(data).ok, path)
	return fresh


func _observe(runtime: WyrdRuntime, quest: String, role: String, slot: String) -> String:
	var resolved: Dictionary = runtime.roles.resolve_slot(quest, StringName(slot), false)
	return "stage=%s variant=%s waiting=%s holder=%s status=%s abolished=%s slot=%s reason=%s slot_holder=%s journal=%s crossing=%s petition=%s levy=%s" % [
		runtime.quests.stage(quest),
		runtime.quests.variant_of(quest),
		runtime.quests.waiting_reason(quest),
		String(runtime.roles.holder(StringName(role))),
		String(runtime.roles.binding_status(StringName(role))),
		str(runtime.roles.abolished(StringName(role))),
		String(resolved["state"]),
		String(resolved["reason"]),
		String(runtime.roles.slot_holder(quest, StringName(slot))),
		" ".join(_journal(runtime, quest)),
		runtime.quests.outcome(quest, "crossing"),
		runtime.quests.outcome(quest, "petition"),
		runtime.quests.outcome(quest, "levy"),
	]


func _journal(runtime: WyrdRuntime, quest: String) -> PackedStringArray:
	var ids := PackedStringArray()
	for entry in runtime.quests.journal(quest):
		ids.append(String(entry["id"]))
	return ids


func _saved_sections() -> PackedStringArray:
	return PackedStringArray([
		"facts", "roles", "quests", "deeds", "social", "precedence", "provenance",
	])


func _play_coverage() -> Dictionary:
	var runtime: WyrdRuntime = _Harness.new().boot_gullhaven(false, 4, true)["runtime"]
	runtime.coverage.enabled = true
	var won := runtime.director.query("topic", "rumor.ferry_toll", "")
	_Harness.new().line_rows(runtime)
	return {
		"counts": runtime.coverage.counts(),
		"id": str(won["id"]),
		"line_id": str(won["line_id"]),
		"saved": runtime.save_state(),
		"storylet": runtime.coverage.count("storylet", "harbor_gossip.generic"),
	}


func _summary_row(rows: Array, key: String) -> Dictionary:
	for item in rows:
		var row: Dictionary = item
		if str(row["key"]) == key:
			return row
	return {}


func _remove(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)
