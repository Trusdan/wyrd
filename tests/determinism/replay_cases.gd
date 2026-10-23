extends RefCounted

## Boots and steps for the matrix and exit replays.
## Route steps stay in the m10 vocabulary and run through the driver.

const _Harness := preload("res://tests/scenario/s2c_harness.gd")
const _Harbor := preload("res://tests/scenario/m9_gullhaven.gd")
const _Election := preload("res://example/playtest/harbor_election.gd")

static var slots := {}


class Poll extends WyrdElectionAdapter:
	var heard: Array = []

	func start_election(role: StringName, departed: StringName) -> void:
		heard.append([String(role), String(departed)])


static func boot(run: Dictionary) -> WyrdRuntime:
	var runtime: WyrdRuntime
	var kind := str(run["kind"])
	match kind:
		"m4_ferry":
			runtime = _boot_m4_ferry()
		"m4_guild":
			runtime = _boot_m4_guild(run)
		"m5":
			runtime = _boot_m5(bool(run.get("member", false)))
		"m6_harbor":
			runtime = _boot_harbor()
		"m6_pack":
			runtime = _boot_pack(int(run.get("seed", 1)))
		"m7_ferry":
			runtime = _boot_gull(false)
		"m7_guild":
			runtime = _boot_gull(true)
		"m9":
			runtime = _boot_generated()
		_:
			push_error("replay case boot %s" % kind)
			runtime = WyrdRuntime.new()
	runtime.config().scheduler_frame_warn_usec = 0
	if not runtime.has_meta("m10_harness"):
		runtime.set_meta("m10_harness", _Harness.new())
	if runtime.has_meta("host") and not runtime.has_meta("m10_host"):
		runtime.set_meta("m10_host", runtime.get_meta("host"))
	return runtime


static func act(runtime: WyrdRuntime, step: Dictionary) -> void:
	var op := str(step.get("op", ""))
	var host := _host(runtime)
	match op:
		"set_kind":
			runtime.social.set_kind(StringName(str(step["a"])), StringName(str(step["b"])), StringName(str(step["kind"])))
		"deed":
			runtime.deeds.record(StringName(str(step["verb"])), StringName(str(step["actor"])), StringName(str(step.get("target", ""))), StringName(str(step.get("place", ""))))
		"fact":
			runtime.facts.set(StringName(str(step["key"])), step["value"])
		"fact_in":
			runtime.facts.set_in(StringName(str(step["key"])), step["value"], StringName(str(step["scope"])))
		"clear_in":
			runtime.facts.clear_in(StringName(str(step["key"])), StringName(str(step["scope"])))
		"assign":
			runtime.roles.assign(StringName(str(step["role"])), StringName(str(step["entity"])))
		"define":
			runtime.roles.define(StringName(str(step["role"])), str(step["text"]))
		"member":
			host.world.add_member(StringName(str(step["faction"])), StringName(str(step["entity"])))
		"alive":
			_set_alive(host, StringName(str(step["id"])), bool(step.get("on", true)))
		"groups":
			host.world.set_groups(StringName(str(step["id"])), PackedStringArray([StringName(str(step["group"]))]))
		"perception":
			host.spatial.set_perception(StringName(str(step["id"])), StringName(str(step["level"])))
		"baseline":
			runtime.social.set_baseline(StringName(str(step["a"])), StringName(str(step["b"])), StringName(str(step["axis"])), float(step["value"]))
		"invalidate":
			runtime.invalidate_groups()
		"poll":
			runtime.register_adapter(WyrdElectionAdapter, Poll.new())
		"console":
			var console := WyrdConsole.new()
			console.bind(runtime)
			console.exec(str(step["line"]))
		"query":
			runtime.director.query(str(step["scope"]), str(step.get("scope_id", "")), str(step.get("speaker", "")))
		"why_not":
			runtime.director.why_not(str(step["id"]), str(step["scope"]), str(step.get("scope_id", "")), str(step.get("speaker", "")))
		"diagnose":
			runtime.director.diagnose(str(step["id"]), str(step["scope"]), str(step.get("scope_id", "")), str(step.get("speaker", "")))
		"candidates":
			runtime.director.candidate_rows(str(step["scope"]), str(step.get("scope_id", "")), str(step.get("speaker", "")))
		"coverage_on":
			runtime.coverage.enabled = true
		"choice_summary":
			runtime.facts.choice_summary()
			runtime.facts.choice_summary({"prefix": "ferry.toll"})
			runtime.facts.choice_summary({"scene": "toll.offer_room"})
		"compact":
			runtime.deeds.compact()
		"offer":
			runtime.generator.offer(StringName(str(step["source"])), str(step["key"]), StringName(str(step.get("tier", ""))))
		"share":
			runtime.config().scheduler_share_generate = int(step["value"])
		"protected":
			host.world.set_protected(StringName(str(step["id"])), bool(step.get("on", true)))
		"propose_open":
			var fields := {"key": str(step.get("key", "")), "source": str(step.get("source", "exit"))}
			if str(step.get("template", "")) != "":
				fields["template"] = str(step["template"])
			if str(step.get("tier", "")) != "":
				fields["tier"] = str(step["tier"])
			runtime.set_meta("m10_proposal", runtime.generator.propose(fields))
		"emit_state":
			runtime.events.emit(&"mechanism_state", {
				"actor": &"player",
				"object": StringName(str(step["object"])),
				"state": StringName(str(step["state"])),
			})
		"seen":
			runtime.storylets.seen_of(str(step["id"]))
		"trace_director":
			runtime.config().trace_director = bool(step.get("on", true))
		"prefix":
			runtime.trace.prefix = str(step.get("text", ""))
		"secrecy":
			var names := PackedStringArray()
			for item in step["tiers"]:
				names.append(str(item))
			runtime.config().secrecy_tiers = names
		"trace_off":
			runtime.trace.enabled = false
		"m4_act":
			_m4_act(runtime, host, step)
		"save_hold":
			slots[str(step["slot"])] = JSON.parse_string(JSON.stringify(runtime.save_state()))
		"load_held":
			var report := runtime.load_state(slots[str(step["slot"])])
			if not report.ok:
				push_error("load_held %s %s" % [str(step["slot"]), report.diagnostics.format()])
		"stew_offer":
			var tier := "low"
			var value: Variant = runtime.facts.get(&"harbor.stew_tier")
			if value != null:
				tier = String(value)
			runtime.generator.offer(&"tavern", "stew-%s" % tier, StringName(tier))
		_:
			push_error("replay case unknown op %s" % op)


