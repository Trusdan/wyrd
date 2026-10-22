extends RefCounted

## Headless Gullhaven routes and scripted providers for the M10 exit suite.
## Providers answer on [method pump], never inside [method WyrdAIProvider.request].

const _Harness := preload("res://tests/scenario/s2c_harness.gd")
const _Harbor := preload("res://tests/scenario/m9_gullhaven.gd")

var ROUTES: Dictionary = {}


func _init() -> void:
	ROUTES = _routes()


func boot(provider: String, seed: int = 1, generated: bool = false, local_tag: bool = false, storm_heard: bool = true) -> Dictionary:
	var opened: Dictionary = {}
	if generated:
		opened = _Harbor.new().boot_generated(seed)
	else:
		opened = _Harness.new().boot_gullhaven(local_tag, 4, storm_heard)
		opened["harness"] = _Harness.new()
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.config().scheduler_frame_warn_usec = 0
	# A stored symbol the player has not learned. Garbage and fuzz quote it.
	runtime.facts.set_in(&"harbor.toll_fate", &"hidden_bell", &"world")
	var scripted: WyrdAIProvider = _make(provider)
	if scripted != null:
		runtime.register_adapter(WyrdAIProvider, scripted)
	var catcher := _Catch.new()
	runtime.bark_ready.connect(catcher.on_bark)
	runtime.dialogue.topic_answered.connect(catcher.on_topic)
	if scripted != null:
		runtime.set_meta("m10_provider", scripted)
	runtime.set_meta("m10_host", opened["host"])
	runtime.set_meta("m10_harness", opened["harness"])
	runtime.set_meta("m10_catch", catcher)
	runtime.trace.enabled = true
	runtime.trace.clear()
	opened["provider"] = scripted
	return opened


func boot_spec(spec: Dictionary, provider: String) -> Dictionary:
	return boot(
		provider,
		int(spec.get("seed", 1)),
		bool(spec.get("generated", false)),
		bool(spec.get("local", false)),
		bool(spec.get("storm", true))
	)


func pump(runtime: WyrdRuntime) -> void:
	if not runtime.has_meta("m10_provider"):
		return
	var provider: Variant = runtime.get_meta("m10_provider")
	if provider == null or not provider.has_method("take_answers"):
		return
	var answers: Array = provider.take_answers()
	answers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	for item in answers:
		var row: Dictionary = item
		var result := WyrdAIResult.new()
		result.ok = bool(row["ok"])
		result.text = str(row["text"])
		result.error = str(row["error"])
		runtime.ai.deliver(int(row["id"]), result)


func play(runtime: WyrdRuntime, route: Array) -> Array:
	var shown: Array = []
	for step in route:
		run_step(runtime, step, shown)
		pump(runtime)
	return shown


