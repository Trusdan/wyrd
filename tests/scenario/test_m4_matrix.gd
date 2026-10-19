extends GutTest

const _Harness := preload("res://tests/scenario/s2c_harness.gd")

## Kill, replace, and vacate each Gullhaven holder at each stage that holder
## appears in. 3 ferry roles x 3 stages x 3 actions, plus 2 guild roles x 2
## stages x 3 actions.
const MATRIX_SIZE := 39

const _FERRY_STAGES: PackedStringArray = ["gossip", "pay_toll", "cross"]
const _GUILD_STAGES: PackedStringArray = ["petition", "signed"]
const _ACTIONS: PackedStringArray = ["kill", "replace", "vacate"]


class Poll extends WyrdElectionAdapter:
	var heard: Array = []

	func start_election(role: StringName, departed: StringName) -> void:
		heard.append([String(role), String(departed)])


func test_matrix_size_is_every_holder_stage_and_action() -> void:
	var cases := _cases()
	assert_eq(cases.size(), MATRIX_SIZE)
	var seen := {}
	for case in cases:
		var key := "%s|%s|%s" % [case["role"], case["stage"], case["action"]]
		assert_false(seen.has(key), key)
		seen[key] = true
	assert_eq(seen.size(), MATRIX_SIZE)


func test_each_fallback_round_trips() -> void:
	for case in _cases():
		if not _run_case(case):
			return


func test_guild_route_bars_a_visitor() -> void:
	var opened := _open_guild(false, true)
	var runtime: WyrdRuntime = opened["runtime"]
	_start_guild(runtime)
	var label := "barred"
	if not assert_eq(runtime.quests.stage("harbor_guild"), "petition", label):
		return
	if not assert_eq(runtime.quests.variant_of("harbor_guild"), "factor.barred", label):
		return
	if not assert_eq(String(runtime.roles.slot_state(&"factor", "harbor_guild")), "barred", label):
		return
	if not assert_eq(runtime.quests.outcome("harbor_guild", "petition"), "route_closed", label):
		return
	if not assert_eq(String(runtime.quests.status("harbor_guild")), "active", label):
		return
	if not assert_true(_journal_ids(runtime, "harbor_guild").has("j_guild_barred"), label):
		return
	_round_trip(runtime, opened["host"], "harbor_guild", &"factor", &"harbor_factor", false, label)


func test_factor_unwilling_when_the_levy_is_refused() -> void:
	var opened := _open_guild(true, true)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.facts.set(&"harbor.factor_refuses", true)
	_start_guild(runtime)
	var label := "unwilling"
	if not assert_eq(runtime.quests.variant_of("harbor_guild"), "factor.unwilling", label):
		return
	if not assert_eq(String(runtime.roles.slot_state(&"factor", "harbor_guild")), "unwilling", label):
		return
	if not assert_eq(String(runtime.quests.status("harbor_guild")), "active", label):
		return
	if not assert_true(_journal_ids(runtime, "harbor_guild").has("j_guild_unwilling"), label):
		return
	_round_trip(runtime, opened["host"], "harbor_guild", &"factor", &"harbor_factor", true, label)


func _run_case(case: Dictionary) -> bool:
	var label := "%s %s %s" % [case["role"], case["stage"], case["action"]]
	var opened: Dictionary = _reach(case)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	var poll: Poll = opened["poll"]
	if not assert_eq(runtime.quests.stage(str(case["quest"])), str(case["stage"]), label + " reach"):
		return false
	_act(runtime, host, case)
	runtime.tick(0)
	if not _assert_fallback(runtime, poll, case, label):
		return false
	return _round_trip(
		runtime,
		host,
		str(case["quest"]),
		StringName(str(case["slot"])),
		StringName(str(case["role"])),
		str(case["quest"]) == "harbor_guild",
		label
	)