static func prepare(runtime: WyrdRuntime, step: Dictionary) -> void:
	var op := str(step.get("op", ""))
	var host := _host(runtime)
	match op:
		"member":
			if host != null:
				host.world.add_member(StringName(str(step["faction"])), StringName(str(step["entity"])))
		"alive":
			if host != null:
				_set_alive(host, StringName(str(step["id"])), bool(step.get("on", true)))
		"groups":
			if host != null:
				host.world.set_groups(StringName(str(step["id"])), PackedStringArray([StringName(str(step["group"]))]))
		"perception":
			if host != null:
				host.spatial.set_perception(StringName(str(step["id"])), StringName(str(step["level"])))
		"poll":
			runtime.register_adapter(WyrdElectionAdapter, Poll.new())
		"coverage_on":
			runtime.coverage.enabled = true
		"share":
			runtime.config().scheduler_share_generate = int(step["value"])
		"protected":
			if host != null:
				host.world.set_protected(StringName(str(step["id"])), bool(step.get("on", true)))
		"trace_director":
			runtime.config().trace_director = bool(step.get("on", true))
		"prefix":
			runtime.trace.prefix = str(step.get("text", ""))
		"secrecy":
			var names := PackedStringArray()
			for item in step["tiers"]:
				names.append(str(item))
			runtime.config().secrecy_tiers = names
		"trace_off":
			runtime.trace.enabled = false
		"m4_act":
			if host != null and str(step["action"]) == "kill":
				_set_alive(host, _default_holder(str(step["role"])), false)
		_:
			pass


