extends GutTest

## Property runs use this seed. 200 passes, one per [method WyrdRng] draw.
const SEED := 20261021
const RUNS := 200
const _SYMBOLS: PackedStringArray = ["paid", "open", "sealed", "cut_line", "ferry_master", "tavern_owner", "low", "mid"]

const _KEYS: PackedStringArray = [
	"player.coins", "player.clearance", "ferry.toll_coins", "harbor.room_taken",
	"harbor.deck_wet", "harbor.watch_alive", "harbor.bell_struck", "harbor.bell_count",
	"harbor.rope_spliced", "harbor.rope_done", "harbor.tongue_seated", "harbor.tongue_done",
	"tavern.stew_bowls", "world.storm_heard", "harbor.factor_refuses", "harbor.guild_signed",
	"harbor.levy_posted", "harbor.toll_fate", "harbor.gazette", "harbor.nets_wanted",
	"harbor.catch_missing", "harbor.boat_adrift", "harbor.line_found", "harbor.visitor_waiting",
	"harbor.stew_wanted", "harbor.stew_tier", "harbor.stew_favors", "harbor.net_fate",
	"harbor.catch_fate", "harbor.line_fate", "harbor.stew_fate", "harbor.mooring_check",
]
const _TYPES: PackedStringArray = [
	"int", "symbol", "int", "bool",
	"bool", "bool", "bool", "int",
	"bool", "bool", "bool", "bool",
	"int", "bool", "bool", "bool",
	"bool", "symbol", "symbol", "bool",
	"bool", "bool", "bool", "bool",
	"bool", "symbol", "int", "symbol",
	"symbol", "symbol", "symbol", "bool",
]


func test_opted_in_line_carries_known_facts_and_entities() -> void:
	var opened := _boot(_SCENE)
	var runtime: WyrdRuntime = opened["runtime"]
	assert_true(runtime.content().ai_lines.has("keeper"))
	assert_false(runtime.content().ai_lines.has("plain"))
	var entry: Dictionary = runtime.content().ai_lines["keeper"]
	assert_eq(str(entry["owner"]), "scene")
	assert_eq(str(entry["id"]), "toll.gate")
	assert_eq(entry["keys"], PackedStringArray(["player.coins", "world.season", "harbor.toll_fate", "harbor.missing"]))
	var news: Dictionary = runtime.content().ai_lines["news"]
	assert_eq(str(news["owner"]), "storylet")
	assert_eq(str(news["id"]), "harbor.news")
	runtime.facts.set_in(&"player.coins", 4, &"world")
	runtime.facts.set_in(&"player.coins", 1, &"known/player")
	runtime.facts.set_in(&"harbor.toll_fate", "paid", &"world")
	runtime.facts.set_in(&"harbor.toll_fate", "tavern_owner", &"known/player")
	_remove_fact(runtime, "harbor.missing")
	runtime.roles.assign(&"tide_clerk", &"ferry_master")
	runtime.trace.clear()
	runtime.ai.set_enabled(false)
	var packet := runtime.ai.packet_for_line("keeper")
	assert_eq(runtime.ai.pending_count(), 0)
	assert_eq(int(packet["v"]), 1)
	assert_eq(str(packet["kind"]), "bark_paraphrase")
	assert_eq(packet["line_ids"], ["keeper"])
	assert_eq(str(packet["text"]), "The book is in the shed.")
	var speaker: Dictionary = packet["speaker"]
	assert_eq(str(speaker["id"]), "ferry_master")
	assert_eq(str(speaker["name"]), "Bram")
	assert_eq(speaker["roles"], ["harbor_clerk"])
	assert_eq(packet["facts"], {"player.coins": 1, "harbor.toll_fate": "tavern_owner"})
	assert_eq(packet["entities"], [
		{"id": "ferry_master", "name": "Bram"},
		{"id": "tavern_owner", "name": "Innkeeper"},
	])
	var drops := _rows(runtime, "ai_packet_drop")
	assert_eq(drops.size(), 3)
	assert_eq(str(drops[0]["fact"]), "world.season")
	assert_eq(str(drops[0]["reason"]), "not_known")
	assert_eq(str(drops[1]["fact"]), "harbor.missing")
	assert_eq(str(drops[1]["reason"]), "unknown")
	assert_eq(str(drops[2]["fact"]), "role.tide_clerk.holder")
	assert_eq(str(drops[2]["reason"]), "secret")
	assert_eq(str(drops[0]["path"]), "keeper")
	assert_eq(_rows(runtime, "resolver").size(), 0)
	var told := runtime.ai.packet_for_line("keeper", &"gossip", &"tavern_owner")
	assert_eq(str(told["speaker"]["id"]), "tavern_owner")
	assert_eq(str(told["speaker"]["name"]), "Innkeeper")
	var quiet := runtime.ai.packet_for_line("gate")
	assert_false(quiet.has("speaker"))
	assert_eq(str(quiet["text"]), "The lane is quiet.")
	var any_line := runtime.ai.packet_for_line("quiet")
	assert_false(any_line.has("speaker"))
	var topic := runtime.ai.packet_for_line("news", &"gossip")
	assert_eq(str(topic["speaker"]["id"]), "ferry_master")
	assert_eq(str(topic["kind"]), "gossip")
	assert_eq(WyrdAIPacket.canonical(packet), WyrdAIPacket.canonical(runtime.ai.packet_for_line("keeper")))


