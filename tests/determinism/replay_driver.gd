extends RefCounted

## Records a run, then replays it into a fresh runtime.
## Each step has an action segment and a pump segment.
## A step is replayed when every Wyrd call in it is a recorded input
## (host and setup run first). Any other step is repeated whole.
## The trace prefix stays empty except where a scenario itself sets it.

const _M10 := preload("res://tests/scenario/m10_gullhaven.gd")
const _Cases := preload("res://tests/determinism/replay_cases.gd")

const MODE := {
	"open": "replayed",
	"lines": "replayed",
	"choose": "replayed",
	"tick": "replayed",
	"unlock": "repeated",
	"open_topic": "replayed",
	"ask": "replayed",
	"bark": "repeated",
	"summary": "replayed",
	"save_load": "repeated",
	"season": "replayed",
	"know": "repeated",
	"nearby": "replayed",
	"carry": "replayed",
	"role": "repeated",
	"start": "repeated",
	"skill": "replayed",
	"fail_action": "replayed",
	"abort": "replayed",
	"owner": "replayed",
	"remove": "replayed",
	"vacate": "repeated",
	"kill_ferry": "repeated",
	"successor": "repeated",
	"arm": "repeated",
	"propose": "repeated",
	"accept": "replayed",
	"host_request": "replayed",
	"audio": "replayed",
	"mooring": "repeated",
	"set_kind": "repeated",
	"deed": "repeated",
	"fact": "repeated",
	"fact_in": "repeated",
	"clear_in": "repeated",
	"assign": "repeated",
	"define": "repeated",
	"member": "replayed",
	"alive": "replayed",
	"groups": "replayed",
	"perception": "replayed",
	"baseline": "repeated",
	"invalidate": "repeated",
	"poll": "replayed",
	"console": "repeated",
	"query": "repeated",
	"why_not": "repeated",
	"diagnose": "repeated",
	"candidates": "repeated",
	"coverage_on": "replayed",
	"choice_summary": "repeated",
	"compact": "repeated",
	"offer": "replayed",
	"share": "replayed",
	"protected": "replayed",
	"propose_open": "replayed",
	"emit_state": "replayed",
	"seen": "repeated",
	"trace_director": "replayed",
	"prefix": "replayed",
	"secrecy": "replayed",
	"trace_off": "replayed",
	"m4_act": "repeated",
	"save_hold": "repeated",
	"load_held": "repeated",
	"stew_offer": "replayed",
}

const _M10_OPS := {
	"open": true, "lines": true, "choose": true, "tick": true, "unlock": true,
	"open_topic": true, "ask": true, "bark": true, "summary": true, "save_load": true,
	"season": true, "know": true, "nearby": true, "carry": true, "role": true,
	"start": true, "skill": true, "fail_action": true, "abort": true, "owner": true,
	"remove": true, "vacate": true, "kill_ferry": true, "successor": true, "arm": true,
	"propose": true, "accept": true, "host_request": true, "audio": true, "mooring": true,
}

static var op_modes := {}
static var seen_kinds := {}
static var split_notes: Array = []
static var split_points := 0
static var started_ms := 0
static var limit_plain_splits := true
static var category_counts := {}
static var unrecorded_lines: Array = []
static var unexercised: Array = []
static var replay_kinds: Array = []
static var _cache := {}
static var _suite: RefCounted


static func reset() -> void:
	op_modes = {}
	seen_kinds = {}
	split_notes = []
	split_points = 0
	category_counts = {}
	unrecorded_lines = []
	unexercised = []
	replay_kinds = []
	_cache = {}


func suite() -> RefCounted:
	if _suite == null:
		_suite = _M10.new()
	return _suite


func route_names() -> PackedStringArray:
	var names: Array = suite().ROUTES.keys()
	names.sort()
	var out := PackedStringArray()
	for item in names:
		out.append(str(item))
	return out