static func m4_runs() -> Array:
	var runs: Array = []
	var ferry: Array = [
		{"quest": "ferry_toll", "role": "tavern_owner", "slot": "tavern"},
		{"quest": "ferry_toll", "role": "ferry_master", "slot": "ferry"},
		{"quest": "ferry_toll", "role": "storm_watcher", "slot": "lookout"},
	]
	var guild: Array = [
		{"quest": "harbor_guild", "role": "harbor_factor", "slot": "factor"},
		{"quest": "harbor_guild", "role": "harbor_reeve", "slot": "reeve"},
	]
	var ferry_stages := ["gossip", "pay_toll", "cross"]
	var guild_stages := ["petition", "signed"]
	var actions := ["kill", "replace", "vacate"]
	for stage_i in ferry_stages.size():
		for role_i in ferry.size():
			for action_i in actions.size():
				runs.append(_m4_one(ferry[role_i], String(ferry_stages[stage_i]), String(actions[action_i]), "m4_ferry"))
	for stage_j in guild_stages.size():
		for role_j in guild.size():
			for action_j in actions.size():
				runs.append(_m4_one(guild[role_j], String(guild_stages[stage_j]), String(actions[action_j]), "m4_guild"))
	return runs


static func _m4_one(item: Dictionary, stage: String, action: String, kind: String) -> Dictionary:
	var case: Dictionary = item.duplicate()
	case["stage"] = stage
	case["action"] = action
	return _boxed("m4:%s:%s:%s" % [case["role"], stage, action], kind, _m4_steps(case), case)


static func m5_runs() -> Array:
	var grid: Array = [
		{"direction": "write", "slot": "unwilling_group", "source": "group"},
		{"direction": "retract", "slot": "unwilling_group", "source": "group"},
		{"direction": "write", "slot": "unwilling_own", "source": "own"},
		{"direction": "retract", "slot": "unwilling_own", "source": "own"},
		{"direction": "write", "slot": "barred", "source": "player"},
		{"direction": "retract", "slot": "barred", "source": "player"},
	]
	var runs: Array = []
	for item in grid:
		var case: Dictionary = item
		var run := {
			"id": "m5:%s:%s" % [case["slot"], case["direction"]],
			"kind": "m5",
			"member": str(case["source"]) == "group",
			"steps": _m5_steps(case),
			"trace": true,
		}
		runs.append(run)
	return runs


