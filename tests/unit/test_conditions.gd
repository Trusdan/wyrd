extends GutTest


func test_signatures_include_m5_and_reject_duplicates() -> void:
	var signatures := WyrdSignatures.new()
	assert_eq(signatures.milestone(&"knows"), "M5")
	assert_eq(signatures.milestone(&"believes"), "M5")
	assert_eq(signatures.milestone(&"held"), "M5")
	assert_eq(signatures.milestone(&"has"), "")
	assert_false(signatures.signature(&"nearby").is_empty())
	assert_false(signatures.register(&"has", [], &"bool"))
	assert_true(signatures.register(&"gullhaven_score", [{"name": &"id", "type": &"entity"}], &"int"))
	assert_eq(String(signatures.signature(&"gullhaven_score")["return"]), "int")


func test_specificity_counts_top_level_and_clauses() -> void:
	assert_eq(_spec("true"), 1)
	assert_eq(_spec("true and false and true"), 3)
	assert_eq(_spec("(true and false) or true"), 1)
	assert_eq(_spec("not (true and false)"), 1)
	assert_eq(_spec("not true and false"), 2)
	assert_eq(_spec(")"), 0)


func test_examples_reads_and_short_circuit_jumps() -> void:
	var coins := _ok("player.coins >= 5 and has(player, harbor_pass)")
	assert_eq(coins.specificity, 2)
	assert_true(coins.reads.has(&"player.coins"))
	assert_eq(_eval(coins, {"player.coins": 5}), true)
	var both := _ok("player.coins > 0 or ferry.toll_coins > 0")
	assert_true(both.reads.has(&"player.coins"))
	assert_true(both.reads.has(&"ferry.toll_coins"))
	assert_true(_has_op(both, "JUMP_IF_TRUE"))
	var skipped := _ok("false and player.coins > 0")
	assert_true(skipped.reads.has(&"player.coins"))
	assert_true(_has_op(skipped, "JUMP_IF_FALSE"))
	assert_eq(_eval(skipped, {"player.coins": 5}), false)
	assert_eq(_eval(_ok("player.coins > 0"), {}), false)
	assert_eq(_eval(_ok("hour in 6..18"), {"hour": 6}), true)
	assert_eq(_eval(_ok("hour in 6..18"), {"hour": 18}), true)
	assert_eq(_eval(_ok("hour in 6..18"), {"hour": 5}), false)
	assert_eq(_eval(_ok("season == spring"), {"season": &"spring"}), true)
	assert_eq(_eval(_ok("fact(npc, holder(ferry), alive)"), {"npc.ferry.alive": true}), true)
	assert_eq(_eval(_ok("npc.{holder(ferry)}.alive"), {"npc.ferry.alive": true}), true)


func test_arithmetic_units_and_day_override() -> void:
	assert_eq(_eval(_ok("2 + 3 * 4 == 14"), {}), true)
	assert_eq(_eval(_ok("(2 + 3) * 4 == 20"), {}), true)
	assert_eq(_eval(_ok("5 / 2 == 2"), {}), true)
	assert_eq(_eval(_ok("5.0 / 2 == 2.5"), {}), true)
	assert_eq(_eval(_ok("not true == false"), {}), true)
	assert_true(_has_int(_ok("deed_score(player, within: 14d) > 0"), 20160))
	assert_true(_has_int(_compile("deed_score(player, within: 2d) > 0", 1000).compiled, 2000))
	assert_true(_has_float(_ok("nearby(player, 6m, tag: corpse) > 0"), 6.0))
	assert_true(_has_int(_ok("deed_score(player, within: 6m) > 0"), 6))
	assert_eq(_codes("6m"), ["E_EXPR_UNIT"])
	assert_eq(_codes("6h"), ["E_NOT_BOOL"])


func test_error_codes() -> void:
	assert_eq(_codes("\"coins\""), ["E_EXPR_SYNTAX"])
	assert_eq(_codes("player.coins >= 1 )"), ["E_EXPR_UNEXPECTED"])
	assert_eq(_codes("has(item_or_tag: harbor_pass, player)"), ["E_EXPR_ARG_ORDER"])
	assert_eq(_codes("has(player, harbor_pass, nope: true)"), ["E_ARG_NAME"])
	assert_eq(_codes("has(player, 1)"), ["E_ARG_TYPE"])
	assert_eq(_codes("frob(player)"), ["E_UNKNOWN_FUNCTION"])
	assert_eq(_codes("not player.coins"), ["E_OP_TYPE"])
	assert_eq(_codes("player.coins"), ["E_NOT_BOOL"])
	assert_eq(_codes("foo.bar > 0"), ["E_UNKNOWN_FACT"])
	assert_eq(_codes("chance(0.5)", WyrdCondition.CONTEXT_WAIT), ["E_CHANCE_CONTEXT"])
	assert_true(_ok("chance(1)").uses_chance)
	assert_eq(_codes("world.weather == calm", WyrdCondition.CONTEXT_WAIT), ["E_WAIT_RESOLVER_MODE"])
	assert_eq(_codes("world.tide > 0", WyrdCondition.CONTEXT_WAIT), ["E_WAIT_RESOLVER_MODE"])
	var clean := _compile("world.hour > 0 and world.season == spring", 1440, WyrdCondition.CONTEXT_WAIT)
	assert_eq(clean.codes, [])
	assert_eq(clean.compiled.specificity, 2)


