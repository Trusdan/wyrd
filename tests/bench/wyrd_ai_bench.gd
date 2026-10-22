extends RefCounted

## Times four AI hook paths on a small inline pack. Fake providers only.
## Booting sits outside every timed region. Timings are never part of a checksum.

const NAMES: Array[String] = ["ai.packet", "ai.validate", "ai.present_overhead", "ai.cache_lookup"]
const PACKET_BATCH := 256
const VALIDATE_BATCH := 256
const PRESENT_BATCH := 1024
const CACHE_ENTRIES := 256
const CACHE_PASSES := 4
const SEED := 0x57595244
const LINE_GATE := "bench_gate"
const LINE_GOSSIP := "bench_gossip"
const AUTHORED := "The gate is shut."
const FAKE_TEXT := "Bram waits."

## Open requests on the runtime just before it was dropped. Zero when the row is clean.
var pending_after := 0

const _BODY := """// [EXAMPLE CONTENT]
language 1

facts
  harbor.gate : symbol stored
  harbor.tide : symbol stored
  harbor.bell : symbol stored
  harbor.lane : symbol stored
  world.secret_name : symbol stored

scene bench.yard
  ai_context: [harbor.gate, harbor.tide, harbor.bell, harbor.lane]
  narrator: The gate is shut. #tag:ai #line:bench_gate
  narrator: Someone heard it. #tag:ai #tag:gossip #line:bench_gossip
  narrator: The lane is quiet. #line:bench_plain
  -> end
"""


func sample(name: String, batch: int = -1) -> Dictionary:
	pending_after = 0
	if not _listed(name):
		return {"error": "unknown metric %s" % name}
	var saved_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	var row := _run(name, batch)
	TranslationServer.set_locale(saved_locale)
	return row


func measure(batch: int = -1) -> Dictionary:
	var metrics := {}
	var ok := true
	for name in NAMES:
		var row: Dictionary = sample(name, batch)
		metrics[name] = row
		if row.has("error"):
			ok = false
	return {"metrics": metrics, "ok": ok}


func _run(name: String, batch: int) -> Dictionary:
	var boot := _boot()
	if boot.has("error"):
		return boot
	var runtime: WyrdRuntime = boot["runtime"]
	var row: Dictionary = {}
	match name:
		"ai.packet":
			row = _time_packet(runtime, _count(batch, PACKET_BATCH))
		"ai.validate":
			row = _time_validate(runtime, _count(batch, VALIDATE_BATCH))
		"ai.present_overhead":
			row = _time_present(runtime, _count(batch, PRESENT_BATCH))
		"ai.cache_lookup":
			row = _time_cache(runtime, _count(batch, CACHE_ENTRIES))
		_:
			row = {"error": "unknown metric %s" % name}
	pending_after = runtime.ai.pending_count()
	if pending_after != 0 and not row.has("error"):
		row = {"error": "open requests %d" % pending_after}
	boot["runtime"] = null
	return row


func _time_packet(runtime: WyrdRuntime, count: int) -> Dictionary:
	var gossip: Dictionary = runtime.ai.packet_for_line(LINE_GOSSIP, &"gossip", &"bram")
	var deeds: Array = gossip.get("deeds", [])
	if deeds.size() != 5:
		return {"error": "gossip deeds %d" % deeds.size()}
	var probe: Dictionary = runtime.ai.packet_for_line(LINE_GATE, &"bark_paraphrase", &"bram")
	var facts: Dictionary = probe.get("facts", {})
	if facts.size() != 4:
		return {"error": "packet facts %d" % facts.size()}
	var started := Time.get_ticks_usec()
	var last: Dictionary = {}
	for _index in count:
		last = runtime.ai.packet_for_line(LINE_GATE, &"bark_paraphrase", &"bram")
	var value := _seconds(started, count)
	var bark_canon := WyrdAIPacket.canonical(last)
	var gossip_canon := WyrdAIPacket.canonical(gossip)
	if bark_canon.is_empty() or gossip_canon.is_empty():
		return {"error": "packet canonical is empty"}
	var checksum := WyrdRng.format_u64(WyrdHash.of_text(bark_canon + "\n" + gossip_canon))
	return _row(value, checksum, {"gossip": gossip})