static func m6_runs() -> Array:
	var runs: Array = []
	runs.append(_pack("m6:priority:4", 4, [{"op": "query", "scope": "topic", "scope_id": "rumor.matrix", "speaker": "ferry"}]))
	runs.append(_pack("m6:priority:11", 11, [{"op": "query", "scope": "topic", "scope_id": "rumor.pair", "speaker": "ferry"}]))
	runs.append(_pack("m6:priority:29", 29, [{"op": "query", "scope": "topic", "scope_id": "rumor.pair", "speaker": "ferry"}]))
	var cells: Array = [
		{"has": 0, "near": false},
		{"has": 0, "near": true},
		{"has": 1, "near": false},
		{"has": 1, "near": true},
	]
	for cell in cells:
		var row: Dictionary = cell
		runs.append(_harbor("m6:bark:%d:%s" % [int(row["has"]), str(row["near"])], [
			{"op": "nearby", "posts": bool(row["near"])},
			{"op": "carry", "item": "lantern", "count": int(row["has"])},
			{"op": "query", "scope": "bark", "scope_id": "", "speaker": "ferry"},
		]))
	runs.append(_harbor("m6:bark:cooldown", [
		{"op": "nearby", "posts": true},
		{"op": "carry", "item": "lantern", "count": 0},
		{"op": "query", "scope": "bark", "scope_id": "", "speaker": "ferry"},
		{"op": "carry", "item": "lantern", "count": 1},
		{"op": "query", "scope": "bark", "scope_id": "", "speaker": "ferry"},
		{"op": "query", "scope": "bark", "scope_id": "", "speaker": "ferry"},
		{"op": "save_hold", "slot": "m6_bark"},
	]))
	runs.append(_harbor("m6:bark:loaded", [
		{"op": "load_held", "slot": "m6_bark"},
		{"op": "nearby", "posts": true},
		{"op": "carry", "item": "lantern", "count": 1},
		{"op": "query", "scope": "bark", "scope_id": "", "speaker": "ferry"},
		{"op": "tick", "minutes": 10},
		{"op": "query", "scope": "bark", "scope_id": "", "speaker": "ferry"},
	]))
	var bells: Array = [
		{"rope": false, "tongue": false},
		{"rope": true, "tongue": false},
		{"rope": false, "tongue": true},
		{"rope": true, "tongue": true},
	]
	for bell in bells:
		var bell_row: Dictionary = bell
		var slot := "m6_bell_%s_%s" % [str(bell_row["rope"]), str(bell_row["tongue"])]
		var steps: Array = [{"op": "tick", "minutes": 0}]
		if bool(bell_row["rope"]):
			steps.append({"op": "emit_state", "object": "harbor_rope", "state": "spliced"})
		if bool(bell_row["tongue"]):
			steps.append({"op": "emit_state", "object": "harbor_tongue", "state": "seated"})
		steps.append({"op": "save_hold", "slot": slot})
		runs.append(_harbor("m6:bell:%s" % slot, steps))
		runs.append(_harbor("m6:bell-load:%s" % slot, [
			{"op": "trace_director", "on": true},
			{"op": "load_held", "slot": slot},
			{"op": "tick", "minutes": 0},
		]))
	runs.append(_harbor("m6:signal", [
		{"op": "tick", "minutes": 0},
		{"op": "emit_state", "object": "harbor_bell", "state": "rung"},
		{"op": "save_hold", "slot": "m6_signal"},
	]))
	runs.append(_harbor("m6:signal:loaded", [
		{"op": "load_held", "slot": "m6_signal"},
	]))
	runs.append(_harbor("m6:secrecy", [
		{"op": "secrecy", "tiers": ["open", "sealed"]},
		{"op": "query", "scope": "topic", "scope_id": "rumor.ledger", "speaker": "ferry"},
		_why("harbor_ledger.sealed"),
		{"op": "fact", "key": "player.clearance", "value": &"open"},
		{"op": "query", "scope": "topic", "scope_id": "rumor.ledger", "speaker": "ferry"},
		_why("harbor_ledger.sealed"),
		{"op": "fact", "key": "player.clearance", "value": &"sealed"},
		{"op": "query", "scope": "topic", "scope_id": "rumor.ledger", "speaker": "ferry"},
		{"op": "save_hold", "slot": "m6_secrecy"},
	]))
	runs.append(_harbor("m6:secrecy:loaded", [
		{"op": "secrecy", "tiers": ["open", "sealed"]},
		{"op": "trace_director", "on": true},
		{"op": "load_held", "slot": "m6_secrecy"},
		{"op": "query", "scope": "topic", "scope_id": "rumor.ledger", "speaker": "ferry"},
	]))
	runs.append(_harbor("m6:secrecy:vault", [
		{"op": "secrecy", "tiers": ["open", "sealed", "vault"]},
		{"op": "fact", "key": "player.clearance", "value": &"vault"},
		{"op": "query", "scope": "topic", "scope_id": "rumor.ledger", "speaker": "ferry"},
		_why("harbor_ledger.sealed"),
	]))
	var seeded: Array = [
		{"op": "nearby", "posts": true},
		{"op": "carry", "item": "lantern", "count": 1},
		{"op": "query", "scope": "bark", "scope_id": "", "speaker": "ferry"},
		{"op": "query", "scope": "topic", "scope_id": "rumor.ferry_toll", "speaker": "ferry"},
	]
	runs.append(_harbor("m6:seed:a", seeded))
	runs.append(_harbor("m6:seed:b", seeded))
	runs.append(_harbor("m6:clearance", [
		{"op": "fact", "key": "player.clearance", "value": &"sealed"},
		{"op": "save_hold", "slot": "m6_clearance"},
	]))
	runs.append(_pack("m6:reads", 3, [
		{"op": "seen", "id": "harbor.alpha"},
		{"op": "diagnose", "id": "harbor.alpha", "scope": "topic", "scope_id": "rumor.pair", "speaker": "ferry"},
		{"op": "candidates", "scope": "topic", "scope_id": "rumor.pair", "speaker": "ferry"},
		{"op": "seen", "id": "harbor.alpha"},
	]))
	runs.append(_harbor("m6:dumps", [
		{"op": "nearby", "posts": true},
		{"op": "carry", "item": "lantern", "count": 0},
		{"op": "query", "scope": "bark", "scope_id": "", "speaker": "ferry"},
		{"op": "carry", "item": "lantern", "count": 1},
		{"op": "tick", "minutes": 30},
		{"op": "query", "scope": "bark", "scope_id": "", "speaker": "ferry"},
	]))
	runs.append(_pack("m6:director:off", 8, [
		{"op": "query", "scope": "topic", "scope_id": "rumor.pair", "speaker": "ferry"},
	]))
	runs.append(_pack("m6:director:on", 8, [
		{"op": "trace_director", "on": true},
		{"op": "query", "scope": "topic", "scope_id": "rumor.pair", "speaker": "ferry"},
	]))
	runs.append(_pack("m6:director:prefix", 8, [
		{"op": "trace_director", "on": true},
		{"op": "prefix", "text": "harbor.alpha"},
		{"op": "query", "scope": "topic", "scope_id": "rumor.pair", "speaker": "ferry"},
		{"op": "save_hold", "slot": "m6_director"},
	]))
	runs.append(_pack("m6:director:loaded", 8, [
		{"op": "trace_director", "on": true},
		{"op": "load_held", "slot": "m6_director"},
		{"op": "query", "scope": "topic", "scope_id": "rumor.pair", "speaker": "ferry"},
	]))
	var quiet := _pack("m6:director:quiet", 8, [
		{"op": "trace_director", "on": true},
		{"op": "query", "scope": "topic", "scope_id": "rumor.pair", "speaker": "ferry"},
	])
	quiet["trace"] = false
	runs.append(quiet)
	return runs


