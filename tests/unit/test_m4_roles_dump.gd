extends GutTest

const _Harness := preload("res://tests/scenario/s2c_harness.gd")
const _MANIFEST := "example/content/gullhaven/harbor.wyrdmanifest.tres"


func test_table_sorts_and_filters_by_prefix() -> void:
	var roles := WyrdRoles.new()
	roles.define(&"role_b", "election")
	roles.assign(&"role_b", &"ada")
	roles.vacate(&"role_b", &"left")
	roles.define(&"role_a")
	var table := roles.render_table("")
	var names := _ids(table)
	assert_eq(names, PackedStringArray(["role_a", "role_b"]))
	assert_true(table.begins_with("role"))
	var pending := _line(table, "role_b")
	assert_true(pending.contains("pending"), pending)
	assert_true(pending.contains("contested"), pending)
	assert_true(pending.contains("election"), pending)
	assert_false(pending.contains("ada"), pending)
	var filtered := _ids(roles.render_table("role_b"))
	assert_eq(filtered, PackedStringArray(["role_b"]))
	assert_eq(_ids(roles.render_table("missing")).size(), 0)


func test_abolished_and_frozen_columns() -> void:
	var roles := WyrdRoles.new()
	roles.define(&"harbor_factor", "faction_assigns(faction.harbor)", false, -1, "", "", &"net_mender", "abolish")
	roles.vacate(&"harbor_factor", &"left")
	var line := _line(roles.render_table(""), "harbor_factor")
	assert_true(line.contains("abolished"), line)
	assert_true(line.contains("faction_assigns(faction.harbor)"), line)
	var opened := _Harness.new().boot_gullhaven()
	var runtime: WyrdRuntime = opened["runtime"]
	var cast := _line(runtime.roles.render_table("storm_watcher"), "storm_watcher")
	assert_true(cast.contains("ferry_toll/lookout=dock_apprentice:default"), cast)


func test_hundreds_of_roles_stay_sorted() -> void:
	var roles := WyrdRoles.new()
	for i in 300:
		roles.define(StringName("role_%03d" % i))
	var names := _ids(roles.render_table(""))
	assert_eq(names.size(), 300)
	assert_eq(names[0], "role_000")
	assert_eq(names[299], "role_299")
	for i in names.size() - 1:
		assert_true(names[i] < names[i + 1], names[i])
	assert_eq(_ids(roles.render_table("role_01")).size(), 10)


func test_roles_command_prints_the_gullhaven_table() -> void:
	var result: Dictionary = WyrdCli.execute(PackedStringArray(["roles"]))
	assert_eq(int(result["exit_code"]), 1)
	assert_true(str(result["output"]).begins_with("wyrd: roles needs one file or directory"))
	var listed: Dictionary = WyrdCli.execute(PackedStringArray(["roles", "--manifest", _MANIFEST]))
	assert_eq(int(listed["exit_code"]), 0, str(listed["output"]))
	var names := _ids(str(listed["output"]))
	assert_eq(names, PackedStringArray([
		"council_member", "dock_runner", "ferry_master", "harbor_factor", "harbor_reeve", "storm_watcher", "tavern_owner",
	]))
	assert_true(_line(str(listed["output"]), "harbor_factor").contains("net_mender"))
	assert_true(_line(str(listed["output"]), "harbor_reeve").contains("tide_clerk"))
	assert_true(_line(str(listed["output"]), "ferry_master").contains("relation(apprentice)"))
	var filtered: Dictionary = WyrdCli.execute(PackedStringArray([
		"roles", "--prefix", "harbor", "--manifest", _MANIFEST,
	]))
	assert_eq(int(filtered["exit_code"]), 0, str(filtered["output"]))
	assert_eq(_ids(str(filtered["output"])), PackedStringArray(["harbor_factor", "harbor_reeve"]))


func test_roles_command_loads_a_save() -> void:
	var opened := _Harness.new().open_pack(_Harness.HARBOR)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.start_new_game(1)
	runtime.roles.vacate(&"harbor_factor", &"left")
	assert_true(runtime.roles.abolished(&"harbor_factor"))
	var path := "user://wyrd_m4_roles_save.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(runtime.save_state()))
	file.close()
	var result: Dictionary = WyrdCli.execute(PackedStringArray([
		"roles", "--manifest", _MANIFEST, "--save", path,
	]))
	assert_eq(int(result["exit_code"]), 0, str(result["output"]))
	var line := _line(str(result["output"]), "harbor_factor")
	assert_true(line.contains("abolished"), line)


func _ids(table: String) -> PackedStringArray:
	var names := PackedStringArray()
	for raw in table.split("\n"):
		var line := String(raw).strip_edges()
		if line.is_empty() or line.begins_with("role "):
			continue
		if line.contains("warning[") or line.contains("error[") or line.contains("info["):
			continue
		names.append(line.split("  ")[0].strip_edges())
	return names


func _line(table: String, role: String) -> String:
	for raw in table.split("\n"):
		var line := String(raw)
		if line.begins_with(role + " ") or line.begins_with(role + "\t"):
			return line
	return ""