func record_route(name: String, provider: String) -> Dictionary:
	var key := "route|%s|%s" % [name, provider]
	if _cache.has(key):
		return _cache[key]
	var spec: Dictionary = suite().ROUTES[name]
	var steps: Array = spec["steps"]
	var opened: Dictionary = suite().boot_spec(spec, provider)
	var runtime: WyrdRuntime = opened["runtime"]
	var recorded := _record_steps(runtime, steps)
	recorded["hash"] = suite().gameplay_hash(runtime)
	recorded["spec"] = spec
	recorded["provider"] = provider
	recorded["steps"] = steps
	recorded["id"] = key
	_release(runtime)
	_cache[key] = recorded
	return recorded


func replay_route(name: String, provider: String, recorded: Dictionary) -> Dictionary:
	var spec: Dictionary = recorded["spec"]
	var opened: Dictionary = suite().boot_spec(spec, provider)
	var runtime: WyrdRuntime = opened["runtime"]
	var steps: Array = recorded["steps"]
	_replay_steps(runtime, steps, recorded["events"], recorded["segments"], 0, steps.size())
	var replayed := {"events": runtime.trace.snapshot(), "hash": suite().gameplay_hash(runtime)}
	_release(runtime)
	return replayed


func record_case(run: Dictionary) -> Dictionary:
	var key := "case|%s" % str(run["id"])
	if _cache.has(key):
		return _cache[key]
	var runtime := _Cases.boot(run)
	_begin(runtime, run)
	var steps: Array = run["steps"]
	var recorded := _record_steps(runtime, steps)
	recorded["hash"] = suite().gameplay_hash(runtime)
	recorded["steps"] = steps
	recorded["run"] = run
	recorded["id"] = key
	_release(runtime)
	_cache[key] = recorded
	return recorded


func replay_case(run: Dictionary, recorded: Dictionary) -> Dictionary:
	var runtime := _Cases.boot(run)
	_begin(runtime, run)
	var steps: Array = recorded["steps"]
	_replay_steps(runtime, steps, recorded["events"], recorded["segments"], 0, steps.size())
	var replayed := {"events": runtime.trace.snapshot(), "hash": suite().gameplay_hash(runtime)}
	_release(runtime)
	return replayed


func split_indexes(segments: Array) -> Array:
	var out: Array = []
	for k in segments.size():
		if _is_split(segments, k):
			out.append(k)
	return out


func choose_plain(indexes: Array) -> Array:
	if not limit_plain_splits or indexes.size() <= 3:
		return indexes
	var mid = indexes[int(indexes.size() / 2)]
	var picked: Array = [indexes[0]]
	if mid != indexes[0]:
		picked.append(mid)
	var last = indexes[indexes.size() - 1]
	if last != mid and last != indexes[0]:
		picked.append(last)
	return picked


func plain_route_split(name: String, recorded: Dictionary, k: int) -> Dictionary:
	split_points += 1
	var spec: Dictionary = recorded["spec"]
	var doc := _prefix_save_route(spec, "", recorded, k)
	return _check_split(recorded, k, doc, "route %s @%d" % [name, k])


func plain_case_split(run: Dictionary, recorded: Dictionary, k: int) -> PackedStringArray:
	split_points += 1
	var doc := _prefix_save_case(run, recorded, k)
	var checked: Dictionary = _check_split(recorded, k, doc, "%s @%d" % [str(run["id"]), k])
	var problems: PackedStringArray = checked["problems"]
	return problems


func echo_route_split(name: String, recorded: Dictionary, k: int) -> Dictionary:
	split_points += 1
	var spec: Dictionary = recorded["spec"]
	var doc := _prefix_save_route(spec, "echo", recorded, k)
	return _check_split(recorded, k, doc, "echo %s @%d" % [name, k])


func play_canon(spec: Dictionary, provider: String) -> String:
	var played := _M10.new()
	var opened: Dictionary = played.boot_spec(spec, provider)
	var runtime: WyrdRuntime = opened["runtime"]
	played.play(runtime, spec["steps"])
	var text := canon(runtime.trace.events)
	_release(runtime)
	return text


