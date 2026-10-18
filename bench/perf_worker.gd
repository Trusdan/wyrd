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
var _quest_mem := 0
var _deeds := 0
var _rumors_ready := false
var _flight_ready := false
var _graph: Dictionary = {}
var _cached_beliefs: Array = []
var _belief_ready := false


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
	_deeds = int(info.get("deeds", "0"))
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
	var before_pack := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var report := _runtime.load_content(manifest)
	print("perf worker loaded")
	if not report.ok:
		return {"error": report.diagnostics.format(), "ok": false}
	_runtime.start_new_game(WyrdPerfScale.SEED)
	_quest_mem = maxi(int(Performance.get_monitor(Performance.MEMORY_STATIC)) - before_pack, 0)
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
		"director.query_coverage":
			row = _sample_query_coverage()
		"director.why_not":
			row = _sample_why_not()
		"compile.tie_lint":
			row = _sample_tie_lint()
		"debug.snapshot":
			row = _sample_snapshot("full")
		"debug.snapshot_page":
			row = _sample_snapshot("page")
		"debug.snapshot_section":
			row = _sample_snapshot("section")
		"memory.quests":
			row = _sample_quest_memory()
		"rumor.tick":
			row = _sample_rumor_tick()
		"scheduler.tick":
			row = _sample_scheduler_tick()
		"publish.issue":
			row = _sample_publish_issue()
		"deeds_known_to":
			row = _sample_known_to()
		"memory.believers":
			row = _sample_believer_cost("memory")
		"memory.per_belief":
			row = _sample_believer_cost("each")
		"save.believers":
			row = _sample_believer_cost("bytes")
		"save.flight":
			row = _sample_flight(true)
		"save.flight_bytes":
			row = _sample_flight(false)
		"load.flight":
			row = _sample_flight_load()
		"deeds.index":
			row = _sample_deed_lookup(true)
		"deeds.scan":
			row = _sample_deed_lookup(false)
		"memory.resident":
			row = _sample_resident()
		_:
			return {"error": "unknown metric %s" % name, "metric": name, "ok": false}
	_restore_shares()
	if _runtime != null and _runtime.deeds != null:
		_runtime.deeds.set_lookup(true)
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
	return _sample_query_batch(false)


func _sample_query_coverage() -> Dictionary:
	return _sample_query_batch(true)


## Same 32-topic batch as [method _sample_query]. Coverage is on only for the
## timed queries, then turned back off so later metrics stay on the default.
func _sample_query_batch(count_hits: bool) -> Dictionary:
	var err := _ensure_stories()
	if not err.is_empty():
		return {"error": err}
	_runtime.start_new_game(WyrdPerfScale.SEED)
	_runtime.coverage.clear()
	_runtime.coverage.enabled = count_hits
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
	var hits := 0
	if count_hits:
		hits = _coverage_hits("storylet")
	_runtime.coverage.enabled = false
	_runtime.coverage.clear()
	return {
		"checksum": str(digest),
		"extra": {"batch": WyrdPerfScale.QUERY_BATCH, "candidates": candidates, "hits": hits},
		"value": (float(elapsed) / 1000000.0) / float(WyrdPerfScale.QUERY_BATCH),
	}


