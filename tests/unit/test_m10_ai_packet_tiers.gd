extends GutTest

const _Exit := preload("res://tests/scenario/m10_gullhaven.gd")
const _IDS: Array[String] = ["a_leave", "sg02", "sg03", "sg04", "sg05", "sg_storm"]


func test_packets_omit_secrets_and_unknown_facts_at_both_tiers() -> void:
	var opened := _Exit.new().boot("null")
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	runtime.config().secrecy_tiers = PackedStringArray(["open", "sealed"])
	runtime.roles.define(&"shadow_clerk", "", true)
	runtime.facts.set_in(&"harbor.toll_fate", &"sealed_cargo", &"world")
	var low := _packets(runtime)
	runtime.facts.set(&"player.clearance", &"sealed")
	var high := _packets(runtime)
	assert_eq(low, high)
	for line_id in _IDS:
		_assert_packet(runtime, host, line_id, low[line_id])
		assert_false((low[line_id]["facts"] as Dictionary).has("world.storm_heard"), line_id)
	runtime.facts.set_in(&"world.storm_heard", true, &"known/player")
	var known := _packets(runtime)
	runtime.facts.set(&"player.clearance", &"open")
	assert_eq(known, _packets(runtime))
	for line_id in _IDS:
		var facts: Dictionary = known[line_id]["facts"]
		if line_id == "sg_storm":
			assert_eq(facts["world.storm_heard"], true)
		else:
			assert_false(facts.has("world.storm_heard"), line_id)
		_assert_packet(runtime, host, line_id, known[line_id])


func _packets(runtime: WyrdRuntime) -> Dictionary:
	var out := {}
	for line_id in _IDS:
		var kind := runtime.ai.kind_for_line(line_id)
		out[line_id] = runtime.ai.packet_for_line(line_id, kind, &"")
	return out


func _assert_packet(runtime: WyrdRuntime, host: WyrdFakeHost, line_id: String, packet: Dictionary) -> void:
	var canonical := WyrdAIPacket.canonical(packet)
	assert_false(canonical.contains("shadow_clerk"), line_id)
	assert_false(canonical.contains("sealed_cargo"), line_id)
	assert_false(canonical.contains("late cargo"), line_id)
	assert_false(canonical.contains("sealed page"), line_id)
	var ids := {}
	for item in packet["entities"]:
		var row: Dictionary = item
		var id := str(row["id"])
		ids[id] = str(row["name"])
		assert_false(id.is_empty(), line_id)
	if packet.has("speaker"):
		var speaker: Dictionary = packet["speaker"]
		var speaker_id := str(speaker["id"])
		assert_true(ids.has(speaker_id), line_id)
		assert_eq(str(ids[speaker_id]), str(speaker["name"]), line_id)
		for role_id in speaker["roles"]:
			assert_true(runtime.roles.revealed(&"player", StringName("role.%s.holder" % role_id)), line_id)
	var facts: Dictionary = packet["facts"]
	for key in facts.keys():
		assert_true(_knows(runtime, String(key)), "%s %s" % [line_id, key])
		var value: Variant = facts[key]
		if value is String and host.world.exists(StringName(value)):
			assert_true(ids.has(String(value)), "%s %s" % [line_id, value])
	if packet.has("deeds"):
		for deed in packet["deeds"]:
			var row: Dictionary = deed
			for field in ["actor", "target", "place"]:
				var deed_id := str(row.get(field, ""))
				if deed_id.is_empty() or not host.world.exists(StringName(deed_id)):
					continue
				assert_true(ids.has(deed_id), "%s %s" % [line_id, deed_id])
				assert_eq(str(ids[deed_id]), host.world.display_name(StringName(deed_id)), line_id)


func _knows(runtime: WyrdRuntime, key: String) -> bool:
	if runtime.roles.revealed(&"player", StringName(key)):
		return true
	return runtime.facts.get_in(StringName(key), &"known/player") != null