func canon(events: Array) -> String:
	var rows: Array = []
	for item in events:
		if item is Dictionary and bool((item as Dictionary).get("timing", false)):
			continue
		rows.append(item)
	return JSON.stringify(rows)


func explain(expected: Array, actual: Array) -> String:
	var found := WyrdTrace.diff(expected, actual)
	if found.is_empty():
		return ""
	var lines := PackedStringArray()
	for row in found:
		lines.append(str(row))
	var pair := _first_row(expected, actual)
	if pair != "":
		lines.append(pair)
	return "\n".join(lines)


func act(runtime: WyrdRuntime, step: Dictionary) -> void:
	var op := str(step.get("op", ""))
	if _M10_OPS.has(op):
		_act_m10(runtime, step)
	else:
		_Cases.act(runtime, step)


func prepare(runtime: WyrdRuntime, step: Dictionary) -> void:
	var op := str(step.get("op", ""))
	if _M10_OPS.has(op):
		_prepare_m10(runtime, step)
	else:
		_Cases.prepare(runtime, step)


func _begin(runtime: WyrdRuntime, run: Dictionary) -> void:
	runtime.config().scheduler_frame_warn_usec = 0
	runtime.trace.prefix = ""
	if bool(run.get("trace", true)):
		runtime.trace.enabled = true
	else:
		runtime.trace.enabled = false
	runtime.trace.clear()


func _record_steps(runtime: WyrdRuntime, steps: Array) -> Dictionary:
	var segments: Array = []
	for i in steps.size():
		var step: Dictionary = steps[i]
		var op := str(step.get("op", ""))
		var mode := "repeated"
		if MODE.has(op):
			mode = str(MODE[op])
		else:
			push_error("replay driver unknown op %s" % op)
		op_modes[op] = mode
		var at := runtime.trace.events.size()
		act(runtime, step)
		var mid := runtime.trace.events.size()
		suite().pump(runtime)
		var end_at := runtime.trace.events.size()
		var pending := 0
		if runtime.ai != null:
			pending = runtime.ai.pending_count()
		var offers := 0
		if runtime.generator != null:
			offers = runtime.generator.pending_count()
		segments.append({
			"at": at,
			"can_save": runtime.can_save(),
			"end": end_at,
			"mid": mid,
			"mode": mode,
			"offers": offers,
			"op": op,
			"pending": pending,
		})
	var events: Array = runtime.trace.snapshot()
	_note_kinds(events)
	return {"events": events, "segments": segments}


func _replay_steps(runtime: WyrdRuntime, steps: Array, events: Array, segments: Array, from_i: int, to_i: int) -> void:
	for i in range(from_i, to_i):
		var step: Dictionary = steps[i]
		var seg: Dictionary = segments[i]
		if str(seg["mode"]) == "repeated":
			act(runtime, step)
		else:
			prepare(runtime, step)
			WyrdTrace.replay(runtime, _slice(events, int(seg["at"]), int(seg["mid"])))
		WyrdTrace.replay(runtime, _slice(events, int(seg["mid"]), int(seg["end"])))


func _is_split(segments: Array, k: int) -> bool:
	var seg: Dictionary = segments[k]
	if not bool(seg["can_save"]):
		return false
	if int(seg["pending"]) != 0:
		return false
	# Load drops the offer queue, so a queued offer is not a split point.
	if int(seg["offers"]) != 0:
		return false
	var open_proposal := false
	for i in k + 1:
		var op := str((segments[i] as Dictionary)["op"])
		if op == "propose" or op == "propose_open":
			open_proposal = true
		elif op == "accept":
			open_proposal = false
	if not open_proposal:
		return true
	for j in range(k + 1, segments.size()):
		if str((segments[j] as Dictionary)["op"]) == "accept":
			return false
	return true


func _prefix_save_route(spec: Dictionary, provider: String, recorded: Dictionary, k: int) -> Dictionary:
	var runtime := _boot_route(spec, provider)
	var steps: Array = recorded["steps"]
	_replay_steps(runtime, steps, recorded["events"], recorded["segments"], 0, k + 1)
	var doc := _round_trip(runtime)
	_release(runtime)
	return doc


