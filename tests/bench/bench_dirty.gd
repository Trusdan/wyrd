extends RefCounted

## Dirty-set timing on the seeded 10k-fact / 5k-condition fixture.
##
## Not a CI gate. One fixed sub-seed per changed-fact count. The first tick is
## cold. The next 1000 ticks are the warm average. Fact values are copies, so
## the caller's fixture stays put.


const WARM_TICKS := 1000
const SUB_SEED := 0x57595245


func measure(fixture: Dictionary) -> Dictionary:
	var compiled: Array[WyrdCompiledCondition] = fixture["compiled"]
	var eval := fixture["evals"] as WyrdRpnEval
	var base_values: PackedInt32Array = fixture["values"]
	var offsets: PackedInt32Array = fixture["offsets"]
	var ids: PackedInt32Array = fixture["ids"]
	var thresholds: PackedInt32Array = fixture["thresholds"]
	var names := _names(int(fixture["facts"]))
	var index := WyrdDepIndex.new()
	var started := Time.get_ticks_usec()
	index.build(compiled)
	var build_usec := Time.get_ticks_usec() - started
	var rows := {}
	var ok := true
	for count in [1, 10, 100]:
		var row := _run(count, compiled, eval, base_values, names, offsets, ids, thresholds, index)
		rows[str(count)] = row
		ok = ok and bool(row["checksum_match"])
	rows["checksum_match"] = ok
	rows["index_build_usec"] = build_usec
	rows["index_entries"] = index.entries
	rows["index_keys"] = index.keys
	return rows


func _run(
	count: int,
	compiled: Array[WyrdCompiledCondition],
	eval: WyrdRpnEval,
	base_values: PackedInt32Array,
	names: Array[StringName],
	offsets: PackedInt32Array,
	ids: PackedInt32Array,
	thresholds: PackedInt32Array,
	index: WyrdDepIndex
) -> Dictionary:
	var values := base_values.duplicate()
	var flags := _scan_rpn(compiled, eval, values)
	var rng := WyrdRng.new(SUB_SEED + count)
	var index_sum := 0
	var eval_sum := 0
	var affected_sum := 0
	var ceiling_sum := 0
	var cold := {}
	for tick in WARM_TICKS + 1:
		var picked := _pick(rng, count, values.size())
		for slot in picked:
			var next := rng.randi_range(0, 8)
			if next >= values[slot]:
				next += 1
			values[slot] = next
		var changed: Array[StringName] = []
		changed.resize(picked.size())
		for i in picked.size():
			changed[i] = names[picked[i]]
		var t0 := Time.get_ticks_usec()
		var hit := index.affected(changed)
		var index_usec := Time.get_ticks_usec() - t0
		var t1 := Time.get_ticks_usec()
		for cond in hit:
			flags[cond] = 1 if eval.eval_bound(compiled[cond], values) == true else 0
		var eval_usec := Time.get_ticks_usec() - t1
		var t2 := Time.get_ticks_usec()
		for cond in hit:
			_gd_one(int(cond), values, offsets, ids, thresholds)
		var ceiling_usec := Time.get_ticks_usec() - t2
		if tick == 0:
			cold = {
				"affected": hit.size(),
				"ceiling_eval_usec": ceiling_usec,
				"ceiling_tick_usec": index_usec + ceiling_usec,
				"eval_usec": eval_usec,
				"index_usec": index_usec,
				"tick_usec": index_usec + eval_usec,
			}
			continue
		index_sum += index_usec
		eval_sum += eval_usec
		ceiling_sum += ceiling_usec
		affected_sum += hit.size()
	var fresh := _scan_rpn(compiled, eval, values)
	var mismatch := 0
	for i in flags.size():
		if flags[i] != fresh[i]:
			mismatch += 1
	var ceiling_count := 0
	for i in compiled.size():
		if _gd_one(i, values, offsets, ids, thresholds):
			ceiling_count += 1
	var rpn_count := 0
	for i in fresh.size():
		if fresh[i] != 0:
			rpn_count += 1
	var matched := mismatch == 0 and ceiling_count == rpn_count
	if not matched:
		push_error("dirty-set checksum diverged for %d changed facts" % count)
	var warm := float(WARM_TICKS)
	var index_usec := float(index_sum) / warm
	var eval_usec := float(eval_sum) / warm
	var ceiling_eval := float(ceiling_sum) / warm
	return {
		"affected_mean": float(affected_sum) / warm,
		"ceiling_eval_usec": ceiling_eval,
		"ceiling_tick_usec": index_usec + ceiling_eval,
		"checksum": _fingerprint(fresh),
		"checksum_match": matched,
		"cold": cold,
		"eval_usec": eval_usec,
		"index_usec": index_usec,
		"tick_usec": index_usec + eval_usec,
		"ticks": WARM_TICKS,
	}


func _names(facts: int) -> Array[StringName]:
	var names: Array[StringName] = []
	names.resize(facts)
	for i in facts:
		names[i] = StringName("gullhaven.fact_%05d" % i)
	return names


func _scan_rpn(compiled: Array[WyrdCompiledCondition], eval: WyrdRpnEval, values: PackedInt32Array) -> PackedByteArray:
	var flags := PackedByteArray()
	flags.resize(compiled.size())
	for i in compiled.size():
		flags[i] = 1 if eval.eval_bound(compiled[i], values) == true else 0
	return flags


func _pick(rng: WyrdRng, count: int, facts: int) -> PackedInt32Array:
	var chosen := {}
	var out := PackedInt32Array()
	out.resize(count)
	var i := 0
	while i < count:
		var slot := rng.randi_range(0, facts - 1)
		if chosen.has(slot):
			continue
		chosen[slot] = true
		out[i] = slot
		i += 1
	return out


func _gd_one(index: int, values: PackedInt32Array, offsets: PackedInt32Array, ids: PackedInt32Array, thresholds: PackedInt32Array) -> bool:
	var begin := offsets[index]
	var end := ids.size()
	if index + 1 < offsets.size():
		end = offsets[index + 1]
	for j in range(begin, end):
		if values[ids[j]] < thresholds[j]:
			return false
	return true


func _fingerprint(flags: PackedByteArray) -> int:
	var fp := 0
	for i in flags.size():
		if flags[i] != 0:
			fp = (fp * 33 + i + 1) & 0x7fffffff
	return fp
