extends GutTest

## Gossip packets, keys, and presentation. Inline pack only.


func test_kind_for_line_and_a_plain_packet_has_no_deeds() -> void:
	var runtime := _boot()
	assert_eq(String(runtime.ai.kind_for_line("gossip")), "gossip")
	assert_eq(String(runtime.ai.kind_for_line("plain")), "bark_paraphrase")
	assert_eq(String(runtime.ai.kind_for_line("tag_only")), "bark_paraphrase")
	var packet := runtime.ai.packet_for_line("plain", runtime.ai.kind_for_line("plain"))
	assert_eq(str(packet["kind"]), "bark_paraphrase")
	assert_false(packet.has("deeds"))
	var keys: Array = packet.keys()
	keys.sort()
	assert_eq(keys, ["entities", "facts", "kind", "line_ids", "text", "v"])
	assert_eq(runtime.ai.cache_key(&"bark_paraphrase", packet), runtime.ai.cache_key(runtime.ai.kind_for_line("plain"), packet))


func test_the_packet_keeps_five_newest_known_deeds() -> void:
	var opened := _boot_host()
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	_record_eight(runtime, host)
	var packet := runtime.ai.packet_for_line("gossip", &"gossip")
	var deeds: Array = packet["deeds"]
	assert_eq(deeds.size(), 5)
	assert_eq(_deed_ids(deeds), [7, 6, 5, 3, 2])
	assert_eq(str(deeds[0]["how"]), "heard")
	assert_eq(int(deeds[0]["minute"]), 40)
	assert_eq(str(deeds[1]["how"]), "saw")
	assert_eq(int(deeds[1]["minute"]), 30)
	assert_eq(str(deeds[2]["how"]), "believed")
	assert_eq(int(deeds[2]["minute"]), 20)
	assert_eq(str(deeds[3]["how"]), "inferred")
	assert_eq(int(deeds[3]["minute"]), 10)
	assert_eq(str(deeds[4]["how"]), "heard")
	assert_eq(int(deeds[4]["minute"]), 10)
	assert_eq(str(deeds[4]["actor"]), "bram")
	assert_eq(str(deeds[4]["target"]), "nia")
	assert_eq(str(deeds[4]["place"]), "dock")
	assert_eq(str(deeds[4]["verb"]), "spoke")
	for row in deeds:
		assert_ne(int(row["id"]), 1)
		assert_ne(int(row["id"]), 4)
		assert_ne(int(row["id"]), 8)
	var ids: Array = []
	for row in packet["entities"]:
		ids.append(str(row["id"]))
	assert_eq(ids, ["bram", "dock", "nia"])
	assert_eq(runtime.ai.validate("Bram shut it.", &"gossip", packet), &"")
	assert_eq(runtime.ai.validate("Zed shut it.", &"gossip", packet), &"names")
	var before := runtime.ai.cache_key(&"gossip", packet)
	host.clock.set_minutes(60)
	host.spatial.set_perception(&"player", &"saw")
	runtime.deeds.record(&"shut", &"bram", &"nia", &"dock", PackedStringArray(), 1.0, PackedStringArray([&"player"]))
	var newer := runtime.ai.cache_key(&"gossip", runtime.ai.packet_for_line("gossip", &"gossip"))
	assert_ne(newer, before)
	host.clock.set_minutes(70)
	runtime.deeds.record(&"left", &"zed", &"", &"dock", PackedStringArray(), 1.0, PackedStringArray([&"stranger"]))
	var still := runtime.ai.cache_key(&"gossip", runtime.ai.packet_for_line("gossip", &"gossip"))
	assert_eq(still, newer)