func _prefix_save_case(run: Dictionary, recorded: Dictionary, k: int) -> Dictionary:
	var runtime := _Cases.boot(run)
	_begin(runtime, run)
	var steps: Array = recorded["steps"]
	_replay_steps(runtime, steps, recorded["events"], recorded["segments"], 0, k + 1)
	var doc := _round_trip(runtime)
	_release(runtime)
	return doc


func _check_split(recorded: Dictionary, k: int, doc: Dictionary, label: String) -> Dictionary:
	var steps: Array = recorded["steps"]
	var trace_on := _trace_on(recorded)
	var problems := PackedStringArray()
	var loaded := _load_into(_fresh_split_runtime(recorded), steps, k, doc)
	problems.append_array(loaded["problems"])
	var host: WyrdRuntime = loaded["runtime"]
	host.trace.enabled = trace_on
	host.trace.clear()
	var tail := _tail_steps(steps, k)
	var suffix := _record_steps(host, tail)
	var live_hash := str(suite().gameplay_hash(host))
	_release(host)
	if live_hash != str(recorded["hash"]):
		problems.append("%s hash" % label)
	for replay_i in 2:
		var again := _load_into(_fresh_split_runtime(recorded), steps, k, doc)
		problems.append_array(again["problems"])
		var fresh: WyrdRuntime = again["runtime"]
		fresh.trace.enabled = trace_on
		fresh.trace.clear()
		_replay_steps(fresh, tail, suffix["events"], suffix["segments"], 0, tail.size())
		var got: Array = fresh.trace.snapshot()
		_release(fresh)
		var mismatch := explain(suffix["events"], got)
		if mismatch != "":
			problems.append("%s replay %d\n%s" % [label, replay_i + 1, mismatch])
		if canon(got) != canon(suffix["events"]):
			problems.append("%s replay bytes %d" % [label, replay_i + 1])
	var uninterrupted: Array = _slice(recorded["events"], int(recorded["segments"][k]["end"]), recorded["events"].size())
	return {"diff": explain(uninterrupted, suffix["events"]), "problems": problems}


func _fresh_split_runtime(recorded: Dictionary) -> WyrdRuntime:
	if recorded.has("spec"):
		var spec: Dictionary = recorded["spec"]
		return _boot_route(spec, str(recorded.get("provider", "")))
	var run: Dictionary = recorded["run"]
	var runtime := _Cases.boot(run)
	_begin(runtime, run)
	return runtime


func _release(runtime: WyrdRuntime) -> void:
	# Runtimes point back at themselves through callables, so drop those links
	# once the trace and the save have been copied out. The comparison is done.
	if runtime == null:
		return
	if runtime.has_meta("m10_host"):
		var host: Variant = runtime.get_meta("m10_host")
		if host is WyrdFakeHost:
			var fake: WyrdFakeHost = host as WyrdFakeHost
			if fake.world != null:
				fake.world.changed = Callable()
		runtime.remove_meta("m10_host")
	if runtime.has_meta("host"):
		runtime.remove_meta("host")
	runtime.remove_meta("m10_provider")
	runtime.remove_meta("m10_harness")
	runtime.remove_meta("m10_catch")
	runtime.facts = null
	runtime.events = null
	runtime.roles = null
	runtime.topics = null
	runtime.documents = null
	runtime.deeds = null
	runtime.social = null
	runtime.rumors = null
	runtime.publish = null
	runtime.effects = null
	runtime.quests = null
	runtime.dialogue = null
	runtime.storylets = null
	runtime.sequences = null
	runtime.director = null
	runtime.generator = null
	runtime.ai = null
	runtime.trace = null
	runtime.debug = null
	runtime.coverage = null
	runtime.set("_queue", null)
	runtime.set("_ctx", null)
	runtime.set("_rpn", null)
	runtime.set("_adapters", {})
	runtime.set("_config", null)
	runtime.set("_content", null)
	runtime.set("_signatures", null)


