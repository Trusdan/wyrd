extends GutTest

## The load-time plan matches the dictionary walk and does not rewrite saved code.


func test_shim_constructs_the_runtime_evaluator() -> void:
	var eval: WyrdRpnEval = preload("res://tests/support/wyrd_rpn_eval.gd").new()
	assert_not_null(eval)


func test_prepare_leaves_saved_opcodes_unchanged() -> void:
	var compiled := _compile("player.coins >= 5 and ferry.toll_coins != 0")
	var code := compiled.code.duplicate()
	var eval := WyrdRpnEval.new()
	eval.bind_facts(PackedStringArray(["player.coins", "ferry.toll_coins", "hour"]))
	eval.prepare(compiled)
	assert_eq(compiled.code, code)
	var ip := 0
	while ip < code.size():
		var op := code[ip]
		assert_true(op >= WyrdOpcodes.PUSH_CONST and op <= WyrdOpcodes.JUMP_IF_TRUE)
		if op == WyrdOpcodes.CALL:
			ip += 3
		elif op == WyrdOpcodes.PUSH_CONST or op == WyrdOpcodes.LOAD_FACT or op == WyrdOpcodes.LOAD_KEY or op == WyrdOpcodes.IN_SET or op == WyrdOpcodes.JUMP or op == WyrdOpcodes.JUMP_IF_FALSE or op == WyrdOpcodes.JUMP_IF_TRUE:
			ip += 2
		else:
			ip += 1


func test_bound_int_walk_matches_the_dictionary_walk() -> void:
	var texts: PackedStringArray = PackedStringArray([
		"player.coins >= 5 and ferry.toll_coins >= 1",
		"player.coins > 0 or ferry.toll_coins > 0",
		"player.coins == 2",
		"player.coins != 2",
		"hour < 6",
		"hour <= 6",
		"hour > 6",
		"not player.coins >= 5",
		"player.coins >= 1 and ferry.toll_coins >= 1 and hour >= 1",
	])
	var rows: Array = [
		[5, 1, 0],
		[4, 9, 0],
		[0, 1, 0],
		[0, 0, 0],
		[2, 0, 0],
		[3, 0, 5],
		[2, 0, 6],
		[0, 0, 7],
	]
	var keys := PackedStringArray(["player.coins", "ferry.toll_coins", "hour"])
	for text in texts:
		var compiled := _compile(text)
		var eval := WyrdRpnEval.new()
		eval.bind_facts(keys)
		eval.prepare(compiled)
		for row in rows:
			var values := PackedInt32Array([row[0], row[1], row[2]])
			var facts := {
				"player.coins": row[0],
				"ferry.toll_coins": row[1],
				"hour": row[2],
			}
			assert_eq(eval.eval_bound(compiled, values), eval.eval(compiled, facts), text)


func test_missing_bound_fact_stays_false() -> void:
	var compiled := _compile("player.coins >= 0 and hour >= 0")
	var eval := WyrdRpnEval.new()
	eval.bind_facts(PackedStringArray(["hour"]))
	eval.prepare(compiled)
	var values := PackedInt32Array([9])
	assert_eq(eval.eval_bound(compiled, values), false)
	assert_eq(eval.eval(compiled, {"hour": 9}), false)


func _compile(text: String) -> WyrdCompiledCondition:
	var diagnostics := WyrdDiagnostics.new()
	var compiled := WyrdCondition.new().compile(text, _schema(), diagnostics, "sample.wyrd", 1, 1)
	assert_eq(diagnostics.items.size(), 0, text)
	return compiled


func _schema() -> WyrdFactSchema:
	var schema := WyrdFactSchema.new()
	for key in ["player.coins", "ferry.toll_coins", "hour"]:
		var fact := WyrdFact.new()
		fact.key = key
		for part in key.split("."):
			fact.segments.append(part)
		fact.type_name = &"int"
		fact.origin = &"stored"
		fact.valid = true
		schema.entries.append(fact)
	return schema