static func m7_runs() -> Array:
	var runs: Array = []
	var ferry: Array = [
		{"quest": "ferry_toll", "role": "tavern_owner", "slot": "tavern"},
		{"quest": "ferry_toll", "role": "ferry_master", "slot": "ferry"},
		{"quest": "ferry_toll", "role": "storm_watcher", "slot": "lookout"},
	]
	var ferry_stages := ["gossip", "pay_toll", "cross"]
	for stage_i in ferry_stages.size():
		for role_i in ferry.size():
			runs.append(_m7_ferry(ferry[role_i], String(ferry_stages[stage_i])))
	var guild: Array = [
		{"quest": "harbor_guild", "role": "harbor_factor", "slot": "factor"},
		{"quest": "harbor_guild", "role": "harbor_reeve", "slot": "reeve"},
	]
	var guild_stages := ["petition", "signed"]
	for stage_j in guild_stages.size():
		for role_j in guild.size():
			runs.append(_m7_guild(guild[role_j], String(guild_stages[stage_j])))
	runs.append({
		"id": "m7:coverage",
		"kind": "m7_ferry",
		"trace": true,
		"steps": [
			{"op": "coverage_on"},
			{"op": "query", "scope": "topic", "scope_id": "rumor.ferry_toll", "speaker": ""},
			{"op": "lines"},
		],
	})
	var choice: Array = _room()
	choice.append({"op": "fact", "key": "player.coins", "value": 0})
	choice.append({"op": "choice_summary"})
	choice.append({"op": "save_hold", "slot": "m7_choice"})
	runs.append({"id": "m7:choice", "kind": "m7_ferry", "trace": true, "steps": choice})
	runs.append({
		"id": "m7:choice:loaded",
		"kind": "m7_ferry",
		"trace": true,
		"steps": [
			{"op": "load_held", "slot": "m7_choice"},
			{"op": "compact"},
		],
	})
	return runs


static func m9_runs() -> Array:
	var stew: Array = [{"op": "share", "value": 64}]
	for round_i in 3:
		stew.append({"op": "fact", "key": "harbor.stew_wanted", "value": true})
		stew.append({"op": "stew_offer"})
		stew.append({"op": "tick", "minutes": 0})
		stew.append({"op": "carry", "item": "fish", "count": round_i + 1})
		stew.append({"op": "share", "value": 0})
		stew.append({"op": "tick", "minutes": 0})
		stew.append({"op": "tick", "minutes": 0})
		stew.append({"op": "share", "value": 64})
	return [
		{"id": "m9:stew", "kind": "m9", "trace": true, "steps": stew},
		{"id": "m9:cap", "kind": "m9", "trace": true, "steps": [
			{"op": "propose", "key": "nets", "template": "net_delivery"},
			{"op": "accept"},
			{"op": "propose", "key": "again", "template": "net_delivery"},
		]},
		{"id": "m9:guard", "kind": "m9", "trace": true, "steps": [
			{"op": "remove", "id": "pier_fisher"},
			{"op": "protected", "id": "line_fisher", "on": true},
			{"op": "propose", "key": "guard", "template": "net_delivery"},
		]},
		{"id": "m9:save", "kind": "m9", "trace": true, "steps": [
			{"op": "propose", "key": "nets", "template": "net_delivery"},
			{"op": "accept"},
			{"op": "propose", "key": "walk", "template": "night_walk"},
			{"op": "accept"},
			{"op": "save_hold", "slot": "m9_save"},
			{"op": "fact", "key": "harbor.boat_adrift", "value": true},
			{"op": "propose_open", "key": "next", "source": "save"},
		]},
		{"id": "m9:save:loaded", "kind": "m9", "trace": true, "steps": [
			{"op": "load_held", "slot": "m9_save"},
			{"op": "fact", "key": "harbor.boat_adrift", "value": true},
			{"op": "propose_open", "key": "next", "source": "save"},
		]},
	]


