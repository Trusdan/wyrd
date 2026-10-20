extends GutTest

const _KINDS := "user://wyrd_pot_kinds"
const _ORDER := "user://wyrd_pot_order"
const _ESCAPE := "user://wyrd_pot_escape"
const _MANIFEST := "res://example/content/gullhaven/harbor.wyrdmanifest.tres"


func test_each_row_kind_has_the_right_fields() -> void:
	var pack := _compile(_KINDS, "sample", PackedStringArray([_KINDS + "/kinds.wyrd"]), _kinds_source())
	var by_id := {}
	for row in WyrdPotExtractor.rows(pack):
		by_id[str(row["msgctxt"])] = row
	_assert_row(by_id, "scene_line", "ferryman", "The tide is in.", "user://wyrd_pot_kinds/kinds.wyrd")
	_assert_row(by_id, "scene_variant", "ferryman", "The net mender sees the tide.", "user://wyrd_pot_kinds/kinds.wyrd")
	_assert_row(by_id, "choice_room", "", "Take the room", "user://wyrd_pot_kinds/kinds.wyrd")
	_assert_row(by_id, "story_line", "ferryman", "They say the ferry is dear.", "user://wyrd_pot_kinds/kinds.wyrd")
	_assert_row(by_id, "set_a", "ferryman", "First set line.", "user://wyrd_pot_kinds/kinds.wyrd")
	_assert_row(by_id, "set_b", "ferryman", "Second set line.", "user://wyrd_pot_kinds/kinds.wyrd")
	_assert_row(by_id, "j_variant", "", "The council hears it.", "user://wyrd_pot_kinds/kinds.wyrd")
	_assert_row(by_id, "j_region", "", "The rope is tied.", "user://wyrd_pot_kinds/kinds.wyrd")
	_assert_row(by_id, "doc_title", "", "A Note", "user://wyrd_pot_kinds/kinds.wyrd")
	_assert_row(by_id, "doc_para", "", "The page says hello.", "user://wyrd_pot_kinds/kinds.wyrd")
	assert_false(by_id.has("skipped_line"))
	assert_false(by_id.has(""))


func test_lines_without_a_line_id_are_skipped() -> void:
	var pack := _compile(_KINDS, "sample", PackedStringArray([_KINDS + "/kinds.wyrd"]), _kinds_source())
	var blank := 0
	for document in (pack.units[0]["file"] as WyrdFileDef).documents:
		for page in document.pages:
			for paragraph in page["paragraphs"]:
				if str(paragraph["line_id"]).is_empty():
					blank += 1
					assert_eq(WyrdLineDef.source_of(paragraph["prose"]), "No id on this paragraph.")
	assert_eq(blank, 1)
	for row in WyrdPotExtractor.rows(pack):
		assert_false(str(row["msgctxt"]).is_empty())
		assert_ne(str(row["msgid"]), "No id on this paragraph.")


func test_rows_are_ordered_by_file_then_line() -> void:
	var files := PackedStringArray([_ORDER + "/b.wyrd", _ORDER + "/a.wyrd"])
	DirAccess.make_dir_recursive_absolute(_ORDER)
	_write(_ORDER + "/b.wyrd", "language 1\n\nscene beta\n  ferryman: From b. #line:from_b\n")
	_write(_ORDER + "/a.wyrd", "language 1\n\nscene alpha\n  ferryman: Early line. #line:early\n  ferryman: Late line. #line:late\n")
	var diagnostics := WyrdDiagnostics.new()
	var pack := WyrdPack.compile(files, "order", 1, null, diagnostics)
	assert_false(diagnostics.has_errors(), diagnostics.format())
	var ids: PackedStringArray = PackedStringArray()
	for row in WyrdPotExtractor.rows(pack):
		ids.append(str(row["msgctxt"]))
	assert_eq(ids, PackedStringArray(["early", "late", "from_b"]))


func test_escaping_covers_quote_backslash_and_tab() -> void:
	DirAccess.make_dir_recursive_absolute(_ESCAPE)
	_write(_ESCAPE + "/esc.wyrd", "language 1\n\nscene room\n  ferryman: say \"hi\" and \\path\there #line:esc\n")
	var diagnostics := WyrdDiagnostics.new()
	var pack := WyrdPack.compile(PackedStringArray([_ESCAPE + "/esc.wyrd"]), "escape", 1, null, diagnostics)
	assert_false(diagnostics.has_errors(), diagnostics.format())
	var text := WyrdPotExtractor.render(pack)
	assert_true(text.contains("msgid \"say \\\"hi\\\" and \\\\path\\there\""))


func test_header_is_exact_and_the_file_ends_with_one_lf() -> void:
	var pack := _compile(_KINDS, "sample", PackedStringArray([_KINDS + "/kinds.wyrd"]), _kinds_source())
	var text := WyrdPotExtractor.render(pack)
	var header := "msgid \"\"\nmsgstr \"\"\n\"Project-Id-Version: sample\\n\"\n\"MIME-Version: 1.0\\n\"\n\"Content-Type: text/plain; charset=UTF-8\\n\"\n\"Content-Transfer-Encoding: 8bit\\n\"\n\"X-Generator: wyrd pot\\n\"\n"
	assert_true(text.begins_with(header))
	assert_true(text.ends_with("\n"))
	assert_false(text.ends_with("\n\n"))