func run_step(runtime: WyrdRuntime, step: Dictionary, shown: Array) -> void:
	var op := str(step.get("op", ""))
	var host: WyrdFakeHost = runtime.get_meta("m10_host")
	var harness: RefCounted = runtime.get_meta("m10_harness")
	match op:
		"open":
			runtime.dialogue.open_scene(str(step["scene"]))
		"lines":
			for row in harness.line_rows(runtime):
				shown.append(_shown(runtime, str(row["id"]), str(row["text"])))
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
			var catcher: _Catch = runtime.get_meta("m10_catch")
			if catcher.topic_line != null:
				var line := catcher.topic_line
				shown.append(_shown(runtime, line.id, line.text))
				catcher.topic_line = null
		"bark":
			_bark(runtime, shown)
		"summary":
			_summary(runtime, str(step["quest"]), shown)
		"save_load":
			var saved := runtime.save_state()
			var parsed: Variant = JSON.parse_string(JSON.stringify(saved))
			var report := runtime.load_state(parsed)
			if not report.ok:
				push_error("m10 save_load: %s" % report.diagnostics.format())
		"season":
			host.clock.season_name = StringName(str(step["name"]))
			runtime.events.emit(&"season_changed", {})
		"know":
			runtime.facts.set_in(StringName(str(step["key"])), step["value"], &"known/player")
		"nearby":
			host.spatial.set_nearby(&"player", 4.0, StringName(str(step.get("tag", "lantern"))), PackedStringArray([&"post"]))
		"carry":
			host.inventory.set_count(&"player", StringName(str(step["item"])), int(step.get("count", 1)))
		"role":
			runtime.roles.assign(StringName(str(step["role"])), StringName(str(step["entity"])))
		"start":
			runtime.quests.start(str(step["quest"]))
		"skill":
			var skills := WyrdFakeSkills.new()
			if bool(step.get("pass", true)):
				skills.set_result(WyrdCommandResult.ok())
			else:
				skills.set_result_for(&"strength", WyrdCommandResult.failed(&"weak"))
			runtime.register_adapter(WyrdSkillAdapter, skills)
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
			runtime.dialogue.locale = "en"
			runtime.dialogue.register_line_audio(func(_line_id: String, _locale: String) -> Variant: return _tone())
		"mooring":
			host.world.add_entity(&"dock.bollard_north", &"object", "North Bollard", PackedStringArray(["bollard"]), true)
			host.world.add_entity(&"dock.bollard_south", &"object", "South Bollard", PackedStringArray(["bollard"]), true)
			host.world.add_entity(&"dock.crate", &"object", "crate", PackedStringArray(), true)
			host.world.add_entity(&"bram", &"person", "Bram", PackedStringArray(["bollard"]), true)
			runtime.facts.set(&"harbor.mooring_check", true)
		_:
			push_error("m10 unknown step %s" % op)


func gameplay_hash(runtime: WyrdRuntime) -> String:
	var saved := WyrdSave.capture(runtime)
	saved.erase("ai")
	return JSON.stringify(saved, "", true)


func filtered_trace(events: Array) -> String:
	var rows: Array = []
	for item in events:
		if not (item is Dictionary):
			continue
		var row: Dictionary = (item as Dictionary).duplicate(true)
		var kind := str(row.get("kind", ""))
		if kind.begins_with("ai_"):
			continue
		if kind == "scheduler" and str(row.get("queue", "")) == "ai_prefetch":
			continue
		for key in row.keys():
			if str(key).begins_with("ai_prefetch_"):
				row.erase(key)
		if kind == "line":
			row.erase("text")
		rows.append(row)
	return JSON.stringify(rows, "", true)


func authored(runtime: WyrdRuntime, line_id: String) -> String:
	var line_def := runtime.content().lines.get(line_id) as WyrdLineDef
	if line_def == null:
		return ""
	return str(runtime.resolve_line(line_def).get("text", ""))


func joined_journal(runtime: WyrdRuntime, quest_id: String) -> String:
	var lines := PackedStringArray()
	for item in runtime.quests.journal(quest_id):
		if item is Dictionary:
			lines.append(str((item as Dictionary).get("text", "")))
	return "\n".join(lines)


func line_texts(events: Array) -> PackedStringArray:
	var lines := PackedStringArray()
	for item in events:
		if item is Dictionary and str((item as Dictionary).get("kind", "")) == "line":
			lines.append(str((item as Dictionary).get("text", "")))
	return lines


func audit_shown(runtime: WyrdRuntime, shown: Array) -> String:
	for item in shown:
		var row: Dictionary = item
		var text := str(row["text"])
		var fallback := str(row["authored"])
		if text == fallback:
			continue
		var path := str(row["path"])
		var use := _last_use(runtime, path)
		if str(use.get("source", "")) != "ai":
			return "%s text changed without source=ai" % path
		var kind := StringName(str(use.get("slot_kind", "bark_paraphrase")))
		var packet: Dictionary = {}
		if path.begins_with("summary:"):
			packet = runtime.ai.summary_packet(path.substr(8), runtime.quests.journal(path.substr(8)))
		else:
			packet = runtime.ai.packet_for_line(path, kind, &"")
		var rule := runtime.ai.validate(text, kind, packet)
		if rule != &"":
			return "%s source=ai failed %s" % [path, String(rule)]
	return ""