static func _boxed(id: String, kind: String, steps: Array, case: Dictionary) -> Dictionary:
	return {
		"action": str(case["action"]),
		"id": id,
		"kind": kind,
		"role": str(case["role"]),
		"stage": str(case["stage"]),
		"steps": steps,
		"trace": true,
	}


static func _m4_steps(case: Dictionary) -> Array:
	var steps: Array = []
	if str(case["quest"]) == "ferry_toll":
		steps.append({"op": "set_kind", "a": "ferry_master", "b": "dock_apprentice", "kind": "apprentice"})
		if str(case["stage"]) == "pay_toll" or str(case["stage"]) == "cross":
			steps.append_array(_room())
		if str(case["stage"]) == "cross":
			steps.append({"op": "tick", "minutes": 0})
		elif str(case["stage"]) == "pay_toll":
			steps.append({"op": "fact", "key": "player.coins", "value": 0})
		steps.append({"op": "poll"})
	else:
		steps.append({"op": "deed", "verb": "asked_guild", "actor": "player", "target": "", "place": "gullhaven"})
		steps.append({"op": "tick", "minutes": 0})
		if str(case["stage"]) == "signed":
			steps.append({"op": "fact", "key": "harbor.guild_signed", "value": true})
			steps.append({"op": "tick", "minutes": 0})
	steps.append({
		"action": str(case["action"]),
		"op": "m4_act",
		"role": str(case["role"]),
		"stage": str(case["stage"]),
	})
	steps.append({"op": "tick", "minutes": 0})
	return steps


static func _m5_steps(case: Dictionary) -> Array:
	var steps: Array = [
		{"op": "perception", "id": "dock_apprentice", "level": "heard"},
		{"op": "baseline", "a": "ferry_master", "b": "line_fisher", "axis": "affinity", "value": -100.0},
		{"op": "invalidate"},
		{"op": "deed", "verb": "asked_council", "actor": "player", "target": "", "place": "gullhaven"},
		{"op": "tick", "minutes": 0},
	]
	if str(case["source"]) == "own":
		steps.append({"op": "fact_in", "key": "harbor.toll_fate", "value": &"lost_at_sea", "scope": "believed/dock_hand"})
		steps.append({"op": "tick", "minutes": 0})
	elif str(case["slot"]) == "barred":
		steps.append({"op": "fact_in", "key": "harbor.toll_fate", "value": &"stolen", "scope": "believed/player"})
		steps.append({"op": "tick", "minutes": 0})
	if str(case["direction"]) == "retract":
		var scope := "believed/player"
		if str(case["source"]) == "group":
			scope = "held/harbor_council"
		elif str(case["source"]) == "own":
			scope = "believed/dock_hand"
		steps.append({"op": "clear_in", "key": "harbor.toll_fate", "scope": scope})
		steps.append({"op": "tick", "minutes": 0})
	return steps


static func _m7_ferry(item: Dictionary, stage: String) -> Dictionary:
	var steps: Array = []
	if stage == "pay_toll" or stage == "cross":
		steps.append_array(_room())
	if stage == "cross":
		steps.append({"op": "tick", "minutes": 0})
	elif stage == "pay_toll":
		steps.append({"op": "fact", "key": "player.coins", "value": 0})
	steps.append({"op": "console", "line": "kill %s" % str(item["role"])})
	steps.append({"op": "console", "line": "time 0"})
	return {"id": "m7:%s:%s" % [item["role"], stage], "kind": "m7_ferry", "steps": steps, "trace": true}


