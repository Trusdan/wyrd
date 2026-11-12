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


func test_mixed_types_compare_unequal_without_a_script_error() -> void:
	var pairs: Array = [
		[true, 1],
		[1, true],
		[false, 0],
		[0, false],
		[true, "true"],
		["true", true],
		[false, "false"],
		[true, &"true"],
		[&"false", false],
		[true, 1.0],
		[0.0, false],
		[true, Vector2(1, 0)],
		[Vector2.ZERO, false],
		[true, []],
		[[], false],
		[false, {"on": true}],
		[1, "1"],
		["1", 1],
		[1, &"1"],
		[&"ready", "ready"],
		["ready", &"ready"],
		[1, Vector2(1, 0)],
		[[1], {"a": 1}],
		[PackedInt32Array([1]), [1]],
		[Color(1, 0, 0), Vector2(1, 0)],
		[Vector2i(1, 0), 1],
		[&"ready", 1],
	]
	for pair in pairs:
		var left: Variant = pair[0]
		var right: Variant = pair[1]
		assert_eq(_eval_op(left, right, WyrdOpcodes.EQ), false, "%s == %s" % [left, right])
		assert_eq(_eval_op(left, right, WyrdOpcodes.NE), true, "%s != %s" % [left, right])
	assert_eq(_eval_in_set(true, [1, "true", &"true"]), false)
	assert_eq(_eval_in_set("ready", [&"ready"]), false)
	assert_engine_error_count(0)


func test_same_type_comparisons_stay() -> void:
	assert_eq(_eval_op(true, true, WyrdOpcodes.EQ), true)
	assert_eq(_eval_op(true, false, WyrdOpcodes.EQ), false)
	assert_eq(_eval_op(false, false, WyrdOpcodes.EQ), true)
	assert_eq(_eval_op(true, false, WyrdOpcodes.NE), true)
	assert_eq(_eval_op(false, false, WyrdOpcodes.NE), false)
	assert_eq(_eval_op(2, 2, WyrdOpcodes.EQ), true)
	assert_eq(_eval_op(2, 3, WyrdOpcodes.EQ), false)
	assert_eq(_eval_op(2, 3, WyrdOpcodes.NE), true)
	assert_eq(_eval_op(1, 1.0, WyrdOpcodes.EQ), true)
	assert_eq(_eval_op(1.0, 1, WyrdOpcodes.EQ), true)
	assert_eq(_eval_op(0, 0.0, WyrdOpcodes.NE), false)
	assert_eq(_eval_op(1.0, 2.0, WyrdOpcodes.EQ), false)
	assert_eq(_eval_op(1.0, 2.0, WyrdOpcodes.NE), true)
	assert_eq(_eval_op(&"ready", &"ready", WyrdOpcodes.EQ), true)
	assert_eq(_eval_op(&"ready", &"idle", WyrdOpcodes.EQ), false)
	assert_eq(_eval_op(&"ready", &"idle", WyrdOpcodes.NE), true)
	assert_eq(_eval_op("ready", "ready", WyrdOpcodes.EQ), true)
	assert_eq(_eval_op("ready", "idle", WyrdOpcodes.NE), true)
	assert_eq(_eval_op(Vector2(1, 2), Vector2(1, 2), WyrdOpcodes.EQ), true)
	assert_eq(_eval_op(Vector2(1, 2), Vector2(3, 4), WyrdOpcodes.NE), true)
	assert_eq(_eval_op([1, 2], [1, 2], WyrdOpcodes.EQ), true)
	assert_eq(_eval_op([1, 2], [2, 1], WyrdOpcodes.EQ), false)
	assert_eq(_eval_op({"a": 1}, {"a": 1}, WyrdOpcodes.EQ), true)
	assert_eq(_eval_in_set(&"ready", [&"idle", &"ready"]), true)
	assert_eq(_eval_in_set(&"gone", [&"idle", &"ready"]), false)
	assert_eq(_eval_op(null, true, WyrdOpcodes.EQ), false)
	assert_eq(_eval_op(null, true, WyrdOpcodes.NE), false)
	assert_eq(_eval_op(1, null, WyrdOpcodes.EQ), false)
	assert_eq(_eval_op(1, null, WyrdOpcodes.NE), false)
	assert_eq(_eval_op(null, null, WyrdOpcodes.EQ), false)
	assert_eq(_eval_op(null, null, WyrdOpcodes.NE), false)
	assert_engine_error_count(0)


