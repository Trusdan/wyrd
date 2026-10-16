extends GutTest


func test_commands_record_console_provenance() -> void:
	var runtime := _boot()
	var console := WyrdConsole.new()
	console.bind(runtime)
	var done := console.run_lines(PackedStringArray([
		"set harbor.coins 4",
		"set harbor.open true",
		"kill ferry_master",
		"vacate storm_watcher",
		"replace ferry_master net_mender",
		"time 45",
		"event tide_turned",
		"event bell_struck object=dock_bell count=2",
	]))
	assert_true(bool(done["ok"]), str(done["output"]))
	assert_eq(int(runtime.facts.get_in(&"harbor.coins")), 4)
	assert_eq(bool(runtime.facts.get_in(&"harbor.open")), true)
	var prov := runtime.effects.provenance_of("harbor.coins")
	assert_eq(str(prov["scene"]), "console")
	assert_eq(str(prov["choice"]), "set")
	assert_eq(int(prov["time"]), 0)
	var open_prov := runtime.effects.provenance_of("harbor.open")
	assert_eq(str(open_prov["scene"]), "console")
	assert_eq(str(open_prov["choice"]), "set")
	assert_eq(String(runtime.roles.holder(&"ferry_master")), "net_mender")
	assert_eq(String(runtime.roles.holder(&"storm_watcher")), "")
	assert_eq(runtime.now_minutes(), 45)
	assert_eq(runtime.events.recent.size(), 2)
	var last: Dictionary = runtime.events.recent[runtime.events.recent.size() - 1]
	assert_eq(str(last["name"]), "bell_struck")
	assert_eq(runtime.trace.events.size(), 0)
	assert_true(str(done["output"]).contains("set harbor.coins = 4"))
	assert_true(str(done["output"]).contains("killed ferry_master"))
	assert_true(str(done["output"]).contains("vacated storm_watcher"))
	assert_true(str(done["output"]).contains("replaced ferry_master holder=net_mender"))
	assert_true(str(done["output"]).contains("time 45"))
	assert_true(str(done["output"]).contains("event bell_struck"))
	console.exec("set harbor.coins")
	assert_push_error("set needs a fact and a value")
	console.exec("kill tavern_owner")
	assert_push_error("unknown role")
	console.exec("time -5")
	assert_push_error("whole number")
	assert_eq(runtime.now_minutes(), 45)
	console.exec("event bell_struck object=dock_bell")
	assert_push_error("missing field")
	console.exec("drop ferry_master")
	assert_push_error("unknown command")
	assert_eq(runtime.trace.events.size(), 0)


func test_scene_text_ui() -> void:
	var runtime := _boot()
	runtime.trace.enabled = true
	var console := WyrdConsole.new()
	console.bind(runtime)
	var opened := console.exec("scene toll.gate")
	assert_true(bool(opened["ok"]), str(opened["output"]))
	assert_true(str(opened["output"]).contains("narrator: The tide is in."))
	console.exec("choose 1")
	assert_push_error("no choices are waiting")
	var advanced := console.exec("advance")
	assert_true(str(advanced["output"]).contains("1 Pay the toll"))
	console.exec("choose 0")
	assert_push_error("out of range")
	var picked := console.exec("choose 1")
	assert_true(bool(picked["ok"]), str(picked["output"]))
	assert_true(str(picked["output"]).contains("narrator: The booth is open."))
	assert_eq(int(runtime.facts.get_in(&"harbor.coins")), 2)
	var scene_prov := runtime.effects.provenance_of("harbor.coins")
	assert_eq(str(scene_prov["scene"]), "toll.gate")
	assert_eq(str(scene_prov["choice"]), "pay")
	var ended := console.exec("advance")
	assert_eq(str(ended["output"]), "scene ended toll.gate\n")
	var rows := _rows(runtime, "console")
	assert_eq(rows.size(), 6)
	for item in rows:
		var row: Dictionary = item
		assert_eq(str(row["source"]), "console")
		assert_eq(str(row["path"]), "console")
	assert_eq(str((rows[0] as Dictionary)["command"]), "scene")
	assert_eq(str((rows[0] as Dictionary)["key"]), "toll.gate")
	console.exec("scene missing.gate")
	assert_push_error("unknown scene")


func test_trace_save_load_and_replay() -> void:
	var runtime := _boot()
	runtime.trace.enabled = true
	var console := WyrdConsole.new()
	console.bind(runtime)
	runtime.trace.prefix = "console"
	var killed := console.exec("vacate storm_watcher")
	assert_true(bool(killed["ok"]))
	assert_eq(_rows(runtime, "console").size(), 1)
	var kept: Dictionary = _rows(runtime, "console")[0]
	assert_eq(str(kept["role"]), "storm_watcher")
	assert_eq(str(kept["source"]), "console")
	runtime.trace.prefix = "harbor.tide"
	runtime.trace.clear()
	var missed := console.exec("set harbor.coins 2")
	assert_true(bool(missed["ok"]))
	assert_eq(_rows(runtime, "console").size(), 0)
	runtime.trace.prefix = "ferry"
	runtime.trace.clear()
	var replaced := console.exec("replace ferry_master net_mender")
	assert_true(bool(replaced["ok"]))
	assert_eq(_rows(runtime, "console").size(), 1)
	runtime.trace.prefix = ""
	runtime.trace.clear()
	var traced := console.exec("set harbor.coins 2")
	assert_true(bool(traced["ok"]))
	assert_eq(_rows(runtime, "console").size(), 1)
	var recorded := runtime.trace.snapshot()
	var stopped := console.exec("quit")
	assert_true(bool(stopped["quit"]))
	console.exec("  ")
	console.exec("# note")
	assert_eq(_rows(runtime, "console").size(), 1)
	var data := runtime.save_state()
	var again := _boot()
	again.trace.enabled = true
	var report := again.load_state(data)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(_rows(again, "console").size(), 0)
	assert_eq(int(again.facts.get_in(&"harbor.coins")), 2)
	var loaded := again.effects.provenance_of("harbor.coins")
	assert_eq(str(loaded["scene"]), "console")
	assert_eq(str(loaded["choice"]), "set")
	assert_eq(String(again.roles.holder(&"ferry_master")), "net_mender")
	assert_eq(String(again.roles.holder(&"storm_watcher")), "")
	var second := _boot()
	WyrdTrace.replay(second, recorded)
	assert_null(second.facts.get_in(&"harbor.coins"))


