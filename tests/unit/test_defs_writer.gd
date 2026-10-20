extends GutTest


func test_tags_header_format_sort_ascii_and_repeat() -> void:
	var first := WyrdDefsGolden.render()
	var second := WyrdDefsGolden.render()
	assert_eq(first, second)
	assert_true(first.ends_with("\n"))
	var lines := _body(first)
	assert_gte(lines.size(), 3)
	assert_eq(lines[0], "!_TAG_FILE_FORMAT\t2\t//")
	assert_eq(lines[1], "!_TAG_FILE_SORTED\t1\t//")
	assert_eq(lines[2], "!_TAG_PROGRAM_NAME\twyrd defs\t//")
	var address := RegEx.new()
	assert_eq(address.compile("^\\d+;\"$"), OK)
	var kinds := ["d", "f", "g", "q", "r", "s", "t"]
	var previous_name := ""
	var previous_file := ""
	var previous_line := 0
	var previous_kind := ""
	for index in range(3, lines.size()):
		var parts := lines[index].split("\t", false)
		assert_eq(parts.size(), 4, lines[index])
		var name := parts[0]
		var file := parts[1]
		var where := parts[2]
		var kind := parts[3]
		var line_no := _address(where)
		assert_ne(address.search(where), null, where)
		assert_true(kinds.has(kind), kind)
		assert_false(name.is_empty())
		assert_eq(name.strip_edges(), name)
		assert_false(name.contains(" "))
		assert_false(name.contains("\t"))
		for unit in name.length():
			assert_lt(name.unicode_at(unit), 128, name)
		var ordered := name > previous_name
		if name == previous_name:
			ordered = file > previous_file
			if file == previous_file:
				ordered = line_no > previous_line
				if line_no == previous_line:
					ordered = kind > previous_kind
		var tied: bool = name == previous_name and file == previous_file and line_no == previous_line and kind == previous_kind
		assert_true(index == 3 or ordered or tied, lines[index])
		previous_name = name
		previous_file = file
		previous_line = line_no
		previous_kind = kind


func test_stage_names_regions_and_variants() -> void:
	var rows := _entries(WyrdDefsGolden.render())
	var cross := _named(rows, "ferry_toll.cross")
	var bare := _named(rows, "cross")
	assert_eq(cross.size(), 1)
	assert_gte(bare.size(), 1)
	var ferry := _one(bare, "example/content/gullhaven/ferry_toll.wyrd")
	assert_eq(str(cross[0]["file"]), str(ferry["file"]))
	assert_eq(int(cross[0]["line"]), int(ferry["line"]))
	assert_eq(int(ferry["line"]), 34)
	assert_eq(_source(str(ferry["file"]), int(ferry["line"])).strip_edges(), "stage cross")
	for stage_name in ["frayed", "spliced", "loose", "seated"]:
		var qualified := _named(rows, "bell_repair.%s" % stage_name)
		var plain := _one(_named(rows, stage_name), "example/content/gullhaven/bell_repair.wyrd")
		assert_eq(qualified.size(), 1, stage_name)
		assert_eq(str(qualified[0]["file"]), "example/content/gullhaven/bell_repair.wyrd")
		assert_eq(int(qualified[0]["line"]), int(plain["line"]))
		assert_eq(str(qualified[0]["kind"]), "s")
		assert_eq(str(plain["kind"]), "s")
		assert_true(_source(str(plain["file"]), int(plain["line"])).strip_edges().begins_with("stage %s" % stage_name))
	for line_no in [26, 29]:
		for row in rows:
			var same: bool = str(row["file"]) == "example/content/gullhaven/ferry_toll.wyrd" and int(row["line"]) == line_no
			assert_false(same, "%s %d" % [str(row["name"]), line_no])


func test_every_entry_points_at_its_declaration() -> void:
	var rows := _entries(WyrdDefsGolden.render())
	var saw := {"d": false, "f": false, "g": false, "q": false, "r": false, "s": false, "t": false}
	for row in rows:
		var kind := str(row["kind"])
		var name := str(row["name"])
		var text := _source(str(row["file"]), int(row["line"])).strip_edges()
		saw[kind] = true
		assert_false(text.begins_with("variant"), "%s %s" % [kind, name])
		match kind:
			"q":
				assert_true(_opens(text, "quest ", name), text)
			"s":
				var stage_id := name
				if name.contains("."):
					var bits := name.split(".")
					stage_id = bits[bits.size() - 1]
				assert_true(_opens(text, "stage ", stage_id), "%s -> %s" % [name, text])
			"g":
				assert_true(_opens(text, "scene ", name), text)
			"r":
				assert_true(_opens(text, "role ", name), text)
			"t":
				assert_true(_opens(text, "storylet ", name), text)
			"d":
				assert_true(_opens(text, "document ", name), text)
			"f":
				assert_true(text.begins_with(name), text)
				var next := text.substr(name.length(), 1)
				assert_true(next == " " or next == ":", "%s -> %s" % [name, text])
	for kind in saw:
		assert_true(bool(saw[kind]), kind)
	assert_eq(_line_of(rows, "q", "ferry_toll"), 4)
	assert_eq(_line_of(rows, "g", "toll.offer_room"), 4)
	assert_eq(_line_of(rows, "r", "tavern_owner"), 4)
	assert_eq(_line_of(rows, "t", "harbor_gossip.generic"), 4)
	assert_eq(_line_of(rows, "d", "ferry_schedule"), 4)
	assert_eq(_line_of(rows, "f", "player.coins"), 11)


func _body(text: String) -> PackedStringArray:
	assert_true(text.ends_with("\n"))
	var lines := text.split("\n")
	assert_eq(lines[lines.size() - 1], "")
	lines.remove_at(lines.size() - 1)
	return lines


func _entries(text: String) -> Array:
	var rows: Array = []
	var lines := _body(text)
	for index in range(3, lines.size()):
		var parts := lines[index].split("\t", false)
		rows.append({
			"file": parts[1],
			"kind": parts[3],
			"line": _address(parts[2]),
			"name": parts[0],
		})
	return rows


func _named(rows: Array, name: String) -> Array:
	var found: Array = []
	for row in rows:
		if str(row["name"]) == name:
			found.append(row)
	return found


func _one(rows: Array, file: String) -> Dictionary:
	for row in rows:
		if str(row["file"]) == file:
			return row
	return {}


func _source(file: String, line: int) -> String:
	var path := file if file.begins_with("/") else "res://" + file
	var rows := FileAccess.get_file_as_string(path).split("\n")
	return rows[line - 1]


func _opens(text: String, keyword: String, id: String) -> bool:
	var prefix := keyword + id
	if not text.begins_with(prefix):
		return false
	if text.length() == prefix.length():
		return true
	var next := text.unicode_at(prefix.length())
	return next == 32 or next == 34 or next == 9


func _address(text: String) -> int:
	return int(text.substr(0, text.find(";")))


func _line_of(rows: Array, kind: String, name: String) -> int:
	for row in rows:
		if str(row["kind"]) == kind and str(row["name"]) == name:
			return int(row["line"])
	return -1
