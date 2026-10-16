extends SceneTree

## Long-lived bench worker. The shell writes one command to the mailbox and
## waits for one JSON line. Samples of one metric share a scripted workload,
## so their checksums match. Timers stay outside that workload.

var _box := ""
var _pack := ""
var _profile := ""
var _facts := 0
var _npcs := 0
var _topics := 0
var _stories_ready := false
var _runtime: WyrdRuntime
var _world: WyrdFakeWorld
var _spatial: WyrdFakeSpatial
var _host: WyrdFakeHost
var _saved_bytes := 0
var _peak := 0
var _ready := false


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var index := 0
	while index < args.size():
		var arg := str(args[index])
		if arg == "--mailbox" and index + 1 < args.size():
			_box = str(args[index + 1])
			index += 2
		elif arg == "--pack" and index + 1 < args.size():
			_pack = str(args[index + 1])
			index += 2
		elif arg == "--profile" and index + 1 < args.size():
			_profile = str(args[index + 1])
			index += 2
		else:
			push_error("perf worker: unknown argument %s" % arg)
			quit(1)
			return
	if _box.is_empty() or _pack.is_empty():
		push_error("perf worker: --mailbox and --pack are required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_box)
	_write_text(_box.path_join("ready"), "ready\n")
	print("perf worker ready")
	while true:
		var req := _box.path_join("req")
		if not FileAccess.file_exists(req):
			OS.delay_msec(30)
			continue
		var line := _read_text(req).strip_edges()
		DirAccess.remove_absolute(req)
		print("perf worker command %s" % line)
		if line == "quit" or line.is_empty():
			_reply({"ok": true})
			break
		_reply(_dispatch(line))
		print("perf worker replied %s" % line)
	quit(0)


func _dispatch(line: String) -> Dictionary:
	if line == "prepare":
		return _prepare()
	if line.begins_with("sample "):
		return _sample(line.substr(7).strip_edges())
	return {"error": "unknown command %s" % line, "ok": false}


func _prepare() -> Dictionary:
	print("perf worker prepare begin")
	var info := WyrdScalePack.read_pack(_pack)
	if info.is_empty():
		return {"error": "pack.txt is missing", "ok": false}
	_profile = str(info.get("profile", _profile))
	_facts = int(info.get("facts", "0"))
	_npcs = int(info.get("npcs", "0"))
	_topics = int(info.get("topics", "0"))
	if _facts < 1 or _npcs < 2:
		return {"error": "pack needs facts and at least two npcs", "ok": false}
	_runtime = WyrdRuntime.new()
	_runtime.trace.enabled = false
	var config := WyrdConfig.new()
	config.compact_after = 0
	config.scheduler_work_per_tick = 64
	_runtime.configure(config)
	_host = WyrdFakeHost.new()
	_host.register_into(_runtime)
	_world = _host.world
	_spatial = _host.spatial
	_world.add_entity(&"player", &"person", "player", PackedStringArray(), true)
	for index in _npcs:
		var id := StringName(_npc(index))
		_world.add_entity(id, &"person", String(id), PackedStringArray(), true)
		_world.add_member(StringName(WyrdPerfScale.GROUP), id)
	_world.set_groups(StringName(WyrdPerfScale.GROUP_AGENT), WyrdPerfScale.DEPTH_GROUPS)
	_runtime.invalidate_groups()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"gullhaven"
	manifest.language_version = 1
	manifest.files = _wyrd_files()
	print("perf worker loading")
	var report := _runtime.load_content(manifest)
	print("perf worker loaded")
	if not report.ok:
		return {"error": report.diagnostics.format(), "ok": false}
	_runtime.start_new_game(WyrdPerfScale.SEED)
	_import_deeds()
	_note_mem()
	_ready = true
	return {
		"metrics": WyrdPerfScale.metrics(),
		"ok": true,
		"profile": _profile,
		"samples": WyrdPerfScale.samples_for(_profile),
		"scale": {
			"deeds": int(info.get("deeds", "0")),
			"facts": _facts,
			"npcs": _npcs,
			"quests": int(info.get("quests", "0")),
			"speakers": int(info.get("speakers", "0")),
			"storylets": int(info.get("storylets", "0")),
			"topics": _topics,
		},
		"seed": WyrdPerfScale.SEED,
		"warmups": WyrdPerfScale.WARMUPS,
	}


func _sample(name: String) -> Dictionary:
	if not _ready:
		return {"error": "prepare first", "metric": name, "ok": false}
	_note_mem()
	var row := {}
	match name:
		"compile.strict":
			row = _sample_compile()
		"tick.recheck":
			row = _sample_tick()
		"believes.own":
			row = _sample_believes(false)
		"believes.group":
			row = _sample_believes(true)
		"perceive.credibility":
			row = _sample_perceive()
		"reputation.cold":
			row = _sample_reputation(false)
		"reputation.cached":
			row = _sample_reputation(true)
		"save.time":
			row = _sample_save(true)
		"save.bytes":
			row = _sample_save(false)
		"load.time":
			row = _sample_load()
		"compact.time":
			row = _sample_compact()
		"memory.peak":
			row = _sample_memory(false)
		"memory.steady":
			row = _sample_memory(true)
		"director.query":
			row = _sample_query()
		"director.why_not":
			row = _sample_why_not()
		"compile.tie_lint":
			row = _sample_tie_lint()
		_:
			return {"error": "unknown metric %s" % name, "metric": name, "ok": false}
	if not str(row.get("error", "")).is_empty():
		row["metric"] = name
		row["ok"] = false
		return row
	row["metric"] = name
	row["ok"] = true
	_note_mem()
	return row


func _sample_compile() -> Dictionary:
	var started := Time.get_ticks_usec()
	var result := WyrdCli.execute(PackedStringArray(["check", "--strict", _pack]))
	var elapsed := Time.get_ticks_usec() - started
	var errors := 0
	var warnings := 0
	for line in str(result["output"]).split("\n"):
		if line.contains("error["):
			errors += 1
		elif line.contains("warning["):
			warnings += 1
	return {
		"checksum": "%s:%s:%s" % [int(result["exit_code"]), errors, warnings],
		"extra": {"exit_code": int(result["exit_code"])},
		"value": float(elapsed) / 1000000.0,
	}


func _sample_tick() -> Dictionary:
	_runtime.start_new_game(WyrdPerfScale.SEED)
	var guard := 0
	var limit := _runtime.condition_count() + 8
	while guard < limit:
		_runtime.tick(0)
		guard += 1
		if _runtime.last_rechecks() == 0:
			break
	var rng := WyrdRng.new(WyrdPerfScale.SEED, WyrdRng.stream_id(&"perf_tick"))
	var times: Array[float] = []
	var dirty_first := 0
	var rechecks := 0
	for step in WyrdPerfScale.TICKS_PER_SAMPLE:
		for _touch in WyrdPerfScale.TICK_TOUCHES:
			var fact_index := rng.randi_bounded(_facts)
			_runtime.facts.set_in(_fact(fact_index), step % 2, &"world")
		var dirty := _dirty_count()
		if step == 0:
			dirty_first = dirty
		var started := Time.get_ticks_usec()
		_runtime.tick(1)
		times.append(float(Time.get_ticks_usec() - started) / 1000000.0)
		rechecks += _runtime.last_rechecks()
	var flags := _runtime.condition_flags()
	var digest := WyrdHash.of_int(flags.size())
	for index in flags.size():
		digest = WyrdHash.combine(digest, int(flags[index]))
	digest = WyrdHash.combine(digest, dirty_first)
	digest = WyrdHash.combine(digest, rechecks)
	return {
		"checksum": str(digest),
		"extra": {"dirty": dirty_first, "rechecks": rechecks},
		"value": _p95(times),
	}


func _sample_believes(group_depth: bool) -> Dictionary:
	_runtime.start_new_game(WyrdPerfScale.SEED)
	_arm_beliefs()
	var believes: Callable = _runtime.function_table()[&"believes"]
	var agent := WyrdPerfScale.GROUP_AGENT if group_depth else WyrdPerfScale.OWN_AGENT
	var key := WyrdPerfScale.BELIEF_FACT
	var hits := 0
	var started := Time.get_ticks_usec()
	for _call in WyrdPerfScale.BELIEVE_CALLS:
		if bool(believes.call([agent, key])):
			hits += 1
	var elapsed := Time.get_ticks_usec() - started
	return {
		"checksum": str(hits),
		"extra": {"calls": WyrdPerfScale.BELIEVE_CALLS},
		"value": (float(elapsed) / 1000000.0) / float(WyrdPerfScale.BELIEVE_CALLS),
	}


func _sample_perceive() -> Dictionary:
	_runtime.deeds.clear()
	_runtime.social.clear_state()
	var witnesses := PackedStringArray([_npc(2), _npc(3), _npc(4)])
	for index in witnesses.size():
		var mode := &"heard" if index == 0 else &"saw"
		_spatial.set_perception(StringName(witnesses[index]), mode, &"gullhaven")
	var tags := PackedStringArray(["toll"])
	var digest := WyrdHash.of_int(WyrdPerfScale.PERCEIVE_BATCH)
	var started := Time.get_ticks_usec()
	for _row in WyrdPerfScale.PERCEIVE_BATCH:
		var id := _runtime.deeds.record(
			&"paid",
			&"player",
			StringName(WyrdPerfScale.OWN_AGENT),
			&"gullhaven",
			tags,
			1.0,
			witnesses,
			&"public",
			false
		)
		var accepted := 0
		for who in witnesses:
			var score := _runtime.credibility_score(StringName(who), &"player")
			if score >= _runtime.credibility_threshold():
				accepted += 1
		digest = WyrdHash.combine(digest, id + accepted)
	var elapsed := Time.get_ticks_usec() - started
	return {
		"checksum": str(digest),
		"extra": {"deeds": WyrdPerfScale.PERCEIVE_BATCH, "witnesses": witnesses.size()},
		"value": (float(elapsed) / 1000000.0) / float(WyrdPerfScale.PERCEIVE_BATCH),
	}


func _sample_reputation(cached: bool) -> Dictionary:
	_import_deeds()
	_runtime.invalidate_groups()
	var subject := StringName("player")
	var group := StringName(WyrdPerfScale.GROUP)
	if cached:
		_runtime.social.reputation(subject, group)
	var started := Time.get_ticks_usec()
	var score := _runtime.social.reputation(subject, group)
	var elapsed := Time.get_ticks_usec() - started
	return {
		"checksum": "%.6f" % score,
		"extra": {"members": _npcs},
		"value": float(elapsed) / 1000000.0,
	}


func _sample_save(timed: bool) -> Dictionary:
	_import_deeds()
	var started := Time.get_ticks_usec()
	var data := _runtime.save_state()
	var text := JSON.stringify(data)
	var elapsed := Time.get_ticks_usec() - started
	_saved_bytes = text.to_utf8_buffer().size()
	_write_text(_save_path(), text)
	data = {}
	text = ""
	if timed:
		return {
			"checksum": "%s:%s" % [_runtime.deeds.size(), _saved_bytes],
			"extra": {"bytes": _saved_bytes},
			"value": float(elapsed) / 1000000.0,
		}
	return {
		"checksum": str(_saved_bytes),
		"extra": {},
		"value": float(_saved_bytes),
	}


func _sample_load() -> Dictionary:
	if not FileAccess.file_exists(_save_path()):
		_sample_save(true)
	var parsed: Variant = JSON.parse_string(_read_text(_save_path()))
	var data: Dictionary = parsed if parsed is Dictionary else {}
	var started := Time.get_ticks_usec()
	var report := _runtime.load_state(data)
	var elapsed := Time.get_ticks_usec() - started
	data = {}
	return {
		"checksum": "%s:%s" % [1 if report.ok else 0, _runtime.deeds.size()],
		"extra": {"ok": report.ok},
		"value": float(elapsed) / 1000000.0,
	}


func _sample_compact() -> Dictionary:
	_import_deeds()
	var before := _runtime.deeds.size()
	var started := Time.get_ticks_usec()
	var after := _runtime.deeds.compact()
	var elapsed := Time.get_ticks_usec() - started
	return {
		"checksum": "%s:%s" % [before, after],
		"extra": {"after": after, "before": before},
		"value": float(elapsed) / 1000000.0,
	}


func _sample_query() -> Dictionary:
	var err := _ensure_stories()
	if not err.is_empty():
		return {"error": err}
	_runtime.start_new_game(WyrdPerfScale.SEED)
	var digest := WyrdHash.of_int(WyrdPerfScale.QUERY_BATCH)
	var candidates := 0
	var started := Time.get_ticks_usec()
	for step in WyrdPerfScale.QUERY_BATCH:
		var topic := "rumor.scale_%02d" % (step % _topics)
		var won := _runtime.director.query("topic", topic, WyrdPerfScale.QUERY_SPEAKER)
		digest = WyrdHash.combine(digest, WyrdHash.of_string_name(StringName(str(won["id"]))))
		candidates = int(won["candidates"])
		digest = WyrdHash.combine(digest, candidates)
	var elapsed := Time.get_ticks_usec() - started
	return {
		"checksum": str(digest),
		"extra": {"batch": WyrdPerfScale.QUERY_BATCH, "candidates": candidates},
		"value": (float(elapsed) / 1000000.0) / float(WyrdPerfScale.QUERY_BATCH),
	}


func _sample_why_not() -> Dictionary:
	var err := _ensure_stories()
	if not err.is_empty():
		return {"error": err}
	_runtime.start_new_game(WyrdPerfScale.SEED)
	var story_id := WyrdScalePack.queried_winner(_topics)
	var digest := WyrdHash.of_int(WyrdPerfScale.WHY_BATCH)
	var reason := ""
	var started := Time.get_ticks_usec()
	for _step in WyrdPerfScale.WHY_BATCH:
		var row := _runtime.director.why_not(story_id, "topic", WyrdPerfScale.QUERY_TOPIC, WyrdPerfScale.QUERY_SPEAKER)
		reason = str(row.get("reason", ""))
		digest = WyrdHash.combine(digest, WyrdHash.of_string_name(StringName(reason)))
		digest = WyrdHash.combine(digest, WyrdHash.of_string_name(StringName(str(row.get("winner", "")))))
	var elapsed := Time.get_ticks_usec() - started
	return {
		"checksum": str(digest),
		"extra": {"batch": WyrdPerfScale.WHY_BATCH, "reason": reason},
		"value": (float(elapsed) / 1000000.0) / float(WyrdPerfScale.WHY_BATCH),
	}


func _sample_tie_lint() -> Dictionary:
	var started := Time.get_ticks_usec()
	var result := WyrdCli.execute(PackedStringArray(["check", "--strict", WyrdScalePack.storylets_root(_pack)]))
	var elapsed := Time.get_ticks_usec() - started
	var errors := 0
	var warnings := 0
	for line in str(result["output"]).split("\n"):
		if line.contains("error["):
			errors += 1
		elif line.contains("warning["):
			warnings += 1
	return {
		"checksum": "%s:%s:%s" % [int(result["exit_code"]), errors, warnings],
		"extra": {"exit_code": int(result["exit_code"]), "warnings": warnings},
		"value": float(elapsed) / 1000000.0,
	}


func _ensure_stories() -> String:
	if _stories_ready:
		return ""
	if _topics < 1:
		return "pack has no topics"
	var extra := _wyrd_files_in(WyrdScalePack.storylets_root(_pack))
	if extra.is_empty():
		return "storylet pack is missing"
	var files := _wyrd_files()
	files.append_array(extra)
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"gullhaven"
	manifest.language_version = 1
	manifest.files = files
	var report := _runtime.load_content(manifest)
	if not report.ok:
		return report.diagnostics.format()
	_runtime.trace.enabled = false
	_runtime.start_new_game(WyrdPerfScale.SEED)
	_stories_ready = true
	return ""


func _sample_memory(steady: bool) -> Dictionary:
	if steady:
		_runtime.tick(0)
	_note_mem()
	var value := _peak if not steady else int(Performance.get_monitor(Performance.MEMORY_STATIC))
	return {"checksum": "memory.static", "extra": {}, "value": float(value)}


func _arm_beliefs() -> void:
	_runtime.facts.set_in(StringName(WyrdPerfScale.BELIEF_FACT), 1, StringName("believed/%s" % WyrdPerfScale.OWN_AGENT))
	_runtime.facts.set_in(StringName(WyrdPerfScale.BELIEF_FACT), 1, StringName("held/%s" % WyrdPerfScale.GROUP))


func _import_deeds() -> void:
	var fixture := WyrdScalePack.load_deeds(_pack)
	_runtime.deeds.import_state(fixture)


func _save_path() -> String:
	return _box.path_join("save.json")


func _dirty_count() -> int:
	var count := 0
	for index in _runtime.condition_count():
		if _runtime.condition_dirty(index):
			count += 1
	return count


func _note_mem() -> void:
	var now := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	if now > _peak:
		_peak = now


func _p95(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var copy := values.duplicate()
	copy.sort()
	var rank := int(ceil(0.95 * float(copy.size())))
	rank = clampi(rank, 1, copy.size())
	return copy[rank - 1]


func _wyrd_files() -> PackedStringArray:
	return _wyrd_files_in(_pack)


func _wyrd_files_in(dir: String) -> PackedStringArray:
	var rows := PackedStringArray()
	var listing := DirAccess.open(dir)
	if listing == null:
		return rows
	listing.list_dir_begin()
	var name := listing.get_next()
	while name != "":
		if name.ends_with(".wyrd") and not listing.current_is_dir():
			rows.append(dir.path_join(name))
		name = listing.get_next()
	listing.list_dir_end()
	rows.sort()
	return rows


func _npc(index: int) -> String:
	return "dock_hand_%03d" % (index % _npcs)


func _fact(index: int) -> StringName:
	return StringName("harbor.scale_%05d" % index)


func _reply(payload: Dictionary) -> void:
	var dest := _box.path_join("resp")
	if FileAccess.file_exists(dest):
		DirAccess.remove_absolute(dest)
	_write_text(_box.path_join("resp.tmp"), JSON.stringify(payload) + "\n")
	DirAccess.rename_absolute(_box.path_join("resp.tmp"), dest)


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("perf worker could not write %s" % path)
		return
	file.store_string(text)
	file.close()


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text