func source_is_ai(runtime: WyrdRuntime) -> bool:
	for item in runtime.trace.events:
		if item is Dictionary and str((item as Dictionary).get("kind", "")) == "ai_use":
			if str((item as Dictionary).get("source", "")) == "ai":
				return true
	return false


func fuzz_outcomes(events: Array) -> Dictionary:
	var counts := {
		"accepted": 0,
		"banned": 0,
		"classifier": 0,
		"error": 0,
		"limits": 0,
		"names": 0,
		"provider": 0,
		"spoiler": 0,
	}
	for item in events:
		if not (item is Dictionary):
			continue
		var row: Dictionary = item
		var kind := str(row.get("kind", ""))
		if kind == "ai_result" and str(row.get("ok", "")) == "false":
			counts["error"] = int(counts["error"]) + 1
		elif kind == "ai_validate":
			if str(row.get("ok", "")) == "true":
				counts["accepted"] = int(counts["accepted"]) + 1
			else:
				var rule := str(row.get("rule", ""))
				if counts.has(rule):
					counts[rule] = int(counts[rule]) + 1
				else:
					counts[rule] = 1
	return counts


func _shown(runtime: WyrdRuntime, line_id: String, text: String) -> Dictionary:
	return {"authored": authored(runtime, line_id), "path": line_id, "text": text}


func _summary(runtime: WyrdRuntime, quest_id: String, shown: Array) -> void:
	var text := runtime.quests.summary(quest_id)
	shown.append({
		"authored": joined_journal(runtime, quest_id),
		"path": "summary:%s" % quest_id,
		"text": text,
	})


func _bark(runtime: WyrdRuntime, shown: Array) -> void:
	var won := runtime.director.query("bark", "", "ferry")
	var story_id := str(won.get("id", ""))
	if story_id.is_empty():
		return
	var story := runtime.content().storylets.get(story_id) as WyrdStoryletDef
	runtime.present_bark(story, {"line_id": str(won.get("line_id", ""))})
	var catcher: _Catch = runtime.get_meta("m10_catch")
	if catcher.bark_line == null:
		return
	var line := catcher.bark_line
	shown.append(_shown(runtime, line.id, line.text))
	catcher.bark_line = null


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


func _last_use(runtime: WyrdRuntime, path: String) -> Dictionary:
	var found := {}
	for item in runtime.trace.events:
		if not (item is Dictionary):
			continue
		var row: Dictionary = item
		if str(row.get("kind", "")) == "ai_use" and str(row.get("path", "")) == path:
			found = row
	return found


func _tone() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	stream.data = PackedByteArray([128, 160, 128, 96])
	return stream


func _make(provider: String) -> WyrdAIProvider:
	match provider:
		"echo":
			return Echo.new()
		"garbage":
			return Garbage.new()
		"silent":
			return Silent.new()
		"fuzz":
			return Fuzz.new()
		_:
			return null