static func _m7_guild(item: Dictionary, stage: String) -> Dictionary:
	var steps: Array = [
		{"op": "deed", "verb": "asked_guild", "actor": "player", "target": "", "place": "gullhaven"},
		{"op": "tick", "minutes": 0},
	]
	if stage == "signed":
		steps.append({"op": "fact", "key": "harbor.guild_signed", "value": true})
		steps.append({"op": "tick", "minutes": 0})
	steps.append({"op": "console", "line": "kill %s" % str(item["role"])})
	steps.append({"op": "console", "line": "time 0"})
	return {"id": "m7:%s:%s" % [item["role"], stage], "kind": "m7_guild", "steps": steps, "trace": true}


static func _room() -> Array:
	return [
		{"op": "open", "scene": "toll.offer_room"},
		{"op": "lines"},
		{"op": "choose", "text": "Take the room"},
		{"op": "lines"},
	]


static func _why(story_id: String) -> Dictionary:
	return {
		"id": story_id,
		"op": "why_not",
		"scope": "topic",
		"scope_id": "rumor.ledger",
		"speaker": "ferry",
	}


static func _harbor(id: String, steps: Array) -> Dictionary:
	return {"id": id, "kind": "m6_harbor", "steps": steps, "trace": true}


static func _pack(id: String, seed_value: int, steps: Array) -> Dictionary:
	return {"id": id, "kind": "m6_pack", "seed": seed_value, "steps": steps, "trace": true}


static func _host(runtime: WyrdRuntime) -> WyrdFakeHost:
	if runtime.has_meta("m10_host"):
		return runtime.get_meta("m10_host") as WyrdFakeHost
	if runtime.has_meta("host"):
		return runtime.get_meta("host") as WyrdFakeHost
	return null


static func _boot_gull(local_tag: bool) -> WyrdRuntime:
	var opened: Dictionary = _Harness.new().boot_gullhaven(local_tag, 4, true)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.set_meta("host", opened["host"])
	runtime.set_meta("m10_host", opened["host"])
	runtime.set_meta("m10_harness", _Harness.new())
	return runtime


static func _boot_m4_ferry() -> WyrdRuntime:
	var runtime := _boot_gull(false)
	var host := _host(runtime)
	host.world.add_entity(&"net_mender", &"person", "Lise", PackedStringArray(), true)
	host.world.add_entity(&"rope_walker", &"person", "Edd", PackedStringArray(), true)
	host.world.add_entity(&"tide_clerk", &"person", "Sella", PackedStringArray(), true)
	host.world.add_entity(&"bell_warden", &"person", "Harl", PackedStringArray(), true)
	return runtime


static func _boot_m4_guild(run: Dictionary) -> WyrdRuntime:
	var opened: Dictionary = _Harness.new().open_pack(_Harness.HARBOR)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	runtime.register_adapter(WyrdElectionAdapter, Poll.new())
	_add_ferry_people(host, true)
	_add_guild_people(host)
	runtime.start_new_game(1)
	host.world.add_member(&"faction.harbor", &"net_mender")
	if not (str(run["role"]) == "harbor_factor" and str(run["action"]) == "vacate"):
		host.world.add_member(&"faction.harbor", &"rope_walker")
	runtime.set_meta("host", host)
	runtime.set_meta("m10_host", host)
	runtime.set_meta("m10_harness", _Harness.new())
	return runtime


static func _boot_m5(member: bool) -> WyrdRuntime:
	var opened: Dictionary = _Harness.new().open_pack(_Harness.HARBOR)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.world.add_entity(&"player", &"person", "traveler", PackedStringArray(), true)
	host.world.add_entity(&"dock_hand", &"person", "hand", PackedStringArray(), true)
	host.world.add_entity(&"line_fisher", &"person", "fisher", PackedStringArray(), true)
	host.world.add_entity(&"dock_apprentice", &"person", "apprentice", PackedStringArray(), true)
	host.world.add_entity(&"ferry_master", &"person", "master", PackedStringArray(), true)
	if member:
		host.world.set_groups(&"dock_hand", PackedStringArray([&"harbor_council"]))
	runtime.start_new_game(4)
	runtime.set_meta("host", host)
	runtime.set_meta("m10_host", host)
	return runtime


static func _boot_harbor() -> WyrdRuntime:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var manifest := load("res://example/content/gullhaven/harbor.wyrdmanifest.tres") as WyrdContentManifest
	var report := runtime.load_content(manifest)
	if not report.ok:
		push_error(report.diagnostics.format())
	runtime.register_adapter(WyrdElectionAdapter, _Election.new())
	runtime.start_new_game(5)
	runtime.set_meta("host", host)
	runtime.set_meta("m10_host", host)
	return runtime