func _assert_fallback(runtime: WyrdRuntime, poll: Poll, case: Dictionary, label: String) -> bool:
	var expect := _expect(case)
	var quest := str(case["quest"])
	var slot := StringName(str(case["slot"]))
	var role := StringName(str(case["role"]))
	var resolved: Dictionary = runtime.roles.resolve_slot(quest, slot, false)
	if not assert_eq(String(resolved["state"]), str(expect["state"]), label + " state"):
		return false
	if not assert_eq(String(resolved["reason"]), str(expect["reason"]), label + " reason"):
		return false
	if not assert_eq(String(runtime.roles.slot_holder(quest, slot)), str(expect["slot_holder"]), label + " slot"):
		return false
	if not assert_eq(String(runtime.roles.holder(role)), str(expect["holder"]), label + " holder"):
		return false
	if not assert_eq(String(runtime.roles.binding_status(role)), str(expect["status"]), label + " status"):
		return false
	if not assert_eq(runtime.roles.abolished(role), bool(expect["abolished"]), label + " abolished"):
		return false
	if not assert_eq(runtime.quests.stage(quest), str(expect["stage"]), label + " stage"):
		return false
	if expect.has("variant") and not assert_eq(runtime.quests.variant_of(quest), str(expect["variant"]), label + " variant"):
		return false
	if expect.has("journal") and not assert_true(_journal_ids(runtime, quest).has(str(expect["journal"])), label + " journal"):
		return false
	if expect.has("waiting") and not assert_eq(runtime.quests.waiting_reason(quest), str(expect["waiting"]), label + " waiting"):
		return false
	if not assert_eq(poll.heard, expect["election"], label + " election"):
		return false
	return true


func _expect(case: Dictionary) -> Dictionary:
	var role := str(case["role"])
	var stage := str(case["stage"])
	var action := str(case["action"])
	var locked := role == "ferry_master" and (stage == "pay_toll" or stage == "cross")
	var row := {
		"abolished": false,
		"election": [],
		"holder": "",
		"reason": "",
		"slot_holder": "",
		"stage": stage,
		"state": "",
		"status": "",
	}
	if role == "storm_watcher":
		row["state"] = "default"
		row["reason"] = "holder"
		row["slot_holder"] = "dock_apprentice"
		row["holder"] = "" if action != "replace" else "bell_warden"
		row["status"] = "empty" if action != "replace" else "default"
		return row
	if role == "tavern_owner":
		if action == "replace":
			row["state"] = "default"
			row["reason"] = "holder"
			row["slot_holder"] = "bell_warden"
			row["holder"] = "bell_warden"
			row["status"] = "default"
		else:
			row["state"] = "empty"
			row["reason"] = "no_holder"
			row["status"] = "empty"
			if stage == "pay_toll":
				row["waiting"] = "on_empty"
		return row
	if role == "ferry_master":
		if locked and action == "replace":
			row["state"] = "default"
			row["reason"] = "holder"
			row["slot_holder"] = "ferry_master"
			row["holder"] = "bell_warden"
			row["status"] = "default"
			return row
		if locked:
			row["state"] = "locked_gone"
			row["slot_holder"] = "ferry_master"
			if action == "kill":
				row["reason"] = "frozen_dead"
				row["holder"] = "ferry_master"
				row["status"] = "default"
			else:
				row["reason"] = "frozen_vacated"
				row["holder"] = "dock_apprentice"
				row["status"] = "successor"
			if stage == "pay_toll":
				row["variant"] = "ferry.locked_gone"
				row["journal"] = "j_ft_gone"
			return row
		if action == "replace":
			row["state"] = "default"
			row["reason"] = "holder"
			row["slot_holder"] = "bell_warden"
			row["holder"] = "bell_warden"
			row["status"] = "default"
		else:
			row["state"] = "successor"
			row["reason"] = "status"
			row["slot_holder"] = "dock_apprentice"
			row["holder"] = "dock_apprentice"
			row["status"] = "successor"
		return row
	if role == "harbor_factor":
		if action == "vacate":
			row["abolished"] = true
			row["state"] = "empty"
			row["reason"] = "no_holder"
			row["status"] = "empty"
			if stage == "petition":
				row["variant"] = "factor.empty"
				row["journal"] = "j_guild_empty"
			else:
				row["waiting"] = "on_empty"
			return row
		if action == "replace":
			row["state"] = "default"
			row["reason"] = "holder"
			row["slot_holder"] = "bell_warden"
			row["holder"] = "bell_warden"
			row["status"] = "default"
			if stage == "petition":
				row["variant"] = "factor.default"
			return row
		row["state"] = "successor"
		row["reason"] = "status"
		row["slot_holder"] = "rope_walker"
		row["holder"] = "rope_walker"
		row["status"] = "successor"
		if stage == "petition":
			row["stage"] = "signed"
			row["journal"] = "j_guild_next"
		return row
	row["election"] = [["harbor_reeve", "tide_clerk"]] if action != "replace" else []
	if action == "replace":
		row["state"] = "default"
		row["reason"] = "holder"
		row["slot_holder"] = "bell_warden"
		row["holder"] = "bell_warden"
		row["status"] = "default"
		return row
	row["state"] = "contested"
	row["reason"] = "contested"
	row["status"] = "contested"
	if stage == "signed":
		row["variant"] = "reeve.contested"
		row["journal"] = "j_guild_vote"
	return row