func _trace_on(recorded: Dictionary) -> bool:
	if recorded.get("run") is Dictionary:
		return bool((recorded["run"] as Dictionary).get("trace", true))
	return true


func _load_into(runtime: WyrdRuntime, steps: Array, k: int, doc: Dictionary) -> Dictionary:
	for i in k + 1:
		prepare(runtime, steps[i])
	runtime.trace.enabled = true
	runtime.trace.clear()
	var report: WyrdLoadReport = runtime.load_state(doc["doc"])
	var load_events: Array = runtime.trace.snapshot()
	var expected_kept: Array = []
	if doc.get("kept") is Array:
		expected_kept = doc["kept"]
	var problems := _load_problems(runtime, report, str(doc["text"]), load_events, expected_kept)
	runtime.trace.clear()
	return {"problems": problems, "runtime": runtime}


func _load_problems(runtime: WyrdRuntime, report: WyrdLoadReport, expected_text: String, load_events: Array, expected_kept: Array) -> PackedStringArray:
	var problems := PackedStringArray()
	if not report.ok:
		problems.append("load not ok %s" % report.diagnostics.format())
	var got_rows := JSON.stringify(report.rows, "", true)
	var want_rows := JSON.stringify(expected_kept, "", true)
	if got_rows != want_rows:
		problems.append("load rows %s expected %s" % [got_rows, want_rows])
	var right := JSON.stringify(runtime.save_state(), "\t", true)
	if expected_text != right:
		var parsed_left: Variant = JSON.parse_string(expected_text)
		var parsed_right: Variant = JSON.parse_string(right)
		problems.append("save differs after load %s" % _first_diff(parsed_left, parsed_right, "save"))
	for item in load_events:
		if not (item is Dictionary):
			problems.append("load trace row is not a dictionary")
			break
		var kind := str((item as Dictionary).get("kind", ""))
		if not kind.begins_with("ai_"):
			problems.append("load trace %s" % JSON.stringify(item))
			break
	return problems


func _boot_route(spec: Dictionary, provider: String) -> WyrdRuntime:
	var opened: Dictionary = suite().boot_spec(spec, provider)
	return opened["runtime"]


func _round_trip(runtime: WyrdRuntime) -> Dictionary:
	var saved := runtime.save_state()
	# JSON.parse_string turns integers into floats. Load that document, then
	# compare the canonical text of the save that was written.
	var text := JSON.stringify(saved, "\t", true)
	var parsed: Variant = JSON.parse_string(JSON.stringify(saved))
	return {"doc": parsed, "kept": _kept_rows(runtime), "text": text}


func _kept_rows(runtime: WyrdRuntime) -> Array:
	var report: WyrdLoadReport = WyrdLoadReport.new()
	WyrdSave._note_kept(runtime, report)
	report.sort_rows()
	return report.rows


func _tail_steps(steps: Array, k: int) -> Array:
	var tail: Array = []
	for i in range(k + 1, steps.size()):
		tail.append(steps[i])
	return tail


func _slice(events: Array, at: int, end_at: int) -> Array:
	return events.slice(at, end_at)


func _note_kinds(events: Array) -> void:
	for item in events:
		if item is Dictionary:
			seen_kinds[str((item as Dictionary).get("kind", ""))] = true


func _first_row(expected: Array, actual: Array) -> String:
	var left := 0
	var right := 0
	while left < expected.size() and right < actual.size():
		if _timing(expected[left]):
			left += 1
			continue
		if _timing(actual[right]):
			right += 1
			continue
		if JSON.stringify(expected[left]) != JSON.stringify(actual[right]):
			return "expected %s\nactual %s" % [JSON.stringify(expected[left]), JSON.stringify(actual[right])]
		left += 1
		right += 1
	return ""


func _timing(row: Variant) -> bool:
	return row is Dictionary and bool((row as Dictionary).get("timing", false))