static func _boot_pack(seed_value: int) -> WyrdRuntime:
	var compiled := _compile(_RANK)
	if compiled["diagnostics"].has_errors():
		push_error(compiled["diagnostics"].format())
	var runtime := WyrdRuntime.new()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([str(compiled["path"])])
	var report := runtime.load_content(manifest)
	if not report.ok:
		push_error(report.diagnostics.format())
	runtime.start_new_game(seed_value)
	return runtime


static func _boot_generated() -> WyrdRuntime:
	var opened: Dictionary = _Harbor.new().boot_generated(1)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.set_meta("host", opened["host"])
	runtime.set_meta("m10_host", opened["host"])
	runtime.set_meta("m10_harness", opened["harness"])
	return runtime


static func _compile(body: String) -> Dictionary:
	var path := _write("user://wyrd_m6_matrix_%d.wyrd" % body.hash(), body)
	var diagnostics := WyrdDiagnostics.new()
	var pack := WyrdPack.compile(PackedStringArray([path]), "harbor", 1, null, diagnostics, path, true)
	return {"diagnostics": diagnostics, "pack": pack, "path": path}


static func _write(path: String, body: String) -> String:
	var lines := PackedStringArray()
	for line in body.strip_edges().split("\n"):
		if line.begins_with("\t\t"):
			lines.append(line.substr(2))
		else:
			lines.append(line)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	file.close()
	return path


static func _add_ferry_people(host: WyrdFakeHost, local_tag: bool) -> void:
	var tags := PackedStringArray()
	if local_tag:
		tags.append("local")
	host.world.add_entity(&"player", &"person", "traveler", tags, true)
	host.world.add_entity(&"tavern_owner", &"person", "innkeeper", PackedStringArray(), true)
	host.world.add_entity(&"ferry_master", &"person", "Bram", PackedStringArray(), true)
	host.world.add_entity(&"storm_watcher", &"person", "watcher", PackedStringArray(), true)
	host.world.add_entity(&"dock_apprentice", &"person", "Nia", PackedStringArray(), true)
	host.world.add_entity(&"dock.bell", &"object", "bell", PackedStringArray(), true)


static func _add_guild_people(host: WyrdFakeHost) -> void:
	host.world.add_entity(&"net_mender", &"person", "Lise", PackedStringArray(), true)
	host.world.add_entity(&"rope_walker", &"person", "Edd", PackedStringArray(), true)
	host.world.add_entity(&"tide_clerk", &"person", "Sella", PackedStringArray(), true)
	host.world.add_entity(&"bell_warden", &"person", "Harl", PackedStringArray(), true)


static func _m4_act(runtime: WyrdRuntime, host: WyrdFakeHost, step: Dictionary) -> void:
	var role := StringName(str(step["role"]))
	var action := str(step["action"])
	if action == "replace":
		runtime.roles.assign(role, &"bell_warden")
		return
	var who := _default_holder(str(step["role"]))
	var locked := str(step["role"]) == "ferry_master" and action == "kill"
	locked = locked and (str(step["stage"]) == "pay_toll" or str(step["stage"]) == "cross")
	if action == "kill":
		_set_alive(host, who, false)
	if locked:
		return
	var reason := &"left"
	if action == "kill":
		reason = &"died"
	runtime.roles.vacate(role, reason)


static func _default_holder(role: String) -> StringName:
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


static func _set_alive(host: WyrdFakeHost, id: StringName, alive: bool) -> void:
	var kind := &"person"
	var shown := String(id)
	for row in _people():
		if StringName(str(row[0])) == id:
			kind = StringName(str(row[1]))
			shown = str(row[2])
	host.world.add_entity(id, kind, shown, PackedStringArray(), alive)


static func _people() -> Array:
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


const _RANK := """
language 1
storylet harbor.ranked
  scope: topic rumor.matrix
  speaker: ferry
  priority: 3
  when: true
  - The ranked line. #line:ranked1
storylet harbor.specific
  scope: topic rumor.matrix
  speaker: ferry
  when: true and true
  - The specific line. #line:specific1
storylet harbor.alpha
  scope: topic rumor.pair
  speaker: ferry
  priority: 1
  - The alpha line. #line:alpha1
storylet harbor.beta
  scope: topic rumor.pair
  speaker: ferry
  priority: 1
  - The beta line. #line:beta1
"""
