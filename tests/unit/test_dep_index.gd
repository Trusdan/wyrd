extends GutTest

## The index agrees with a direct scan of reads. Patterns match the whole key.


func test_exact_keys_are_sorted_and_deduped() -> void:
	var index := WyrdDepIndex.new()
	index.build([
		_cond([&"player.coins", &"season"]),
		_cond([&"season"]),
		_cond([&"player.coins"]),
		_cond([&"hour"]),
	])
	assert_eq(_ints(index.affected([&"player.coins"])), [0, 2])
	assert_eq(_ints(index.affected([&"season", &"player.coins"])), [0, 1, 2])
	assert_eq(_ints(index.affected([&"missing"])), [])
	assert_eq(_ints(index.affected([&"player.coins", &"player.coins"])), [0, 2])
	assert_eq(index.keys, 3)
	assert_eq(index.entries, 5)


func test_pattern_depends_on_the_whole_key() -> void:
	var index := WyrdDepIndex.new()
	index.build([
		_cond([&"npc.{id}.alive"]),
		_cond([&"town.{id}.district.{id}.open"]),
		_cond([&"{id}.flag"]),
		_cond([&"player.coins"]),
	])
	assert_eq(_ints(index.affected([&"npc.ferry.alive"])), [0])
	assert_eq(_ints(index.affected([&"npc.other.alive"])), [0])
	assert_eq(_ints(index.affected([&"npc.ferry.met"])), [])
	assert_eq(_ints(index.affected([&"npc.alive"])), [])
	assert_eq(_ints(index.affected([&"town.west.district.dock.open"])), [1])
	assert_eq(_ints(index.affected([&"town.west.lane.dock.open"])), [])
	assert_eq(_ints(index.affected([&"ferry.flag"])), [2])
	assert_eq(_ints(index.affected([&"ferry.flag.extra"])), [])
	assert_eq(_ints(index.affected([&"player.coins", &"npc.ferry.alive"])), [0, 3])


func test_computed_segment_uses_the_schema_pattern() -> void:
	var compiled := _compile("player.coins > 0 and npc.{holder(ferry)}.alive")
	assert_true(compiled.reads.has(&"player.coins"))
	assert_true(compiled.reads.has(&"npc.{id}.alive"))
	var code := compiled.code.duplicate()
	var index := WyrdDepIndex.new()
	index.build([compiled])
	assert_eq(compiled.code, code)
	assert_eq(_ints(index.affected([&"npc.ferry.alive"])), [0])
	assert_eq(_ints(index.affected([&"npc.clerk.alive"])), [0])
	assert_eq(_ints(index.affected([&"npc.ferry.met"])), [])
	assert_eq(_ints(index.affected([&"player.coins"])), [0])


func test_random_fixture_matches_a_direct_scan() -> void:
	var rng := WyrdRng.new(0x57595244)
	var exact: Array[StringName] = []
	for i in 40:
		exact.append(StringName("gullhaven.fact_%02d" % i))
	var patterns: Array[StringName] = [
		&"npc.{id}.alive",
		&"npc.{id}.met",
		&"place.{id}.open",
		&"{id}.flag",
		&"gullhaven.{id}.rank",
		&"town.{id}.district.{id}.open",
	]
	var conditions: Array[WyrdCompiledCondition] = []
	for _n in 500:
		var item := WyrdCompiledCondition.new()
		var width := rng.randi_range(1, 4)
		for _j in width:
			if rng.randi_range(0, 3) == 0:
				item.reads.append(patterns[rng.randi_range(0, patterns.size() - 1)])
			else:
				item.reads.append(exact[rng.randi_range(0, exact.size() - 1)])
		conditions.append(item)
	var index := WyrdDepIndex.new()
	index.build(conditions)
	for _q in 25:
		var changed: Array[StringName] = []
		var width := rng.randi_range(1, 8)
		for _j in width:
			changed.append(_random_key(rng, exact))
		assert_eq(_ints(index.affected(changed)), _ints(_brute(conditions, changed)))


func test_empty_input_stays_empty() -> void:
	var index := WyrdDepIndex.new()
	var none: Array[WyrdCompiledCondition] = []
	index.build(none)
	var keys: Array[StringName] = [&"player.coins"]
	assert_eq(index.affected(keys).size(), 0)
	assert_eq(index.entries, 0)
	assert_eq(index.keys, 0)


func _cond(reads: Array[StringName]) -> WyrdCompiledCondition:
	var item := WyrdCompiledCondition.new()
	item.reads = reads
	return item


func _compile(text: String) -> WyrdCompiledCondition:
	var diagnostics := WyrdDiagnostics.new()
	var compiled := WyrdCondition.new().compile(text, _schema(), diagnostics, "sample.wyrd", 1, 1)
	assert_eq(diagnostics.items.size(), 0, text)
	return compiled


func _schema() -> WyrdFactSchema:
	var schema := WyrdFactSchema.new()
	_fact(schema, "player.coins", "int")
	_fact(schema, "npc.{id}.alive", "bool")
	return schema


func _fact(schema: WyrdFactSchema, key: String, type_name: String) -> void:
	var fact := WyrdFact.new()
	fact.key = key
	for part in key.split("."):
		fact.segments.append(part)
	fact.type_name = StringName(type_name)
	fact.origin = &"stored"
	fact.valid = true
	schema.entries.append(fact)


func _random_key(rng: WyrdRng, exact: Array[StringName]) -> StringName:
	match rng.randi_range(0, 6):
		0:
			return StringName("npc.person_%02d.alive" % rng.randi_range(0, 15))
		1:
			return StringName("npc.person_%02d.met" % rng.randi_range(0, 15))
		2:
			return StringName("place.place_%02d.open" % rng.randi_range(0, 10))
		3:
			return StringName("holder_%02d.flag" % rng.randi_range(0, 10))
		4:
			return StringName("gullhaven.rank_%02d.rank" % rng.randi_range(0, 8))
		5:
			return StringName("town.zone_%02d.district.block_%02d.open" % [rng.randi_range(0, 4), rng.randi_range(0, 4)])
		_:
			return exact[rng.randi_range(0, exact.size() - 1)]


func _brute(conditions: Array[WyrdCompiledCondition], changed: Array[StringName]) -> PackedInt32Array:
	var hits := PackedInt32Array()
	for i in conditions.size():
		var matched := false
		for read in conditions[i].reads:
			if matched:
				break
			for key in changed:
				if _read_hit(String(read), String(key)):
					hits.append(i)
					matched = true
					break
	return hits


func _read_hit(read: String, key: String) -> bool:
	var left := read.split(".")
	var right := key.split(".")
	var patterned := false
	for segment in left:
		if segment.begins_with("{"):
			patterned = true
			break
	if not patterned:
		return read == key
	if left.size() != right.size():
		return false
	for i in left.size():
		if left[i].begins_with("{"):
			continue
		if left[i] != right[i]:
			return false
	return true


func _ints(row: PackedInt32Array) -> Array:
	var out: Array = []
	for n in row:
		out.append(int(n))
	return out