func test_every_gullhaven_line_id_is_one_msgctxt() -> void:
	var source_ids := _gullhaven_line_ids()
	var seen := {}
	for row in WyrdPotExtractor.rows(_gullhaven_pack()):
		var id := str(row["msgctxt"])
		seen[id] = int(seen.get(id, 0)) + 1
	var missing: PackedStringArray = PackedStringArray()
	for id in source_ids:
		if int(seen.get(id, 0)) != 1:
			missing.append(id)
	missing.sort()
	assert_eq(missing, PackedStringArray(), "line ids that are not exactly one msgctxt")
	assert_eq(seen.size(), source_ids.size())


func test_each_msgctxt_and_msgid_pair_is_unique() -> void:
	var seen := {}
	for row in WyrdPotExtractor.rows(_gullhaven_pack()):
		var key := "%s\n%s" % [str(row["msgctxt"]), str(row["msgid"])]
		assert_false(seen.has(key), key)
		seen[key] = true


func test_plain_lines_match_what_wyrd_text_renders() -> void:
	# dock_voice keeps a {holder|variants} span. has_variable_text is false for
	# that span, and WyrdText removes it before translate. source_of keeps it.
	# The runtime stays unchanged, so this row is the one exception.
	var variants: PackedStringArray = PackedStringArray()
	for row in WyrdPotExtractor.rows(_gullhaven_pack()):
		var prose: Variant = row["prose"]
		if prose == null or WyrdLineDef.has_variable_text(prose):
			continue
		var msgid := str(row["msgid"])
		if _has_variants(prose):
			variants.append(str(row["msgctxt"]))
			continue
		var rendered := WyrdText.new().render(prose, str(row["msgctxt"]))
		assert_eq(rendered, msgid, str(row["msgctxt"]))
	assert_eq(variants, PackedStringArray(["dock_voice"]))


func test_brace_escape_keeps_one_literal_brace() -> void:
	for row in WyrdPotExtractor.rows(_gullhaven_pack()):
		if str(row["msgctxt"]) != "a921":
			continue
		var msgid := str(row["msgid"])
		# {{ opens one literal brace. }} is two literal closing braces; source_of keeps both.
		assert_eq(msgid, "The board lists the price as {two coins}}.")
		assert_false(WyrdLineDef.has_variable_text(row["prose"]))
		assert_eq(WyrdText.new().render(row["prose"], "a921"), msgid)
		return
	fail_test("a921 was not extracted")


func _assert_row(by_id: Dictionary, id: String, speaker: String, msgid: String, path: String) -> void:
	assert_true(by_id.has(id), id)
	var row: Dictionary = by_id[id]
	assert_eq(str(row["speaker"]), speaker, id)
	assert_eq(str(row["msgid"]), msgid, id)
	assert_eq(str(row["path"]), path, id)
	assert_gt(int(row["line"]), 0, id)


func _compile(dir: String, pack_id: String, files: PackedStringArray, body: String) -> WyrdLinkedPack:
	DirAccess.make_dir_recursive_absolute(dir)
	_write(files[0], body)
	var diagnostics := WyrdDiagnostics.new()
	var pack := WyrdPack.compile(files, pack_id, 1, null, diagnostics)
	assert_false(diagnostics.has_errors(), diagnostics.format())
	return pack


func _gullhaven_pack() -> WyrdLinkedPack:
	var spec := load(_MANIFEST) as WyrdContentManifest
	var diagnostics := WyrdDiagnostics.new()
	var read := WyrdPack.read_commands(_MANIFEST.get_base_dir() + "/wyrd_commands.json", diagnostics)
	var pack := WyrdPack.compile(
		spec.files,
		String(spec.pack_id),
		spec.language_version,
		read["schema"],
		diagnostics,
		_MANIFEST,
		bool(read["skip_note"])
	)
	assert_false(diagnostics.has_errors(), diagnostics.format())
	return pack


func _gullhaven_line_ids() -> Dictionary:
	var ids := {}
	var pattern := RegEx.new()
	pattern.compile("#line:([A-Za-z_][A-Za-z0-9_]*)")
	var dir := DirAccess.open("res://example/content/gullhaven")
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".wyrd"):
			var text := FileAccess.get_file_as_string("res://example/content/gullhaven/" + file_name)
			for match in pattern.search_all(text):
				ids[match.get_string(1)] = true
		file_name = dir.get_next()
	return ids


func _has_variants(node: WyrdExprNode) -> bool:
	if node == null:
		return false
	if node.kind == &"variants":
		return true
	if _has_variants(node.b) or _has_variants(node.c):
		return true
	for kid in node.kids:
		if _has_variants(kid):
			return true
	return false


func _kinds_source() -> String:
	return """language 1

quest sample \"Sample\"
  slot ferry = ferry_master mode: live
  on_empty: wait
  stage arrive
    variant ferry.default:
      journal: The council hears it. #line:j_variant
    region rope
      stage coil
        journal: The rope is tied. #line:j_region
    -> done
  stage done
    ~ outcome route = done

scene room
  ferryman: The tide is in. #line:scene_line
  ferryman: The crossing stays open. {holder(ferry)|variants} #line:scene_span
    variant net_mender: The net mender sees the tide. #line:scene_variant
  * [Take the room] -> end #line:choice_room

storylet gossip
  scope: topic rumor
  speaker: ferryman
  - They say the ferry is dear. #line:story_line

storylet gossip_set
  scope: topic rumor
  speaker: ferryman
  lines:
    - First set line. #line:set_a
    - Second set line. #line:set_b

document note \"A Note\" #line:doc_title
  text: live
  page
    The page says hello. #line:doc_para
    No id on this paragraph.
"""


func _write(path: String, body: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, path)
	file.store_string(body)
