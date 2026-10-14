extends GutTest


func test_concrete_match_pattern_match_and_miss() -> void:
	var schema := WyrdFactSchema.new()
	_append(schema, "player.coins")
	_append(schema, "npc.{id}.alive")
	var coins := schema.lookup(_segs("player", "coins"))
	assert_not_null(coins)
	assert_eq(coins.key, "player.coins")
	var alive := schema.lookup(_segs("npc", "ferry", "alive"))
	assert_not_null(alive)
	assert_eq(alive.key, "npc.{id}.alive")
	assert_null(schema.lookup(_segs("player", "missing")))
	assert_null(schema.lookup(PackedStringArray()))


func test_concrete_key_beats_pattern_and_wildcard_query_skips_exact() -> void:
	var schema := WyrdFactSchema.new()
	_append(schema, "npc.{id}.alive")
	_append(schema, "npc.ferry.alive")
	var concrete := schema.lookup(_segs("npc", "ferry", "alive"))
	assert_eq(concrete.key, "npc.ferry.alive")
	var pattern := schema.lookup(_segs("npc", "{id}", "alive"))
	assert_eq(pattern.key, "npc.{id}.alive")
	_append(schema, "hour")
	assert_eq(schema.lookup(_segs("hour")).key, "hour")


func _append(schema: WyrdFactSchema, key: String) -> void:
	var fact := WyrdFact.new()
	fact.key = key
	for part in key.split("."):
		fact.segments.append(part)
	fact.type_name = &"int"
	fact.origin = &"stored"
	fact.valid = true
	schema.entries.append(fact)


func _segs(a: String, b: String = "", c: String = "") -> PackedStringArray:
	var parts := PackedStringArray()
	parts.append(a)
	if b != "":
		parts.append(b)
	if c != "":
		parts.append(c)
	return parts