func _cases() -> Array:
	var rows: Array = []
	var ferry: Array = [
		{"quest": "ferry_toll", "role": "tavern_owner", "slot": "tavern"},
		{"quest": "ferry_toll", "role": "ferry_master", "slot": "ferry"},
		{"quest": "ferry_toll", "role": "storm_watcher", "slot": "lookout"},
	]
	for stage in _FERRY_STAGES:
		for role in ferry:
			for action in _ACTIONS:
				var case: Dictionary = (role as Dictionary).duplicate()
				case["stage"] = String(stage)
				case["action"] = String(action)
				rows.append(case)
	var guild: Array = [
		{"quest": "harbor_guild", "role": "harbor_factor", "slot": "factor"},
		{"quest": "harbor_guild", "role": "harbor_reeve", "slot": "reeve"},
	]
	for stage in _GUILD_STAGES:
		for role in guild:
			for action in _ACTIONS:
				var case: Dictionary = (role as Dictionary).duplicate()
				case["stage"] = String(stage)
				case["action"] = String(action)
				rows.append(case)
	return rows


func _reach(case: Dictionary) -> Dictionary:
	if str(case["quest"]) == "harbor_guild":
		return _reach_guild(case)
	return _reach_ferry(str(case["stage"]))


func _reach_ferry(stage: String) -> Dictionary:
	var opened := _Harness.new().boot_gullhaven(false, 4, true)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	_add_guild_people(host)
	runtime.social.set_kind(&"ferry_master", &"dock_apprentice", &"apprentice")
	if stage == "pay_toll" or stage == "cross":
		_finish_room(runtime)
	if stage == "cross":
		runtime.tick(0)
	elif stage == "pay_toll":
		runtime.facts.set(&"player.coins", 0)
	var poll := Poll.new()
	runtime.register_adapter(WyrdElectionAdapter, poll)
	opened["poll"] = poll
	return opened


func _reach_guild(case: Dictionary) -> Dictionary:
	var opened := _open_guild(true, false)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.world.add_member(&"faction.harbor", &"net_mender")
	if not (str(case["role"]) == "harbor_factor" and str(case["action"]) == "vacate"):
		host.world.add_member(&"faction.harbor", &"rope_walker")
	_start_guild(runtime)
	if str(case["stage"]) == "signed":
		runtime.facts.set(&"harbor.guild_signed", true)
		runtime.tick(0)
	return opened


func _open_guild(local_tag: bool, with_successor: bool) -> Dictionary:
	var opened := _Harness.new().open_pack(_Harness.HARBOR)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	var poll := Poll.new()
	runtime.register_adapter(WyrdElectionAdapter, poll)
	_add_ferry_people(host, local_tag)
	_add_guild_people(host)
	if with_successor:
		host.world.add_member(&"faction.harbor", &"net_mender")
		host.world.add_member(&"faction.harbor", &"rope_walker")
	runtime.start_new_game(1)
	opened["poll"] = poll
	return opened


func _start_guild(runtime: WyrdRuntime) -> void:
	runtime.deeds.record(&"asked_guild", &"player", &"", &"gullhaven")
	runtime.tick(0)


func _act(runtime: WyrdRuntime, host: WyrdFakeHost, case: Dictionary) -> void:
	var role := StringName(str(case["role"]))
	var action := str(case["action"])
	if action == "replace":
		runtime.roles.assign(role, &"bell_warden")
		return
	var who := _default_holder(str(case["role"]))
	var locked_kill := str(case["role"]) == "ferry_master" and action == "kill"
	locked_kill = locked_kill and (str(case["stage"]) == "pay_toll" or str(case["stage"]) == "cross")
	if action == "kill":
		_set_alive(host, who, false)
	if locked_kill:
		return
	var reason := &"died" if action == "kill" else &"left"
	runtime.roles.vacate(role, reason)


