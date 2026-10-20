extends GutTest

const _MANIFEST := "example/content/gullhaven/harbor.wyrdmanifest.tres"
const _FILE := "res://example/content/gullhaven/facts.wyrd"


class _Fake extends RefCounted:
	var md5 := "a"
	var reads := 0
	var runs := 0
	var exit_code := 0
	var output := ""
	var errors := 0
	var warnings := 0
	var next_md5 := ""
	var scripted: Array = []

	func read_md5(_path: String) -> String:
		reads += 1
		return md5

	func run_check(_args: PackedStringArray) -> Dictionary:
		runs += 1
		if not next_md5.is_empty():
			md5 = next_md5
			next_md5 = ""
		if not scripted.is_empty():
			var row: Dictionary = scripted.pop_front()
			return row
		return {
			"exit_code": exit_code,
			"output": output,
			"errors": errors,
			"warnings": warnings,
		}


func test_the_first_tick_prints_markers_around_the_rows() -> void:
	var fake := _Fake.new()
	fake.output = "res://a.wyrd:2:1: error[E_HEADER_MISSING]: missing language header\n"
	fake.errors = 1
	var text := _open(fake).tick(0)
	assert_eq(
		text,
		"wyrd: check started\nres://a.wyrd:2:1: error[E_HEADER_MISSING]: missing language header\nwyrd: check finished errors=1 warnings=0\n"
	)


func test_a_tick_before_500_ms_does_not_poll() -> void:
	var fake := _Fake.new()
	var watch := _open(fake)
	watch.tick(0)
	var reads := fake.reads
	assert_gt(reads, 0)
	assert_eq(watch.tick(499), "")
	assert_eq(fake.reads, reads)
	assert_eq(fake.runs, 1)


func test_a_poll_at_500_ms_with_no_change_prints_nothing() -> void:
	var fake := _Fake.new()
	var watch := _open(fake)
	watch.tick(0)
	var reads := fake.reads
	assert_eq(watch.tick(500), "")
	assert_gt(fake.reads, reads)
	assert_eq(fake.runs, 1)


func test_a_changed_md5_reruns_the_cycle() -> void:
	var fake := _Fake.new()
	fake.output = "res://a.wyrd:1:1: warning[W_CLAIM]: changed\n"
	fake.warnings = 1
	var watch := _open(fake)
	watch.tick(0)
	fake.md5 = "b"
	var text := watch.tick(500)
	assert_eq(fake.runs, 2)
	assert_true(text.begins_with("wyrd: check started\n"))
	assert_true(text.contains("warning[W_CLAIM]"))
	assert_true(text.strip_edges().ends_with("wyrd: check finished errors=0 warnings=1"))


func test_adding_or_removing_a_wyrd_file_reruns_the_cycle() -> void:
	var root := "user://wyrd_check_watch_dir"
	_wipe(root)
	DirAccess.make_dir_recursive_absolute(root)
	_write(root.path_join("a.wyrd"), "language 1\n")
	var fake := _Fake.new()
	var watch := WyrdCheckWatch.new(
		{"manifest": "", "note_path": root},
		PackedStringArray(["check", root]),
		Callable(fake, &"read_md5"),
		Callable(fake, &"run_check")
	)
	assert_false(watch.tick(0).is_empty())
	assert_eq(watch.tick(500), "")
	_write(root.path_join("b.wyrd"), "language 1\n")
	assert_false(watch.tick(1000).is_empty())
	DirAccess.remove_absolute(root.path_join("b.wyrd"))
	assert_false(watch.tick(1500).is_empty())
	assert_eq(fake.runs, 3)
	_wipe(root)


func test_manifest_file_list_and_commands_edits_rerun_the_cycle() -> void:
	var root := "user://wyrd_check_watch_manifest"
	_wipe(root)
	DirAccess.make_dir_recursive_absolute(root)
	var a := root.path_join("a.wyrd")
	var b := root.path_join("b.wyrd")
	_write(a, "language 1\n")
	_write(b, "language 1\n")
	var manifest := root.path_join("pack.wyrdmanifest.tres")
	_write_manifest(manifest, PackedStringArray([a]))
	var commands := root.path_join("wyrd_commands.json")
	_write(commands, "{\"commands\":[]}\n")
	var fake := _Fake.new()
	var watch := WyrdCheckWatch.new(
		{"manifest": manifest, "note_path": manifest},
		PackedStringArray(["check", "--manifest", manifest]),
		Callable(),
		Callable(fake, &"run_check")
	)
	assert_false(watch.tick(0).is_empty())
	_write_manifest(manifest, PackedStringArray([a, b]))
	assert_false(watch.tick(500).is_empty())
	_write(b, "language 1\n\nfacts\n  player.coins : int stored\n")
	var saw_b := watch.tick(1000)
	assert_false(saw_b.is_empty(), "the reloaded files list did not include b.wyrd")
	_write(commands, "{\"commands\":[\"look\"]}\n")
	assert_false(watch.tick(1500).is_empty())
	assert_eq(fake.runs, 4)
	_wipe(root)


