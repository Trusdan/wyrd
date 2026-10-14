extends GutTest


func test_stored_resolved_poll_and_doc() -> void:
	var schema := _schema(_text("""
	language 1
	facts
	  player.coins : int stored doc: "How many coins are carried."
	  tide.height : float stored
	  npc.{id}.alive : bool source: world.is_alive
	  world.season : symbol source: time.season invalidate: on_event(season_changed)
	  world.hour : int source: time.hour invalidate: poll(15)
	  world.weather : symbol source: world.weather invalidate: per_query
	"""))
	assert_eq(schema.entries.size(), 6)
	var coins := schema.entries[0]
	assert_eq(coins.key, "player.coins")
	assert_eq(String(coins.type_name), "int")
	assert_eq(String(coins.origin), "stored")
	assert_eq(coins.doc, "How many coins are carried.")
	assert_false(coins.is_pattern())
	var tide := schema.entries[1]
	assert_eq(String(tide.type_name), "float")
	var alive := schema.entries[2]
	assert_eq(alive.key, "npc.{id}.alive")
	assert_true(alive.is_pattern())
	assert_eq(alive.resolver, "world.is_alive")
	assert_eq(String(alive.origin), "resolved")
	var season := schema.entries[3]
	assert_eq(String(season.invalidate), "on_event")
	assert_eq(season.invalidate_arg, "season_changed")
	var hour := schema.entries[4]
	assert_eq(String(hour.invalidate), "poll")
	assert_eq(hour.invalidate_arg, "15")
	var weather := schema.entries[5]
	assert_eq(String(weather.invalidate), "per_query")
	assert_eq(weather.resolver, "world.weather")


func test_duplicate_key() -> void:
	var parsed := _parse(_text("""
	language 1
	facts
	  player.coins : int stored
	  player.coins : bool stored
	"""))
	assert_true(parsed.diagnostics.has_errors())
	assert_eq(parsed.diagnostics.format(), "sample.wyrd:4:3: error[E_FACTS_DUPLICATE]: duplicate fact key \"player.coins\"\n")


func test_stored_and_resolved_pattern_overlap() -> void:
	var parsed := _parse(_text("""
	language 1
	facts
	  npc.{id}.alive : bool source: world.is_alive
	  npc.ferry.alive : bool stored
	"""))
	assert_eq(
		parsed.diagnostics.format(),
		"sample.wyrd:4:3: error[E_FACTS_DUPLICATE]: fact keys \"npc.{id}.alive\" and \"npc.ferry.alive\" are both stored and resolved\n"
	)


func test_same_key_stored_and_resolved() -> void:
	var parsed := _parse(_text("""
	language 1
	facts
	  player.coins : int stored
	  player.coins : int source: bag.count
	"""))
	assert_true(parsed.diagnostics.format().contains("fact key \"player.coins\" is both stored and resolved"))


func test_overlapping_patterns_are_duplicates() -> void:
	var parsed := _parse(_text("""
	language 1
	facts
	  npc.{id}.alive : bool stored
	  npc.{name}.alive : bool stored
	"""))
	assert_eq(parsed.diagnostics.items.size(), 1)
	assert_eq(parsed.diagnostics.items[0].code, WyrdDiagnostic.E_FACTS_DUPLICATE)
	assert_eq(
		parsed.diagnostics.format(),
		"sample.wyrd:4:3: error[E_FACTS_DUPLICATE]: fact keys \"npc.{id}.alive\" and \"npc.{name}.alive\" overlap\n"
	)


