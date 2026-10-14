extends RefCounted

## Fixed 10k-fact / 5k-condition timing case. Not a CI gate.
##
## Compile and fixture setup stay outside the timed loops. The warm pass is a
## second full scan. A dirty set is not part of this slice.


func measure() -> Dictionary:
	var fixture := _fixture()
	var rpn_cold := _pass_rpn(fixture)
	var rpn_warm := _pass_rpn(fixture)
	var gd_cold := _pass_gd(fixture)
	var gd_warm := _pass_gd(fixture)
	var ex_cold := _pass_expr(fixture)
	var ex_warm := _pass_expr(fixture)
	var count := int(fixture["count"])
	return {
		"checksum_match": rpn_cold["checksum"] == gd_cold["checksum"] and rpn_cold["checksum"] == ex_cold["checksum"],
		"conditions": count,
		"facts": int(fixture["facts"]),
		"godot": Engine.get_version_info()["string"],
		"os": OS.get_name(),
		"processor": OS.get_processor_name(),
		"readers": {
			"expression": _row(ex_cold, ex_warm, count),
			"gdscript": _row(gd_cold, gd_warm, count),
			"rpn": _row(rpn_cold, rpn_warm, count),
		},
		"seed": "0x57595244",
		"setup_usec": int(fixture["setup_usec"]),
	}


func _fixture() -> Dictionary:
	var started := Time.get_ticks_usec()
	var facts := 10000
	var count := 5000
	var schema := WyrdFactSchema.new()
	var values := PackedInt32Array()
	values.resize(facts)
	var fact_map := {}
	for i in facts:
		var fact := WyrdFact.new()
		var key := "gullhaven.fact_%05d" % i
		fact.key = key
		fact.segments.append("gullhaven")
		fact.segments.append("fact_%05d" % i)
		fact.type_name = &"int"
		fact.origin = &"stored"
		fact.valid = true
		schema.entries.append(fact)
	var rng := WyrdRng.new(0x57595244)
	for i in facts:
		values[i] = rng.randi_range(0, 9)
		fact_map["gullhaven.fact_%05d" % i] = values[i]
	var signatures := WyrdSignatures.new()
	var compiled: Array[WyrdCompiledCondition] = []
	var offsets := PackedInt32Array()
	var ids := PackedInt32Array()
	var thresholds := PackedInt32Array()
	var exprs: Array[Expression] = []
	var rows: Array = []
	var joiner := " and "
	var probe := Expression.new()
	if probe.parse("a >= 0 and b >= 0", PackedStringArray(["a", "b"])) != OK:
		joiner = " && "
	var letters: PackedStringArray = PackedStringArray(["a", "b", "c", "d", "e"])
	for n in count:
		var width := rng.randi_range(2, 5)
		offsets.append(ids.size())
		var parts: PackedStringArray = PackedStringArray()
		var expr_parts: PackedStringArray = PackedStringArray()
		var inputs: Array = []
		var names := PackedStringArray()
		for j in width:
			var id := rng.randi_range(0, facts - 1)
			var threshold := rng.randi_range(0, 9)
			ids.append(id)
			thresholds.append(threshold)
			parts.append("%s >= %d" % ["gullhaven.fact_%05d" % id, threshold])
			expr_parts.append("%s >= %d" % [letters[j], threshold])
			names.append(letters[j])
			inputs.append(values[id])
		var text := " and ".join(parts)
		var diagnostics := WyrdDiagnostics.new()
		var item := WyrdCondition.new().compile(text, schema, diagnostics, "bench.wyrd", 1, 1, WyrdCondition.CONTEXT_STORYLET, WyrdCondition.MINUTES_PER_DAY, signatures)
		if diagnostics.has_errors():
			push_error(diagnostics.format())
		compiled.append(item)
		var expr := Expression.new()
		var parsed := expr.parse(joiner.join(expr_parts), names)
		if parsed != OK:
			parsed = expr.parse(" && ".join(expr_parts), names)
		if parsed != OK:
			push_error("expression did not parse")
		exprs.append(expr)
		rows.append(inputs)
	return {
		"compiled": compiled,
		"count": count,
		"evals": WyrdRpnEval.new(),
		"exprs": exprs,
		"fact_map": fact_map,
		"facts": facts,
		"ids": ids,
		"offsets": offsets,
		"rows": rows,
		"setup_usec": Time.get_ticks_usec() - started,
		"thresholds": thresholds,
		"values": values,
	}


func _pass_rpn(fixture: Dictionary) -> Dictionary:
	var compiled: Array[WyrdCompiledCondition] = fixture["compiled"]
	var eval := fixture["evals"] as WyrdRpnEval
	var facts: Dictionary = fixture["fact_map"]
	var started := Time.get_ticks_usec()
	var checksum := 0
	for item in compiled:
		if eval.eval(item, facts) == true:
			checksum += 1
	return {"checksum": checksum, "usec": Time.get_ticks_usec() - started}


func _pass_gd(fixture: Dictionary) -> Dictionary:
	var values: PackedInt32Array = fixture["values"]
	var offsets: PackedInt32Array = fixture["offsets"]
	var ids: PackedInt32Array = fixture["ids"]
	var thresholds: PackedInt32Array = fixture["thresholds"]
	var started := Time.get_ticks_usec()
	var checksum := 0
	for i in offsets.size():
		var begin := offsets[i]
		var end := ids.size()
		if i + 1 < offsets.size():
			end = offsets[i + 1]
		var ok := true
		for j in range(begin, end):
			if values[ids[j]] < thresholds[j]:
				ok = false
				break
		if ok:
			checksum += 1
	return {"checksum": checksum, "usec": Time.get_ticks_usec() - started}


func _pass_expr(fixture: Dictionary) -> Dictionary:
	var exprs: Array[Expression] = fixture["exprs"]
	var rows: Array = fixture["rows"]
	var started := Time.get_ticks_usec()
	var checksum := 0
	for i in exprs.size():
		if exprs[i].execute(rows[i], null, false) == true:
			checksum += 1
	return {"checksum": checksum, "usec": Time.get_ticks_usec() - started}


func _row(cold: Dictionary, warm: Dictionary, count: int) -> Dictionary:
	return {
		"batch_cold_usec": int(cold["usec"]),
		"batch_warm_usec": int(warm["usec"]),
		"checksum": int(cold["checksum"]),
		"per_eval_cold_usec": float(cold["usec"]) / float(count),
		"per_eval_warm_usec": float(warm["usec"]) / float(count),
	}
