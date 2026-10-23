extends GutTest

## Saved trail: distinct top-level stages, newest last, at most 32.


func test_entries_are_distinct_newest_last_and_capped_at_32() -> void:
	var lines := PackedStringArray()
	lines.append("language 1")
	lines.append("")
	lines.append("quest long_walk \"Long Walk\"")
	lines.append("  start when false")
	for index in 33:
		lines.append("  stage s%02d" % index)
		lines.append("    waits_until false")
	var runtime := _boot("\n".join(lines))
	runtime.quests.start("long_walk")
	for index in range(1, 33):
		assert_eq(runtime.quests.advance("long_walk", "s%02d" % index), "")
	var trail: Array = runtime.save_state()["quests"]["long_walk"]["trail"]
	var expected: Array = []
	for index in range(1, 33):
		expected.append("s%02d" % index)
	assert_eq(trail, expected)
	assert_eq(trail.size(), 32)
	assert_eq(String(trail[trail.size() - 1]), "s32")


func test_a_loop_keeps_the_latest_position() -> void:
	var runtime := _boot(_HOP)
	runtime.quests.start("hop")
	assert_eq(_trail(runtime, "hop"), ["s00"])
	assert_eq(runtime.quests.advance("hop", "s01"), "")
	assert_eq(_trail(runtime, "hop"), ["s00", "s01"])
	assert_eq(runtime.quests.advance("hop", "s00"), "")
	assert_eq(_trail(runtime, "hop"), ["s01", "s00"])
	assert_eq(runtime.quests.advance("hop", "s01"), "")
	assert_eq(_trail(runtime, "hop"), ["s00", "s01"])


func test_a_region_entry_is_not_recorded() -> void:
	var runtime := _boot(_LAMP)
	runtime.quests.start("lantern_watch")
	var saved := runtime.save_state()
	var row: Dictionary = saved["quests"]["lantern_watch"]
	assert_eq(row["trail"], ["watch"])
	assert_eq(String(row["regions"]["wick"]["stage"]), "dark")


func test_trail_survives_save_and_load_and_a_missing_key_loads() -> void:
	var runtime := _boot(_HOP)
	runtime.quests.start("hop")
	assert_eq(runtime.quests.advance("hop", "s01"), "")
	var saved := runtime.save_state()
	var again := _boot(_HOP)
	var report := again.load_state(saved)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(_trail(again, "hop"), ["s00", "s01"])
	var stripped: Dictionary = saved.duplicate(true)
	(stripped["quests"]["hop"] as Dictionary).erase("trail")
	var bare := _boot(_HOP)
	var loaded := bare.load_state(stripped)
	assert_true(loaded.ok, loaded.diagnostics.format())
	assert_eq(bare.quests.stage("hop"), "s01")
	assert_false(bare.save_state()["quests"]["hop"].has("trail"))


const _HOP := """
language 1

quest hop "Hop"
  start when false
  stage s00
    waits_until false
  stage s01
    waits_until false
"""

const _LAMP := """
language 1

quest lantern_watch "Lantern Watch"
  start when false
  stage watch
    waits_until false
    region wick
      stage trim
        -> dark
      stage dark
        waits_until false
"""


func _trail(runtime: WyrdRuntime, quest_id: String) -> Array:
	return runtime.save_state()["quests"][quest_id]["trail"]


func _boot(body: String) -> WyrdRuntime:
	var path := "user://wyrd_quest_trail_%d.wyrd" % body.hash()
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file)
	file.store_string(body)
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"trail"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(7)
	return runtime
