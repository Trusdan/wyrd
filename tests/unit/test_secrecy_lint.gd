extends GutTest


func _tiers() -> PackedStringArray:
	return PackedStringArray(["open", "sealed"])


func test_open_storylet_line_warns_once_at_the_span() -> void:
	var result := _compile("""
		language 1
		facts
		  player.coins : int stored
		storylet harbor.sealed
		  scope: bark
		  speaker: dock_clerk
		  priority: 2
		  secrecy: sealed
		  ~ set player.coins = 2
		  - The ledger stays shut. #line:sealed_line
		storylet harbor.open
		  scope: bark
		  speaker: dock_clerk
		  priority: 1
		  secrecy: open
		  - The coins are {player.coins}. #line:open_line
		""", _tiers())
	_assert_one(
		result,
		"{player.coins}",
		"text at secrecy \"open\" shows \"player.coins\", which is only set at secrecy \"sealed\" or higher"
	)
	var pack: WyrdLinkedPack = result["pack"]
	var writers: Array = _fact(pack, "player.coins")["writers"]
	assert_eq(writers.size(), 1)
	assert_false(writers[0].has("tier"))
	assert_eq(pack.xref.writer_tiers("player.coins"), ["sealed"])


func test_untiered_stage_writer_suppresses_the_warning() -> void:
	var result := _compile("""
		language 1
		facts
		  player.coins : int stored
		quest ferry_toll "The Ferry Toll"
		  stage arrive
		    ~ set player.coins = 1
		storylet harbor.sealed
		  scope: bark
		  speaker: dock_clerk
		  priority: 2
		  secrecy: sealed
		  ~ set player.coins = 2
		  - The ledger stays shut. #line:sealed_line
		storylet harbor.open
		  scope: bark
		  speaker: dock_clerk
		  priority: 1
		  secrecy: open
		  - The coins are {player.coins}. #line:open_line
		""", _tiers())
	_assert_none(result)


func test_if_condition_does_not_warn() -> void:
	var result := _compile("""
		language 1
		facts
		  player.coins : int stored
		storylet harbor.sealed
		  scope: bark
		  speaker: dock_clerk
		  priority: 2
		  secrecy: sealed
		  ~ set player.coins = 2
		  - The ledger stays shut. #line:sealed_line
		storylet harbor.open
		  scope: bark
		  speaker: dock_clerk
		  priority: 1
		  secrecy: open
		  - {if player.coins >= 1}The purse is heavy.{end} #line:open_line
		""", _tiers())
	_assert_none(result)


func test_without_tiers_the_lint_does_not_run() -> void:
	var result := _compile("""
		language 1
		facts
		  player.coins : int stored
		storylet harbor.sealed
		  scope: bark
		  speaker: dock_clerk
		  priority: 2
		  secrecy: sealed
		  ~ set player.coins = 2
		  - The ledger stays shut. #line:sealed_line
		storylet harbor.open
		  scope: bark
		  speaker: dock_clerk
		  priority: 1
		  secrecy: open
		  - The coins are {player.coins}. #line:open_line
		""")
	_assert_none(result)


func test_open_line_inside_sealed_storylet_does_not_warn() -> void:
	var result := _compile("""
		language 1
		facts
		  player.coins : int stored
		storylet harbor.sealed
		  scope: bark
		  speaker: dock_clerk
		  secrecy: sealed
		  ~ set player.coins = 2
		  - The coins are {player.coins}. #secrecy:open #line:open_line
		""", _tiers())
	_assert_none(result)


func test_open_paragraph_inside_sealed_document_does_not_warn() -> void:
	var result := _compile("""
		language 1
		facts
		  player.coins : int stored
		document harbor_ledger "Harbor Ledger" #secrecy:sealed #line:ledger_title
		  text: live
		  page
		    The coins are {player.coins}. #secrecy:open #line:ledger_open
		  on_read:
		    ~ set player.coins = 1
		""", _tiers())
	_assert_none(result)


func test_unknown_text_tier_does_not_warn() -> void:
	var result := _compile("""
		language 1
		facts
		  player.coins : int stored
		storylet harbor.sealed
		  scope: bark
		  speaker: dock_clerk
		  priority: 2
		  secrecy: sealed
		  ~ set player.coins = 2
		  - The ledger stays shut. #line:sealed_line
		storylet harbor.open
		  scope: bark
		  speaker: dock_clerk
		  priority: 1
		  secrecy: open
		  - The coins are {player.coins}. #secrecy:hidden #line:hidden_line
		""", _tiers())
	_assert_none(result)


func test_unknown_writer_tier_is_ignored() -> void:
	var result := _compile("""
		language 1
		facts
		  player.coins : int stored
		storylet harbor.hidden
		  scope: bark
		  speaker: dock_clerk
		  priority: 2
		  secrecy: hidden
		  ~ set player.coins = 2
		  - The ledger stays shut. #line:hidden_line
		storylet harbor.open
		  scope: bark
		  speaker: dock_clerk
		  priority: 1
		  secrecy: open
		  - The coins are {player.coins}. #line:open_line
		""", _tiers())
	_assert_none(result)
	var pack: WyrdLinkedPack = result["pack"]
	assert_eq(pack.xref.writer_tiers("player.coins"), ["hidden"])