func test_pattern_overlaps_a_concrete_key_in_both_orders() -> void:
	var pattern_first := _parse(_text("""
	language 1
	facts
	  npc.{id}.alive : bool stored
	  npc.miller.alive : bool stored
	"""))
	assert_eq(pattern_first.diagnostics.items.size(), 1)
	assert_eq(pattern_first.diagnostics.items[0].code, WyrdDiagnostic.E_FACTS_DUPLICATE)
	assert_eq(
		pattern_first.diagnostics.format(),
		"sample.wyrd:4:3: error[E_FACTS_DUPLICATE]: fact keys \"npc.{id}.alive\" and \"npc.miller.alive\" overlap\n"
	)
	var concrete_first := _parse(_text("""
	language 1
	facts
	  npc.miller.alive : bool stored
	  npc.{id}.alive : bool stored
	"""))
	assert_eq(concrete_first.diagnostics.items.size(), 1)
	assert_eq(concrete_first.diagnostics.items[0].code, WyrdDiagnostic.E_FACTS_DUPLICATE)
	assert_eq(
		concrete_first.diagnostics.format(),
		"sample.wyrd:4:3: error[E_FACTS_DUPLICATE]: fact keys \"npc.miller.alive\" and \"npc.{id}.alive\" overlap\n"
	)


func test_stored_and_resolved_wildcards_overlap() -> void:
	var parsed := _parse(_text("""
	language 1
	facts
	  npc.{id}.alive : bool stored
	  npc.{name}.alive : bool source: world.is_alive
	"""))
	assert_eq(parsed.diagnostics.items.size(), 1)
	assert_eq(parsed.diagnostics.items[0].code, WyrdDiagnostic.E_FACTS_DUPLICATE)
	assert_eq(
		parsed.diagnostics.format(),
		"sample.wyrd:4:3: error[E_FACTS_DUPLICATE]: fact keys \"npc.{id}.alive\" and \"npc.{name}.alive\" are both stored and resolved\n"
	)


func test_distinct_keys_do_not_overlap() -> void:
	var schema := _schema(_text("""
	language 1
	facts
	  npc.{id}.alive : bool stored
	  npc.{id}.dead : bool stored
	  npc.alive : bool stored
	  npc.{id}.alive.today : bool stored
	"""))
	assert_eq(schema.entries.size(), 4)


func test_unknown_type_is_facts_syntax() -> void:
	var parsed := _parse(_text("""
	language 1
	facts
	  player.coins : string stored
	"""))
	assert_eq(
		parsed.diagnostics.format(),
		"sample.wyrd:3:18: error[E_FACTS_SYNTAX]: unknown fact type \"string\"\n"
	)
	assert_eq(parsed.schema.entries.size(), 0)


func test_doc_escape_is_stored() -> void:
	var schema := _schema("language 1\nfacts\n  player.coins : int stored doc: \"say \\\"hi\\\"\"\n")
	assert_eq(schema.entries.size(), 1)
	assert_eq(schema.entries[0].doc, "say \"hi\"")


func test_section_7_example_has_no_errors() -> void:
	var source := WyrdSource.load_file("res://example/content/gullhaven/ferry_toll.wyrd")
	assert_not_null(source)
	var diagnostics := WyrdDiagnostics.new()
	var tree := WyrdParser.new().parse(source, diagnostics)
	assert_eq(diagnostics.format(), "")
	assert_eq(tree.children.size(), 3)
	assert_eq(String(tree.children[0].kind), "facts")
	assert_eq(tree.children[0].entries.size(), 4)
	assert_eq(String(tree.children[1].kind), "quest")
	assert_eq(tree.children[1].title, "The Ferry Toll")
	assert_eq(String(tree.children[2].kind), "scene")


class _Parsed:
	extends RefCounted
	var diagnostics: WyrdDiagnostics
	var schema: WyrdFactSchema
	var tree: WyrdNode


func _parse(text: String) -> _Parsed:
	var parsed := _Parsed.new()
	var source := WyrdSource.new("sample.wyrd", text)
	parsed.diagnostics = WyrdDiagnostics.new()
	parsed.tree = WyrdParser.new().parse(source, parsed.diagnostics)
	parsed.schema = parsed.tree.schema
	return parsed


func _text(body: String) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for line in body.strip_edges().split("\n"):
		if line.begins_with("\t"):
			lines.append(line.substr(1))
		else:
			lines.append(line)
	return "\n".join(lines) + "\n"


func _schema(text: String) -> WyrdFactSchema:
	var parsed := _parse(text)
	assert_eq(parsed.diagnostics.format(), "", parsed.diagnostics.format())
	return parsed.schema