func _round_trip(
	runtime: WyrdRuntime,
	host: WyrdFakeHost,
	quest: String,
	slot: StringName,
	role: StringName,
	local_tag: bool,
	label: String
) -> bool:
	if not assert_true(runtime.can_save(), label + " save"):
		return false
	var saved := runtime.save_state()
	if not assert_false(saved.is_empty(), label + " blob"):
		return false
	var parsed: Variant = JSON.parse_string(JSON.stringify(saved))
	if not assert_true(parsed is Dictionary, label + " json"):
		return false
	var fresh_open := _Harness.new().open_pack(_Harness.HARBOR)
	var fresh: WyrdRuntime = fresh_open["runtime"]
	_mirror(host, fresh_open["host"], local_tag)
	var report := fresh.load_state(parsed)
	if not assert_true(report.ok, label + " " + report.diagnostics.format()):
		return false
	if not assert_true(_same(saved, fresh.save_state()), label + " identical"):
		return false
	if not assert_eq(fresh.quests.stage(quest), runtime.quests.stage(quest), label + " loaded stage"):
		return false
	if not assert_eq(String(fresh.roles.slot_state(slot, quest)), String(runtime.roles.slot_state(slot, quest)), label + " loaded slot"):
		return false
	if not assert_eq(String(fresh.roles.holder(role)), String(runtime.roles.holder(role)), label + " loaded holder"):
		return false
	return true


func _mirror(src: WyrdFakeHost, dst: WyrdFakeHost, local_tag: bool) -> void:
	for row in _people():
		var id := StringName(str(row[0]))
		var tags := PackedStringArray()
		if id == &"player" and local_tag:
			tags.append("local")
		var alive := true
		if src.world.exists(id):
			alive = src.world.is_alive(id)
		dst.world.add_entity(id, StringName(str(row[1])), str(row[2]), tags, alive)
	for member in src.world.members(&"faction.harbor"):
		dst.world.add_member(&"faction.harbor", StringName(str(member)))


func _add_ferry_people(host: WyrdFakeHost, local_tag: bool) -> void:
	var tags := PackedStringArray()
	if local_tag:
		tags.append("local")
	host.world.add_entity(&"player", &"person", "traveler", tags, true)
	host.world.add_entity(&"tavern_owner", &"person", "innkeeper", PackedStringArray(), true)
	host.world.add_entity(&"ferry_master", &"person", "Bram", PackedStringArray(), true)
	host.world.add_entity(&"storm_watcher", &"person", "watcher", PackedStringArray(), true)
	host.world.add_entity(&"dock_apprentice", &"person", "Nia", PackedStringArray(), true)
	host.world.add_entity(&"dock.bell", &"object", "bell", PackedStringArray(), true)


func _add_guild_people(host: WyrdFakeHost) -> void:
	host.world.add_entity(&"net_mender", &"person", "Lise", PackedStringArray(), true)
	host.world.add_entity(&"rope_walker", &"person", "Edd", PackedStringArray(), true)
	host.world.add_entity(&"tide_clerk", &"person", "Sella", PackedStringArray(), true)
	host.world.add_entity(&"bell_warden", &"person", "Harl", PackedStringArray(), true)


func _people() -> Array:
	return [
		["player", "person", "traveler"],
		["tavern_owner", "person", "innkeeper"],
		["ferry_master", "person", "Bram"],
		["storm_watcher", "person", "watcher"],
		["dock_apprentice", "person", "Nia"],
		["dock.bell", "object", "bell"],
		["net_mender", "person", "Lise"],
		["rope_walker", "person", "Edd"],
		["tide_clerk", "person", "Sella"],
		["bell_warden", "person", "Harl"],
	]


func _default_holder(role: String) -> StringName:
	match role:
		"tavern_owner":
			return &"tavern_owner"
		"ferry_master":
			return &"ferry_master"
		"storm_watcher":
			return &"storm_watcher"
		"harbor_factor":
			return &"net_mender"
		_:
			return &"tide_clerk"


func _set_alive(host: WyrdFakeHost, id: StringName, alive: bool) -> void:
	var kind := &"person"
	var shown := String(id)
	for row in _people():
		if StringName(str(row[0])) == id:
			kind = StringName(str(row[1]))
			shown = str(row[2])
	host.world.add_entity(id, kind, shown, PackedStringArray(), alive)


func _finish_room(runtime: WyrdRuntime) -> void:
	var harness := _Harness.new()
	runtime.dialogue.open_scene("toll.offer_room")
	harness.line_rows(runtime)
	harness.choose_text(runtime, "Take the room")
	harness.line_rows(runtime)


func _journal_ids(runtime: WyrdRuntime, quest: String) -> PackedStringArray:
	var ids := PackedStringArray()
	for entry in runtime.quests.journal(quest):
		ids.append(String(entry["id"]))
	return ids


func _same(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):
		return false
	if left is Dictionary:
		if left.size() != right.size():
			return false
		for key in left.keys():
			if not right.has(key) or not _same(left[key], right[key]):
				return false
		return true
	if left is Array:
		if left.size() != right.size():
			return false
		for i in left.size():
			if not _same(left[i], right[i]):
				return false
		return true
	return left == right