func _first_diff(left: Variant, right: Variant, path: String) -> String:
	if typeof(left) != typeof(right):
		return "%s type" % path
	var nested := ""
	if left is Dictionary:
		var keys: Array = left.keys()
		for right_key in right.keys():
			if not left.has(right_key):
				return "%s missing %s" % [path, str(right_key)]
		for left_key in keys:
			if not right.has(left_key):
				return "%s extra %s" % [path, str(left_key)]
			nested = _first_diff(left[left_key], right[left_key], "%s.%s" % [path, str(left_key)])
			if nested != "":
				return nested
		return ""
	if left is Array:
		if left.size() != right.size():
			return "%s length %d/%d" % [path, left.size(), right.size()]
		for i in left.size():
			nested = _first_diff(left[i], right[i], "%s[%d]" % [path, i])
			if nested != "":
				return nested
		return ""
	if left != right:
		return "%s %s != %s" % [path, str(left), str(right)]
	return ""


func _host(runtime: WyrdRuntime) -> WyrdFakeHost:
	return runtime.get_meta("m10_host") as WyrdFakeHost


func _prepare_m10(runtime: WyrdRuntime, step: Dictionary) -> void:
	var op := str(step.get("op", ""))
	var host := _host(runtime)
	match op:
		"fail_action":
			host.actions.set_result_for(StringName(str(step["command"])), WyrdCommandResult.failed(StringName(str(step["reason"]))))
		"nearby":
			_nearby(host, step)
		"carry":
			host.inventory.set_count(&"player", StringName(str(step["item"])), int(step.get("count", 1)))
		"owner":
			host.inventory.set_owner(StringName(str(step["item"])), StringName(str(step["who"])))
		"remove":
			host.world.remove_entity(StringName(str(step["id"])))
		"season":
			host.clock.season_name = StringName(str(step["name"]))
		"skill":
			_skill(runtime, step)
		"audio":
			_audio(runtime)
		"mooring":
			_mooring_entities(host)
		"kill_ferry":
			host.world.add_entity(&"ferry_master", &"person", "Bram", PackedStringArray(), false)
		_:
			pass


func _act_m10(runtime: WyrdRuntime, step: Dictionary) -> void:
	var op := str(step.get("op", ""))
	var host := _host(runtime)
	var harness: RefCounted = runtime.get_meta("m10_harness")
	match op:
		"open":
			runtime.dialogue.open_scene(str(step["scene"]))
		"lines":
			harness.line_rows(runtime)
		"choose":
			harness.choose_text(runtime, str(step["text"]))
		"tick":
			runtime.tick(int(step.get("minutes", 0)))
		"unlock":
			runtime.topics.unlock(StringName(str(step["topic"])))
		"open_topic":
			runtime.dialogue.open(str(step["npc"]))
		"ask":
			runtime.dialogue.ask_topic(str(step["npc"]), str(step["topic"]))
		"bark":
			_bark(runtime)
		"summary":
			runtime.quests.summary(str(step["quest"]))
		"save_load":
			var saved := runtime.save_state()
			var parsed: Variant = JSON.parse_string(JSON.stringify(saved))
			var report := runtime.load_state(parsed)
			if not report.ok:
				push_error("replay save_load: %s" % report.diagnostics.format())
		"season":
			host.clock.season_name = StringName(str(step["name"]))
			runtime.events.emit(&"season_changed", {})
		"know":
			runtime.facts.set_in(StringName(str(step["key"])), step["value"], &"known/player")
		"nearby":
			_nearby(host, step)
		"carry":
			host.inventory.set_count(&"player", StringName(str(step["item"])), int(step.get("count", 1)))
		"role":
			runtime.roles.assign(StringName(str(step["role"])), StringName(str(step["entity"])))
		"start":
			runtime.quests.start(str(step["quest"]))
		"skill":
			_skill(runtime, step)
		"fail_action":
			host.actions.set_result_for(StringName(str(step["command"])), WyrdCommandResult.failed(StringName(str(step["reason"]))))
		"abort":
			runtime.dialogue.abort(StringName(str(step.get("reason", "left"))))
		"owner":
			host.inventory.set_owner(StringName(str(step["item"])), StringName(str(step["who"])))
		"remove":
			host.world.remove_entity(StringName(str(step["id"])))
		"vacate":
			runtime.roles.vacate(StringName(str(step["role"])), StringName(str(step.get("reason", "died"))))
		"kill_ferry":
			host.world.add_entity(&"ferry_master", &"person", "Bram", PackedStringArray(), false)
			runtime.roles.vacate(&"ferry_master", &"died")
		"successor":
			runtime.roles.define(&"ferry_master", "relation(apprentice)")
			runtime.social.set_kind(&"ferry_master", &"dock_apprentice", &"apprentice")
			runtime.roles.vacate(&"ferry_master", &"died")
		"arm":
			_arm(runtime, str(step["template"]))
		"propose":
			_arm(runtime, str(step["template"]))
			var proposal: WyrdProposal = runtime.generator.propose({
				"key": str(step.get("key", "exit")),
				"source": "exit",
				"template": str(step["template"]),
				"tier": str(step.get("tier", "")),
			})
			runtime.set_meta("m10_proposal", proposal)
		"accept":
			var pending: Variant = runtime.get_meta("m10_proposal", null)
			if pending is WyrdProposal:
				runtime.generator.accept(pending)
		"host_request":
			var packet := runtime.ai.packet_for_line("a_leave", &"bark_paraphrase", &"")
			runtime.ai.request(&"bark_paraphrase", packet, {}, &"a_leave")
		"audio":
			_audio(runtime)
		"mooring":
			_mooring_entities(host)
			runtime.facts.set(&"harbor.mooring_check", true)
		_:
			push_error("replay driver unknown m10 step %s" % op)