func _routes() -> Dictionary:
	var room := [
		{"op": "open", "scene": "toll.offer_room"},
		{"op": "lines"},
		{"op": "choose", "text": "Take the room"},
		{"op": "lines"},
	]
	var out := {}
	out["take_room"] = {"steps": room}
	out["local_place"] = {"local": true, "steps": [
		{"op": "open", "scene": "toll.offer_room"},
		{"op": "lines"},
		{"op": "choose", "text": "I have a place in town"},
		{"op": "lines"},
	]}
	out["lodging_fails"] = {"steps": [
		{"op": "fail_action", "command": "assign_lodging", "reason": "full"},
		{"op": "open", "scene": "toll.offer_room"},
		{"op": "lines"},
		{"op": "choose", "text": "Take the room"},
		{"op": "lines"},
	]}
	out["pay_and_cross"] = {"steps": room + [
		{"op": "tick", "minutes": 60},
		{"op": "open", "scene": "toll.depart"},
		{"op": "lines"},
	]}
	out["notice_fails"] = {"steps": [
		{"op": "fail_action", "command": "post_notice", "reason": "lost"},
	] + room}
	out["ferry_empty"] = {"steps": [
		{"op": "open", "scene": "toll.offer_room"},
		{"op": "lines"},
		{"op": "kill_ferry"},
		{"op": "choose", "text": "Take the room"},
		{"op": "lines"},
	]}
	out["successor"] = {"steps": [
		{"op": "successor"},
	] + room + [
		{"op": "tick", "minutes": 0},
		{"op": "open", "scene": "toll.depart"},
		{"op": "lines"},
	]}
	out["season_storm"] = {"steps": [
		{"op": "season", "name": "storm"},
		{"op": "open", "scene": "toll.offer_room"},
		{"op": "lines"},
		{"op": "abort", "reason": "left"},
	]}
	out["abort_pending"] = {"steps": [
		{"op": "open", "scene": "toll.offer_room"},
		{"op": "abort", "reason": "left"},
		{"op": "open", "scene": "toll.offer_room"},
		{"op": "abort", "reason": "left"},
	]}
	out["text_silent"] = {"steps": [
		{"op": "open", "scene": "toll.offer_room"},
		{"op": "lines"},
	]}
	out["text_voiced"] = {"steps": [
		{"op": "audio"},
		{"op": "open", "scene": "toll.offer_room"},
		{"op": "lines"},
	]}
	out["unset_rumour"] = {"storm": false, "steps": [{"op": "tick", "minutes": 0}]}
	out["dock_errand"] = {"steps": [
		{"op": "open", "scene": "toll.offer_room"},
		{"op": "lines"},
		{"op": "choose", "text": "Ask the dock errand"},
		{"op": "lines"},
		{"op": "open", "scene": "toll.offer_room"},
		{"op": "lines"},
		{"op": "choose", "text": "Send the errand on"},
		{"op": "lines"},
	]}
	out["dock_crate_pass"] = {"steps": _crate(true, "Lift the crate")}
	out["dock_crate_fail"] = {"steps": _crate(false, "Lift the crate")}
	out["dock_crate_leave"] = {"steps": _crate(true, "Leave it")}
	out["dock_rumour"] = {"steps": room + [
		{"op": "open_topic", "npc": "tavern_owner"},
		{"op": "ask", "npc": "tavern_owner", "topic": "storm_rumour"},
		{"op": "open", "scene": "dock.rumour_talk"},
		{"op": "lines"},
		{"op": "summary", "quest": "dock_rumour"},
		{"op": "summary", "quest": "ferry_toll"},
	]}
	out["storm_rumour"] = {"steps": room + [
		{"op": "open_topic", "npc": "tavern_owner"},
		{"op": "ask", "npc": "tavern_owner", "topic": "storm_rumour"},
	]}
	out["ferry_gossip"] = {"steps": [
		{"op": "season", "name": "autumn"},
		{"op": "know", "key": "harbor.toll_fate", "value": &"paid"},
		{"op": "role", "role": "tavern", "entity": "tavern_owner"},
		{"op": "unlock", "topic": "rumor.ferry_toll"},
		{"op": "open_topic", "npc": "tavern_owner"},
		{"op": "ask", "npc": "tavern_owner", "topic": "rumor.ferry_toll"},
	]}
	out["lantern_barks"] = {"steps": [
		{"op": "nearby"},
		{"op": "tick", "minutes": 0},
		{"op": "bark"},
		{"op": "carry", "item": "lantern", "count": 1},
		{"op": "tick", "minutes": 0},
		{"op": "bark"},
	]}
	out["save_mid_room"] = {"steps": [
		{"op": "open", "scene": "toll.offer_room"},
		{"op": "lines"},
		{"op": "choose", "text": "Take the room"},
		{"op": "lines"},
		{"op": "save_load"},
		{"op": "summary", "quest": "ferry_toll"},
		{"op": "tick", "minutes": 60},
		{"op": "open", "scene": "toll.depart"},
		{"op": "lines"},
	]}
	out["exit_replay"] = {"steps": room + [
		{"op": "summary", "quest": "ferry_toll"},
		{"op": "host_request"},
		{"op": "summary", "quest": "ferry_toll"},
	]}
	out["mooring_pick"] = {"steps": [
		{"op": "mooring"},
		{"op": "tick", "minutes": 2},
	]}
	out["mooring_gone"] = {"steps": [
		{"op": "mooring"},
		{"op": "tick", "minutes": 2},
		{"op": "remove", "id": "dock.bollard_north"},
		{"op": "remove", "id": "dock.bollard_south"},
		{"op": "tick", "minutes": 1},
	]}
	out["net_delivery"] = {"generated": true, "steps": [
		{"op": "propose", "key": "nets", "template": "net_delivery"},
		{"op": "accept"},
		{"op": "owner", "item": "net.mended", "who": "net_mender"},
		{"op": "tick", "minutes": 0},
		{"op": "tick", "minutes": 0},
	]}
	out["stolen_catch"] = {"generated": true, "steps": [
		{"op": "remove", "id": "pier_fisher"},
		{"op": "propose", "key": "catch", "template": "stolen_catch"},
		{"op": "accept"},
		{"op": "owner", "item": "catch.day", "who": "line_fisher"},
		{"op": "tick", "minutes": 0},
		{"op": "tick", "minutes": 0},
	]}
	out["cut_look"] = {"generated": true, "steps": _cut("Thank them and look at the line")}
	out["cut_leave"] = {"generated": true, "steps": _cut("Leave it for now")}
	out["cut_gone"] = {"generated": true, "steps": _cut("Leave it for now") + [
		{"op": "remove", "id": "dock.bollard_north"},
		{"op": "tick", "minutes": 0},
	]}
	out["cut_empty"] = {"generated": true, "steps": [
		{"op": "remove", "id": "dock.bollard_north"},
		{"op": "propose", "key": "line", "template": "cut_line"},
	]}
	out["night_walk"] = {"generated": true, "steps": _night("Walk them there")}
	out["night_expire"] = {"generated": true, "steps": _night("Not tonight") + [
		{"op": "tick", "minutes": 360},
	]}
	return out