func test_fact_values_of_another_type_compare_unequal() -> void:
	var eq_flag := _compile("flag == true")
	var ne_flag := _compile("flag != true")
	var eq_count := _compile("count == 1")
	var ne_count := _compile("count != 1")
	var eq_label := _compile("label == ready")
	var ne_label := _compile("label != ready")
	var eq_hours := _compile("count == hour")
	var ne_hours := _compile("count != hour")
	var member := _compile("label in [ready, idle]")
	var eval := WyrdRpnEval.new()
	for value in [1, "true", 1.0, &"true", Vector2.ZERO]:
		assert_eq(eval.eval(eq_flag, {"flag": value}), false, str(value))
		assert_eq(eval.eval(ne_flag, {"flag": value}), true, str(value))
	assert_eq(eval.eval(eq_flag, {"flag": true}), true)
	assert_eq(eval.eval(ne_flag, {"flag": true}), false)
	assert_eq(eval.eval(eq_flag, {"flag": false}), false)
	assert_eq(eval.eval(ne_flag, {"flag": false}), true)
	assert_eq(eval.eval(eq_flag, {}), false)
	assert_eq(eval.eval(ne_flag, {}), false)
	assert_eq(eval.eval(eq_count, {"count": "1"}), false)
	assert_eq(eval.eval(ne_count, {"count": "1"}), true)
	assert_eq(eval.eval(eq_count, {"count": true}), false)
	assert_eq(eval.eval(ne_count, {"count": true}), true)
	assert_eq(eval.eval(eq_count, {"count": 1}), true)
	assert_eq(eval.eval(ne_count, {"count": 1}), false)
	assert_eq(eval.eval(eq_count, {"count": 1.0}), true)
	assert_eq(eval.eval(ne_count, {"count": 1.0}), false)
	assert_eq(eval.eval(eq_count, {"count": 2.0}), false)
	assert_eq(eval.eval(eq_label, {"label": &"ready"}), true)
	assert_eq(eval.eval(ne_label, {"label": &"ready"}), false)
	assert_eq(eval.eval(eq_label, {"label": &"idle"}), false)
	assert_eq(eval.eval(ne_label, {"label": &"idle"}), true)
	assert_eq(eval.eval(eq_label, {"label": "ready"}), false)
	assert_eq(eval.eval(ne_label, {"label": "ready"}), true)
	assert_eq(eval.eval(eq_label, {"label": true}), false)
	assert_eq(eval.eval(ne_label, {"label": 1}), true)
	assert_eq(eval.eval(eq_hours, {"count": true, "hour": 1}), false)
	assert_eq(eval.eval(ne_hours, {"count": true, "hour": 1}), true)
	assert_eq(eval.eval(eq_hours, {"count": 1, "hour": "1"}), false)
	assert_eq(eval.eval(ne_hours, {"count": "1", "hour": 1}), true)
	assert_eq(eval.eval(eq_hours, {"count": 2, "hour": 2}), true)
	assert_eq(eval.eval(ne_hours, {"count": 2, "hour": 2}), false)
	assert_eq(eval.eval(member, {"label": &"ready"}), true)
	assert_eq(eval.eval(member, {"label": &"gone"}), false)
	assert_eq(eval.eval(member, {"label": true}), false)
	assert_eq(eval.eval(member, {"label": "ready"}), false)
	var bound := WyrdRpnEval.new()
	bound.bind_facts(PackedStringArray(["flag"]))
	bound.prepare(eq_flag)
	bound.prepare(ne_flag)
	assert_eq(bound.eval_bound(eq_flag, PackedInt32Array([1])), false)
	assert_eq(bound.eval_bound(ne_flag, PackedInt32Array([0])), true)
	assert_engine_error_count(0)


func _compile(text: String) -> WyrdCompiledCondition:
	var diagnostics := WyrdDiagnostics.new()
	var compiled := WyrdCondition.new().compile(text, _schema(), diagnostics, "sample.wyrd", 1, 1)
	assert_eq(diagnostics.items.size(), 0, text)
	return compiled


func _eval_op(left: Variant, right: Variant, op: int) -> Variant:
	var compiled := WyrdCompiledCondition.new()
	compiled.consts = [left, right]
	compiled.code = PackedInt32Array([
		WyrdOpcodes.PUSH_CONST, 0,
		WyrdOpcodes.PUSH_CONST, 1,
		op,
	])
	return WyrdRpnEval.new().eval(compiled, {})


func _eval_in_set(needle: Variant, items: Array) -> Variant:
	var compiled := WyrdCompiledCondition.new()
	var consts: Array = [needle]
	var code: Array[int] = [WyrdOpcodes.PUSH_CONST, 0]
	for item in items:
		consts.append(item)
		code.append(WyrdOpcodes.PUSH_CONST)
		code.append(consts.size() - 1)
	code.append(WyrdOpcodes.IN_SET)
	code.append(items.size())
	compiled.consts = consts
	compiled.code = PackedInt32Array(code)
	return WyrdRpnEval.new().eval(compiled, {})


func _schema() -> WyrdFactSchema:
	var schema := WyrdFactSchema.new()
	for key in ["player.coins", "ferry.toll_coins", "hour", "count"]:
		_store(schema, key, &"int")
	_store(schema, "flag", &"bool")
	_store(schema, "label", &"symbol")
	return schema


func _store(schema: WyrdFactSchema, key: String, type_name: StringName) -> void:
	var fact := WyrdFact.new()
	fact.key = key
	for part in key.split("."):
		fact.segments.append(part)
	fact.type_name = type_name
	fact.origin = &"stored"
	fact.valid = true
	schema.entries.append(fact)