func test_counts_include_errors_and_warnings_but_not_info() -> void:
	var result: Dictionary = WyrdCli.execute(PackedStringArray(["check", "--watch", "--manifest", _MANIFEST]))
	var watch: WyrdCheckWatch = result["watch"]
	var lines := watch.tick(0).strip_edges().split("\n")
	assert_eq(lines[0], "wyrd: check started")
	var diagnostics := _gullhaven_diagnostics()
	var errors := 0
	var warnings := 0
	var infos := 0
	for item in diagnostics.items:
		var severity := String(item.severity)
		if severity == "error":
			errors += 1
		elif severity == "warning":
			warnings += 1
		elif severity == "info":
			infos += 1
	assert_gt(infos, 0)
	assert_gt(warnings, 0)
	assert_eq(lines[lines.size() - 1], "wyrd: check finished errors=%d warnings=%d" % [errors, warnings])
	assert_eq("\n".join(lines.slice(1, lines.size() - 1)), diagnostics.format().strip_edges())


func test_a_load_failure_stays_between_the_markers_and_the_next_cycle_recovers() -> void:
	var fake := _Fake.new()
	var watch := _open(fake)
	var first := watch.tick(0).strip_edges()
	assert_eq(first, "wyrd: check started\nwyrd: check finished errors=0 warnings=0")
	fake.md5 = "b"
	fake.scripted.append({
		"exit_code": 1,
		"output": "wyrd: not a content manifest: pack.tres\n",
		"errors": 1,
		"warnings": 0,
	})
	var failed := watch.tick(500).strip_edges()
	assert_eq(
		failed,
		"wyrd: check started\nwyrd: not a content manifest: pack.tres\nwyrd: check finished errors=1 warnings=0"
	)
	fake.md5 = "c"
	fake.output = "res://a.wyrd:1:1: warning[W_CLAIM]: back\n"
	fake.warnings = 1
	var recovered := watch.tick(1000).strip_edges()
	assert_eq(
		recovered,
		"wyrd: check started\nres://a.wyrd:1:1: warning[W_CLAIM]: back\nwyrd: check finished errors=0 warnings=1"
	)


func test_a_broken_header_is_reported_on_the_next_cycle() -> void:
	var root := "user://wyrd_check_watch_header"
	_wipe(root)
	DirAccess.make_dir_recursive_absolute(root)
	var dest := root.path_join("facts.wyrd")
	_write(dest, FileAccess.get_file_as_string(_FILE))
	var result: Dictionary = WyrdCli.execute(PackedStringArray(["check", "--watch", root]))
	var watch: WyrdCheckWatch = result["watch"]
	watch.tick(0)
	_write(dest, "// broken\n")
	var text := watch.tick(500)
	assert_true(text.contains("error[E_HEADER_MISSING]"), text)
	assert_true(text.contains("wyrd: check finished errors=1 warnings=0"), text)
	_wipe(root)


func test_a_save_during_a_cycle_triggers_the_next_one() -> void:
	var fake := _Fake.new()
	fake.next_md5 = "during"
	var watch := _open(fake)
	assert_false(watch.tick(0).is_empty())
	assert_eq(fake.md5, "during")
	assert_false(watch.tick(500).is_empty())
	assert_eq(fake.runs, 2)


func _open(fake: _Fake) -> WyrdCheckWatch:
	return WyrdCheckWatch.new(
		{"manifest": "", "note_path": _FILE},
		PackedStringArray(["check", _FILE]),
		Callable(fake, &"read_md5"),
		Callable(fake, &"run_check")
	)


func _gullhaven_diagnostics() -> WyrdDiagnostics:
	var path := "res://" + _MANIFEST
	var spec := load(path) as WyrdContentManifest
	var diagnostics := WyrdDiagnostics.new()
	var read := WyrdPack.read_commands(path.get_base_dir() + "/wyrd_commands.json", diagnostics)
	WyrdPack.compile(
		spec.files,
		String(spec.pack_id),
		spec.language_version,
		read["schema"],
		diagnostics,
		path,
		bool(read["skip_note"])
	)
	return diagnostics


func _write_manifest(path: String, files: PackedStringArray) -> void:
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"watch"
	manifest.language_version = 1
	manifest.files = files
	assert_eq(ResourceSaver.save(manifest, path), OK)


func _write(path: String, body: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, path)
	file.store_string(body)


func _wipe(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		return
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name != "." and file_name != "..":
			_wipe(path.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