func test_missing_line_warns_and_returns_empty() -> void:
	var runtime: WyrdRuntime = _boot(_SCENE)["runtime"]
	assert_eq(runtime.ai.packet_for_line("plain"), {})
	assert_push_warning("not an opted-in line")
	assert_eq(runtime.ai.packet_for_line("no-such-line"), {})
	assert_push_warning("not an opted-in line")


func test_canonical_ignores_insertion_order() -> void:
	var left := {"b": 1, "a": {"z": true, "y": "no"}}
	var right := {"a": {"y": "no", "z": true}, "b": 1}
	assert_eq(WyrdAIPacket.canonical(left), WyrdAIPacket.canonical(right))
	assert_ne(left.keys()[0], right.keys()[0])


func test_fallback_text() -> void:
	assert_eq(WyrdAIPacket.fallback_text(&"bark_paraphrase", {"text": "The gate is shut."}), "The gate is shut.")
	assert_eq(WyrdAIPacket.fallback_text(&"journal_summary", {"entries": ["one", "two"], "text": "nope"}), "one\ntwo")
	assert_eq(WyrdAIPacket.fallback_text(&"journal_summary", {"text": "day"}), "day")
	assert_eq(WyrdAIPacket.fallback_text(&"gossip", {}), "")


func test_known_facts_only_over_seeded_runs() -> void:
	var opened := _boot(_property_source())
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	runtime.roles.assign(&"tide_clerk", &"ferry_master")
	runtime.trace.enabled = false
	var rng := WyrdRng.new(SEED)
	var allowed := {}
	for key in _KEYS:
		allowed[key] = true
	allowed["role.harbor_clerk.holder"] = true
	for i in RUNS:
		runtime.facts.clear_values()
		for index in _KEYS.size():
			var key := String(_KEYS[index])
			var world_value: Variant = _roll(rng, String(_TYPES[index]))
			assert_true(runtime.facts.set_in(StringName(key), world_value, &"world"), key)
			if rng.randi_bounded(2) == 0:
				continue
			var known_value: Variant = _other(String(_TYPES[index]), world_value)
			assert_true(runtime.facts.set_in(StringName(key), known_value, &"known/player"), key)
		var mode := i % 3
		if mode == 0:
			runtime.config().secrecy_tiers = PackedStringArray()
		else:
			runtime.config().secrecy_tiers = PackedStringArray(["open", "sealed"])
			var clearance := "open" if mode == 1 else "sealed"
			assert_true(runtime.facts.set_in(&"player.clearance", clearance, &"world"))
		assert_true(runtime.facts.set_in(&"role.harbor_clerk.holder", "paid", &"world"))
		if rng.randi_bounded(2) == 1:
			assert_true(runtime.facts.set_in(&"role.harbor_clerk.holder", "mid", &"known/player"))
		var packet := runtime.ai.packet_for_line("ledger")
		assert_eq(WyrdAIPacket.canonical(packet), WyrdAIPacket.canonical(runtime.ai.packet_for_line("ledger")))
		var speaker: Dictionary = packet["speaker"]
		assert_eq(str(speaker["id"]), "ferry_master")
		assert_eq(speaker["roles"], ["harbor_clerk"])
		for key in packet["facts"].keys():
			assert_true(allowed.has(String(key)), String(key))
			assert_true(_knows(runtime, String(key)), "%s run %d" % [key, i])
			var expected: Variant = _expected(runtime, String(key))
			assert_eq(str(packet["facts"][key]), str(expected), "%s run %d" % [key, i])
			var world_now: Variant = runtime.facts.get_in(StringName(String(key)), &"world")
			if world_now != null and str(world_now) != str(expected):
				assert_ne(str(packet["facts"][key]), str(world_now), "%s run %d" % [key, i])
		for key in allowed.keys():
			if _knows(runtime, String(key)):
				assert_true(packet["facts"].has(key), "%s run %d" % [key, i])
			else:
				assert_false(packet["facts"].has(key), "%s run %d" % [key, i])
		_assert_entities(host, packet)


func _knows(runtime: WyrdRuntime, key: String) -> bool:
	if runtime.roles.revealed(&"player", StringName(key)):
		return true
	return runtime.facts.get_in(StringName(key), &"known/player") != null