func _nearby(host: WyrdFakeHost, step: Dictionary) -> void:
	var posts := PackedStringArray()
	if bool(step.get("posts", true)):
		posts = PackedStringArray([&"post"])
	host.spatial.set_nearby(&"player", 4.0, StringName(str(step.get("tag", "lantern"))), posts)


func _skill(runtime: WyrdRuntime, step: Dictionary) -> void:
	var skills := WyrdFakeSkills.new()
	if bool(step.get("pass", true)):
		skills.set_result(WyrdCommandResult.ok())
	else:
		skills.set_result_for(&"strength", WyrdCommandResult.failed(&"weak"))
	runtime.register_adapter(WyrdSkillAdapter, skills)


func _audio(runtime: WyrdRuntime) -> void:
	runtime.dialogue.locale = "en"
	runtime.dialogue.register_line_audio(func(_line_id: String, _locale: String) -> Variant: return _tone())


func _tone() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	stream.data = PackedByteArray([128, 160, 128, 96])
	return stream


func _mooring_entities(host: WyrdFakeHost) -> void:
	host.world.add_entity(&"dock.bollard_north", &"object", "North Bollard", PackedStringArray(["bollard"]), true)
	host.world.add_entity(&"dock.bollard_south", &"object", "South Bollard", PackedStringArray(["bollard"]), true)
	host.world.add_entity(&"dock.crate", &"object", "crate", PackedStringArray(), true)
	host.world.add_entity(&"bram", &"person", "Bram", PackedStringArray(["bollard"]), true)


func _arm(runtime: WyrdRuntime, template_id: String) -> void:
	match template_id:
		"net_delivery":
			runtime.facts.set(&"harbor.nets_wanted", true)
		"stolen_catch":
			runtime.facts.set(&"harbor.catch_missing", true)
		"cut_line":
			runtime.facts.set(&"harbor.boat_adrift", true)
		"night_walk":
			runtime.facts.set(&"harbor.visitor_waiting", true)
		_:
			pass


func _bark(runtime: WyrdRuntime) -> void:
	var won := runtime.director.query("bark", "", "ferry")
	var story_id := str(won.get("id", ""))
	if story_id.is_empty():
		return
	var story := runtime.content().storylets.get(story_id) as WyrdStoryletDef
	runtime.present_bark(story, {"line_id": str(won.get("line_id", ""))})