func _crate(passed: bool, label: String) -> Array:
	return [
		{"op": "start", "quest": "dock_crate"},
		{"op": "skill", "pass": passed},
		{"op": "open", "scene": "dock.crate_talk"},
		{"op": "lines"},
		{"op": "choose", "text": label},
		{"op": "lines"},
	]


func _cut(label: String) -> Array:
	return [
		{"op": "propose", "key": "line", "template": "cut_line"},
		{"op": "accept"},
		{"op": "open", "scene": "cut.ask"},
		{"op": "lines"},
		{"op": "choose", "text": label},
		{"op": "lines"},
		{"op": "tick", "minutes": 0},
	]


func _night(label: String) -> Array:
	return [
		{"op": "propose", "key": "walk", "template": "night_walk"},
		{"op": "accept"},
		{"op": "open", "scene": "night.walk"},
		{"op": "lines"},
		{"op": "choose", "text": label},
		{"op": "lines"},
		{"op": "tick", "minutes": 0},
	]


class _Catch extends RefCounted:
	var bark_line: WyrdLineView
	var topic_line: WyrdLineView

	func on_bark(line: WyrdLineView) -> void:
		bark_line = line

	func on_topic(_npc: StringName, _topic: StringName, line: WyrdLineView) -> void:
		topic_line = line


