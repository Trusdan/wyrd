extends GutTest


func test_tag_lines_preserves_bytes_and_is_idempotent() -> void:
	var taken := {}
	var raw := "language 1\r\n\r\nscene room\r\n  keeper: Hello // note\r\n  keeper: Stay. #line:keep\r\n  * [Stay] -> done\r\n  - (done)\r\n"
	var once: Dictionary = WyrdTagLines.tag_text(raw, "res://room.wyrd", "harbor", taken)
	var text := str(once["text"])
	var notes: PackedStringArray = once["notes"]
	assert_eq(notes.size(), 2)
	var hello_id := str(notes[0]).split("#line:")[1]
	var choice_id := str(notes[1]).split("#line:")[1]
	var expected := "language 1\r\n\r\nscene room\r\n  keeper: Hello #line:%s // note\r\n  keeper: Stay. #line:keep\r\n  * [Stay] -> done #line:%s\r\n  - (done)\r\n" % [hello_id, choice_id]
	assert_eq(text, expected)
	var again_taken := {}
	var twice: Dictionary = WyrdTagLines.tag_text(text, "res://room.wyrd", "harbor", again_taken)
	assert_eq(str(twice["text"]), text)
	assert_eq((twice["notes"] as PackedStringArray).size(), 0)


func test_dry_run_does_not_write() -> void:
	var path := "user://wyrd_tag_dry.wyrd"
	var original := "language 1\n\nscene room\n  keeper: Hello.\n"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(original)
	file.close()
	var result: Dictionary = WyrdTagLines.tag_files(PackedStringArray([path]), "harbor", true)
	assert_eq(int(result["exit_code"]), 0)
	assert_true(str(result["output"]).contains("+ #line:"))
	assert_eq(FileAccess.get_file_as_string(path), original)


func test_ids_are_stable_and_lengthen_on_collision() -> void:
	var taken := {}
	var first := WyrdTagLines.make_id("harbor", "res://room.wyrd", "room", 0, taken)
	var second := WyrdTagLines.make_id("harbor", "res://room.wyrd", "room", 0, taken)
	assert_eq(first, second)
	assert_eq(first.length(), 4)
	taken[first] = true
	var longer := WyrdTagLines.make_id("harbor", "res://room.wyrd", "room", 0, taken)
	assert_ne(longer, first)
	assert_gt(longer.length(), 4)
	var other := WyrdTagLines.make_id("harbor", "res://room.wyrd", "room", 1, {})
	assert_ne(other, first)