func _time_validate(runtime: WyrdRuntime, count: int) -> Dictionary:
	var judge := _Always.new()
	runtime.ai.register_classifier(Callable(judge, &"judge"))
	var packet: Dictionary = runtime.ai.packet_for_line(LINE_GATE, &"bark_paraphrase", &"bram")
	var text := FAKE_TEXT
	var rule := runtime.ai.validate(text, &"bark_paraphrase", packet)
	if not String(rule).is_empty():
		return {"error": "validate rejected %s" % String(rule)}
	var entities := _entity_count(runtime)
	var banned := _banned_count(runtime)
	var spoilers := _spoiler_count(runtime, packet)
	if entities < 1 or banned < 1 or spoilers < 1:
		return {"error": "validate saw entities %d banned %d spoilers %d" % [entities, banned, spoilers]}
	var started := Time.get_ticks_usec()
	for _index in count:
		rule = runtime.ai.validate(text, &"bark_paraphrase", packet)
	if not String(rule).is_empty():
		return {"error": "validate rejected %s" % String(rule)}
	var value := _seconds(started, count)
	return _row(value, "pass:%d" % text.length(), {
		"banned": banned,
		"entities": entities,
		"spoilers": spoilers,
	})


func _time_present(runtime: WyrdRuntime, count: int) -> Dictionary:
	var view := WyrdLineView.new()
	view.id = LINE_GATE
	view.speaker = &"bram"
	view.text = AUTHORED
	view.text_source = &"authored"
	var authored := _seconds(_loop_authored(view, count), count)
	if view.text != AUTHORED or view.text_source != &"authored":
		return {"error": "authored loop changed the line"}
	var null_check := _present_once(runtime, view)
	if null_check != "":
		return {"error": null_check}
	var null_ticks := _loop_present(runtime, view, count)
	var null_value := _seconds(null_ticks, count)
	if view.text != AUTHORED or view.text_source != &"authored":
		return {"error": "null present changed the line"}
	var provider := WyrdFakeAIText.new()
	provider.text = FAKE_TEXT
	runtime.register_adapter(WyrdAIProvider, provider)
	var packet: Dictionary = runtime.ai.packet_for_line(LINE_GATE, &"bark_paraphrase", &"bram")
	var sent := runtime.ai.request(&"bark_paraphrase", packet, {}, StringName(LINE_GATE))
	if sent == 0:
		return {"error": "request refused"}
	if runtime.ai.cached_text(runtime.ai.cache_key(&"bark_paraphrase", packet)) != FAKE_TEXT:
		return {"error": "fake text was not cached"}
	var shown := _present_once(runtime, view)
	if shown != "":
		return {"error": shown}
	if view.text != FAKE_TEXT or view.text_source != &"ai":
		return {"error": "present missed the cache"}
	var fake_hit := _seconds(_loop_present(runtime, view, count), count)
	if view.text != FAKE_TEXT or view.text_source != &"ai":
		return {"error": "fake present missed the cache"}
	runtime.register_adapter(WyrdAIProvider, WyrdNullAIProvider.new())
	var checksum := "authored|authored|ai:%s" % WyrdRng.format_u64(WyrdHash.of_text(FAKE_TEXT))
	return _row(null_value, checksum, {
		"authored": authored,
		"fake_hit": fake_hit,
		"null_delta": null_value - authored,
	})


func _time_cache(runtime: WyrdRuntime, entries: int) -> Dictionary:
	runtime.register_adapter(WyrdAIProvider, WyrdFakeAIText.new())
	runtime.ai.clear_cache()
	var packets: Array = []
	var texts := PackedStringArray()
	var rows: Array = []
	for index in entries:
		var packet: Dictionary = runtime.ai.packet_for_line(LINE_GATE, &"bark_paraphrase", &"bram")
		var text := "Line %03d." % index
		packet["text"] = text
		var key := runtime.ai.cache_key(&"bark_paraphrase", packet)
		packets.append(packet)
		texts.append(text)
		rows.append({"k": key, "t": text})
	runtime.ai.import_cache({"cache": rows, "v": 1}, true, WyrdLoadReport.new())
	if runtime.ai.cache_size() != entries:
		return {"error": "cache size %d" % runtime.ai.cache_size()}
	var started := Time.get_ticks_usec()
	var hits := 0
	var lookup: Dictionary = {}
	var got := ""
	for _pass in CACHE_PASSES:
		for index in entries:
			lookup = packets[index]
			got = runtime.ai.cached_text(runtime.ai.cache_key(&"bark_paraphrase", lookup))
			if got != texts[index]:
				return {"error": "cache missed entry %d" % index}
			hits += 1
	var value := _seconds(started, entries * CACHE_PASSES)
	if hits != entries * CACHE_PASSES:
		return {"error": "cache hits %d" % hits}
	var miss_started := Time.get_ticks_usec()
	for index in entries:
		lookup = (packets[0] as Dictionary).duplicate(true)
		lookup["text"] = "Miss %03d." % index
		got = runtime.ai.cached_text(runtime.ai.cache_key(&"bark_paraphrase", lookup))
		if got != "":
			return {"error": "cache miss returned text"}
	var miss := _seconds(miss_started, entries)
	var mixed := 0
	for index in texts.size():
		var piece := WyrdHash.of_text(texts[index])
		mixed = piece if index == 0 else WyrdHash.combine(mixed, piece)
	var checksum := "%d:%d:%s" % [entries, hits, WyrdRng.format_u64(mixed)]
	return _row(value, checksum, {"entries": entries, "miss": miss})