class _Texts extends RefCounted:
	static func invalid(packet: Dictionary, which: int) -> String:
		match which:
			0:
				return ""
			1:
				return "{x}"
			2:
				return "a".repeat(241)
			3:
				return outsider(packet)
			4:
				return "one\ntwo"
			_:
				return "a hidden_bell sits."
		return ""

	static func outsider(packet: Dictionary) -> String:
		var ids := {}
		for item in packet.get("entities", []):
			if item is Dictionary:
				ids[str((item as Dictionary).get("id", ""))] = true
		if not ids.has("ferry_master"):
			return "Bram heard it."
		if not ids.has("dock_apprentice"):
			return "Nia heard it."
		return "Bram\nheard it."

	static func paraphrase(text: String) -> String:
		var body := text
		if body.ends_with("."):
			body = body.substr(0, body.length() - 1)
		return "%s, they say." % body


## Each provider extends [WyrdAIProvider] directly. A subclass of a subclass
## fails [method WyrdRuntime.register_adapter].
class Echo extends WyrdAIProvider:
	var held: Array = []
	var answered: int = 0

	func id() -> StringName:
		return &"echo"

	func prompt_version() -> int:
		return 1

	func locales() -> PackedStringArray:
		return PackedStringArray(["en"])

	func request(req: WyrdAIRequest) -> void:
		held.append({"error": "", "id": req.id, "ok": true, "text": str(req.packet.get("text", ""))})

	func cancel(_request_id: int) -> void:
		pass

	func take_answers() -> Array:
		var out: Array = held.duplicate()
		held.clear()
		answered += out.size()
		return out


class Silent extends WyrdAIProvider:
	var held: Array = []

	func id() -> StringName:
		return &"silent"

	func prompt_version() -> int:
		return 1

	func locales() -> PackedStringArray:
		return PackedStringArray(["en"])

	func request(req: WyrdAIRequest) -> void:
		held.append(req)

	func cancel(_request_id: int) -> void:
		pass

	func take_answers() -> Array:
		return []


class Garbage extends WyrdAIProvider:
	var held: Array = []
	var answered: int = 0
	var _n: int = 0

	func id() -> StringName:
		return &"garbage"

	func prompt_version() -> int:
		return 1

	func locales() -> PackedStringArray:
		return PackedStringArray(["en"])

	func request(req: WyrdAIRequest) -> void:
		var which := _n % 6
		_n += 1
		held.append({"error": "", "id": req.id, "ok": true, "text": _Texts.invalid(req.packet, which)})

	func cancel(_request_id: int) -> void:
		pass

	func take_answers() -> Array:
		var out: Array = held.duplicate()
		held.clear()
		answered += out.size()
		return out


class Fuzz extends WyrdAIProvider:
	var held: Array = []
	var answered: int = 0
	var _state: int = 10

	func id() -> StringName:
		return &"fuzz"

	func prompt_version() -> int:
		return 1

	func locales() -> PackedStringArray:
		return PackedStringArray(["en"])

	func request(req: WyrdAIRequest) -> void:
		var roll := _next() % 9
		if roll == 8:
			held.append({"error": "fuzz", "id": req.id, "ok": false, "text": ""})
		elif roll == 6:
			held.append({"error": "", "id": req.id, "ok": true, "text": str(req.packet.get("text", ""))})
		elif roll == 7:
			held.append({"error": "", "id": req.id, "ok": true, "text": _Texts.paraphrase(str(req.packet.get("text", "")))})
		else:
			held.append({"error": "", "id": req.id, "ok": true, "text": _Texts.invalid(req.packet, roll)})

	func cancel(_request_id: int) -> void:
		pass

	func take_answers() -> Array:
		var out: Array = held.duplicate()
		held.clear()
		answered += out.size()
		return out

	func _next() -> int:
		var x := _state
		x = (x ^ (x << 13)) & 0xFFFFFFFF
		x = (x ^ (x >> 17)) & 0xFFFFFFFF
		x = (x ^ (x << 5)) & 0xFFFFFFFF
		_state = x
		return x