## One inspector build. [param mode] `page` filters every section. `section`
## asks only for facts with that same prefix and page window. A new game plus
## the deed import and one write per scale fact run first.
func _sample_snapshot(mode: String) -> Dictionary:
	_runtime.start_new_game(WyrdPerfScale.SEED)
	_import_deeds()
	_fill_scale_facts()
	var prefix := ""
	var offset := 0
	var limit := 0
	var sections := PackedStringArray()
	if mode == "page" or mode == "section":
		prefix = WyrdPerfScale.SNAPSHOT_PREFIX
		offset = WyrdPerfScale.SNAPSHOT_OFFSET
		limit = WyrdPerfScale.SNAPSHOT_LIMIT
	if mode == "section":
		sections = PackedStringArray(["facts"])
	var started := Time.get_ticks_usec()
	var doc := _runtime.debug.snapshot(sections, prefix, offset, limit)
	var elapsed := Time.get_ticks_usec() - started
	return {
		"checksum": _snapshot_checksum(doc),
		"extra": {
			"deeds": _section_total(doc, "deeds"),
			"facts": _section_total(doc, "facts"),
			"limit": limit,
			"offset": offset,
			"prefix": prefix,
			"roles": _section_total(doc, "roles"),
			"rows": _section_page_rows(doc),
		},
		"value": float(elapsed) / 1000000.0,
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


func _fill_scale_facts() -> void:
	for index in _facts:
		_runtime.facts.set_in(_fact(index), index, &"world")


func _coverage_hits(kind: String) -> int:
	var counted := _runtime.coverage.counts()
	var bag: Variant = counted.get(kind, {})
	if not (bag is Dictionary):
		return 0
	var hits := 0
	for id in (bag as Dictionary).keys():
		hits += int((bag as Dictionary)[id])
	return hits


func _snapshot_checksum(doc: Dictionary) -> String:
	var parts: PackedStringArray = []
	for section_name in WyrdDebug.SECTIONS:
		var name := String(section_name)
		var total := _section_total(doc, name)
		var rows := _section_rows(doc, name)
		parts.append("%s:%d:%d" % [name, total, rows])
	return "|".join(parts)


func _section_total(doc: Dictionary, name: String) -> int:
	var page := _section_page(doc, name)
	return int(page.get("total", -1))


func _section_rows(doc: Dictionary, name: String) -> int:
	var page := _section_page(doc, name)
	var rows: Variant = page.get("rows", [])
	if rows is Array:
		return (rows as Array).size()
	return 0


func _section_page_rows(doc: Dictionary) -> int:
	var count := 0
	for section_name in WyrdDebug.SECTIONS:
		count += _section_rows(doc, String(section_name))
	return count


func _section_page(doc: Dictionary, name: String) -> Dictionary:
	var section: Variant = doc.get(name, {})
	if section is Dictionary:
		return section
	return {}


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


func _sample_quest_memory() -> Dictionary:
	return {
		"checksum": "memory.quests",
		"extra": {"bytes": _quest_mem},
		"value": float(_quest_mem),
	}


func _sample_resident() -> Dictionary:
	_note_mem()
	return {"checksum": "memory.static", "extra": {}, "value": float(_peak)}


## One median tick with the rumor queue full. Reach tokens sit ahead of the
## precise hops, and the precise policy mutates [code]harbor.toll_fate[/code].
func _sample_rumor_tick() -> Dictionary:
	var seeded := _queue_rumor_work()
	if not str(seeded.get("error", "")).is_empty():
		return seeded
	_set_shares(64, 0, 64, 0, 0)
	var times := _time_ticks()
	return {
		"checksum": _rumor_checksum(int(seeded["coarse_id"])),
		"extra": {
			"carry": _runtime.scheduler().carry("rumor"),
			"reached": int(seeded["reached"]),
			"whispered": int(seeded["whispered"]),
		},
		"value": _median(times),
	}


## Default shares, with rumor hops, one gazette issue, and cache refresh all queued.
func _sample_scheduler_tick() -> Dictionary:
	var seeded := _queue_rumor_work()
	if not str(seeded.get("error", "")).is_empty():
		return seeded
	_warm_cache()
	_restore_shares()
	var times := _time_ticks()
	var gazette := _gazette_text()
	return {
		"checksum": "%s:%s:%s:%s" % [
			_runtime.scheduler().carry("rumor"),
			_runtime.scheduler().carry("publish"),
			_runtime.scheduler().carry("cache_refresh"),
			gazette.length(),
		],
		"extra": {"gazette": gazette.length()},
		"value": _median(times),
	}


func _sample_publish_issue() -> Dictionary:
	var err := _arm_scale_believers()
	if not err.is_empty():
		return {"error": err}
	_runtime.facts.set_in(StringName(WyrdPerfScale.MUTATION_FIELD), &"lost_at_sea", &"world")
	_runtime.restore_clock(WyrdPerfScale.SEED, 60)
	_runtime.publish.enqueue_due()
	var tokens := _runtime.scheduler().carry_tokens("publish")
	if tokens.is_empty():
		return {"error": "harbor gazette did not queue an issue"}
	var started := Time.get_ticks_usec()
	var slices := 0
	var token := String(tokens[0])
	while slices < 100000:
		slices += 1
		if _runtime.publish.issue(token):
			break
	var elapsed := Time.get_ticks_usec() - started
	var gazette := _gazette_text()
	if gazette.is_empty():
		return {"error": "harbor gazette did not issue"}
	return {
		"checksum": gazette,
		"extra": {"deeds": _runtime.deeds.size(), "slices": slices},
		"value": float(elapsed) / 1000000.0,
	}


func _sample_known_to() -> Dictionary:
	var err := _arm_scale_believers()
	if not err.is_empty():
		return {"error": err}
	var started := Time.get_ticks_usec()
	var rows := _runtime.deeds_known_to(StringName(WyrdPerfScale.GROUP), 0, &"whispered")
	var elapsed := Time.get_ticks_usec() - started
	var digest := WyrdHash.of_int(rows.size())
	if not rows.is_empty():
		digest = WyrdHash.combine(digest, int((rows[0] as Dictionary)["id"]))
		digest = WyrdHash.combine(digest, int((rows[rows.size() - 1] as Dictionary)["id"]))
	return {
		"checksum": str(digest),
		"extra": {"rows": rows.size()},
		"value": float(elapsed) / 1000000.0,
	}


func _sample_believer_cost(kind: String) -> Dictionary:
	var measured := _measure_believers()
	if not str(measured.get("error", "")).is_empty():
		return measured
	var count := int(measured["count"])
	var memory := int(measured["memory"])
	var bytes := int(measured["bytes"])
	var value := float(bytes)
	if kind == "memory":
		value = float(memory)
	elif kind == "each":
		value = float(memory) / float(count)
	return {
		"checksum": "%s:%s" % [count, bytes],
		"extra": {"beliefs": count, "bytes": bytes, "memory": memory},
		"value": value,
	}


func _sample_flight(timed: bool) -> Dictionary:
	var seeded := _queue_flight()
	if not str(seeded.get("error", "")).is_empty():
		return seeded
	var started := Time.get_ticks_usec()
	var data := _runtime.save_state()
	var text := JSON.stringify(data)
	var elapsed := Time.get_ticks_usec() - started
	var size := text.to_utf8_buffer().size()
	_write_text(_flight_path(), text)
	var jobs := 0
	var flight: Variant = data.get("flight", {})
	if flight is Dictionary:
		var rumor: Variant = (flight as Dictionary).get("rumor", {})
		if rumor is Dictionary:
			var listed: Variant = (rumor as Dictionary).get("jobs", [])
			if listed is Array:
				jobs = (listed as Array).size()
	data = {}
	text = ""
	var checksum := "%s:%s:%s" % [_runtime.deeds.size(), jobs, _runtime.scheduler().carry("rumor")]
	if timed:
		return {
			"checksum": checksum,
			"extra": {"bytes": size, "jobs": jobs},
			"value": float(elapsed) / 1000000.0,
		}
	return {"checksum": str(size), "extra": {"jobs": jobs}, "value": float(size)}


func _sample_flight_load() -> Dictionary:
	if not FileAccess.file_exists(_flight_path()):
		var saved := _sample_flight(true)
		if not str(saved.get("error", "")).is_empty():
			return saved
	var err := _ensure_flight_content()
	if not err.is_empty():
		return {"error": err}
	var parsed: Variant = JSON.parse_string(_read_text(_flight_path()))
	var data: Dictionary = parsed if parsed is Dictionary else {}
	var started := Time.get_ticks_usec()
	var report := _runtime.load_state(data)
	var elapsed := Time.get_ticks_usec() - started
	data = {}
	var jobs: Variant = _runtime.rumors.export_state().get("jobs", [])
	var job_count := 0
	if jobs is Array:
		job_count = (jobs as Array).size()
	return {
		"checksum": "%s:%s:%s" % [1 if report.ok else 0, _runtime.deeds.size(), job_count],
		"extra": {"jobs": job_count, "ok": report.ok},
		"value": float(elapsed) / 1000000.0,
	}


## [param indexed] true times the hour-bucket index. False walks every row.
## The score is checked against the other mode before the timer starts.
func _sample_deed_lookup(indexed: bool) -> Dictionary:
	_runtime.start_new_game(WyrdPerfScale.SEED)
	_import_deeds()
	_runtime.restore_clock(WyrdPerfScale.SEED, _deed_clock())
	_runtime.deeds.set_lookup(true)
	var indexed_score := _deed_score()
	_runtime.deeds.set_lookup(false)
	var scanned_score := _deed_score()
	if indexed_score != scanned_score:
		_runtime.deeds.set_lookup(true)
		return {
			"error": "index score %s != scan %s" % [indexed_score, scanned_score],
		}
	_runtime.deeds.set_lookup(indexed)
	var score := 0.0
	var started := Time.get_ticks_usec()
	for _step in WyrdPerfScale.QUERY_BATCH:
		score = _deed_score()
	var elapsed := Time.get_ticks_usec() - started
	_runtime.deeds.set_lookup(true)
	return {
		"checksum": "%.6f" % score,
		"extra": {"batch": WyrdPerfScale.QUERY_BATCH, "within": WyrdPerfScale.DEED_WITHIN},
		"value": (float(elapsed) / 1000000.0) / float(WyrdPerfScale.QUERY_BATCH),
	}


func _queue_rumor_work() -> Dictionary:
	var err := _boot_rumor()
	if not err.is_empty():
		return {"error": err}
	var seeded := _seed_rumors(true)
	if int(seeded["whispered"]) < 1 or int(seeded["reached"]) < 1:
		return {"error": "rumor pack did not seed precise and coarse deeds"}
	return seeded


## Scale deed log plus in-flight rumor and gazette tokens. The hops are not run.
## The quest pack stays loaded so the save is the scale game with rumors in flight.
func _queue_flight() -> Dictionary:
	var err := _boot_flight()
	if not err.is_empty():
		return {"error": err}
	_import_deeds()
	var seeded := _seed_rumors(true)
	if int(seeded["whispered"]) < 1 or int(seeded["reached"]) < 1:
		return {"error": "rumor pack did not seed precise and coarse deeds"}
	_runtime.publish.enqueue_due()
	return seeded


func _boot_flight() -> String:
	var err := _ensure_flight_content()
	if not err.is_empty():
		return err
	_runtime.start_new_game(WyrdPerfScale.SEED)
	_runtime.trace.enabled = false
	_apply_graph()
	return ""


func _ensure_flight_content() -> String:
	var err := _ensure_rumors()
	if not err.is_empty():
		return err
	if _flight_ready:
		return ""
	var files := _wyrd_files()
	files.append_array(_wyrd_files_in(WyrdScalePack.rumors_root(_pack)))
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"gullhaven"
	manifest.language_version = 1
	manifest.files = files
	var report := _runtime.load_content(manifest)
	if not report.ok:
		return report.diagnostics.format()
	_runtime.trace.enabled = false
	_flight_ready = true
	return ""


func _boot_rumor() -> String:
	var err := _ensure_rumors()
	if not err.is_empty():
		return err
	_runtime.start_new_game(WyrdPerfScale.SEED)
	_runtime.trace.enabled = false
	_apply_graph()
	return ""


func _ensure_rumors() -> String:
	if _rumors_ready:
		return ""
	var dir := WyrdScalePack.rumors_root(_pack)
	var files := _wyrd_files_in(dir)
	if files.is_empty():
		return "rumor pack is missing"
	_graph = WyrdScalePack.read_rumors(_pack)
	if _graph.is_empty() or (_graph["friends"] as Array).is_empty():
		return "rumor graph is missing"
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"gullhaven"
	manifest.language_version = 1
	manifest.files = files
	var report := _runtime.load_content(manifest)
	if not report.ok:
		return report.diagnostics.format()
	_runtime.trace.enabled = false
	var registered := _register_policies()
	if not registered.is_empty():
		return registered
	_rumors_ready = true
	return ""


func _register_policies() -> String:
	for item in _graph["policies"]:
		var row: Dictionary = item
		var policy := WyrdRumorPolicy.new()
		policy.id = StringName(str(row["id"]))
		policy.kinds = PackedStringArray([str(row["kind"])])
		policy.max_hops = int(row["hops"])
		policy.verbs = PackedStringArray([str(row["verb"])])
		policy.pass_chance = float(row["chance"])
		var field := str(row["field"])
		if not field.is_empty():
			if field != WyrdPerfScale.MUTATION_FIELD or str(row["to"]) != WyrdPerfScale.MUTATION_TO or float(row["keep"]) != 0.0:
				return "rumor graph mutation does not match the bench callable"
			policy.mutations = [{
				"field": field,
				"keep_chance_fn": Callable(self, &"_keep_none"),
				"to": Callable(self, &"_to_waived"),
			}]
		_runtime.register_rumor_policy(policy)
	return ""


func _apply_graph() -> void:
	_spatial.set_precision(StringName(WyrdPerfScale.COARSE_PLACE), &"coarse")
	_spatial.set_precision(StringName(WyrdPerfScale.PRECISE_PLACE), &"precise")
	var places: Dictionary = _graph["places"]
	for name in places.keys():
		_spatial.set_place(StringName(str(name)), StringName(str(places[name])))
	for edge in _graph["friends"]:
		var pair: PackedStringArray = edge
		_runtime.social.set_kind(StringName(pair[0]), StringName(pair[1]), StringName(WyrdPerfScale.RUMOR_KIND))


## Coarse deeds are recorded at minute 0. The clock then moves to one hour so
## reach tokens queue before the precise hops.
func _seed_rumors(reach_first: bool) -> Dictionary:
	var places: Dictionary = _graph["places"]
	var names: Array = places.keys()
	names.sort()
	var whispered := 0
	var reached := 0
	var coarse_id := 0
	if reach_first:
		_runtime.perception_claim(WyrdPerfScale.MUTATION_FIELD, &"lost_at_sea")
		for name in names:
			if str(places[name]) != WyrdPerfScale.COARSE_PLACE:
				continue
			var id := _runtime.deeds.record(
				&"arrived",
				StringName(str(name)),
				&"player",
				StringName(WyrdPerfScale.COARSE_PLACE)
			)
			if coarse_id == 0:
				coarse_id = id
			reached += 1
		_runtime.clear_perception_claim()
		_runtime.restore_clock(WyrdPerfScale.SEED, 60)
		_runtime.rumors.enqueue_due()
	_runtime.perception_claim(WyrdPerfScale.MUTATION_FIELD, &"stolen")
	for name in names:
		if str(places[name]) != WyrdPerfScale.PRECISE_PLACE:
			continue
		_runtime.deeds.record(
			&"whispered",
			StringName(str(name)),
			&"player",
			StringName(WyrdPerfScale.PRECISE_PLACE)
		)
		whispered += 1
	_runtime.clear_perception_claim()
	return {"coarse_id": coarse_id, "reached": reached, "whispered": whispered}


func _warm_cache() -> void:
	var kinds := PackedStringArray([WyrdPerfScale.RUMOR_KIND])
	var steps := mini(_npcs, WyrdPerfScale.QUERY_BATCH)
	for step in steps:
		_runtime.social.path_exists(
			StringName(_npc(step)),
			StringName(_npc((step + 2) % _npcs)),
			kinds,
			2
		)
	if _npcs >= 2:
		_runtime.social.set_kind(StringName(_npc(0)), StringName(_npc(1)), StringName(WyrdPerfScale.RUMOR_KIND))


func _belief_pairs() -> Dictionary:
	if _belief_ready:
		return {"pairs": _cached_beliefs}
	var seeded := _queue_rumor_work()
	if not str(seeded.get("error", "")).is_empty():
		return seeded
	_set_shares(64, 0, 64, 0, 0)
	var guard := 0
	while _runtime.scheduler().carry("rumor") > 0 and guard < WyrdPerfScale.RUMOR_DRAIN_TICKS:
		_runtime.tick(0)
		guard += 1
	_restore_shares()
	var pairs: Array = []
	for index in _npcs:
		var who := _npc(index)
		for row in _runtime.deeds.believer_deeds(StringName(who)):
			pairs.append({
				"id": int(row["id"]),
				"t": int(row["t"]),
				"who": who,
			})
	if pairs.is_empty():
		return {"error": "rumor spread produced no beliefs"}
	_cached_beliefs = pairs
	_belief_ready = true
	return {"pairs": pairs}


## Replays the drained pack's adoption pairs onto a fresh scale deed log.
func _arm_scale_believers() -> String:
	var found := _belief_pairs()
	if not str(found.get("error", "")).is_empty():
		return str(found["error"])
	_runtime.start_new_game(WyrdPerfScale.SEED)
	_import_deeds()
	for pair in found["pairs"]:
		var row: Dictionary = pair
		_runtime.deeds.note_believer(int(row["id"]), StringName(str(row["who"])), int(row["t"]))
	return ""


func _measure_believers() -> Dictionary:
	var found := _belief_pairs()
	if not str(found.get("error", "")).is_empty():
		return found
	_runtime.start_new_game(WyrdPerfScale.SEED)
	_import_deeds()
	var before := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	for pair in found["pairs"]:
		var row: Dictionary = pair
		_runtime.deeds.note_believer(int(row["id"]), StringName(str(row["who"])), int(row["t"]))
	var memory := maxi(int(Performance.get_monitor(Performance.MEMORY_STATIC)) - before, 0)
	var exported := _runtime.deeds.export_state()
	var with_bytes := JSON.stringify(exported).to_utf8_buffer().size()
	for item in exported["rows"]:
		(item as Dictionary).erase("believers")
	var without_bytes := JSON.stringify(exported).to_utf8_buffer().size()
	exported = {}
	return {
		"bytes": with_bytes - without_bytes,
		"count": (found["pairs"] as Array).size(),
		"memory": memory,
	}


func _rumor_checksum(coarse_id: int) -> String:
	var level := -1
	if coarse_id > 0:
		level = _runtime.rumors.reach_level(str(coarse_id), StringName(WyrdPerfScale.COARSE_PLACE))
	return "%s:%s:%s" % [
		_runtime.scheduler().carry("rumor"),
		_belief_count(),
		level,
	]


func _belief_count() -> int:
	var count := 0
	for index in _npcs:
		count += _runtime.deeds.believer_deeds(StringName(_npc(index))).size()
	return count


func _gazette_text() -> String:
	var value: Variant = _runtime.facts.get_in(StringName(WyrdPerfScale.GAZETTE_FACT), &"world")
	if value == null:
		return ""
	return str(value)


func _deed_score() -> float:
	return _runtime.deeds.score_matching(&"", null, null, null, WyrdPerfScale.DEED_WITHIN)


func _deed_clock() -> int:
	return 1000 + maxi(_deeds, 1) - 1


func _time_ticks() -> Array[float]:
	var times: Array[float] = []
	for _step in WyrdPerfScale.TICKS_PER_SAMPLE:
		var started := Time.get_ticks_usec()
		_runtime.tick(0)
		times.append(float(Time.get_ticks_usec() - started) / 1000000.0)
	return times


func _set_shares(work: int, waits: int, rumor: int, publish: int, cache: int) -> void:
	var config := _runtime.config()
	config.scheduler_work_per_tick = work
	config.scheduler_share_waits = waits
	config.scheduler_share_rumor = rumor
	config.scheduler_share_publish = publish
	config.scheduler_share_cache = cache


func _restore_shares() -> void:
	if _runtime == null:
		return
	_set_shares(64, 40, 12, 8, 4)


func _keep_none(_value: Variant, _hop: int) -> float:
	return 0.0


func _to_waived(_value: Variant, _hop: int) -> StringName:
	return StringName(WyrdPerfScale.MUTATION_TO)


func _flight_path() -> String:
	return _box.path_join("flight.json")


func _median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var copy := values.duplicate()
	copy.sort()
	var mid := int(copy.size() / 2.0)
	if copy.size() % 2 == 1:
		return copy[mid]
	return (copy[mid - 1] + copy[mid]) / 2.0


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