func _loop_authored(view: WyrdLineView, count: int) -> int:
	var started := Time.get_ticks_usec()
	for _index in count:
		view.text = AUTHORED
		view.text_source = &"authored"
	return started


func _loop_present(runtime: WyrdRuntime, view: WyrdLineView, count: int) -> int:
	var started := Time.get_ticks_usec()
	for _index in count:
		view.text = AUTHORED
		view.text_source = &"authored"
		runtime.ai.present(view, LINE_GATE)
	return started


## Empty when the null provider keeps the authored line, or when a hit shows the fake text.
func _present_once(runtime: WyrdRuntime, view: WyrdLineView) -> String:
	view.text = AUTHORED
	view.text_source = &"authored"
	runtime.ai.present(view, LINE_GATE)
	if runtime.ai.is_active():
		if view.text == FAKE_TEXT and view.text_source == &"ai":
			return ""
		return "present missed the cache"
	if view.text == AUTHORED and view.text_source == &"authored":
		return ""
	return "null present changed the line"


func _boot() -> Dictionary:
	var path := "user://wyrd_ai_bench.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"error": "bench pack was not written"}
	file.store_string(_BODY)
	file.close()
	var runtime := WyrdRuntime.new()
	var config := WyrdConfig.new()
	var terms := PackedStringArray()
	for index in 8:
		terms.append("zzban%d" % index)
	config.ai_banned_terms = terms
	runtime.configure(config)
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	host.world.add_entity(&"player", &"person", "traveler", PackedStringArray(), true)
	for person_id in _people():
		var shown := "Bram" if person_id == "bram" else person_id
		host.world.add_entity(StringName(person_id), &"person", shown, PackedStringArray(), true)
	host.world.add_entity(&"dock", &"place", "dock", PackedStringArray(), true)
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"ai_bench"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var report := runtime.load_content(manifest)
	if not report.ok:
		return {"error": report.diagnostics.format()}
	runtime.start_new_game(SEED)
	runtime.trace.enabled = false
	if not _know(runtime, &"harbor.gate", "shut"):
		return {"error": "fact harbor.gate was not stored"}
	if not _know(runtime, &"harbor.tide", "low"):
		return {"error": "fact harbor.tide was not stored"}
	if not _know(runtime, &"harbor.bell", "still"):
		return {"error": "fact harbor.bell was not stored"}
	if not _know(runtime, &"harbor.lane", "quiet"):
		return {"error": "fact harbor.lane was not stored"}
	if not runtime.facts.set_in(&"world.secret_name", "hidden_bell", &"world"):
		return {"error": "fact world.secret_name was not stored"}
	_record_eight(runtime, host)
	if runtime.content() == null or not runtime.content().ai_lines.has(LINE_GATE):
		return {"error": "opt-in missing"}
	if not runtime.content().ai_lines.has(LINE_GOSSIP):
		return {"error": "gossip opt-in missing"}
	return {"runtime": runtime}


func _record_eight(runtime: WyrdRuntime, host: WyrdFakeHost) -> void:
	_deed(runtime, host, 1, &"saw", &"met", &"zed", &"", PackedStringArray([&"player"]))
	_deed(runtime, host, 10, &"heard", &"spoke", &"bram", &"nia", PackedStringArray([&"player"]))
	_deed(runtime, host, 10, &"inferred", &"spoke", &"bram", &"nia", PackedStringArray([&"player"]))
	_deed(runtime, host, 15, &"saw", &"met", &"zed", &"", PackedStringArray([&"stranger"]))
	var believed := _deed(runtime, host, 20, &"saw", &"spoke", &"bram", &"nia", PackedStringArray([&"stranger"]))
	runtime.deeds.note_believer(believed, &"player", 20)
	_deed(runtime, host, 30, &"saw", &"shut", &"bram", &"nia", PackedStringArray([&"player"]))
	_deed(runtime, host, 40, &"heard", &"rang", &"bram", &"nia", PackedStringArray([&"player"]))
	_deed(runtime, host, 50, &"saw", &"left", &"zed", &"", PackedStringArray([&"stranger"]))