func test_cli_batch_and_release_strip() -> void:
	var path := _write_pack()
	var ran: Dictionary = WyrdCli.execute(PackedStringArray([
		"console",
		path,
		"--cmd",
		"set harbor.coins 4",
		"--cmd",
		"scene toll.gate",
		"--cmd",
		"kill ferry_master",
	]))
	assert_eq(int(ran["exit_code"]), 0, str(ran["output"]))
	assert_true(str(ran["output"]).contains("set harbor.coins = 4"))
	assert_true(str(ran["output"]).contains("narrator: The tide is in."))
	assert_true(str(ran["output"]).contains("killed ferry_master"))
	var missing: Dictionary = WyrdCli.execute(PackedStringArray(["console", path, "--cmd"]))
	assert_eq(int(missing["exit_code"]), 1)
	assert_eq(str(missing["output"]), "wyrd: --cmd needs a command\n")
	var unknown: Dictionary = WyrdCli.execute(PackedStringArray(["console", path, "--cmd", "drop ferry_master"]))
	assert_push_error("unknown command")
	assert_eq(int(unknown["exit_code"]), 1)
	var save_path := "user://wyrd_m7_console_save.json"
	var runtime := _boot()
	var console := WyrdConsole.new()
	console.bind(runtime)
	console.exec("set harbor.coins 9")
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(runtime.save_state()))
	file.close()
	var loaded: Dictionary = WyrdCli.execute(PackedStringArray([
		"console",
		path,
		"--save",
		save_path,
		"--cmd",
		"time 5",
	]))
	assert_eq(int(loaded["exit_code"]), 0, str(loaded["output"]))
	assert_true(str(loaded["output"]).contains("time 5"))
	var absent: Dictionary = WyrdCli.execute(PackedStringArray([
		"console",
		path,
		"--save",
		"user://wyrd_m7_console_missing.json",
		"--cmd",
		"time 1",
	]))
	assert_eq(int(absent["exit_code"]), 1)
	assert_true(str(absent["output"]).contains("no such file"))
	assert_false(WyrdCli.console_in_build(false))
	assert_true(WyrdCli.console_in_build(true))
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	assert_true(preset.contains("exclude_filter=\"%s\"" % WyrdConsole.RELEASE_EXCLUDE))
	var runtime_body := FileAccess.get_file_as_string("res://addons/wyrd/runtime/wyrd_runtime.gd")
	var facade_body := FileAccess.get_file_as_string("res://addons/wyrd/runtime/wyrd.gd")
	var plugin_body := FileAccess.get_file_as_string("res://addons/wyrd/plugin.gd")
	assert_false(runtime_body.contains("wyrd_console"))
	assert_false(runtime_body.contains("runtime/console"))
	assert_false(facade_body.contains("wyrd_console"))
	assert_false(plugin_body.contains("wyrd_console"))
	var cli_body := FileAccess.get_file_as_string("res://addons/wyrd/cli/wyrd_cli_app.gd")
	assert_true(cli_body.contains("res://addons/wyrd/runtime/console/wyrd_console.gd"))
	assert_false(cli_body.contains("preload(\"res://addons/wyrd/runtime/console/wyrd_console.gd\")"))


func _rows(runtime: WyrdRuntime, kind: String) -> Array:
	var found: Array = []
	for item in runtime.trace.events:
		var row: Dictionary = item
		if str(row.get("kind", "")) == kind:
			found.append(row)
	return found


func _boot() -> WyrdRuntime:
	var path := _write_pack()
	var diagnostics := WyrdDiagnostics.new()
	WyrdPack.compile(PackedStringArray([path]), "harbor", 1, null, diagnostics, path, true)
	assert_false(diagnostics.has_errors(), diagnostics.format())
	var runtime := WyrdRuntime.new()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(1)
	return runtime


func _write_pack() -> String:
	var path := "user://wyrd_m7_console_pack.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(_PACK.strip_edges() + "\n")
	file.close()
	return path


const _PACK := """
language 1
facts
  harbor.coins : int stored
  harbor.open : bool stored
events
  tide_turned()
  bell_struck(object: symbol, count: int)
role ferry_master
  scope: place(gullhaven)
  default_holder: ferry_master
  succession: none
  vacancy: hold
role storm_watcher
  default_holder: storm_watcher
  succession: none
  vacancy: hold
scene toll.gate
  narrator: The tide is in. #line:tide
  when harbor.open: narrator: The booth flag is up. #line:flag
  * [Pay the toll] -> paid #line:pay
    ~ set harbor.coins = 2
  - (paid)
  narrator: The booth is open. #line:open
  -> end
"""