func test_sealed_document_writer_warns_on_an_open_paragraph() -> void:
	var result := _compile("""
		language 1
		facts
		  player.coins : int stored
		document harbor_note "Harbor Note" #secrecy:open #line:note_title
		  text: live
		  page
		    The coins are {player.coins}. #line:note_body
		document harbor_ledger "Harbor Ledger" #secrecy:sealed #line:ledger_title
		  text: live
		  page
		    The ledger stays shut. #line:ledger_shut
		  on_read:
		    ~ set player.coins = 1
		""", _tiers())
	_assert_one(
		result,
		"{player.coins}",
		"text at secrecy \"open\" shows \"player.coins\", which is only set at secrecy \"sealed\" or higher"
	)
	var pack: WyrdLinkedPack = result["pack"]
	assert_eq(pack.xref.writer_tiers("player.coins"), ["sealed"])


func test_document_fact_writer_is_untiered() -> void:
	var result := _compile("""
		language 1
		facts
		  player.clearance : symbol stored
		document harbor_note "Harbor Note" #secrecy:open #line:note_title
		  text: live
		  page
		    The mark is {player.clearance}. #line:note_body
		document harbor_gazette "Harbor Gazette" publishes_by harbor_guild every 1 day delay 1 hour
		  fact player.clearance
		""", _tiers())
	_assert_none(result)
	var pack: WyrdLinkedPack = result["pack"]
	var writers: Array = _fact(pack, "player.clearance")["writers"]
	assert_eq(writers.size(), 1)
	assert_eq(str(writers[0]["kind"]), "document")
	assert_false(writers[0].has("tier"))
	assert_eq(pack.xref.writer_tiers("player.clearance"), [""])


func test_choice_effect_writer_warns_on_untiered_text() -> void:
	var result := _compile("""
		language 1
		facts
		  player.coins : int stored
		quest ferry_toll "The Ferry Toll"
		  stage arrive
		    scene dock.talk
		    -> done
		  stage done
		scene dock.talk
		  narrator: The coins are {player.coins}. #line:dock_coins
		  * [Pay the toll] -> end #secrecy:sealed #line:c_pay
		    ~ set player.coins = 2
		  -> end
		""", _tiers())
	_assert_one(
		result,
		"{player.coins}",
		"text with no secrecy shows \"player.coins\", which is only set at secrecy \"sealed\" or higher"
	)


func test_fact_with_no_writers_does_not_warn() -> void:
	var result := _compile("""
		language 1
		facts
		  player.coins : int stored
		storylet harbor.open
		  scope: bark
		  speaker: dock_clerk
		  secrecy: open
		  - The coins are {player.coins}. #line:open_line
		""", _tiers())
	_assert_none(result)
	var diagnostics: WyrdDiagnostics = result["diagnostics"]
	assert_true(diagnostics.format().contains("warning[W_FACT_NEVER_SET]"))


func _compile(body: String, tiers: PackedStringArray = PackedStringArray()) -> Dictionary:
	var source := _text(body)
	var diagnostics := WyrdDiagnostics.new()
	var path := "user://wyrd_secrecy_%d.wyrd" % Time.get_ticks_usec()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(source)
	file.close()
	var pack: WyrdLinkedPack
	if tiers.is_empty():
		pack = WyrdPack.compile(PackedStringArray([path]), "gullhaven", 1, null, diagnostics, path, true)
	else:
		pack = WyrdPack.compile(PackedStringArray([path]), "gullhaven", 1, null, diagnostics, path, true, tiers)
	return {"diagnostics": diagnostics, "pack": pack, "source": source}


func _assert_one(result: Dictionary, needle: String, message: String) -> void:
	var diagnostics: WyrdDiagnostics = result["diagnostics"]
	assert_false(diagnostics.has_errors(), diagnostics.format())
	var hits := _leaks(diagnostics)
	assert_eq(hits.size(), 1, diagnostics.format())
	var hit: WyrdDiagnostic = hits[0]
	assert_eq(hit.message, message)
	var span := _span(str(result["source"]), needle)
	assert_eq(hit.line, span.x, diagnostics.format())
	assert_eq(hit.col, span.y, diagnostics.format())


func _assert_none(result: Dictionary) -> void:
	var diagnostics: WyrdDiagnostics = result["diagnostics"]
	assert_false(diagnostics.has_errors(), diagnostics.format())
	assert_eq(_leaks(diagnostics).size(), 0, diagnostics.format())


func _leaks(diagnostics: WyrdDiagnostics) -> Array:
	var hits: Array = []
	for item in diagnostics.items:
		if item.code == WyrdDiagnostic.W_SECRECY_LEAK:
			hits.append(item)
	return hits


func _span(source: String, needle: String) -> Vector2i:
	var lines := source.split("\n")
	for i in lines.size():
		var col := lines[i].find(needle)
		if col >= 0:
			return Vector2i(i + 1, col + 1)
	return Vector2i(-1, -1)


func _fact(pack: WyrdLinkedPack, key: String) -> Dictionary:
	for fact in pack.xref.facts:
		if str(fact["key"]) == key:
			return fact
	return {}


func _text(body: String) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for line in body.strip_edges().split("\n"):
		if line.begins_with("\t\t"):
			lines.append(line.substr(2))
		elif line.begins_with("\t"):
			lines.append(line.substr(1))
		else:
			lines.append(line)
	return "\n".join(lines) + "\n"
