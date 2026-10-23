extends GutTest

## 200 seeded mutations of the schema 4 fixture and the two Gullhaven saves.
## The same seed always walks the same mutations. No wall clock.

const _Load := preload("res://tests/migration/fixture_load.gd")
const _Harness := preload("res://tests/scenario/s2c_harness.gd")
const SEED := 20261023
const MUTATIONS := 200


func test_seeded_loader_fuzz() -> void:
	var bases: Array = [
		_Load.read("res://tests/fixtures/schema4_ai_harbor.json"),
		_Load.read("res://tests/migration/fixtures/gullhaven_v0.7.0-m9.json"),
		_Load.read("res://tests/migration/fixtures/gullhaven_v0.8.0-m10.json"),
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var clean := 0
	var warned := 0
	var refused := 0
	var refused_changed := 0
	var classes: Array[String] = ["drop", "type", "truncate", "hex"]
	for index in MUTATIONS:
		var kind: String = classes[index % 4]
		var base: Dictionary = bases[index % 3]
		var parsed: Variant = JSON.parse_string(JSON.stringify(base))
		var doc: Dictionary = parsed
		var path := _mutate(doc, kind, rng)
		var runtime: WyrdRuntime = _Harness.new().boot_gullhaven()["runtime"]
		var before := JSON.stringify(runtime.save_state(), "\t", true)
		var hits := [0]
		runtime.load_report_ready.connect(func(_report): hits[0] += 1)
		var report := runtime.load_state(doc)
		if not (report is WyrdLoadReport):
			assert_true(false, "mutation %d %s %s: not a report" % [index, kind, path])
			return
		if _unexpected(index, kind, path, report):
			return
		var saved := runtime.save_state()
		if _unexpected(index, kind, path, report):
			return
		if hits[0] != 1:
			assert_eq(hits[0], 1, "mutation %d %s %s: signal" % [index, kind, path])
			return
		var refusing := _refusing(report)
		if report.ok == refusing:
			assert_true(false, "mutation %d %s %s: ok=%s refusing=%s" % [index, kind, path, report.ok, refusing])
			return
		if not report.ok:
			if _refused_rows(report) != 1:
				assert_eq(_refused_rows(report), 1, "mutation %d %s %s" % [index, kind, path])
				return
			var after := JSON.stringify(saved, "\t", true)
			if after != before:
				refused_changed += 1
				assert_eq(after, before, "mutation %d %s %s changed state" % [index, kind, path])
				return
			refused += 1
		elif report.diagnostics.items.is_empty():
			clean += 1
		else:
			warned += 1
	assert_eq(refused_changed, 0)
	assert_eq(clean + warned + refused, MUTATIONS)
	assert_engine_error_count(0)
	print("fuzz seed=%d clean=%d warned=%d refused=%d refused_changed=%d" % [SEED, clean, warned, refused, refused_changed])


func _unexpected(index: int, kind: String, path: String, report: WyrdLoadReport) -> bool:
	for item in get_errors():
		var err: GutTrackedError = item
		if err.handled:
			continue
		if err.is_engine_error():
			err.handled = true
			assert_true(false, "mutation %d %s %s: engine error %s" % [index, kind, path, str(err.code)])
			return true
		if not err.is_push_error():
			continue
		var text := "%s %s" % [str(err.code), str(err.rationale)]
		var rng_noise := text.find("WyrdRng") >= 0 or text.find("16 hex") >= 0 or text.find("state rejected") >= 0
		var allowed := (not report.ok) and rng_noise
		var policy := text.find("WyrdRumor") >= 0 and _has_code(report, "E_SAVE_POLICY")
		if allowed or policy:
			err.handled = true
			continue
		err.handled = true
		assert_true(false, "mutation %d %s %s: push_error %s" % [index, kind, path, text])
		return true
	return false


func _refusing(report: WyrdLoadReport) -> bool:
	for item in report.diagnostics.items:
		if item.severity != WyrdDiagnostic.SEVERITY_ERROR:
			continue
		var code := String(item.code)
		if code.begins_with("E_SAVE_") and code != "E_SAVE_POLICY":
			return true
	return false


func _has_code(report: WyrdLoadReport, code: String) -> bool:
	for item in report.diagnostics.items:
		if String(item.code) == code:
			return true
	return false


func _refused_rows(report: WyrdLoadReport) -> int:
	var count := 0
	for row in report.rows:
		if String((row as Dictionary).get("kind", "")) == "refused":
			count += 1
	return count


func _mutate(doc: Dictionary, kind: String, rng: RandomNumberGenerator) -> String:
	if kind == "hex":
		return _mutate_hex(doc, rng)
	if kind == "truncate":
		return _mutate_truncate(doc, rng)
	var paths: Array = []
	_collect(doc, [], paths)
	if paths.is_empty():
		return "(none)"
	var picked: Array = paths[rng.randi() % paths.size()]
	if kind == "drop":
		_erase(doc, picked)
		return _path_text(picked)
	_put(doc, picked, _other_type(_at(doc, picked), rng))
	return _path_text(picked)


func _mutate_truncate(doc: Dictionary, rng: RandomNumberGenerator) -> String:
	var paths: Array = []
	_collect_arrays(doc, [], paths)
	if paths.is_empty():
		return "(no-array)"
	var picked: Array = paths[rng.randi() % paths.size()]
	var rows: Array = _at(doc, picked)
	rows.resize(rows.size() - 1)
	return _path_text(picked)


func _mutate_hex(doc: Dictionary, rng: RandomNumberGenerator) -> String:
	var bad_hex: Array[String] = ["zz", "abcd", "000000000000000g", "", "not-hex-digits!!"]
	var bad: String = bad_hex[rng.randi() % bad_hex.size()]
	var which := rng.randi() % 3
	if which == 0:
		doc["seed"] = bad
		return "seed"
	if which == 1:
		var content: Variant = doc.get("content", {})
		var packs: Array = []
		if content is Dictionary:
			var listed: Variant = (content as Dictionary).get("packs", [])
			if listed is Array:
				packs = listed
		if packs.is_empty() or not (packs[0] is Dictionary):
			doc["seed"] = bad
			return "seed"
		(packs[0] as Dictionary)["hash"] = bad
		return "content.packs.0.hash"
	var rng_bag: Dictionary = {}
	if doc.get("rng") is Dictionary:
		rng_bag = doc["rng"]
	var names: Array = rng_bag.keys()
	if names.is_empty():
		doc["rng"] = {
			"chance": {
				"inc": "0000000000000001",
				"seed": "0000000000000001",
				"state": bad,
				"v": 1,
			},
		}
		return "rng.chance.state"
	names.sort()
	var stream := str(names[rng.randi() % names.size()])
	if not (rng_bag[stream] is Dictionary):
		rng_bag[stream] = {"inc": "0000000000000001", "seed": "0000000000000001", "state": bad, "v": 1}
		return "rng.%s.state" % stream
	(rng_bag[stream] as Dictionary)["state"] = bad
	return "rng.%s.state" % stream


func _other_type(current: Variant, rng: RandomNumberGenerator) -> Variant:
	var choices: Array = ["mutated", 7, [1], {"mutated": true}, null]
	var pool: Array = []
	for item in choices:
		if typeof(item) != typeof(current):
			pool.append(item)
	if pool.is_empty():
		return null
	return pool[rng.randi() % pool.size()]


func _collect(node: Variant, prefix: Array, out: Array) -> void:
	if node is Dictionary:
		var body: Dictionary = node
		var keys: Array = body.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
		for key in keys:
			var path: Array = prefix.duplicate()
			path.append(key)
			out.append(path)
			_collect(body[key], path, out)
	elif node is Array:
		var rows: Array = node
		for index in rows.size():
			var path: Array = prefix.duplicate()
			path.append(index)
			out.append(path)
			_collect(rows[index], path, out)


func _collect_arrays(node: Variant, prefix: Array, out: Array) -> void:
	if node is Dictionary:
		var body: Dictionary = node
		var keys: Array = body.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
		for key in keys:
			var path: Array = prefix.duplicate()
			path.append(key)
			_collect_arrays(body[key], path, out)
	elif node is Array:
		var rows: Array = node
		if rows.size() > 0:
			out.append(prefix.duplicate())
		for index in rows.size():
			var path: Array = prefix.duplicate()
			path.append(index)
			_collect_arrays(rows[index], path, out)


func _at(node: Variant, path: Array) -> Variant:
	var current: Variant = node
	for step in path:
		current = current[step]
	return current


func _put(node: Variant, path: Array, value: Variant) -> void:
	var current: Variant = node
	for index in path.size() - 1:
		current = current[path[index]]
	current[path[path.size() - 1]] = value


func _erase(node: Variant, path: Array) -> void:
	var current: Variant = node
	for index in path.size() - 1:
		current = current[path[index]]
	var last: Variant = path[path.size() - 1]
	if current is Dictionary:
		(current as Dictionary).erase(last)
	elif current is Array and typeof(last) == TYPE_INT:
		(current as Array).remove_at(int(last))


func _path_text(path: Array) -> String:
	var parts := PackedStringArray()
	for step in path:
		parts.append(str(step))
	return ".".join(parts)
