extends GutTest

## Pure cache, [method WyrdHash.of_text], and [method WyrdAIValidator.safe_text].


func test_of_text_matches_string_name_and_skips_the_memo() -> void:
	for sample in ["", "cache", "abcdefghijklmnopq", "café", "雪"]:
		assert_eq(WyrdHash.of_text(sample), WyrdHash.of_string_name(StringName(sample)), sample)
	var fresh := "xq7-cache-key!"
	var before := WyrdHash._short_hash.size()
	assert_false(WyrdHash._short_hash.has(StringName(fresh)))
	assert_eq(WyrdHash.of_text(fresh), WyrdHash.of_text(fresh))
	assert_eq(WyrdHash._short_hash.size(), before)
	assert_false(WyrdHash._short_hash.has(StringName(fresh)))
	assert_eq(WyrdHash.of_text(fresh), WyrdHash.of_string_name(StringName(fresh)))


func test_insert_order_evicts_oldest_and_honors_cap() -> void:
	var cache := WyrdAICache.new()
	assert_eq(cache.insert("a", "one", 2).size(), 0)
	assert_eq(cache.insert("b", "two", 2).size(), 0)
	assert_eq(cache.insert("c", "three", 2), PackedStringArray(["a"]))
	assert_eq(cache.keys(), PackedStringArray(["b", "c"]))
	assert_eq(cache.text_for("b"), "two")
	assert_eq(cache.text_for("missing"), "")
	assert_false(cache.has("a"))
	assert_eq(cache.insert("b", "two-b", 2).size(), 0)
	assert_eq(cache.keys(), PackedStringArray(["c", "b"]))
	assert_eq(cache.text_for("b"), "two-b")
	assert_eq(cache.size(), 2)
	assert_eq(cache.insert("d", "four", 0).size(), 0)
	assert_eq(cache.insert("e", "five", -3).size(), 0)
	assert_eq(cache.keys(), PackedStringArray(["c", "b"]))


func test_import_round_trip_skips_bad_rows_and_trims() -> void:
	var cache := WyrdAICache.new()
	cache.insert("aaaaaaaaaaaaaaaa", "stale", 4)
	var rows: Array = [
		{"k": "0123456789abcdef", "t": "one"},
		{"k": "fedcba9876543210", "t": "two"},
		"nope",
		{"k": "abcdef0123456789", "t": "upper".to_upper()},
		{"k": "0123456789abcde", "t": "short"},
		{"k": "000000000000000g", "t": "bad"},
		{"k": "1111111111111111", "t": "{x}"},
		{"k": "2222222222222222", "t": "a\nb"},
		{"k": "3333333333333333", "t": ""},
		{"k": "4444444444444444", "t": "   "},
	]
	# "ABCDEF0123456789" is the uppercase form the brief names.
	rows[3] = {"k": "ABCDEF0123456789", "t": "upper"}
	assert_eq(cache.import_rows(rows, 8), 8)
	assert_eq(cache.keys(), PackedStringArray(["0123456789abcdef", "fedcba9876543210"]))
	assert_eq(cache.text_for("0123456789abcdef"), "one")
	var again := WyrdAICache.new()
	assert_eq(again.import_rows(cache.export_rows(), 8), 0)
	assert_eq(again.export_rows(), cache.export_rows())
	var many: Array = []
	for i in 4:
		many.append({"k": "%016x" % i, "t": "row %d" % i})
	assert_eq(cache.import_rows(many, 2), 0)
	assert_eq(cache.keys(), PackedStringArray(["0000000000000002", "0000000000000003"]))
	assert_eq(cache.text_for("0000000000000003"), "row 3")
	assert_false(cache.has("0000000000000000"))


func test_safe_text() -> void:
	assert_true(WyrdAIValidator.safe_text("The gate is shut."))
	assert_true(WyrdAIValidator.safe_text(_letters(240)))
	assert_false(WyrdAIValidator.safe_text(""))
	assert_false(WyrdAIValidator.safe_text("   "))
	assert_false(WyrdAIValidator.safe_text(_letters(241)))
	assert_false(WyrdAIValidator.safe_text("one\ntwo"))
	assert_false(WyrdAIValidator.safe_text("one\rtwo"))
	assert_false(WyrdAIValidator.safe_text("a%sb" % String.chr(1)))
	assert_false(WyrdAIValidator.safe_text("a%sb" % String.chr(0x7F)))
	assert_false(WyrdAIValidator.safe_text("a%sb" % String.chr(0x200B)))
	assert_false(WyrdAIValidator.safe_text("a%sb" % String.chr(0x2028)))
	assert_false(WyrdAIValidator.safe_text("a%sb" % String.chr(0x2060)))
	assert_false(WyrdAIValidator.safe_text("a%sb" % String.chr(0xFEFF)))
	for mark in ["{", "}", "#", "[", "]", "<", ">"]:
		assert_false(WyrdAIValidator.safe_text("a%sb" % mark), mark)


func _letters(count: int) -> String:
	var text := ""
	for _i in count:
		text += "a"
	return text