func _deed(runtime: WyrdRuntime, host: WyrdFakeHost, minute: int, mode: StringName, verb: StringName, actor: StringName, target: StringName, witnesses: PackedStringArray) -> int:
	host.clock.set_minutes(minute)
	host.spatial.set_perception(&"player", mode)
	return runtime.deeds.record(verb, actor, target, &"dock", PackedStringArray(), 1.0, witnesses)


func _people() -> PackedStringArray:
	var people := PackedStringArray(["bram", "nia", "zed", "stranger"])
	for index in 28:
		people.append("p%02d" % (index + 4))
	return people


func _know(runtime: WyrdRuntime, key: StringName, value: String) -> bool:
	if not runtime.facts.set_in(key, value, &"world"):
		return false
	return runtime.facts.set_in(key, value, &"known/player")


func _entity_count(runtime: WyrdRuntime) -> int:
	var world := runtime.adapter(WyrdWorldAdapter) as WyrdWorldAdapter
	if world == null:
		return 0
	var names := {}
	for id in world.candidates(WyrdEntityFilter.new()):
		var shown := world.display_name(StringName(str(id)))
		if shown.is_empty():
			continue
		names[shown] = true
	return names.size()


func _banned_count(runtime: WyrdRuntime) -> int:
	var count := 0
	if runtime.config() == null:
		return 0
	for term in runtime.config().ai_banned_terms:
		if not String(term).is_empty():
			count += 1
	return count


func _spoiler_count(runtime: WyrdRuntime, packet: Dictionary) -> int:
	var found := {}
	var listed := {}
	var raw: Variant = packet.get("facts", {})
	if raw is Dictionary:
		listed = raw
	var secrecy := ""
	if runtime.config() != null:
		secrecy = runtime.config().secrecy_fact
	var world := runtime.adapter(WyrdWorldAdapter) as WyrdWorldAdapter
	for key in runtime.facts.world_keys():
		if listed.has(key) or key == secrecy:
			continue
		var world_value: Variant = runtime.facts.get_in(StringName(key), &"world")
		var known_value: Variant = runtime.facts.get_in(StringName(key), &"known/player")
		if known_value != null and _same(known_value, world_value):
			continue
		if not (world_value is String or world_value is StringName):
			continue
		var text := String(world_value)
		_add_form(found, text)
		_add_form(found, text.replace("_", " "))
		if world != null and world.exists(StringName(text)):
			_add_form(found, world.display_name(StringName(text)))
	if runtime.content() != null and runtime.roles != null:
		for id in runtime.content().roles.keys():
			var role := runtime.content().roles[id] as WyrdRoleDef
			if role == null or role.visibility != "secret":
				continue
			var role_key := "role.%s.holder" % role.id
			if runtime.roles.revealed(&"player", StringName(role_key)):
				continue
			_add_form(found, role.id)
			_add_form(found, role.id.replace("_", " "))
	return found.size()


func _add_form(found: Dictionary, form: String) -> void:
	var text := form.strip_edges()
	if text.length() < 3 or found.has(text):
		return
	found[text] = true


func _same(left: Variant, right: Variant) -> bool:
	if left == right:
		return true
	if (left is String or left is StringName) and (right is String or right is StringName):
		return String(left) == String(right)
	return false


func _listed(name: String) -> bool:
	for item in NAMES:
		if item == name:
			return true
	return false


func _count(batch: int, fallback: int) -> int:
	if batch >= 1:
		return batch
	return fallback


func _seconds(started: int, calls: int) -> float:
	var elapsed := Time.get_ticks_usec() - started
	return float(elapsed) / 1000000.0 / float(calls)


func _row(value: float, checksum: String, extra: Dictionary) -> Dictionary:
	if not is_finite(value) or value < 0.0:
		return {"error": "timing is not a finite time"}
	if checksum.is_empty():
		return {"error": "checksum is empty"}
	return {"checksum": checksum, "extra": extra, "value": value}


class _Always extends RefCounted:
	func judge(_text: String, _kind: StringName, _packet: Dictionary) -> bool:
		return true