func test_prefetch_and_present_use_gossip() -> void:
	var runtime := _boot()
	var provider := _Hold.new()
	provider.answer_now = true
	runtime.register_adapter(WyrdAIProvider, provider)
	runtime.trace.clear()
	runtime.dialogue.open_scene("gate")
	assert_eq(provider.waiting.size(), 2)
	assert_eq(String(provider.waiting[0].kind), "gossip")
	assert_eq(String(provider.waiting[1].kind), "bark_paraphrase")
	assert_eq(str(_rows(runtime, "ai_request")[0]["slot_kind"]), "gossip")
	assert_eq(str(_rows(runtime, "ai_request")[1]["slot_kind"]), "bark_paraphrase")
	var view := runtime.dialogue.line()
	assert_eq(view.text, "The gate is shut..")
	assert_eq(str(view.text_source), "ai")
	assert_eq(str(_use(runtime, "gossip")["slot_kind"]), "gossip")
	assert_eq(str(_use(runtime, "gossip")["reason"]), "hit")
	assert_eq(str(_use(runtime, "gossip")["source"]), "ai")
	runtime.dialogue.advance()
	var plain := runtime.dialogue.line()
	assert_eq(plain.text, "The lane is quiet..")
	assert_eq(str(plain.text_source), "ai")
	assert_eq(str(_use(runtime, "plain")["slot_kind"]), "bark_paraphrase")
	runtime.dialogue.advance()
	var tagged := runtime.dialogue.line()
	assert_eq(tagged.id, "tag_only")
	assert_eq(tagged.text, "Nobody repeats this.")
	assert_eq(_uses(runtime, "tag_only").size(), 0)


func test_a_gossip_bark_sweeps_as_gossip() -> void:
	var runtime := _boot()
	runtime.config().ai_max_inflight = 8
	var provider := _Hold.new()
	runtime.register_adapter(WyrdAIProvider, provider)
	runtime.trace.clear()
	runtime.tick(0)
	assert_eq(provider.waiting.size(), 1)
	assert_eq(String(provider.waiting[0].kind), "gossip")
	assert_eq(provider.waiting[0].owner, "bark:rumor.bell")
	assert_eq(str(_rows(runtime, "ai_request")[0]["slot_kind"]), "gossip")
	assert_true(provider.waiting[0].packet.has("deeds"))
	assert_eq((provider.waiting[0].packet["deeds"] as Array).size(), 0)


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


func _deed_ids(deeds: Array) -> Array:
	var ids: Array = []
	for row in deeds:
		ids.append(int(row["id"]))
	return ids


func _boot() -> WyrdRuntime:
	return _boot_host()["runtime"]


func _boot_host() -> Dictionary:
	var path := "user://wyrd_m10_gossip.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(_BODY)
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = "m10gossip"
	manifest.files = PackedStringArray([path])
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	host.world.add_entity(&"player", &"person", "Traveler", PackedStringArray(), true)
	host.world.add_entity(&"bram", &"person", "Bram", PackedStringArray(), true)
	host.world.add_entity(&"nia", &"person", "Nia", PackedStringArray(), true)
	host.world.add_entity(&"dock", &"place", "Dock", PackedStringArray(), true)
	host.world.add_entity(&"zed", &"person", "Zed", PackedStringArray(), true)
	host.world.add_entity(&"stranger", &"person", "Stranger", PackedStringArray(), true)
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(1)
	runtime.trace.enabled = true
	return {"host": host, "runtime": runtime}


func _use(runtime: WyrdRuntime, line_id: String) -> Dictionary:
	var rows := _uses(runtime, line_id)
	if rows.is_empty():
		return {}
	return rows[rows.size() - 1]


func _uses(runtime: WyrdRuntime, line_id: String) -> Array:
	var rows: Array = []
	for event in _rows(runtime, "ai_use"):
		if str(event.get("path", "")) == line_id:
			rows.append(event)
	return rows


func _rows(runtime: WyrdRuntime, kind: String) -> Array:
	var rows: Array = []
	for event in runtime.trace.events:
		if str(event.get("kind", "")) == kind:
			rows.append(event)
	return rows


class _Hold extends WyrdAIProvider:
	var answer_now: bool = false
	var waiting: Array[WyrdAIRequest] = []

	func id() -> StringName:
		return &"gossip-text"

	func prompt_version() -> int:
		return 1

	func locales() -> PackedStringArray:
		return PackedStringArray(["en"])

	func request(req: WyrdAIRequest) -> void:
		waiting.append(req)
		if not answer_now:
			return
		var result := WyrdAIResult.new()
		result.ok = true
		result.text = str(req.packet.get("text", "")) + "."
		req.reply(result)

	func cancel(_request_id: int) -> void:
		pass


const _BODY := """// [EXAMPLE CONTENT]
language 1

scene gate
  narrator: The gate is shut. #tag:ai #tag:gossip #line:gossip
  narrator: The lane is quiet. #tag:ai #line:plain
  narrator: Nobody repeats this. #tag:gossip #line:tag_only
  -> end

storylet rumor.bell
  scope: bark
  speaker: bram
  - The gate is shut. #tag:ai #tag:gossip #line:gossip_bark
"""