func test_interp_forms_and_unbalanced() -> void:
	var parsed := _scene("""
language 1
facts
  player.coins : int stored
  season : symbol stored
  hour : int stored
  npc.{id}.alive : bool source: world.is_alive invalidate: on_event(npc_died)

scene toll.gate
  clerk: Toll {player.coins}.
  clerk: {if season == spring}{if hour in 6..18}day{else}night{end}{else}off{end}
  clerk: Ask {holder(ferry)|variants}.
  clerk: {fact(npc, holder(ferry), alive)}
  clerk: {if player.coins >= 5}paid
  clerk: {else} now
""")
	assert_eq(parsed.kinds[0], "value")
	assert_eq(parsed.kinds[1], "if")
	assert_eq(parsed.kinds[2], "variants")
	assert_eq(parsed.kinds[3], "value")
	assert_true(parsed.codes.has("E_INTERP_UNBALANCED"))
	assert_eq(parsed.reads[3], "npc.{id}.alive")


func _spec(text: String) -> int:
	return _compile(text).compiled.specificity


func _ok(text: String) -> WyrdCompiledCondition:
	var row := _compile(text)
	assert_eq(row.codes, [], text)
	return row.compiled


func _codes(text: String, context: StringName = WyrdCondition.CONTEXT_STORYLET) -> Array:
	return _compile(text, 1440, context).codes


func _compile(text: String, day: int = 1440, context: StringName = WyrdCondition.CONTEXT_STORYLET) -> Dictionary:
	var diagnostics := WyrdDiagnostics.new()
	var compiled := WyrdCondition.new().compile(text, _schema(), diagnostics, "sample.wyrd", 1, 1, context, day)
	var codes: Array = []
	for item in diagnostics.items:
		codes.append(String(item.code))
	return {"codes": codes, "compiled": compiled}


func _eval(compiled: WyrdCompiledCondition, facts: Dictionary) -> Variant:
	return WyrdRpnEval.new().eval(compiled, facts, {
		&"has": func(args: Array) -> bool: return str(args[1]) == "harbor_pass",
		&"holder": func(_args: Array) -> StringName: return &"ferry",
	})


func _has_op(compiled: WyrdCompiledCondition, name: String) -> bool:
	for line in WyrdOpcodes.disasm(compiled.code, compiled.consts):
		if line.contains(name):
			return true
	return false


func _has_int(compiled: WyrdCompiledCondition, value: int) -> bool:
	for item in compiled.consts:
		if item is int and int(item) == value:
			return true
	return false


func _has_float(compiled: WyrdCompiledCondition, value: float) -> bool:
	for item in compiled.consts:
		if item is float and is_equal_approx(float(item), value):
			return true
	return false


func _schema() -> WyrdFactSchema:
	var schema := WyrdFactSchema.new()
	_fact(schema, "player.coins", "int", "stored", "", "")
	_fact(schema, "ferry.toll_coins", "int", "stored", "", "")
	_fact(schema, "season", "symbol", "stored", "", "")
	_fact(schema, "hour", "int", "stored", "", "")
	_fact(schema, "secret.missing_toll", "bool", "stored", "", "")
	_fact(schema, "npc.{id}.alive", "bool", "resolved", "on_event", "npc_died")
	_fact(schema, "world.weather", "symbol", "resolved", "per_query", "")
	_fact(schema, "world.tide", "int", "resolved", "", "")
	_fact(schema, "world.hour", "int", "resolved", "poll", "15")
	_fact(schema, "world.season", "symbol", "resolved", "on_event", "season_changed")
	return schema


func _fact(schema: WyrdFactSchema, key: String, type_name: String, origin: String, invalidate: String, arg: String) -> void:
	var fact := WyrdFact.new()
	fact.key = key
	for part in key.split("."):
		fact.segments.append(part)
	fact.type_name = StringName(type_name)
	fact.origin = StringName(origin)
	fact.invalidate = StringName(invalidate)
	fact.invalidate_arg = arg
	fact.valid = true
	schema.entries.append(fact)


func _scene(text: String) -> Dictionary:
	var source := WyrdSource.new("sample.wyrd", text)
	var file_diag := WyrdDiagnostics.new()
	var tokens := WyrdLexer.new().tokenize(source, file_diag)
	var tree := WyrdParser.new().parse_tokens(source, tokens, file_diag)
	var kinds: PackedStringArray = PackedStringArray()
	var codes: PackedStringArray = PackedStringArray()
	var reads: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {}
	for token in tokens:
		if token.kind != &"interp" or seen.has(token.line):
			continue
		seen[token.line] = true
		var line_tokens: Array[WyrdToken] = []
		for item in tokens:
			if item.line == token.line and item.kind != &"eof":
				line_tokens.append(item)
		var diag := WyrdDiagnostics.new()
		var root := WyrdInterp.new().compile_line(line_tokens, tree.schema, diag, source.path)
		for kid in root.kids:
			if kid.kind == &"text":
				continue
			kinds.append(String(kid.kind))
			if kid.payload is WyrdCompiledCondition:
				var compiled := kid.payload as WyrdCompiledCondition
				reads.append("" if compiled.reads.is_empty() else String(compiled.reads[0]))
			elif kid.kind == &"if" and kid.payload is WyrdCompiledCondition:
				reads.append("")
			else:
				reads.append("")
		for item in diag.items:
			codes.append(String(item.code))
	return {"codes": codes, "kinds": kinds, "reads": reads}