func _expected(runtime: WyrdRuntime, key: String) -> Variant:
	if key.begins_with("role.") and key.ends_with(".holder") and runtime.roles.revealed(&"player", StringName(key)):
		var role := key.substr(5, key.length() - 12)
		return String(runtime.roles.holder(StringName(role)))
	return runtime.facts.get_in(StringName(key), &"known/player")


func _assert_entities(host: WyrdFakeHost, packet: Dictionary) -> void:
	var ids := {}
	var previous := ""
	for row in packet["entities"]:
		var id := str(row["id"])
		assert_true(previous <= id)
		previous = id
		ids[id] = str(row["name"])
		var shown := host.world.display_name(StringName(id))
		assert_eq(str(row["name"]), shown if not shown.is_empty() else id)
	if packet.has("speaker"):
		var speaker_id := str(packet["speaker"]["id"])
		assert_true(ids.has(speaker_id))
		assert_eq(ids[speaker_id], str(packet["speaker"]["name"]))
	for value in packet["facts"].values():
		if not (value is String):
			continue
		if host.world.exists(StringName(value)):
			assert_true(ids.has(value), value)


func _roll(rng: WyrdRng, type_name: String) -> Variant:
	if type_name == "bool":
		return rng.randi_bounded(2) == 1
	if type_name == "int":
		return rng.randi_range(0, 20)
	return String(_SYMBOLS[rng.randi_bounded(_SYMBOLS.size())])


func _other(type_name: String, world_value: Variant) -> Variant:
	if type_name == "bool":
		return not bool(world_value)
	if type_name == "int":
		return int(world_value) + 7
	var at := _SYMBOLS.find(String(world_value))
	if at < 0:
		return "paid"
	return String(_SYMBOLS[(at + 1) % _SYMBOLS.size()])


func _remove_fact(runtime: WyrdRuntime, key: String) -> void:
	var schema := runtime.content().schema
	var next: Array[WyrdFact] = []
	for fact in schema.entries:
		if fact.key == key:
			continue
		next.append(fact)
	schema.entries = next


func _boot(body: String) -> Dictionary:
	var path := "user://wyrd_m10_packet_%d.wyrd" % body.hash()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(body)
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = "m10packet"
	manifest.files = PackedStringArray([path])
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	host.world.add_entity(&"player", &"person", "traveler", PackedStringArray(), true)
	host.world.add_entity(&"ferry_master", &"person", "Bram", PackedStringArray(), true)
	host.world.add_entity(&"tavern_owner", &"person", "Innkeeper", PackedStringArray(), true)
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(1)
	runtime.trace.enabled = true
	return {"host": host, "runtime": runtime}


func _rows(runtime: WyrdRuntime, kind: String) -> Array:
	var rows: Array = []
	for event in runtime.trace.events:
		if str(event.get("kind", "")) == kind:
			rows.append(event)
	return rows


func _property_source() -> String:
	var lines: PackedStringArray = PackedStringArray([
		"// [EXAMPLE CONTENT]",
		"language 1",
		"",
		"facts",
	])
	for index in _KEYS.size():
		lines.append("  %s : %s stored" % [String(_KEYS[index]), String(_TYPES[index])])
	lines.append("  role.harbor_clerk.holder : symbol stored")
	lines.append("")
	lines.append("role harbor_clerk")
	lines.append("  default_holder: ferry_master")
	lines.append("  visibility: public")
	lines.append("")
	lines.append("role tide_clerk")
	lines.append("  visibility: secret")
	lines.append("")
	var ctx := PackedStringArray()
	for key in _KEYS:
		ctx.append(key)
	ctx.append("role.harbor_clerk.holder")
	lines.append("storylet harbor.ledger")
	lines.append("  scope: bark")
	lines.append("  speaker: ferry_master")
	lines.append("  ai_context: [%s]" % ", ".join(ctx))
	lines.append("  - The ledger is open. #tag:ai #line:ledger")
	return "\n".join(lines) + "\n"


const _SCENE := """// [EXAMPLE CONTENT]
language 1

events
  season_changed()

facts
  player.coins : int stored
  player.clearance : symbol stored
  harbor.toll_fate : symbol stored
  harbor.missing : symbol stored
  world.season : symbol source: time.season invalidate: on_event(season_changed)
  role.harbor_clerk.holder : symbol stored

role harbor_clerk
  default_holder: ferry_master
  visibility: public

role tide_clerk
  visibility: secret

scene toll.gate
  ai_context: [player.coins, world.season, harbor.toll_fate, harbor.missing]
  narrator: The gate is shut. #line:plain
  narrator: The lane is quiet. #tag:ai #line:gate
  ferry_master: The book is in the shed. #tag:ai #line:keeper
  -> end

storylet harbor.news
  scope: topic harbor_toll
  speaker: harbor_clerk
  ai_context: [player.coins, harbor.toll_fate]
  - The harbor has news. #tag:ai #line:news

storylet harbor.quiet
  scope: bark
  speaker: any
  - The harbor is quiet. #tag:ai #line:quiet
"""
